use Samaki::Plugout;
use Samaki::Utils;
use Duck::CSV;
use JSON::Fast;
use Log::Async;

unit class Samaki::Plugout::CSVGeo does Samaki::Plugout;

has $.name = 'csv-geo';
has $.description = 'View CSV data with GeoJSON/WKT/polyline columns or GeoJSON files on an interactive map';
has $.clear-before = False;

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
  info "executing CSVGeo with $path";

  # Derive name from filename (not from the passed $name parameter)
  my $file-basename = $path.basename.subst(/\. <[a..z A..Z]>+ $/, '');

  # Determine file type
  my $is-geojson = $path ~~ /\. [geojson|json] $/;
  my $file-type = $is-geojson ?? 'geojson' !! 'csv';

  my ($content, $latlon-pairs-json);

  if $is-geojson {
    # Read GeoJSON file
    $content = slurp $path;
    $latlon-pairs-json = to-json([]);
    info "Processing GeoJSON file";
  } else {
    # Read CSV
    my @rows = read-csv("$path");
    return unless @rows;

    # Get column names
    my @columns = @rows[0].keys.sort;

    # Detect lat/lon column pairs (still useful for lat/lon columns)
    my @latlon-pairs = self.detect-latlon-pairs(@columns);

    info "Detected lat/lon pairs: {@latlon-pairs.map({ $_<lat> ~ '/' ~ $_<lon> }).join(', ')}" if @latlon-pairs;

    # Read the raw CSV content
    $content = slurp $path;

    # Prepare metadata for JavaScript
    $latlon-pairs-json = to-json(@latlon-pairs);
  }

  # Create out/ subdirectory
  my $out-dir = $data-dir.child('out');
  $out-dir.mkdir unless $out-dir.e;

  # Generate file paths using filename
  my $js-file = $out-dir.child("{$file-basename}-csv-geo-data.js");
  my $html-file = $out-dir.child("{$file-basename}-csv-geo.html");
  my $title = html-escape($data-dir.basename ~ " : " ~ $file-basename);

  # Find all existing csv-geo-data.js files in the out directory
  my @all-data-files;
  my @dataset-info;

  for $out-dir.dir.sort -> $file {
    next unless $file ~~ /'-csv-geo-data.js'$/;
    my $basename = $file.basename;
    my $dataset-name = $basename.subst('-csv-geo-data.js', '');
    @all-data-files.push($basename);
    @dataset-info.push(%(
      filename => $basename,
      name => $dataset-name,
      is-current => ($basename eq "{$file-basename}-csv-geo-data.js")
    ));
  }

  # Add current file if it's not in the list yet
  unless @all-data-files.grep("{$file-basename}-csv-geo-data.js") {
    @all-data-files.push("{$file-basename}-csv-geo-data.js");
    @dataset-info.push(%(
      filename => "{$file-basename}-csv-geo-data.js",
      name => $file-basename,
      is-current => True
    ));
  }

  # Move current dataset to the front so it's the active tab
  @dataset-info = @dataset-info.sort: { -$_<is-current> };

  info "Found {@all-data-files.elems} data file(s): {@all-data-files.join(', ')}";

  # Build JavaScript data file
  my $js-content = self.build-js-data($file-basename, $content, $latlon-pairs-json, $file-type);

  # Build HTML content with all data files
  my $html = self.build-html($title, @dataset-info);

  # Write both files
  spurt $js-file, $js-content;
  spurt $html-file, $html;
  info "opening $html-file";
  shell-open $html-file;
}


method detect-latlon-pairs(@columns) {
  my @pairs;
  my %used-cols;

  for @columns -> $col {
    next if %used-cols{$col};

    # Check if this is a latitude column (case-insensitive using fc for Unicode case folding)
    my $col-fc = $col.fc;
    my $is-lat = $col-fc eq 'lat'.fc
              || $col-fc eq 'latitude'.fc
              || $col-fc ~~ /'_lat' $/
              || $col-fc ~~ /'_latitude' $/;

    next unless $is-lat;

    # Try to find matching longitude column
    # Extract base/prefix (e.g., "start_lat" -> "start", "abc_lat" -> "abc", "LAT" -> "")
    my $base = $col;
    $base ~~ s/:i '_'? lat(itude)? $//;

    # Build longitude candidates preserving the case pattern of the original column
    my $lon-col;
    my @candidates;

    if $base {
      # For prefixed columns (e.g., "abc_lat"), try suffix variations
      # Try to preserve the case pattern
      @candidates = (
        $base ~ '_lon',      # abc_lon
        $base ~ '_lng',      # abc_lng
        $base ~ '_longitude' # abc_longitude
      );
    }

    # Always try standard variations without prefix
    @candidates.append('lon', 'lng', 'longitude', 'LON', 'LNG', 'LONGITUDE');

    # Find matching column using case-insensitive comparison
    for @candidates -> $candidate {
      my $matched = @columns.first: -> $c {
        !%used-cols{$c} && $c.fc eq $candidate.fc
      };

      if $matched {
        $lon-col = $matched;
        last;
      }
    }

    if $lon-col {
      @pairs.push(%(lat => $col, lon => $lon-col));
      %used-cols{$col} = True;
      %used-cols{$lon-col} = True;
      info "Found lat/lon pair: $col, $lon-col";
    }
  }

  return @pairs;
}


method build-js-data($dataset-name, $content, $latlon-pairs-json, $type) {
  my $escaped-content;
  my $data-field;

  if $type eq 'geojson' {
    # For GeoJSON, we can embed it directly as JSON (no escaping needed for string)
    $escaped-content = $content.trans(['\\', '"', "\n", "\r"] => ['\\\\', '\\"', '\\n', '']);
    $data-field = qq[geojsonContent: "$escaped-content"];
  } else {
    # Escape the CSV content for embedding in JavaScript
    $escaped-content = $content.trans(['\\', '"', "\n", "\r"] => ['\\\\', '\\"', '\\n', '']);
    $data-field = qq[csvContent: "$escaped-content"];
  }

  return qq:to/JS/;
  // Data and metadata for dataset: $dataset-name (type: $type)
  if (typeof window.datasets === 'undefined') \{
    window.datasets = \{\};
  \}
  window.datasets['$dataset-name'] = \{
    type: '$type',
    $data-field,
    latlonPairs: $latlon-pairs-json
  \};
  JS
}

method build-html($title, @dataset-info) {
  # Build script tags for all datasets
  my $script-tags = @dataset-info.map(-> $ds {
    qq[    <script src="{$ds<filename>}"></script>]
  }).join("\n");

  my $html = q:to/HTML/;
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>TITLE_PLACEHOLDER</title>

    <!-- Leaflet CSS/JS -->
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>

    <!-- jQuery + DataTables -->
    <script src="https://code.jquery.com/jquery-3.7.0.min.js"></script>
    <link rel="stylesheet" href="https://cdn.datatables.net/1.13.7/css/jquery.dataTables.css">
    <script src="https://cdn.datatables.net/1.13.7/js/jquery.dataTables.min.js"></script>

    <!-- Papa Parse for CSV parsing -->
    <script src="https://cdn.jsdelivr.net/npm/papaparse@5.4.1/papaparse.min.js"></script>

    <!-- wkx for parsing WKT, WKB, EWKB, EWKT, and other geo formats -->
    <script src="https://cdn.jsdelivr.net/npm/wkx@0.5.0/dist/wkx.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/@mapbox/polyline@1.2.1/src/polyline.js"></script>

    <style>
      body {
        margin: 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        height: 100vh;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
        background-color: #f8f9fa;
      }

      #map-container {
        height: 75vh;
        position: relative;
        flex-shrink: 0;
      }

      #map-container.fullscreen {
        position: fixed;
        top: 0;
        left: 0;
        width: 100vw;
        height: 100vh;
        z-index: 9999;
      }

      #map {
        height: 100%;
        width: 100%;
      }

      #controls {
        position: absolute;
        top: 10px;
        left: 50px;
        right: 60px;
        z-index: 1000;
        background: rgba(255, 255, 255, 0.6);
        padding: 8px 12px;
        border: 2px solid rgba(255, 255, 255, 1);
        border-radius: 4px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.2);
        display: flex;
        gap: 8px;
        align-items: center;
        flex-wrap: wrap;
      }

      #show-all-btn {
        padding: 6px 12px;
        font-family: inherit;
        font-size: 12px;
        background: #3b82f6;
        color: white;
        border: none;
        border-radius: 3px;
        cursor: pointer;
        white-space: nowrap;
      }

      #show-all-btn:hover {
        background: #2563eb;
      }

      #fullscreen-btn {
        position: absolute;
        top: 10px;
        right: 10px;
        z-index: 1000;
        width: 32px;
        height: 32px;
        padding: 0;
        font-size: 18px;
        background: white;
        color: #333;
        border: 2px solid #e2e8f0;
        border-radius: 4px;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        line-height: 1;
        box-shadow: 0 2px 4px rgba(0,0,0,0.2);
      }

      #fullscreen-btn:hover {
        background: #f8f9fa;
        border-color: #cbd5e1;
      }

      #tile-selector, #palette-selector, #key-selector, #marker-size-selector, #marker-color-selector {
        padding: 5px 8px;
        font-family: inherit;
        font-size: 12px;
        border: 1px solid #e2e8f0;
        border-radius: 3px;
        background: white;
        cursor: pointer;
        max-width: 200px;
        min-width: 0;
      }

      #tile-selector:hover, #palette-selector:hover, #key-selector:hover, #marker-size-selector:hover, #marker-color-selector:hover {
        border-color: #cbd5e1;
      }

      #legend-box {
        position: absolute;
        top: 52px;
        right: 10px;
        z-index: 1000;
        background: rgba(255, 255, 255, 0.95);
        border: 1px solid #e2e8f0;
        border-radius: 4px;
        padding: 8px;
        max-height: 300px;
        max-width: 200px;
        overflow-y: auto;
        font-family: inherit;
        font-size: 11px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        display: none;
      }

      .legend-item {
        display: flex;
        align-items: center;
        gap: 6px;
        padding: 3px 0;
        line-height: 1.3;
      }

      .legend-color {
        width: 12px;
        height: 12px;
        border-radius: 2px;
        flex-shrink: 0;
      }

      .legend-label {
        color: #2c3e50;
        word-break: break-word;
      }

      #divider {
        height: 6px;
        background: #e2e8f0;
        cursor: ns-resize;
        position: relative;
        flex-shrink: 0;
      }

      #divider:hover {
        background: #cbd5e1;
      }

      #divider::after {
        content: '';
        position: absolute;
        left: 50%;
        top: 50%;
        transform: translate(-50%, -50%);
        width: 40px;
        height: 3px;
        background: #94a3b8;
        border-radius: 2px;
      }

      #table-container {
        flex: 1;
        overflow: hidden;
        display: flex;
        flex-direction: column;
        background: white;
        min-height: 100px;
      }

      #table-wrappers {
        flex: 1;
        overflow: hidden;
        position: relative;
      }

      #tabs {
        display: flex;
        gap: 4px;
        padding: 10px 20px 0 20px;
        background: #f8f9fa;
        border-bottom: 2px solid #cbd5e1;
        flex-shrink: 0;
        position: relative;
      }

      .tab {
        padding: 8px 16px;
        background: #e2e8f0;
        border: 1px solid #cbd5e1;
        border-bottom: 2px solid #cbd5e1;
        border-radius: 4px 4px 0 0;
        cursor: pointer;
        font-size: 13px;
        color: #64748b;
        transition: all 0.2s;
        position: relative;
        margin-bottom: -2px;
      }

      .tab:hover {
        background: #f1f5f9;
      }

      .tab.active {
        background: white;
        color: #2c3e50;
        font-weight: 500;
        border-color: #cbd5e1;
        border-bottom: 2px solid white;
        z-index: 1;
      }

      .tab-checkbox {
        margin-right: 6px;
        cursor: pointer;
        vertical-align: middle;
      }

      .tab-label {
        cursor: pointer;
        user-select: none;
      }

      .table-wrapper {
        position: absolute;
        top: 0;
        left: 0;
        right: 0;
        bottom: 0;
        overflow: auto;
        padding: 0 20px 20px 20px;
        display: none;
      }

      .table-wrapper.active {
        display: block;
      }

      h2 {
        margin: 0 0 15px 0;
        color: #2c3e50;
        font-size: 18px;
        font-weight: 500;
      }

      .table-wrapper table {
        width: 100% !important;
        font-size: 12px;
      }

      .table-wrapper table thead th {
        background-color: #f1f5f9;
        color: #2c3e50;
        padding: 8px 6px;
      }

      .table-wrapper table tbody td {
        padding: 6px;
      }

      .table-wrapper table tbody tr {
        cursor: pointer;
      }

      .table-wrapper table tbody tr:hover {
        background-color: #f1f5f9;
      }

      .table-wrapper table tbody tr.selected {
        background-color: #dbeafe !important;
      }

      .color-indicator {
        display: inline-block;
        width: 12px;
        height: 12px;
        border-radius: 2px;
        margin-right: 4px;
        vertical-align: middle;
      }

      /* DataTables controls - make them smaller */
      .dataTables_wrapper .dataTables_length,
      .dataTables_wrapper .dataTables_filter,
      .dataTables_wrapper .dataTables_info,
      .dataTables_wrapper .dataTables_paginate {
        font-size: 10px;
        padding: 2px;
      }

      .dataTables_wrapper .dataTables_length select,
      .dataTables_wrapper .dataTables_filter input {
        font-size: 10px;
        padding: 2px 4px;
      }

      .dataTables_wrapper .dataTables_paginate .paginate_button {
        font-size: 10px;
        padding: 2px 6px;
      }

      .dataTables_wrapper .dataTables_info {
        text-align: center;
        width: 100%;
        margin: 8px 0;
      }

      .custom-marker-icon {
        background: transparent;
        border: none;
      }

      /* JSON Tree Viewer Styles */
      .json-viewer {
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
        font-size: 12px;
        line-height: 1.5;
        overflow: auto;
        padding: 0;
        height: 100%;
        display: flex;
        flex-direction: column;
      }

      .json-viewer-header {
        margin: 0;
        padding: 4px 8px 4px 8px;
        border-bottom: 1px solid #e2e8f0;
        flex-shrink: 0;
        display: flex;
        align-items: center;
      }

      .json-viewer-content {
        flex: 1;
        overflow: auto;
        padding: 8px 12px;
      }

      .json-fit-button {
        padding: 2px 8px;
        font-family: inherit;
        font-size: 11px;
        background: #3b82f6;
        color: white;
        border: none;
        border-radius: 2px;
        cursor: pointer;
        transition: background 0.2s;
      }

      .json-fit-button:hover {
        background: #2563eb;
      }

      .json-color-picker {
        display: inline-flex;
        gap: 4px;
        margin-left: 8px;
        align-items: center;
      }

      .color-radio-wrapper {
        display: inline-block;
      }

      .color-radio-input {
        display: none;
      }

      .color-radio-label {
        display: inline-block;
        width: 16px;
        height: 16px;
        border: 2px solid #cbd5e1;
        border-radius: 3px;
        cursor: pointer;
        transition: all 0.2s;
        box-sizing: border-box;
      }

      .color-radio-label:hover {
        border-color: #64748b;
        transform: scale(1.1);
      }

      .color-radio-input:checked + .color-radio-label {
        border-color: #1e293b;
        border-width: 2px;
        box-shadow: 0 0 0 2px #1e293b;
      }

      .json-key {
        color: #8b5cf6;
        font-weight: 500;
      }

      .json-string {
        color: #10b981;
      }

      .json-number {
        color: #3b82f6;
      }

      .json-boolean {
        color: #ef4444;
      }

      .json-null {
        color: #94a3b8;
      }

      .json-item {
        margin-left: 20px;
      }

      .json-expandable {
        cursor: pointer;
        user-select: none;
      }

      .json-expandable::before {
        content: '▶';
        display: inline-block;
        width: 12px;
        margin-right: 4px;
        color: #64748b;
        transition: transform 0.2s;
      }

      .json-expandable.expanded::before {
        transform: rotate(90deg);
      }

      .json-collapsed {
        display: none;
      }

      .json-bracket {
        color: #64748b;
      }

      .json-feature {
        cursor: pointer;
        padding: 2px 4px;
        margin: -2px -4px;
        border-radius: 3px;
        transition: background-color 0.2s;
      }

      .json-feature:hover {
        background-color: #f1f5f9;
      }

      .json-feature-selected {
        background-color: #dbeafe !important;
      }
    </style>
  </head>
  <body>
    <div id="map-container">
      <div id="map"></div>
      <button id="fullscreen-btn" title="Fullscreen">⛶</button>
      <div id="controls">
        <button id="show-all-btn">Show All</button>
        <select id="tile-selector">
          <option value="light" selected>Light (Positron)</option>
          <option value="dark">Dark (Dark Matter)</option>
          <option value="satellite">Satellite</option>
          <option value="topo">Topographic</option>
          <option value="osm">OpenStreetMap</option>
        </select>
        <select id="palette-selector">
          <option value="muted" selected>Muted</option>
          <option value="pastel">Pastel</option>
          <option value="bright">Bright</option>
          <option value="earth">Earth Tones</option>
          <option value="vivid">Vivid</option>
          <option value="monochrome">Monochrome</option>
          <option value="blackborders">Black Borders</option>
          <option value="whiteborders">White Borders</option>
        </select>
        <select id="key-selector">
          <option value="none" selected>Legend: none</option>
        </select>
        <select id="marker-size-selector">
          <option value="tiny-fixed">Tiny</option>
          <option value="small-fixed">Small</option>
          <option value="medium-fixed" selected>Medium</option>
          <option value="large-fixed">Large</option>
          <option value="tiny-zoom">Tiny (zoom)</option>
          <option value="small-zoom">Small (zoom)</option>
          <option value="medium-zoom">Medium (zoom)</option>
          <option value="large-zoom">Large (zoom)</option>
        </select>
        <select id="marker-color-selector">
          <option value="row" selected>By Row</option>
          <option value="alternate">Alternate</option>
          <option value="red">Red</option>
          <option value="blue">Blue</option>
          <option value="green">Green</option>
          <option value="yellow">Yellow</option>
          <option value="orange">Orange</option>
          <option value="purple">Purple</option>
          <option value="black">Black</option>
        </select>
      </div>
      <div id="legend-box"></div>
    </div>

    <div id="divider"></div>

    <div id="table-container">
      <div id="tabs"></div>
      <div id="table-wrappers"></div>
    </div>

    <!-- External data files -->
    SCRIPT_TAGS_PLACEHOLDER

    <script>
      // Load wkx and Buffer from the browserified bundle
      const wkx = require('wkx');
      const Buffer = require('buffer').Buffer;

      // Global datasets structure
      // Each dataset will have: { name, rowData, columns, geoColumns, dataTable, colorOffset }
      let allDatasets = {};
      let activeDatasetName = null;

      // Unescape CSV-escaped JSON: replace literal \n with newlines and "" with "
      // This handles JSON that was escaped when exported from databases/tools
      function unescapeCSVJSON(str) {
        // Replace backslash-n (char codes 92,110) with newline (char code 10)
        const backslashN = String.fromCharCode(92) + String.fromCharCode(110);
        const newline = String.fromCharCode(10);
        let result = str;
        while (result.indexOf(backslashN) >= 0) {
          result = result.replace(backslashN, newline);
        }
        // Replace doubled quotes with single quotes
        while (result.indexOf('""') >= 0) {
          result = result.replace('""', '"');
        }
        return result;
      }

      // Check if a string might benefit from CSV unescaping
      function needsUnescaping(str) {
        // Check for backslash-n sequence (char codes 92,110)
        for (let i = 0; i < str.length - 1; i++) {
          if (str.charCodeAt(i) === 92 && str.charCodeAt(i+1) === 110) {
            return true;
          }
        }
        // Check for doubled quotes
        return str.indexOf('""') >= 0;
      }

      // Try to parse a JSON string and check if it's GeoJSON
      function tryParseAsGeoJSON(jsonStr, debug) {
        try {
          const json = JSON.parse(jsonStr);

          // Check for coordinates property anywhere in the object
          const hasCoordinates = json.coordinates !== undefined ||
                                 (json.geometry && json.geometry.coordinates !== undefined);

          // Check for GeoJSON type keywords
          const hasGeoType = json.type && (
            json.type === 'Point' ||
            json.type === 'LineString' ||
            json.type === 'Polygon' ||
            json.type === 'MultiPoint' ||
            json.type === 'MultiLineString' ||
            json.type === 'MultiPolygon' ||
            json.type === 'GeometryCollection' ||
            json.type === 'Feature' ||
            json.type === 'FeatureCollection'
          );

          // Check for geometry with type
          const hasGeometry = json.geometry && json.geometry.type;

          if (hasCoordinates || hasGeoType || hasGeometry) {
            if (debug) console.log('✓ Detected as GeoJSON');

            // Return directly if it's already a Feature or FeatureCollection
            if (json.type === 'Feature' || json.type === 'FeatureCollection') {
              return json;
            }

            // If it has geometry type and coordinates, wrap it as a Feature
            if (json.type && json.coordinates) {
              return {
                type: 'Feature',
                geometry: json,
                properties: {}
              };
            }

            // If it has a geometry property, wrap it
            if (json.geometry) {
              return {
                type: 'Feature',
                geometry: json.geometry,
                properties: json.properties || {}
              };
            }

            // Otherwise, just return it and let Leaflet handle it
            return json;
          }
        } catch (e) {
          // Not valid JSON or not GeoJSON
          if (debug) console.log('✗ JSON parse failed:', e.message);
        }
        return null;
      }

      // Validate that all coordinates in a GeoJSON object are within valid
      // lat/lon ranges.  Rejects garbage produced by WKB parsers mis-decoding
      // non-WKB data (e.g. polyline strings decoded via base64).
      function hasValidCoords(geojson) {
        function checkCoord(c) {
          // c is [lng, lat] in GeoJSON
          return Array.isArray(c) && c.length >= 2 &&
                 isFinite(c[0]) && c[0] >= -180 && c[0] <= 180 &&
                 isFinite(c[1]) && c[1] >= -90  && c[1] <= 90;
        }
        function checkCoords(coords) {
          if (!Array.isArray(coords) || coords.length === 0) return false;
          if (Array.isArray(coords[0])) {
            return coords.every(checkCoords);  // nested (rings, multi-geometries)
          }
          return checkCoord(coords);  // leaf [lng, lat]
        }
        function checkGeom(g) {
          if (!g) return false;
          if (g.type === 'GeometryCollection') return (g.geometries || []).every(checkGeom);
          return checkCoords(g.coordinates || []);
        }
        if (!geojson) return false;
        if (geojson.type === 'Feature') return checkGeom(geojson.geometry);
        if (geojson.type === 'FeatureCollection') return (geojson.features || []).every(hasValidCoords);
        return checkGeom(geojson);  // bare geometry
      }

      // Try to decode a Google Encoded Polyline (precision 5 or 6).
      // isPolylineColumn = true means the column name contains "polyline",
      // so we trust the data and skip the strict heuristics.
      function tryParseAsPolyline(str, isPolylineColumn, debug) {
        if (!str) return null;
        // Some CSV generators double-escape backslashes (\\  becomes \). Unescape before decoding.
        var bs = String.fromCharCode(92);
        str = str.replace(new RegExp(bs + bs + bs + bs, 'g'), bs);

        // Basic requirement: only ASCII chars 63–126
        if (!/^[?-~]+$/.test(str)) {
          if (debug) console.log('✗ Not polyline: chars outside 63-126 range');
          return null;
        }

        if (!isPolylineColumn) {
          // Strict heuristics to avoid false positives on random text / identifiers.

          // Must be long enough to plausibly encode ≥2 real coordinate pairs.
          if (str.length < 20) {
            if (debug) console.log('✗ Not polyline: too short (' + str.length + ' < 20)');
            return null;
          }

          // Must contain chars from the "exotic" set produced by real coordinate
          // deltas: ? @ [ \ ] ^ { | } ~  (codes 63-64, 91-94, 123-126).
          // Underscores and backticks are excluded because they're common in
          // identifiers and contribute nothing to confidence.
          if (!/[?@\[\\\]^{|}~]/.test(str)) {
            if (debug) console.log('✗ Not polyline: no polyline-characteristic chars');
            return null;
          }

          // Must have sufficient character diversity (encoded paths visit many
          // different delta magnitudes; plain identifiers are repetitive).
          var distinctChars = new Set(str.split('')).size;
          if (distinctChars < 10) {
            if (debug) console.log('✗ Not polyline: insufficient char diversity (' + distinctChars + ' distinct)');
            return null;
          }
        }

        // Try precision 5 (Google Maps standard), then precision 6 (Valhalla/OSRM).
        for (var precision of [5, 6]) {
          try {
            var raw = polyline.decode(str, precision);
            var coords = raw.map(function(c) { return [c[1], c[0]]; });
            if (coords.length < 2) continue;

            // All decoded points must be within valid lat/lon range.
            var valid = coords.every(function(c) {
              return c[1] >= -90 && c[1] <= 90 && c[0] >= -180 && c[0] <= 180;
            });
            if (!valid) {
              if (debug) console.log('✗ polyline' + precision + ': coords out of range');
              continue;
            }

            var lats = coords.map(function(c) { return c[1]; });
            var lngs = coords.map(function(c) { return c[0]; });
            var minLat = Math.min.apply(null, lats), maxLat = Math.max.apply(null, lats);
            var minLng = Math.min.apply(null, lngs), maxLng = Math.max.apply(null, lngs);
            var span = (maxLat - minLat) + (maxLng - minLng);

            if (!isPolylineColumn && span < 0.001) {
              // Decoded to near-zero near-origin coordinates — almost certainly a
              // false positive from a short identifier.
              if (debug) console.log('✗ polyline' + precision + ': bbox span too small (' + span.toFixed(6) + ')');
              continue;
            }

            console.log('✓ polyline' + precision + ' decoded: ' + coords.length + ' pts, bbox=[' +
              minLng.toFixed(4) + ',' + minLat.toFixed(4) + ' → ' +
              maxLng.toFixed(4) + ',' + maxLat.toFixed(4) + ']' +
              (isPolylineColumn ? ' (column name match)' : ''));
            return {
              type: 'Feature',
              geometry: { type: 'LineString', coordinates: coords },
              properties: { polylinePrecision: precision }
            };
          } catch (e) {
            if (debug) console.log('✗ polyline' + precision + ' decode failed:', e.message);
          }
        }
        return null;
      }

      // Try to parse a value as geo data using wkx
      // opts.isPolylineColumn: true if the column name contains "polyline"
      function tryParseGeo(value, debug, opts) {
        if (!value || typeof value !== 'string') return null;
        const trimmed = value.trim();
        if (!trimmed) return null;
        const isPolylineColumn = opts && opts.isPolylineColumn;

        // For polyline columns, try the polyline decoder first so that
        // WKB base64 can't accidentally parse the encoded string as a Point.
        let result;
        if (isPolylineColumn) {
          result = tryParseAsPolyline(trimmed, true, debug);
          if (result) {
            if (debug) console.log('✓ Parsed as encoded polyline');
            return result;
          }
        }

        // Try to parse as regular JSON (most common case)
        result = tryParseAsGeoJSON(trimmed, debug);
        if (result) {
          if (!hasValidCoords(result)) {
            if (debug) console.log('✗ GeoJSON had out-of-range coordinates');
            result = null;
          } else {
            if (debug) console.log('✓ Parsed as regular JSON');
            return result;
          }
        }

        // Try WKT/WKB formats
        const parsers = [
          // WKT/EWKT string
          { name: 'WKT/EWKT', fn: () => wkx.Geometry.parse(trimmed).toGeoJSON() },
          // WKB hex
          { name: 'WKB hex', fn: () => wkx.Geometry.parse(new Buffer(trimmed, 'hex')).toGeoJSON() },
          // WKB base64
          { name: 'WKB base64', fn: () => wkx.Geometry.parse(new Buffer(trimmed, 'base64')).toGeoJSON() }
        ];

        for (const parser of parsers) {
          try {
            const result = parser.fn();
            if (result) {
              if (!hasValidCoords(result)) {
                if (debug) console.log('✗', parser.name, 'produced out-of-range coordinates (likely mis-decoded binary)');
                continue;
              }
              if (debug) console.log('✓ Parsed as', parser.name);
              return result;
            }
          } catch (e) {
            if (debug) console.log('✗', parser.name, 'failed:', e.message);
          }
        }
        // If all parsing attempts failed, check if the value might be CSV-escaped JSON
        if (needsUnescaping(trimmed)) {
          if (debug) console.log('Detected CSV escaping, trying to unescape...');
          const unescaped = unescapeCSVJSON(trimmed);

          // Try parsing the unescaped version as GeoJSON
          result = tryParseAsGeoJSON(unescaped, debug);
          if (result) {
            if (debug) console.log('✓ Parsed after unescaping CSV-escaped JSON');
            return result;
          }

          // Try WKT/WKB on unescaped version too
          for (const parser of parsers) {
            try {
              const result = parser.fn.call(null);
              if (result) {
                if (debug) console.log('✓ Parsed as', parser.name, 'after unescaping');
                return result;
              }
            } catch (e) {
              // Silently fail on retry
            }
          }
        }

        if (debug) {
          console.log('Failed to parse value (length=' + trimmed.length + ')');
          console.log('Sample:', trimmed.substring(0, 100));
        }

        return null;
      }

      // Detect which columns contain geo data
      function detectGeoColumns(rows, columnNames) {
        const detected = [];
        const sampleSize = Math.min(5, rows.length);

        console.log('=== Geo Column Detection ===');
        console.log('Checking', columnNames.length, 'columns across', sampleSize, 'sample rows');

        for (const col of columnNames) {
          const isPolylineColumn = /polyline/i.test(col);
          let foundGeo = false;

          for (let i = 0; i < sampleSize; i++) {
            const val = rows[i][col];
            if (!val) continue;

            // Enable debug for first value in each column
            const debug = i === 0;
            if (debug) {
              console.log('\n--- Column:', col, (isPolylineColumn ? '(polyline column)' : ''), '---');
              console.log('Sample length:', val.length);
            }

            const parsed = tryParseGeo(val, debug, { isPolylineColumn });
            if (parsed) {
              detected.push(col);
              foundGeo = true;
              console.log('✓ Column "' + col + '" detected as geo data');
              break;
            }
          }

          if (!foundGeo) {
            if (isPolylineColumn) {
              // Column name says polyline — include it even if sample values didn't parse.
              console.log('✓ Column "' + col + '" included as polyline column (name match, values may be empty in sample)');
              detected.push(col);
            } else {
              const firstVal = rows[0] && rows[0][col];
              if (firstVal && firstVal.length > 50) {
                console.log('✗ Column "' + col + '" not detected (sample: ' + firstVal.substring(0, 50) + '...)');
              }
            }
          }
        }

        console.log('\n=== Detection Complete ===');
        console.log('Found', detected.length, 'geo columns:', detected.join(', '));
        return detected;
      }

      function parseAllDatasets() {
        const datasetNames = Object.keys(window.datasets);
        console.log('Parsing', datasetNames.length, 'datasets:', datasetNames);

        let colorOffset = 0;
        const colorsPerDataset = 12; // Each dataset gets 12 colors

        datasetNames.forEach(function(datasetName) {
          const dataset = window.datasets[datasetName];
          const datasetType = dataset.type || 'csv';

          if (datasetType === 'geojson') {
            parseGeoJSONDataset(datasetName, dataset, colorOffset);
          } else {
            parseCSVDataset(datasetName, dataset, colorOffset);
          }

          colorOffset += colorsPerDataset;
        });

        // Set first dataset as active
        if (datasetNames.length > 0) {
          activeDatasetName = datasetNames[0];
        }
      }

      function parseGeoJSONDataset(datasetName, dataset, colorOffset) {
        const geojsonContent = dataset.geojsonContent;
        let geojson;

        try {
          geojson = JSON.parse(geojsonContent);
        } catch (e) {
          console.error('Failed to parse GeoJSON for', datasetName, ':', e);
          return;
        }

        // Build rowData array from GeoJSON features
        const rowData = [];
        let features = [];

        if (geojson.type === 'FeatureCollection') {
          features = geojson.features || [];
        } else if (geojson.type === 'Feature') {
          features = [geojson];
        } else if (geojson.type && geojson.coordinates) {
          // Bare geometry - wrap in Feature
          features = [{
            type: 'Feature',
            geometry: geojson,
            properties: {}
          }];
        }

        features.forEach(function(feature, index) {
          const rowObj = {
            index: index,
            datasetName: datasetName,
            features: [feature],
            data: feature.properties || {}
          };
          rowData.push(rowObj);
        });

        // Store dataset info
        allDatasets[datasetName] = {
          name: datasetName,
          type: 'geojson',
          rowData: rowData,
          columns: [],
          geoColumns: [],
          latlonPairs: [],
          colorOffset: colorOffset,
          dataTable: null,
          rawGeoJSON: geojson
        };
      }

      function parseCSVDataset(datasetName, dataset, colorOffset) {
          const csvContent = dataset.csvContent;
          const latlonPairs = dataset.latlonPairs;

          const parsed = Papa.parse(csvContent, {
            header: true,
            skipEmptyLines: true
          });

          if (!parsed.data || parsed.data.length === 0) {
            console.error('No CSV data parsed for', datasetName);
            return;
          }

          // Get columns from the first row
          const columns = Object.keys(parsed.data[0]);

          // Detect geo columns using wkx
          const geoColumns = detectGeoColumns(parsed.data, columns);

          // Build rowData array
          const rowData = [];
          parsed.data.forEach(function(row, index) {
            const rowObj = {
              index: index,
              datasetName: datasetName,
              features: [],
              data: {}
            };

            // Copy all column data
            columns.forEach(function(col) {
              rowObj.data[col] = row[col] || '';
            });

            // Extract geo features from designated columns using wkx
            geoColumns.forEach(function(col) {
              const val = row[col];
              if (!val) return;

              const isPolylineColumn = /polyline/i.test(col);
              try {
                const geojson = tryParseGeo(val, false, { isPolylineColumn });
                if (!geojson) return;

                // Tag a feature with _sourceCol so the table can link back to it
                function tagCol(f) {
                  return Object.assign({}, f, {
                    properties: Object.assign({}, f.properties || {}, { _sourceCol: col })
                  });
                }

                // Handle different GeoJSON types
                if (geojson.type === 'Feature') {
                  rowObj.features.push(tagCol(geojson));
                } else if (geojson.type === 'FeatureCollection') {
                  geojson.features.forEach(function(f) {
                    rowObj.features.push(tagCol(f));
                  });
                } else if (geojson.type && geojson.coordinates) {
                  // Bare geometry - wrap in Feature
                  rowObj.features.push({
                    type: 'Feature',
                    geometry: geojson,
                    properties: { _sourceCol: col }
                  });
                }
              } catch (e) {
                console.warn('Failed to parse geo data in row ' + index + ', column ' + col + ':', e);
              }
            });

            // Create Point features from lat/lon pairs
            latlonPairs.forEach(function(pair) {
              const latVal = row[pair.lat];
              const lonVal = row[pair.lon];

              if (latVal && lonVal) {
                const lat = parseFloat(latVal);
                const lon = parseFloat(lonVal);

                if (!isNaN(lat) && !isNaN(lon)) {
                  rowObj.features.push({
                    type: 'Feature',
                    geometry: {
                      type: 'Point',
                      coordinates: [lon, lat]
                    },
                    properties: {
                      lat_col: pair.lat,
                      lon_col: pair.lon
                    }
                  });
                }
              }
            });

            rowData.push(rowObj);
          });

          // Store dataset info
          allDatasets[datasetName] = {
            name: datasetName,
            type: 'csv',
            rowData: rowData,
            columns: columns,
            geoColumns: geoColumns,
            latlonPairs: latlonPairs,
            colorOffset: colorOffset,
            dataTable: null
          };
      }

      // Global state
      let map;
      let allLayerGroups = {}; // Key format: "datasetName::rowIndex"
      let currentSelection = null;
      let currentTileLayer;
      let currentPalette = localStorage.getItem('samaki-palette') || 'muted';
      let currentKey = 'none';
      let keyColorMap = {};
      let currentMarkerSize = 'medium';
      let markerScaleWithZoom = false;
      let currentMarkerColor = 'row';
      let featureCyclers = {}; // Key: "datasetName::rowIndex::colName" → [cycleFn, ...]

      // Color palettes
      const colorPalettes = {
        muted: [
          '#4a6fa5', '#8b5a5a', '#5a8770', '#9b845f', '#6d5f8b', '#8b6b7a',
          '#5a8b8b', '#9b7a5a', '#5f6d8b', '#7a8b5f', '#5a7a8b', '#8b6a6a'
        ],
        pastel: [
          '#a8b9d1', '#d1a8b9', '#b9d1a8', '#d1c1a8', '#b5a8d1', '#d1a8c1',
          '#a8d1c1', '#c1a8d1', '#a8c1d1', '#c1d1a8', '#d1a8a8', '#a8d1a8'
        ],
        bright: [
          '#3b82f6', '#ef4444', '#10b981', '#f59e0b', '#8b5cf6', '#ec4899',
          '#14b8a6', '#f97316', '#6366f1', '#84cc16', '#06b6d4', '#f43f5e'
        ],
        earth: [
          '#8b7355', '#6b8e23', '#cd853f', '#8fbc8f', '#d2691e', '#9acd32',
          '#bc8f8f', '#daa520', '#808000', '#b8860b', '#a0522d', '#6b8e23'
        ],
        vivid: [
          '#ff6b6b', '#4ecdc4', '#45b7d1', '#f7b731', '#5f27cd', '#00d2d3',
          '#ff9ff3', '#54a0ff', '#48dbfb', '#1dd1a1', '#feca57', '#ff6348'
        ],
        monochrome: [
          '#404040', '#404040', '#404040', '#404040', '#404040', '#404040',
          '#404040', '#404040', '#404040', '#404040', '#404040', '#404040'
        ],
        blackborders: [
          '#cccccc', '#cccccc', '#cccccc', '#cccccc', '#cccccc', '#cccccc',
          '#cccccc', '#cccccc', '#cccccc', '#cccccc', '#cccccc', '#cccccc'
        ],
        whiteborders: [
          '#555555', '#555555', '#555555', '#555555', '#555555', '#555555',
          '#555555', '#555555', '#555555', '#555555', '#555555', '#555555'
        ]
      };

      // Special styling for border-based palettes
      const borderPalettes = {
        blackborders: { borderColor: '#000000', borderWidth: 2.5 },
        whiteborders: { borderColor: '#ffffff', borderWidth: 2.5 }
      };

      // Marker size configurations
      const markerSizes = {
        tiny: { marker: 8, circle: 3, scaledRadius: 500, icon: [12, 12], anchor: [6, 12] },
        small: { marker: 12, circle: 5, scaledRadius: 2000, icon: [16, 16], anchor: [8, 16] },
        medium: { marker: 20, circle: 8, scaledRadius: 5000, icon: [24, 24], anchor: [12, 24] },
        large: { marker: 28, circle: 12, scaledRadius: 10000, icon: [32, 32], anchor: [16, 32] }
      };

      // Marker color options
      const markerColorOptions = {
        red: '#ef4444',
        blue: '#3b82f6',
        green: '#10b981',
        yellow: '#eab308',
        orange: '#f97316',
        purple: '#8b5cf6',
        black: '#1f2937'
      };

      // Get current marker size config
      function getMarkerSize() {
        return markerSizes[currentMarkerSize] || markerSizes.medium;
      }

      // Get marker color based on settings
      function getMarkerColor(datasetName, rowIndex) {
        if (currentMarkerColor === 'row') {
          // Use row-based color (original behavior)
          return getColorForRow(datasetName, rowIndex);
        } else if (currentMarkerColor === 'alternate') {
          // Use the next color in the palette
          const dataset = allDatasets[datasetName];
          if (!dataset) return colorPalettes[currentPalette][0];
          const palette = colorPalettes[currentPalette];
          const baseColor = getColorForRow(datasetName, rowIndex);
          const baseIndex = palette.indexOf(baseColor);
          const alternateIndex = baseIndex >= 0 ? (baseIndex + 1) % palette.length : 1;
          return palette[alternateIndex];
        } else if (markerColorOptions[currentMarkerColor]) {
          // Use fixed color
          const color = markerColorOptions[currentMarkerColor];
          if (rowIndex === 0) {
            console.log('Using fixed marker color:', currentMarkerColor, '=', color);
          }
          return color;
        } else {
          // Fallback to row color
          console.warn('Unknown marker color option:', currentMarkerColor, '- falling back to row color');
          return getColorForRow(datasetName, rowIndex);
        }
      }

      // Tile provider configurations
      const tileProviders = {
        osm: {
          url: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          attribution: '© OpenStreetMap contributors',
          maxZoom: 19
        },
        light: {
          url: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
          attribution: '© OpenStreetMap contributors © CARTO',
          maxZoom: 19
        },
        dark: {
          url: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          attribution: '© OpenStreetMap contributors © CARTO',
          maxZoom: 19
        },
        satellite: {
          url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          attribution: '© Esri',
          maxZoom: 18
        },
        topo: {
          url: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
          attribution: '© OpenStreetMap contributors © OpenTopoMap',
          maxZoom: 17
        }
      };

      // Build key color map when key changes (across all datasets)
      function buildKeyColorMap() {
        keyColorMap = {};

        if (currentKey === 'none') {
          return;
        }

        // Collect unique values in the key column across all datasets
        const uniqueValues = new Set();
        Object.values(allDatasets).forEach(function(dataset) {
          dataset.rowData.forEach(function(row) {
            const value = row.data[currentKey] || 'null';
            uniqueValues.add(value);
          });
        });

        // Assign colors to each unique value
        const palette = colorPalettes[currentPalette];
        const sortedValues = Array.from(uniqueValues).sort();
        sortedValues.forEach(function(value, index) {
          keyColorMap[value] = palette[index % palette.length];
        });

        console.log('Built key color map for', currentKey, ':', keyColorMap);
      }

      // Helper function to get color for a row in a dataset
      function getColorForRow(datasetName, rowIndex) {
        const dataset = allDatasets[datasetName];
        if (!dataset) return colorPalettes[currentPalette][0];

        const palette = colorPalettes[currentPalette];

        if (currentKey === 'none') {
          // Use dataset color offset + row index + any manual color offset adjustment
          const colorOffsetAdjustment = dataset.colorOffsetAdjustment || 0;
          const colorIndex = (dataset.colorOffset + rowIndex + colorOffsetAdjustment) % palette.length;
          return palette[colorIndex];
        } else {
          // Key behavior: color by key value
          const row = dataset.rowData[rowIndex];
          const keyValue = row.data[currentKey] || 'null';
          return keyColorMap[keyValue] || palette[0];
        }
      }

      // Update legend box
      function updateLegend() {
        const legendBox = document.getElementById('legend-box');

        if (currentKey === 'none') {
          legendBox.style.display = 'none';
          return;
        }

        legendBox.style.display = 'block';

        // Sort key values for consistent display
        const sortedKeys = Object.keys(keyColorMap).sort();

        let html = '<div style="font-weight: 500; margin-bottom: 4px;">' + currentKey + '</div>';
        sortedKeys.forEach(function(value) {
          const color = keyColorMap[value];
          html += '<div class="legend-item">';
          html += '<div class="legend-color" style="background-color: ' + color + ';"></div>';
          html += '<div class="legend-label">' + value + '</div>';
          html += '</div>';
        });

        legendBox.innerHTML = html;
      }

      // Helper function to create geo data summary
      function summarizeGeoData(geoStr) {
        try {
          const geojson = tryParseGeo(geoStr);
          if (!geojson) {
            return geoStr.substring(0, 50) + (geoStr.length > 50 ? '...' : '');
          }

          let summary = '';

          if (geojson.type === 'Feature') {
            const geomType = geojson.geometry ? geojson.geometry.type : 'Unknown';
            const coordCount = countCoordinates(geojson.geometry);
            summary = `Feature: ${geomType}, ${coordCount} coord${coordCount !== 1 ? 's' : ''}`;
          } else if (geojson.type === 'FeatureCollection') {
            const featureCount = geojson.features ? geojson.features.length : 0;
            summary = `FeatureCollection: ${featureCount} feature${featureCount !== 1 ? 's' : ''}`;
          } else if (geojson.type && geojson.coordinates) {
            // Bare geometry
            const coordCount = countCoordinates(geojson);
            summary = `${geojson.type}: ${coordCount} coord${coordCount !== 1 ? 's' : ''}`;
          } else {
            summary = 'Geometry';
          }

          return summary;
        } catch (e) {
          return geoStr.substring(0, 50) + (geoStr.length > 50 ? '...' : '');
        }
      }

      // Count coordinates in a geometry
      function countCoordinates(geometry) {
        if (!geometry || !geometry.coordinates) return 0;

        function countArray(arr) {
          if (typeof arr[0] === 'number') return 1;
          return arr.reduce((sum, item) => sum + countArray(item), 0);
        }

        return countArray(geometry.coordinates);
      }

      // Copy to clipboard
      function copyToClipboard(text) {
        navigator.clipboard.writeText(text).then(function() {
          console.log('Copied to clipboard');
        }).catch(function(err) {
          console.error('Failed to copy:', err);
        });
      }

      // Initialize on page load
      document.addEventListener('DOMContentLoaded', function() {
        parseAllDatasets();
        initializeMap();
        initializeTable();
        setupJSONExpanders();
        setupEventHandlers();
      });

      // Map initialization
      function initializeMap() {
        map = L.map('map');

        // Create a custom pane for markers so they appear above other features
        map.createPane('markerPane');
        map.getPane('markerPane').style.zIndex = 650; // Higher than overlayPane (400)

        featureCyclers = {};

        // Restore tile and palette from localStorage (or use defaults)
        const savedTile = localStorage.getItem('samaki-tile') || 'light';
        const savedPalette = localStorage.getItem('samaki-palette') || 'muted';
        const tileSelector = document.getElementById('tile-selector');
        const paletteSelector = document.getElementById('palette-selector');
        if (tileSelector) tileSelector.value = savedTile;
        if (paletteSelector) paletteSelector.value = savedPalette;

        // Add initial tile layer
        const initProvider = tileProviders[savedTile] || tileProviders.osm;
        currentTileLayer = L.tileLayer(initProvider.url, {
          maxZoom: initProvider.maxZoom,
          attribution: initProvider.attribution
        }).addTo(map);

        // Create layer groups for each row in each dataset
        Object.values(allDatasets).forEach(function(dataset) {
          dataset.rowData.forEach(function(row) {
            const layerGroup = L.layerGroup();

            row.features.forEach(function(feature) {
              const color = getColorForRow(dataset.name, row.index);
              const markerColor = getMarkerColor(dataset.name, row.index);

              const geoLayer = L.geoJSON(feature, {
                pointToLayer: function(feature, latlng) {
                  const size = getMarkerSize();
                  // Recalculate color inside pointToLayer to ensure fresh value
                  const actualMarkerColor = getMarkerColor(dataset.name, row.index);

                  if (row.index === 0) {
                    console.log('pointToLayer: dataset=', dataset.name, 'row=', row.index, 'color=', actualMarkerColor, 'scaled=', markerScaleWithZoom, 'size=', size);
                  }

                  // All markers are circles with black borders
                  if (markerScaleWithZoom) {
                    // Use L.circle which scales with zoom (radius in meters)
                    const circle = L.circle(latlng, {
                      radius: size.scaledRadius, // meters
                      fillColor: actualMarkerColor,
                      color: '#000000',
                      weight: 2,
                      opacity: 1,
                      fillOpacity: 0.9,
                      pane: 'markerPane'
                    });
                    if (row.index === 0) {
                      console.log('Created L.circle with radius:', size.scaledRadius, 'meters, fillColor:', actualMarkerColor);
                    }
                    return circle;
                  } else {
                    // Use circleMarker for fixed size (radius in pixels)
                    const circleMarker = L.circleMarker(latlng, {
                      radius: size.circle,
                      fillColor: actualMarkerColor,
                      color: '#000000',
                      weight: 2,
                      opacity: 1,
                      fillOpacity: 0.9,
                      pane: 'markerPane'
                    });
                    if (row.index === 0) {
                      console.log('Created L.circleMarker with radius:', size.circle, 'pixels, fillColor:', actualMarkerColor);
                    }
                    return circleMarker;
                  }
                }
              });

              // Per-feature click state: 0=default, 1=highlighted (orange), 2=invisible
              let featureState = 0;
              const _sourceCol = feature.properties && feature.properties._sourceCol;

              function applyNonPointStyle(state) {
                geoLayer.eachLayer(function(layer) {
                  if (layer instanceof L.CircleMarker || layer instanceof L.Circle) return;
                  if (!layer.setStyle) return;
                  if (state === 0) {
                    layer.setStyle({ color: color, fillColor: color, fillOpacity: 0.25, weight: 4, opacity: 0.75 });
                  } else if (state === 1) {
                    layer.setStyle({ color: '#ff6600', fillColor: '#ff6600', fillOpacity: 0.5, weight: 8, opacity: 0.9 });
                    layer.bringToFront();
                  } else {
                    layer.setStyle({ opacity: 0, fillOpacity: 0 });
                  }
                });
              }

              applyNonPointStyle(0);

              // Register cycler so the table cell can trigger this feature's state change
              if (_sourceCol) {
                const _cycleKey = dataset.name + '::' + row.index + '::' + _sourceCol;
                if (!featureCyclers[_cycleKey]) featureCyclers[_cycleKey] = [];
                featureCyclers[_cycleKey].push(function() {
                  featureState = (featureState + 1) % 3;
                  applyNonPointStyle(featureState);
                  return featureState;
                });
              }

              // Add popup with row data
              const popupContent = buildPopupContent(dataset, row, feature);
              geoLayer.bindPopup(popupContent);

              // Click: cycle state, sync table cell, select table row
              geoLayer.on('click', function(e) {
                featureState = (featureState + 1) % 3;
                applyNonPointStyle(featureState);
                if (_sourceCol) {
                  const _cycleKey = dataset.name + '::' + row.index + '::' + _sourceCol;
                  const td = document.querySelector('[data-cycle-key="' + _cycleKey + '"]');
                  if (td) updateTableCellCycleVisual(td, featureState);
                }
                selectRowFromMap(dataset.name, row.index);
              });

              layerGroup.addLayer(geoLayer);
            });

            const layerKey = dataset.name + '::' + row.index;
            allLayerGroups[layerKey] = layerGroup;
            layerGroup.addTo(map);
          });
        });

        // Fit map to all features
        fitAllBounds();
      }

      // Update the visual appearance of a geo table cell based on cycle state.
      // state 0=default, 1=highlighted (orange), 2=invisible (faded/strikethrough)
      function updateTableCellCycleVisual(td, state) {
        const span = td.querySelector('.geo-summary');
        if (!span) return;
        if (state === 0) {
          span.style.color = '#666';
          span.style.fontWeight = '';
          span.style.textDecoration = '';
          span.title = 'Click to highlight on map';
        } else if (state === 1) {
          span.style.color = '#ff6600';
          span.style.fontWeight = 'bold';
          span.style.textDecoration = '';
          span.title = 'Click to hide';
        } else {
          span.style.color = '#ccc';
          span.style.fontWeight = '';
          span.style.textDecoration = 'line-through';
          span.title = 'Click to restore';
        }
      }

      function buildPopupContent(dataset, row, feature) {
        let html = '<div style="font-size: 11px; max-width: 300px;">';
        html += '<strong>' + dataset.name + ' - Row ' + (row.index + 1) + '</strong><br><br>';

        // Show first few key/value pairs from the row data
        let count = 0;
        const maxFields = 5;
        const maxValueLength = 50;

        for (let key in row.data) {
          if (count >= maxFields) break;

          // Skip geo columns
          if (dataset.geoColumns.includes(key)) continue;

          let value = row.data[key] || '';

          // Truncate long values
          if (value.length > maxValueLength) {
            value = value.substring(0, maxValueLength) + '...';
          }

          html += '<strong>' + key + ':</strong> ' + value + '<br>';
          count++;
        }

        html += '</div>';
        return html;
      }

      function fitAllBounds() {
        const allBounds = [];

        Object.values(allLayerGroups).forEach(function(layerGroup) {
          layerGroup.eachLayer(function(layer) {
            try {
              if (layer.getBounds) {
                const b = layer.getBounds();
                if (b && b.isValid()) {
                  console.log('fitAllBounds: layer bounds', b.toBBoxString());
                  allBounds.push(b);
                } else {
                  console.log('fitAllBounds: skipping invalid bounds from', layer);
                }
              } else if (layer.getLatLng) {
                const latlng = layer.getLatLng();
                allBounds.push(L.latLngBounds([latlng, latlng]));
              }
            } catch (e) {
              console.warn('fitAllBounds: error getting bounds:', e);
            }
          });
        });

        console.log('fitAllBounds: collected', allBounds.length, 'valid bounds');
        if (allBounds.length > 0) {
          const bounds = allBounds[0];
          allBounds.slice(1).forEach(function(b) {
            bounds.extend(b);
          });
          console.log('fitAllBounds: final bbox', bounds.toBBoxString());
          map.fitBounds(bounds, { padding: [20, 20] });
        } else {
          map.setView([0, 0], 2);
        }
      }

      // Table initialization - creates tabs and tables for all datasets
      function initializeTable() {
        const tabsContainer = document.getElementById('tabs');
        const wrappersContainer = document.getElementById('table-wrappers');

        // Populate key selector with columns from all datasets
        const allColumns = new Set();
        const excludedCols = new Set();

        Object.values(allDatasets).forEach(function(dataset) {
          dataset.columns.forEach(function(col) {
            allColumns.add(col);
          });
          dataset.geoColumns.forEach(function(col) {
            excludedCols.add(col);
          });
          dataset.latlonPairs.forEach(function(pair) {
            excludedCols.add(pair.lat);
            excludedCols.add(pair.lon);
          });
        });

        const keySelector = document.getElementById('key-selector');
        Array.from(allColumns).sort().forEach(function(col) {
          if (!excludedCols.has(col)) {
            const option = document.createElement('option');
            option.value = col;
            option.textContent = 'Key: ' + col;
            keySelector.appendChild(option);
          }
        });

        // Create a tab and table/viewer for each dataset
        Object.values(allDatasets).forEach(function(dataset, idx) {
          // Create tab
          const tab = document.createElement('div');
          tab.className = 'tab';
          if (idx === 0) tab.classList.add('active');
          tab.dataset.datasetName = dataset.name;

          // Add visibility checkbox
          const checkbox = document.createElement('input');
          checkbox.type = 'checkbox';
          checkbox.className = 'tab-checkbox';
          checkbox.checked = true;
          checkbox.dataset.datasetName = dataset.name;
          checkbox.onclick = function(e) {
            e.stopPropagation();
            toggleDatasetVisibility(dataset.name, this.checked);
          };

          // Add label with dataset name
          const label = document.createElement('span');
          label.className = 'tab-label';
          label.textContent = dataset.name;
          label.onclick = function() {
            switchToDataset(dataset.name);
          };

          tab.appendChild(checkbox);
          tab.appendChild(label);
          tabsContainer.appendChild(tab);

          // Create wrapper
          const wrapper = document.createElement('div');
          wrapper.className = 'table-wrapper';
          if (idx === 0) wrapper.classList.add('active');
          wrapper.id = 'wrapper-' + dataset.name;

          if (dataset.type === 'geojson') {
            // Create JSON viewer for GeoJSON
            const jsonViewer = document.createElement('div');
            jsonViewer.className = 'json-viewer';

            // Add header with fit button
            const header = document.createElement('div');
            header.className = 'json-viewer-header';

            const fitButton = document.createElement('button');
            fitButton.className = 'json-fit-button';
            fitButton.textContent = 'Jump';
            fitButton.dataset.datasetName = dataset.name;
            fitButton.addEventListener('click', function() {
              fitToDataset(this.dataset.datasetName);
            });

            header.appendChild(fitButton);

            // Add color picker with radio buttons
            const colorPicker = document.createElement('div');
            colorPicker.className = 'json-color-picker';
            colorPicker.dataset.datasetName = dataset.name;

            // Get current palette to show color options
            const palette = colorPalettes[currentPalette];
            for (let i = 0; i < palette.length; i++) {
              const wrapper = document.createElement('span');
              wrapper.className = 'color-radio-wrapper';

              const input = document.createElement('input');
              input.type = 'radio';
              input.name = 'color-' + dataset.name;
              input.value = i;
              input.id = 'color-' + dataset.name + '-' + i;
              input.className = 'color-radio-input';
              if (i === 0) {
                input.checked = true;
              }

              const label = document.createElement('label');
              label.htmlFor = input.id;
              label.className = 'color-radio-label';
              label.style.backgroundColor = palette[i];
              label.title = 'Color ' + (i + 1);

              input.addEventListener('change', function() {
                if (this.checked) {
                  switchDatasetColorOffset(colorPicker.dataset.datasetName, parseInt(this.value));
                }
              });

              wrapper.appendChild(input);
              wrapper.appendChild(label);
              colorPicker.appendChild(wrapper);
            }

            header.appendChild(colorPicker);

            // Store the color picker reference for this dataset
            dataset.colorPicker = colorPicker;
            dataset.colorOffsetAdjustment = 0;
            jsonViewer.appendChild(header);

            // Add content
            const content = document.createElement('div');
            content.className = 'json-viewer-content';
            content.innerHTML = renderJSON(dataset.rawGeoJSON, 0, dataset.name);
            jsonViewer.appendChild(content);

            wrapper.appendChild(jsonViewer);
            wrappersContainer.appendChild(wrapper);
          } else {
            // Create table for CSV

          // Create table
          const table = document.createElement('table');
          table.className = 'display';
          table.id = 'dataTable-' + dataset.name;
          table.style.width = '100%';

          // Table header
          const thead = document.createElement('thead');
          const headerRow = document.createElement('tr');

          // Color and # columns
          const colorTh = document.createElement('th');
          colorTh.textContent = 'Color';
          headerRow.appendChild(colorTh);

          const numTh = document.createElement('th');
          numTh.textContent = '#';
          headerRow.appendChild(numTh);

          dataset.columns.forEach(function(col) {
            const th = document.createElement('th');
            th.textContent = col;
            headerRow.appendChild(th);
          });

          thead.appendChild(headerRow);
          table.appendChild(thead);

          // Table body
          const tbody = document.createElement('tbody');
          dataset.rowData.forEach(function(row) {
            const tr = document.createElement('tr');
            tr.dataset.rowIndex = row.index;
            tr.dataset.datasetName = dataset.name;

            // Color indicator cell
            const colorTd = document.createElement('td');
            const colorSpan = document.createElement('span');
            colorSpan.className = 'color-indicator';
            colorSpan.style.backgroundColor = getColorForRow(dataset.name, row.index);
            colorTd.appendChild(colorSpan);
            tr.appendChild(colorTd);

            // Row number cell
            const numTd = document.createElement('td');
            numTd.textContent = row.index + 1;
            tr.appendChild(numTd);

            // Data cells
            dataset.columns.forEach(function(col) {
              const td = document.createElement('td');
              const cellValue = row.data[col] || '';

              // Check if this column contains geo data
              if (dataset.geoColumns.includes(col) && cellValue) {
                // Show summary instead of full geo data
                const summary = summarizeGeoData(cellValue);
                const summarySpan = document.createElement('span');
                summarySpan.className = 'geo-summary';
                summarySpan.textContent = summary;
                summarySpan.style.fontStyle = 'italic';
                summarySpan.style.color = '#666';
                summarySpan.style.cursor = 'pointer';
                summarySpan.title = 'Click to highlight on map';

                // Mark the td with a key so the map click handler can find it
                const _cycleKey = dataset.name + '::' + row.index + '::' + col;
                td.setAttribute('data-cycle-key', _cycleKey);

                // Clicking the summary cycles this column's features on the map
                summarySpan.onclick = function(e) {
                  e.stopPropagation();
                  const fns = featureCyclers[_cycleKey] || [];
                  let newState = 0;
                  fns.forEach(function(fn) { newState = fn(); });
                  updateTableCellCycleVisual(td, newState);
                };

                // Add copy button
                const copyBtn = document.createElement('button');
                copyBtn.textContent = '📋';
                copyBtn.style.marginLeft = '6px';
                copyBtn.style.padding = '2px 6px';
                copyBtn.style.fontSize = '11px';
                copyBtn.style.border = '1px solid #ccc';
                copyBtn.style.borderRadius = '3px';
                copyBtn.style.background = '#f8f9fa';
                copyBtn.style.cursor = 'pointer';
                copyBtn.title = 'Copy as GeoJSON';
                copyBtn.onclick = function(e) {
                  e.stopPropagation();
                  const geojson = tryParseGeo(cellValue, false, { isPolylineColumn: /polyline/i.test(col) });
                  copyToClipboard(geojson ? JSON.stringify(geojson, null, 2) : cellValue);
                  copyBtn.textContent = '✓';
                  setTimeout(function() {
                    copyBtn.textContent = '📋';
                  }, 1000);
                };

                // Add copy raw button
                const copyRawBtn = document.createElement('button');
                copyRawBtn.textContent = '⬆';
                copyRawBtn.style.marginLeft = '4px';
                copyRawBtn.style.padding = '2px 6px';
                copyRawBtn.style.fontSize = '11px';
                copyRawBtn.style.border = '1px solid #ccc';
                copyRawBtn.style.borderRadius = '3px';
                copyRawBtn.style.background = '#f8f9fa';
                copyRawBtn.style.cursor = 'pointer';
                copyRawBtn.title = 'Copy raw value';
                copyRawBtn.onclick = function(e) {
                  e.stopPropagation();
                  copyToClipboard(cellValue);
                  copyRawBtn.textContent = '✓';
                  setTimeout(function() {
                    copyRawBtn.textContent = '⬆';
                  }, 1000);
                };

                td.appendChild(summarySpan);
                td.appendChild(copyBtn);
                td.appendChild(copyRawBtn);
              } else {
                td.textContent = cellValue;
              }

              tr.appendChild(td);
            });

            tbody.appendChild(tr);
          });

            table.appendChild(tbody);
            wrapper.appendChild(table);
            wrappersContainer.appendChild(wrapper);

            // Initialize DataTable
            const dt = $('#dataTable-' + dataset.name).DataTable({
              pageLength: 10,
              searching: true,
              ordering: true,
              dom: 'lfitp', // length selector and filter at top, then info (centered), table, pagination
              infoCallback: function(settings, start, end, max, total, pre) {
                return 'Showing ' + start + ' to ' + end + ' of ' + total + ' entries (total: ' + max + ')';
              }
            });

            dataset.dataTable = dt;
          }
        });
      }

      // Track feature indices while rendering
      let featureIndexCounter = 0;

      // Render JSON as collapsible HTML
      function renderJSON(obj, depth = 0, datasetName = null, resetCounter = true) {
        if (resetCounter && depth === 0) {
          featureIndexCounter = 0;
        }

        const indent = '  '.repeat(depth);
        let html = '';

        if (obj === null) {
          return '<span class="json-null">null</span>';
        }

        if (typeof obj !== 'object') {
          if (typeof obj === 'string') {
            return '<span class="json-string">"' + escapeHtml(obj) + '"</span>';
          } else if (typeof obj === 'number') {
            return '<span class="json-number">' + obj + '</span>';
          } else if (typeof obj === 'boolean') {
            return '<span class="json-boolean">' + obj + '</span>';
          }
          return String(obj);
        }

        const isArray = Array.isArray(obj);
        const openBracket = isArray ? '[' : '{';
        const closeBracket = isArray ? ']' : '}';
        const entries = isArray ? obj.map((v, i) => [i, v]) : Object.entries(obj);

        if (entries.length === 0) {
          return '<span class="json-bracket">' + openBracket + closeBracket + '</span>';
        }

        // Check if this is a Feature
        const isFeature = obj.type === 'Feature' && obj.geometry;
        const featureIndex = isFeature ? featureIndexCounter++ : -1;

        const wrapperClass = isFeature ? 'json-feature' : '';
        const wrapperAttrs = isFeature && datasetName
          ? ` data-dataset="${datasetName}" data-feature-index="${featureIndex}"`
          : '';

        if (wrapperClass) {
          html += '<span class="' + wrapperClass + '"' + wrapperAttrs + '>';
        }

        html += '<span class="json-expandable">';
        html += '<span class="json-bracket">' + openBracket + '</span>';
        html += '</span>';
        html += '<div class="json-item json-collapsed">';

        entries.forEach(function([key, value], index) {
          const isLast = index === entries.length - 1;

          html += '<div>';
          if (!isArray) {
            html += '<span class="json-key">"' + escapeHtml(String(key)) + '"</span>: ';
          }

          if (value && typeof value === 'object') {
            html += renderJSON(value, depth + 1, datasetName, false);
          } else {
            html += renderJSON(value, depth + 1, datasetName, false);
          }

          if (!isLast) {
            html += ',';
          }
          html += '</div>';
        });

        html += '</div>';
        html += '<span class="json-bracket">' + closeBracket + '</span>';

        if (wrapperClass) {
          html += '</span>';
        }

        return html;
      }

      function escapeHtml(str) {
        const div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
      }

      // Setup JSON tree expand/collapse
      function setupJSONExpanders() {
        document.querySelectorAll('.json-expandable').forEach(function(el) {
          el.addEventListener('click', function(e) {
            e.stopPropagation();
            const item = this.nextElementSibling;
            if (item && item.classList.contains('json-item')) {
              if (this.classList.contains('expanded')) {
                this.classList.remove('expanded');
                item.classList.add('json-collapsed');
              } else {
                this.classList.add('expanded');
                item.classList.remove('json-collapsed');
              }
            }
          });
        });

        // Setup feature click handlers
        document.querySelectorAll('.json-feature').forEach(function(el) {
          el.addEventListener('click', function(e) {
            e.stopPropagation();
            const datasetName = this.dataset.dataset;
            const featureIndex = parseInt(this.dataset.featureIndex);

            if (datasetName && !isNaN(featureIndex)) {
              // Clear previous selection
              document.querySelectorAll('.json-feature-selected').forEach(function(sel) {
                sel.classList.remove('json-feature-selected');
              });

              // Mark this feature as selected
              this.classList.add('json-feature-selected');

              // Select the row (which zooms to the feature)
              selectRow(datasetName, featureIndex);
            }
          });
        });
      }

      // Switch to a different dataset tab
      function switchToDataset(datasetName) {
        // Update active tab
        document.querySelectorAll('.tab').forEach(function(tab) {
          if (tab.dataset.datasetName === datasetName) {
            tab.classList.add('active');
          } else {
            tab.classList.remove('active');
          }
        });

        // Update active table wrapper
        document.querySelectorAll('.table-wrapper').forEach(function(wrapper) {
          if (wrapper.id === 'wrapper-' + datasetName) {
            wrapper.classList.add('active');
          } else {
            wrapper.classList.remove('active');
          }
        });

        activeDatasetName = datasetName;
      }

      // Toggle visibility of all layers for a dataset
      function toggleDatasetVisibility(datasetName, visible) {
        Object.keys(allLayerGroups).forEach(function(layerKey) {
          if (layerKey.startsWith(datasetName + '::')) {
            const layerGroup = allLayerGroups[layerKey];
            if (visible) {
              layerGroup.addTo(map);
            } else {
              layerGroup.remove();
            }
          }
        });
      }

      // Event handlers
      function setupEventHandlers() {
        // Row click handler - delegated to handle all dataset tables
        $(document).on('click', '.table-wrapper tbody tr', function() {
          const rowIndex = parseInt($(this).data('row-index'));
          const datasetName = $(this).data('dataset-name');
          selectRow(datasetName, rowIndex);
        });

        // Show all button
        document.getElementById('show-all-btn').addEventListener('click', function() {
          showAll();
        });

        // Fullscreen button
        document.getElementById('fullscreen-btn').addEventListener('click', function() {
          toggleFullscreen();
        });

        // Tile provider selector
        document.getElementById('tile-selector').addEventListener('change', function(e) {
          localStorage.setItem('samaki-tile', e.target.value);
          switchTileProvider(e.target.value);
        });

        // Palette selector
        document.getElementById('palette-selector').addEventListener('change', function(e) {
          localStorage.setItem('samaki-palette', e.target.value);
          switchPalette(e.target.value);
        });

        // Key selector
        document.getElementById('key-selector').addEventListener('change', function(e) {
          switchKey(e.target.value);
        });

        // Marker size selector (combined with scale)
        document.getElementById('marker-size-selector').addEventListener('change', function(e) {
          const parts = e.target.value.split('-');
          const size = parts[0]; // tiny, small, medium, large
          const scale = parts[1]; // fixed or zoom
          console.log('Size selector changed to:', e.target.value, '-> size:', size, 'scale:', scale);
          switchMarkerSize(size);
          toggleMarkerScale(scale === 'zoom');
        });

        // Marker color selector
        document.getElementById('marker-color-selector').addEventListener('change', function(e) {
          switchMarkerColor(e.target.value);
        });

        // Divider drag handler
        setupDividerDrag();
      }

      function toggleFullscreen() {
        const mapContainer = document.getElementById('map-container');

        if (!document.fullscreenElement) {
          // Enter fullscreen
          document.documentElement.requestFullscreen().then(function() {
            mapContainer.classList.add('fullscreen');
            // Invalidate map size to ensure proper rendering
            setTimeout(function() {
              map.invalidateSize();
            }, 100);
          }).catch(function(err) {
            console.error('Error attempting to enable fullscreen:', err);
          });
        } else {
          // Exit fullscreen
          document.exitFullscreen().then(function() {
            mapContainer.classList.remove('fullscreen');
            // Invalidate map size to ensure proper rendering
            setTimeout(function() {
              map.invalidateSize();
            }, 100);
          });
        }
      }

      // Listen for fullscreen changes (e.g., user pressing ESC)
      document.addEventListener('fullscreenchange', function() {
        const mapContainer = document.getElementById('map-container');
        if (!document.fullscreenElement) {
          // Exited fullscreen
          mapContainer.classList.remove('fullscreen');
          setTimeout(function() {
            map.invalidateSize();
          }, 100);
        }
      });

      function switchTileProvider(providerKey) {
        const provider = tileProviders[providerKey];
        if (!provider) return;

        // Remove current tile layer
        if (currentTileLayer) {
          map.removeLayer(currentTileLayer);
        }

        // Add new tile layer
        currentTileLayer = L.tileLayer(provider.url, {
          maxZoom: provider.maxZoom,
          attribution: provider.attribution
        }).addTo(map);

        // Move tile layer to back so features are on top
        currentTileLayer.bringToBack();
      }

      // Helper function to update layer colors (polygons, lines - NOT markers)
      function updateLayerColors(layerGroup, newColor) {
        const isBorderPalette = !!borderPalettes[currentPalette];
        const borderStyle = borderPalettes[currentPalette];

        layerGroup.eachLayer(function(layer) {
          // For geoJSON layers that contain multiple sub-layers, iterate through them
          if (layer.eachLayer) {
            layer.eachLayer(function(subLayer) {
              // Skip markers (circles and circleMarkers) - they use getMarkerColor()
              if (subLayer instanceof L.CircleMarker || subLayer instanceof L.Circle) {
                return; // Don't update marker colors when palette changes
              }

              // Skip old divIcon markers (we don't use these anymore but keep for safety)
              if (subLayer.setIcon && subLayer.options && subLayer.options.icon) {
                return;
              }

              // Update sublayer style for polygons, lines, etc.
              if (subLayer.setStyle) {
                if (isBorderPalette) {
                  subLayer.setStyle({
                    color: borderStyle.borderColor,
                    fillColor: newColor,
                    weight: borderStyle.borderWidth,
                    fillOpacity: 0.6
                  });
                } else {
                  subLayer.setStyle({
                    color: newColor,
                    fillColor: newColor,
                    weight: 2,
                    fillOpacity: 0.3
                  });
                }
              }
            });
          }
          // Skip direct markers
          else if (layer instanceof L.CircleMarker || layer instanceof L.Circle) {
            return; // Don't update marker colors when palette changes
          }
          // Skip old divIcon markers
          else if (layer.setIcon && layer.options && layer.options.icon) {
            return;
          }
          // Update the layer's style for direct polygons, lines, etc.
          else if (layer.setStyle) {
            if (isBorderPalette) {
              layer.setStyle({
                color: borderStyle.borderColor,
                fillColor: newColor,
                weight: borderStyle.borderWidth,
                fillOpacity: 0.6
              });
            } else {
              layer.setStyle({
                color: newColor,
                fillColor: newColor,
                weight: 2,
                fillOpacity: 0.3
              });
            }
          }
        });
      }

      function switchKey(keyCol) {
        currentKey = keyCol;

        // Rebuild key color map
        buildKeyColorMap();

        // Update legend
        updateLegend();

        // Update all map features
        Object.keys(allLayerGroups).forEach(function(layerKey) {
          const [datasetName, rowIndex] = layerKey.split('::');
          const layerGroup = allLayerGroups[layerKey];
          const newColor = getColorForRow(datasetName, parseInt(rowIndex));

          updateLayerColors(layerGroup, newColor);
        });

        // Update table color indicators for all datasets
        Object.values(allDatasets).forEach(function(dataset) {
          const selector = '#dataTable-' + dataset.name + ' .color-indicator';
          document.querySelectorAll(selector).forEach(function(indicator, index) {
            if (index < dataset.rowData.length) {
              indicator.style.backgroundColor = getColorForRow(dataset.name, dataset.rowData[index].index);
            }
          });
        });
      }

      function switchMarkerSize(sizeKey) {
        if (!markerSizes[sizeKey]) return;

        currentMarkerSize = sizeKey;

        // Recreate all markers with new size
        recreateAllMarkers();
      }

      function toggleMarkerScale(enabled) {
        markerScaleWithZoom = enabled;

        // Recreate all markers with new scaling behavior
        recreateAllMarkers();
      }

      function switchMarkerColor(colorKey) {
        console.log('Switching marker color to:', colorKey);
        currentMarkerColor = colorKey;

        // Recreate all markers with new color
        recreateAllMarkers();
      }

      function recreateAllMarkers() {
        featureCyclers = {};

        // Store current map view
        const center = map.getCenter();
        const zoom = map.getZoom();

        // Rebuild all layer groups
        Object.values(allDatasets).forEach(function(dataset) {
          dataset.rowData.forEach(function(row) {
            const layerKey = dataset.name + '::' + row.index;
            const oldLayerGroup = allLayerGroups[layerKey];
            const wasOnMap = map.hasLayer(oldLayerGroup);

            // Remove old layer group
            if (wasOnMap) {
              oldLayerGroup.remove();
            }

            // Create new layer group
            const newLayerGroup = L.layerGroup();

            row.features.forEach(function(feature) {
              const color = getColorForRow(dataset.name, row.index);

              const geoLayer = L.geoJSON(feature, {
                pointToLayer: function(feature, latlng) {
                  const size = getMarkerSize();
                  // Recalculate color inside pointToLayer to ensure fresh value
                  const actualMarkerColor = getMarkerColor(dataset.name, row.index);

                  if (row.index === 0) {
                    console.log('recreateAllMarkers pointToLayer: dataset=', dataset.name, 'row=', row.index, 'color=', actualMarkerColor, 'scaled=', markerScaleWithZoom, 'size=', size);
                  }

                  // All markers are circles with black borders
                  if (markerScaleWithZoom) {
                    // Use L.circle which scales with zoom (radius in meters)
                    const circle = L.circle(latlng, {
                      radius: size.scaledRadius,
                      fillColor: actualMarkerColor,
                      color: '#000000',
                      weight: 2,
                      opacity: 1,
                      fillOpacity: 0.9,
                      pane: 'markerPane'
                    });
                    if (row.index === 0) {
                      console.log('Created L.circle with radius:', size.scaledRadius, 'meters, fillColor:', actualMarkerColor);
                    }
                    return circle;
                  } else {
                    // Use circleMarker for fixed size (radius in pixels)
                    const circleMarker = L.circleMarker(latlng, {
                      radius: size.circle,
                      fillColor: actualMarkerColor,
                      color: '#000000',
                      weight: 2,
                      opacity: 1,
                      fillOpacity: 0.9,
                      pane: 'markerPane'
                    });
                    if (row.index === 0) {
                      console.log('Created L.circleMarker with radius:', size.circle, 'pixels, fillColor:', actualMarkerColor);
                    }
                    return circleMarker;
                  }
                }
              });

              // Per-feature click state: 0=default, 1=highlighted (orange), 2=invisible
              // (states reset when markers are recreated via palette/size changes)
              let featureState = 0;
              const _sourceCol = feature.properties && feature.properties._sourceCol;

              function applyNonPointStyle(state) {
                geoLayer.eachLayer(function(layer) {
                  if (layer instanceof L.CircleMarker || layer instanceof L.Circle) return;
                  if (!layer.setStyle) return;
                  if (state === 0) {
                    layer.setStyle({ color: color, fillColor: color, fillOpacity: 0.25, weight: 4, opacity: 0.75 });
                  } else if (state === 1) {
                    layer.setStyle({ color: '#ff6600', fillColor: '#ff6600', fillOpacity: 0.5, weight: 8, opacity: 0.9 });
                    layer.bringToFront();
                  } else {
                    layer.setStyle({ opacity: 0, fillOpacity: 0 });
                  }
                });
              }

              applyNonPointStyle(0);

              // Register cycler so the table cell can trigger this feature's state change
              if (_sourceCol) {
                const _cycleKey = dataset.name + '::' + row.index + '::' + _sourceCol;
                if (!featureCyclers[_cycleKey]) featureCyclers[_cycleKey] = [];
                featureCyclers[_cycleKey].push(function() {
                  featureState = (featureState + 1) % 3;
                  applyNonPointStyle(featureState);
                  return featureState;
                });
              }

              // Add popup with row data
              const popupContent = buildPopupContent(dataset, row, feature);
              geoLayer.bindPopup(popupContent);

              // Click: cycle state, sync table cell, select table row
              geoLayer.on('click', function(e) {
                featureState = (featureState + 1) % 3;
                applyNonPointStyle(featureState);
                if (_sourceCol) {
                  const _cycleKey = dataset.name + '::' + row.index + '::' + _sourceCol;
                  const td = document.querySelector('[data-cycle-key="' + _cycleKey + '"]');
                  if (td) updateTableCellCycleVisual(td, featureState);
                }
                selectRowFromMap(dataset.name, row.index);
              });

              newLayerGroup.addLayer(geoLayer);
            });

            // Replace old layer group
            allLayerGroups[layerKey] = newLayerGroup;

            // Add back to map if it was visible before
            if (wasOnMap) {
              newLayerGroup.addTo(map);
            }
          });
        });

        // Restore map view
        map.setView(center, zoom);
      }

      function switchPalette(paletteKey) {
        if (!colorPalettes[paletteKey]) return;

        currentPalette = paletteKey;

        // Rebuild key color map with new palette
        buildKeyColorMap();

        // Update legend
        updateLegend();

        // Update all map features
        Object.keys(allLayerGroups).forEach(function(layerKey) {
          const [datasetName, rowIndex] = layerKey.split('::');
          const layerGroup = allLayerGroups[layerKey];
          const newColor = getColorForRow(datasetName, parseInt(rowIndex));

          updateLayerColors(layerGroup, newColor);
        });

        // Update table color indicators for all datasets
        Object.values(allDatasets).forEach(function(dataset) {
          const selector = '#dataTable-' + dataset.name + ' .color-indicator';
          document.querySelectorAll(selector).forEach(function(indicator, index) {
            if (index < dataset.rowData.length) {
              indicator.style.backgroundColor = getColorForRow(dataset.name, dataset.rowData[index].index);
            }
          });

          // Rebuild color picker for the new palette
          if (dataset.colorPicker) {
            const palette = colorPalettes[paletteKey];
            const currentOffset = dataset.colorOffsetAdjustment || 0;

            dataset.colorPicker.innerHTML = '';
            for (let i = 0; i < palette.length; i++) {
              const wrapper = document.createElement('span');
              wrapper.className = 'color-radio-wrapper';

              const input = document.createElement('input');
              input.type = 'radio';
              input.name = 'color-' + dataset.name;
              input.value = i;
              input.id = 'color-' + dataset.name + '-' + i;
              input.className = 'color-radio-input';
              if (i === currentOffset) {
                input.checked = true;
              }

              const label = document.createElement('label');
              label.htmlFor = input.id;
              label.className = 'color-radio-label';
              label.style.backgroundColor = palette[i];
              label.title = 'Color ' + (i + 1);

              input.addEventListener('change', function() {
                if (this.checked) {
                  switchDatasetColorOffset(dataset.colorPicker.dataset.datasetName, parseInt(this.value));
                }
              });

              wrapper.appendChild(input);
              wrapper.appendChild(label);
              dataset.colorPicker.appendChild(wrapper);
            }
          }
        });
      }

      function setupDividerDrag() {
        const divider = document.getElementById('divider');
        const mapContainer = document.getElementById('map-container');
        let isDragging = false;
        let startY = 0;
        let startHeight = 0;

        divider.addEventListener('mousedown', function(e) {
          isDragging = true;
          startY = e.clientY;
          startHeight = mapContainer.offsetHeight;
          document.body.style.cursor = 'ns-resize';
          document.body.style.userSelect = 'none';
          e.preventDefault();
        });

        document.addEventListener('mousemove', function(e) {
          if (!isDragging) return;

          const deltaY = e.clientY - startY;
          const newHeight = startHeight + deltaY;
          const windowHeight = window.innerHeight;

          // Constrain height between 20% and 80% of window height
          const minHeight = windowHeight * 0.2;
          const maxHeight = windowHeight * 0.8;

          if (newHeight >= minHeight && newHeight <= maxHeight) {
            mapContainer.style.height = newHeight + 'px';
            // Trigger Leaflet map resize
            if (map) {
              setTimeout(function() { map.invalidateSize(); }, 50);
            }
          }
        });

        document.addEventListener('mouseup', function() {
          if (isDragging) {
            isDragging = false;
            document.body.style.cursor = '';
            document.body.style.userSelect = '';
          }
        });
      }

      function selectRow(datasetName, rowIndex) {
        // Switch to the dataset's tab
        switchToDataset(datasetName);

        // Update table selection
        $('.table-wrapper tbody tr').removeClass('selected');
        $('.table-wrapper tbody tr[data-dataset-name="' + datasetName + '"][data-row-index="' + rowIndex + '"]').addClass('selected');

        // Hide all layers
        Object.values(allLayerGroups).forEach(function(lg) {
          lg.remove();
        });

        // Show only selected row's layer
        const layerKey = datasetName + '::' + rowIndex;
        const selectedLayer = allLayerGroups[layerKey];
        if (selectedLayer) {
          selectedLayer.addTo(map);

          // Fit bounds to selected features
          const bounds = [];
          selectedLayer.eachLayer(function(layer) {
            try {
              if (layer.getBounds) {
                const b = layer.getBounds();
                if (b && b.isValid()) bounds.push(b);
              } else if (layer.getLatLng) {
                const latlng = layer.getLatLng();
                bounds.push(L.latLngBounds([latlng, latlng]));
              }
            } catch (e) {}
          });

          if (bounds.length > 0) {
            const combinedBounds = bounds[0];
            bounds.slice(1).forEach(function(b) {
              combinedBounds.extend(b);
            });
            map.fitBounds(combinedBounds, { padding: [50, 50] });
          }
        }

        currentSelection = { datasetName: datasetName, rowIndex: rowIndex };
      }

      function selectRowFromMap(datasetName, rowIndex) {
        // Switch to the dataset's tab
        switchToDataset(datasetName);

        $('.table-wrapper tbody tr').removeClass('selected');

        const dataset = allDatasets[datasetName];
        if (!dataset) return;

        const dataRowIndex = dataset.rowData.findIndex(function(r) { return r.index === rowIndex; });
        if (dataRowIndex < 0) return;

        const dt = dataset.dataTable;
        const pageLength = dt.page.len();
        const pageNumber = Math.floor(dataRowIndex / pageLength);

        dt.page(pageNumber).draw('page');

        setTimeout(function() {
          const $targetRow = $('.table-wrapper tbody tr[data-dataset-name="' + datasetName + '"][data-row-index="' + rowIndex + '"]');
          if ($targetRow.length > 0) {
            $targetRow.addClass('selected');
            const rowElement = $targetRow[0];
            if (rowElement) {
              rowElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
          }
        }, 200);

        currentSelection = { datasetName: datasetName, rowIndex: rowIndex };
      }

      function showAll() {
        // Clear table selection
        $('.table-wrapper tbody tr').removeClass('selected');

        // Show all layers
        Object.values(allLayerGroups).forEach(function(lg) {
          lg.addTo(map);
        });

        // Fit to all bounds
        fitAllBounds();

        currentSelection = null;
      }

      function fitToDataset(datasetName) {
        const dataset = allDatasets[datasetName];
        if (!dataset) return;

        // Clear table/JSON selection highlighting
        $('.table-wrapper tbody tr').removeClass('selected');
        document.querySelectorAll('.json-feature-selected').forEach(function(sel) {
          sel.classList.remove('json-feature-selected');
        });

        // Keep all layers visible (don't hide anything)
        Object.values(allLayerGroups).forEach(function(lg) {
          lg.addTo(map);
        });

        // Collect bounds for this dataset only
        const datasetBounds = [];
        dataset.rowData.forEach(function(row) {
          const layerKey = datasetName + '::' + row.index;
          const layerGroup = allLayerGroups[layerKey];

          if (layerGroup) {
            layerGroup.eachLayer(function(layer) {
              try {
                if (layer.getBounds) {
                  const b = layer.getBounds();
                  if (b && b.isValid()) datasetBounds.push(b);
                } else if (layer.getLatLng) {
                  const latlng = layer.getLatLng();
                  datasetBounds.push(L.latLngBounds([latlng, latlng]));
                }
              } catch (e) {}
            });
          }
        });

        // Fit to dataset bounds
        if (datasetBounds.length > 0) {
          const combinedBounds = datasetBounds[0];
          datasetBounds.slice(1).forEach(function(b) {
            combinedBounds.extend(b);
          });
          map.fitBounds(combinedBounds, { padding: [50, 50] });
        }

        currentSelection = null;
      }

      function switchDatasetColorOffset(datasetName, offset) {
        const dataset = allDatasets[datasetName];
        if (!dataset) return;

        // Store the color offset adjustment for this dataset
        dataset.colorOffsetAdjustment = offset;

        // Update colors for all features in this dataset
        dataset.rowData.forEach(function(row) {
          const layerKey = datasetName + '::' + row.index;
          const layerGroup = allLayerGroups[layerKey];

          if (layerGroup) {
            const newColor = getColorForRow(datasetName, row.index);
            updateLayerColors(layerGroup, newColor);
          }
        });
      }
    </script>
  </body>
  </html>
  HTML

  # Replace placeholders with actual values
  $html = $html.subst('TITLE_PLACEHOLDER', $title, :g);
  $html = $html.subst('SCRIPT_TAGS_PLACEHOLDER', $script-tags);

  return $html;
}

=begin pod

=head1 NAME

Samaki::Plugout::CSVGeo -- Display CSV data or GeoJSON files on an interactive map

=head1 DESCRIPTION

Visualize CSV data containing geographic columns or GeoJSON files on an interactive map.

For CSV files: displays with a synchronized data table. Auto-detects lat/lon pairs, GeoJSON, WKT, WKB, and encoded polyline (polyline5/polyline6) formats in columns.

For GeoJSON files: displays with a collapsible JSON tree viewer for exploring the structure.

Includes map tile options, color palettes, and linked selection between map features and table rows. Multiple datasets can be loaded simultaneously with tabbed navigation.

=end pod
