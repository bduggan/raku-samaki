use Samaki::Plugout;
use Samaki::Utils;
use Duck::CSV;
use JSON::Fast;
use Log::Async;

unit class Samaki::Plugout::DeckGLBin does Samaki::Plugout;

has $.name = 'deckgl-bin';
has $.description = 'Visualize spatial bins (H3, geohash, GeoJSON/WKT) with 3D heights using deck.gl';
has $.clear-before = False;

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
  info "executing DeckGLBin with $path";

  my $file-basename = $path.basename.subst(/\. <[a..z A..Z]>+ $/, '');

  # Determine file type
  my $is-geojson = $path ~~ /\. [geojson|json] $/;
  my $file-type = $is-geojson ?? 'geojson' !! 'csv';

  my ($content, $numeric-cols-json);

  if $is-geojson {
    $content = slurp $path;
    $numeric-cols-json = to-json([]);
    info "Processing GeoJSON file";
  } else {
    # Read CSV
    my @rows = read-csv("$path");
    return unless @rows;

    # Get column names
    my @columns = @rows[0].keys.sort;

    # Detect numeric columns (potential value columns for height)
    my @numeric-cols = self.detect-numeric-columns(@rows, @columns);
    info "Detected numeric columns: {@numeric-cols.join(', ')}" if @numeric-cols;

    $content = slurp $path;
    $numeric-cols-json = to-json(@numeric-cols);
  }

  # Create out/ subdirectory
  my $out-dir = $data-dir.child('out');
  $out-dir.mkdir unless $out-dir.e;

  # Generate file paths
  my $js-file = $out-dir.child("{$file-basename}-deckgl-data.js");
  my $html-file = $out-dir.child("{$file-basename}-deckgl-bin.html");
  my $title = html-escape($data-dir.basename ~ " : " ~ $file-basename);

  # Find all existing deckgl-data.js files in the out directory
  my @all-data-files;
  my @dataset-info;

  for $out-dir.dir.sort -> $file {
    next unless $file ~~ /'-deckgl-data.js'$/;
    my $basename = $file.basename;
    my $dataset-name = $basename.subst('-deckgl-data.js', '');
    @all-data-files.push($basename);
    @dataset-info.push(%(
      filename => $basename,
      name => $dataset-name,
      is-current => ($basename eq "{$file-basename}-deckgl-data.js")
    ));
  }

  # Add current file if it's not in the list yet
  unless @all-data-files.grep("{$file-basename}-deckgl-data.js") {
    @all-data-files.push("{$file-basename}-deckgl-data.js");
    @dataset-info.push(%(
      filename => "{$file-basename}-deckgl-data.js",
      name => $file-basename,
      is-current => True
    ));
  }

  # Move current dataset to the front
  @dataset-info = @dataset-info.sort: { -$_<is-current> };

  info "Found {@all-data-files.elems} data file(s): {@all-data-files.join(', ')}";

  # Build JavaScript data file
  my $js-content = self.build-js-data($file-basename, $content, $numeric-cols-json, $file-type);

  # Build HTML content with all data files
  my $html = self.build-html($title, @dataset-info);

  # Write both files
  spurt $js-file, $js-content;
  spurt $html-file, $html;
  info "opening $html-file";
  shell-open $html-file;
}

method detect-numeric-columns(@rows, @columns) {
  my @numeric;
  my $sample-size = min(10, @rows.elems);

  for @columns -> $col {
    my $numeric-count = 0;
    for ^$sample-size -> $i {
      my $val = @rows[$i]{$col} // '';
      if $val ~~ /^ '-'? \d+ ['.' \d+]? $/ {
        $numeric-count++;
      }
    }
    # Consider numeric if >80% of samples are numeric
    if $numeric-count >= ($sample-size * 0.8) {
      @numeric.push($col);
    }
  }

  return @numeric;
}

method build-js-data($dataset-name, $content, $numeric-cols-json, $file-type) {
  my $escaped = $content.trans(['\\', '"', "\n", "\r"] => ['\\\\', '\\"', '\\n', '']);

  my $data-field;
  if $file-type eq 'geojson' {
    $data-field = qq[geojsonContent: "$escaped"];
  } else {
    $data-field = qq[csvContent: "$escaped"];
  }

  return qq:to/JS/;
  // Data and metadata for dataset: $dataset-name (type: $file-type)
  if (typeof window.datasets === 'undefined') \{
    window.datasets = \{\};
  \}
  window.datasets['$dataset-name'] = \{
    type: '$file-type',
    $data-field,
    numericColumns: $numeric-cols-json
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

    <!-- H3 for hex operations - must load before deck.gl (v3.x required by deck.gl 8.x) -->
    <script src="https://unpkg.com/h3-js@3.7.2/dist/h3-js.umd.js"></script>

    <!-- deck.gl and dependencies -->
    <script src="https://unpkg.com/deck.gl@8.9.35/dist.min.js"></script>
    <script src="https://unpkg.com/maplibre-gl@3.6.2/dist/maplibre-gl.js"></script>
    <link href="https://unpkg.com/maplibre-gl@3.6.2/dist/maplibre-gl.css" rel="stylesheet" />


    <!-- Papa Parse for CSV -->
    <script src="https://cdn.jsdelivr.net/npm/papaparse@5.4.1/papaparse.min.js"></script>

    <!-- wkx for WKT/WKB parsing -->
    <script src="https://cdn.jsdelivr.net/npm/wkx@0.5.0/dist/wkx.min.js"></script>

    <style>
      body {
        margin: 0;
        padding: 0;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
        background: #1a1a2e;
        color: #eee;
      }

      #container {
        position: relative;
        width: 100vw;
        height: 100vh;
      }

      #deck-canvas {
        width: 100%;
        height: 100%;
      }

      #controls {
        position: absolute;
        top: 10px;
        left: 10px;
        z-index: 1000;
        background: rgba(30, 30, 50, 0.9);
        padding: 12px 16px;
        border-radius: 8px;
        box-shadow: 0 4px 12px rgba(0,0,0,0.4);
        min-width: 220px;
      }

      #controls h3 {
        margin: 0 0 12px 0;
        font-size: 14px;
        font-weight: 500;
        color: #8be9fd;
      }

      .control-group {
        margin-bottom: 12px;
      }

      .control-group label {
        display: block;
        font-size: 11px;
        color: #bd93f9;
        margin-bottom: 4px;
        text-transform: uppercase;
        letter-spacing: 0.5px;
      }

      .control-group select, .control-group input[type="range"] {
        width: 100%;
        padding: 6px 8px;
        font-family: inherit;
        font-size: 12px;
        background: #ffffff;
        color: #333333;
        border: 1px solid #cccccc;
        border-radius: 4px;
        cursor: pointer;
      }

      .control-group select option {
        background: #ffffff;
        color: #333333;
        padding: 4px 8px;
      }

      .control-group select:hover, .control-group input[type="range"]:hover {
        border-color: #999999;
      }

      .range-value {
        font-size: 11px;
        color: #50fa7b;
        text-align: right;
        margin-top: 2px;
      }

      #stats {
        position: absolute;
        bottom: 10px;
        left: 10px;
        z-index: 1000;
        background: rgba(30, 30, 50, 0.9);
        padding: 10px 14px;
        border-radius: 6px;
        font-size: 11px;
        color: #f8f8f2;
      }

      #stats span {
        color: #50fa7b;
      }

      #layers-list {
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .layer-item {
        display: flex;
        align-items: center;
        gap: 6px;
        padding: 4px 6px;
        border-radius: 3px;
        cursor: pointer;
        user-select: none;
        background: rgba(255, 255, 255, 0.05);
        border: 1px solid transparent;
      }

      .layer-item:hover {
        background: rgba(255, 255, 255, 0.1);
      }

      .layer-item.dragging {
        opacity: 0.5;
        border: 1px dashed #8be9fd;
      }

      .layer-item.drag-over {
        border-top: 2px solid #8be9fd;
      }

      .layer-drag-handle {
        color: #64748b;
        font-size: 10px;
        cursor: grab;
        flex-shrink: 0;
      }

      .layer-item input[type="checkbox"] {
        cursor: pointer;
        flex-shrink: 0;
      }

      .layer-item label {
        cursor: pointer;
        color: #f8f8f2;
        font-size: 11px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      #legend {
        position: absolute;
        bottom: 10px;
        right: 10px;
        z-index: 1000;
        background: rgba(30, 30, 50, 0.9);
        padding: 10px 14px;
        border-radius: 6px;
      }

      #legend-title {
        font-size: 11px;
        color: #bd93f9;
        text-transform: uppercase;
        letter-spacing: 0.5px;
        margin-bottom: 8px;
      }

      #legend-gradient {
        width: 120px;
        height: 12px;
        border-radius: 2px;
        margin-bottom: 4px;
      }

      #legend-labels {
        display: flex;
        justify-content: space-between;
        font-size: 10px;
        color: #f8f8f2;
      }
    </style>
  </head>
  <body>
    <div id="container">
      <div id="deck-canvas"></div>

      <div id="controls">
        <h3>TITLE_PLACEHOLDER</h3>

        <div class="control-group" id="layers-group" style="display:none">
          <label>Layers</label>
          <div id="layers-list"></div>
        </div>

        <div class="control-group">
          <label>Value Column (Height)</label>
          <select id="value-column"></select>
        </div>

        <div class="control-group" id="latlon-style-group" style="display:none">
          <label>Point Style</label>
          <select id="latlon-style">
            <option value="column">Column (3D)</option>
            <option value="scatter">Scatter</option>
          </select>
        </div>

        <div class="control-group" id="column-radius-group" style="display:none">
          <label>Column Radius</label>
          <input type="range" id="column-radius" min="10" max="2000" step="10" value="100">
          <div class="range-value" id="column-radius-value">100</div>
        </div>

        <div class="control-group">
          <label id="elevation-scale-label">Elevation Scale</label>
          <input type="range" id="elevation-scale" min="1" max="500" step="1" value="10">
          <div class="range-value" id="elevation-scale-value">10</div>
        </div>

        <div class="control-group">
          <label>Opacity</label>
          <input type="range" id="opacity" min="0.1" max="1" step="0.05" value="0.8">
          <div class="range-value" id="opacity-value">0.8</div>
        </div>

        <div class="control-group">
          <label>Color Scheme</label>
          <select id="color-scheme">
            <option value="viridis" selected>Viridis</option>
            <option value="plasma">Plasma</option>
            <option value="inferno">Inferno</option>
            <option value="magma">Magma</option>
            <option value="turbo">Turbo</option>
            <option value="cividis">Cividis</option>
            <option value="warm">Warm</option>
            <option value="cool">Cool</option>
            <option value="spectral">Spectral</option>
            <option value="blues">Blues</option>
            <option value="reds">Reds</option>
            <option value="greens">Greens</option>
            <option value="oranges">Oranges</option>
            <option value="greyscale">Greyscale</option>
            <option value="bw">Black & White</option>
          </select>
        </div>

        <div class="control-group">
          <label>Base Map</label>
          <select id="basemap">
            <option value="dark">Dark</option>
            <option value="light" selected>Light</option>
            <option value="streets">Streets</option>
          </select>
        </div>
      </div>

      <div id="stats">
        Features: <span id="feature-count">0</span> |
        Type: <span id="bin-type">-</span>
      </div>

      <div id="legend">
        <div id="legend-title">Value</div>
        <div id="legend-gradient"></div>
        <div id="legend-labels">
          <span id="legend-min">0</span>
          <span id="legend-max">100</span>
        </div>
      </div>
    </div>

    <!-- External data files -->
    SCRIPT_TAGS_PLACEHOLDER

    <script>
      // Load wkx
      const wkx = require('wkx');
      const Buffer = require('buffer').Buffer;

      // Color schemes (RGB arrays for deck.gl)
      const colorSchemes = {
        viridis: [[68, 1, 84], [72, 40, 120], [62, 74, 137], [49, 104, 142], [38, 130, 142], [31, 158, 137], [53, 183, 121], [109, 205, 89], [180, 222, 44], [253, 231, 37]],
        plasma: [[13, 8, 135], [75, 3, 161], [125, 3, 168], [168, 34, 150], [203, 70, 121], [229, 107, 93], [248, 148, 65], [253, 195, 40], [240, 249, 33]],
        inferno: [[0, 0, 4], [40, 11, 84], [101, 21, 110], [159, 42, 99], [212, 72, 66], [245, 125, 21], [250, 193, 39], [252, 255, 164]],
        magma: [[0, 0, 4], [28, 16, 68], [79, 18, 123], [129, 37, 129], [181, 54, 122], [229, 80, 100], [251, 135, 97], [254, 194, 135], [252, 253, 191]],
        warm: [[110, 64, 170], [175, 57, 152], [221, 68, 119], [245, 102, 80], [244, 152, 48], [219, 206, 69], [175, 240, 91]],
        cool: [[110, 64, 170], [67, 97, 198], [45, 144, 206], [55, 186, 182], [94, 217, 141], [160, 234, 100]],
        spectral: [[158, 1, 66], [213, 62, 79], [244, 109, 67], [253, 174, 97], [254, 224, 139], [255, 255, 191], [230, 245, 152], [171, 221, 164], [102, 194, 165], [50, 136, 189], [94, 79, 162]],
        greyscale: [[0, 0, 0], [32, 32, 32], [64, 64, 64], [96, 96, 96], [128, 128, 128], [160, 160, 160], [192, 192, 192], [224, 224, 224], [255, 255, 255]],
        bw: [[0, 0, 0], [255, 255, 255]],
        blues: [[8, 29, 88], [37, 52, 148], [34, 94, 168], [29, 145, 192], [65, 182, 196], [127, 205, 187], [199, 233, 180], [237, 248, 177]],
        reds: [[103, 0, 13], [165, 15, 21], [203, 24, 29], [239, 59, 44], [251, 106, 74], [252, 146, 114], [252, 187, 161], [254, 224, 210]],
        greens: [[0, 68, 27], [0, 109, 44], [35, 139, 69], [65, 171, 93], [116, 196, 118], [161, 217, 155], [199, 233, 192], [229, 245, 224]],
        oranges: [[127, 39, 4], [166, 54, 3], [217, 72, 1], [241, 105, 19], [253, 141, 60], [253, 174, 107], [253, 208, 162], [254, 230, 206]],
        turbo: [[48, 18, 59], [86, 36, 163], [54, 92, 228], [14, 155, 215], [20, 205, 145], [110, 237, 56], [208, 238, 17], [254, 195, 21], [252, 128, 8], [221, 55, 4], [122, 4, 3]],
        cividis: [[0, 32, 77], [0, 58, 102], [46, 83, 112], [87, 107, 115], [122, 131, 116], [157, 156, 109], [194, 182, 92], [233, 210, 68], [253, 241, 42]]
      };

      // Base map styles
      const basemapStyles = {
        dark: 'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json',
        light: 'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json',
        streets: 'https://basemaps.cartocdn.com/gl/voyager-gl-style/style.json'
      };

      // State
      let parsedData = []; // merged features for value calculations
      let datasetLayers = {}; // { name: { features, type, binCol, visible, latlonStyle } }
      let activeLayerName = null;
      let binType = 'unknown';
      let binColumn = null;
      let valueColumn = null;
      let minValue = 0;
      let maxValue = 1;
      let deckgl = null;

      // Try to parse geo data (GeoJSON, WKT, WKB)
      function tryParseGeo(value) {
        if (!value || typeof value !== 'string') return null;
        const trimmed = value.trim();
        if (!trimmed) return null;

        // Try GeoJSON first
        try {
          const json = JSON.parse(trimmed);
          if (json.type && (json.coordinates || json.geometry || json.features)) {
            return json;
          }
        } catch (e) {}

        // Try WKT/EWKT
        try {
          return wkx.Geometry.parse(trimmed).toGeoJSON();
        } catch (e) {}

        // Try WKB hex
        try {
          return wkx.Geometry.parse(new Buffer(trimmed, 'hex')).toGeoJSON();
        } catch (e) {}

        return null;
      }

      // Convert decimal H3 index to hex string
      function h3DecimalToHex(decimal) {
        // Handle both string and number inputs
        const bigInt = BigInt(decimal);
        return bigInt.toString(16);
      }

      // Detect H3 index (supports both hex and decimal formats)
      function isH3Index(value) {
        if (value === null || value === undefined) return false;
        const str = String(value).trim();
        if (!str) return false;

        // Check if it's a 15-character hex string
        if (/^[0-9a-fA-F]{15}$/.test(str)) {
          try {
            return h3.h3IsValid(str);
          } catch (e) {
            return false;
          }
        }

        // Check if it's a decimal number (H3 indices are large integers)
        if (/^\d{15,20}$/.test(str)) {
          try {
            const hexStr = h3DecimalToHex(str);
            return h3.h3IsValid(hexStr);
          } catch (e) {
            return false;
          }
        }

        return false;
      }

      // Normalize H3 index to hex format
      function normalizeH3Index(value) {
        const str = String(value).trim();
        if (/^[0-9a-fA-F]{15}$/.test(str)) {
          return str;
        }
        if (/^\d{15,20}$/.test(str)) {
          return h3DecimalToHex(str);
        }
        return null;
      }

      // Geohash base32 alphabet
      const GEOHASH_CHARS = '0123456789bcdefghjkmnpqrstuvwxyz';

      // Decode geohash to lat/lon
      function decodeGeohash(hash) {
        hash = hash.toLowerCase();
        let latMin = -90, latMax = 90;
        let lonMin = -180, lonMax = 180;
        let isLon = true;

        for (const char of hash) {
          const idx = GEOHASH_CHARS.indexOf(char);
          if (idx === -1) return null;

          for (let bit = 4; bit >= 0; bit--) {
            const bitVal = (idx >> bit) & 1;
            if (isLon) {
              const mid = (lonMin + lonMax) / 2;
              if (bitVal) lonMin = mid;
              else lonMax = mid;
            } else {
              const mid = (latMin + latMax) / 2;
              if (bitVal) latMin = mid;
              else latMax = mid;
            }
            isLon = !isLon;
          }
        }

        return {
          latitude: (latMin + latMax) / 2,
          longitude: (lonMin + lonMax) / 2,
          latMin, latMax, lonMin, lonMax
        };
      }

      // Detect geohash
      function isGeohash(value) {
        if (!value || typeof value !== 'string') return false;
        const trimmed = value.trim().toLowerCase();
        // Geohashes are base32 encoded, typically 4-12 characters
        if (!/^[0-9b-hjkmnp-z]{4,12}$/.test(trimmed)) return false;
        const decoded = decodeGeohash(trimmed);
        return decoded !== null;
      }

      // Get geohash boundary as GeoJSON polygon
      function geohashToPolygon(hash) {
        const decoded = decodeGeohash(hash.toLowerCase());
        if (!decoded) return null;
        const { latMin, latMax, lonMin, lonMax } = decoded;
        return {
          type: 'Polygon',
          coordinates: [[
            [lonMin, latMin],
            [lonMax, latMin],
            [lonMax, latMax],
            [lonMin, latMax],
            [lonMin, latMin]
          ]]
        };
      }

      // Detect lat/lon column pairs
      function detectLatLonColumns(columns) {
        const used = {};
        for (const col of columns) {
          if (used[col]) continue;
          const colLower = col.toLowerCase();
          const isLat = colLower === 'lat' || colLower === 'latitude' ||
                        colLower.endsWith('_lat') || colLower.endsWith('_latitude');
          if (!isLat) continue;

          // Extract base prefix
          let base = col.replace(/_?lat(itude)?$/i, '');

          // Build longitude candidates
          const candidates = [];
          if (base) {
            candidates.push(base + '_lon', base + '_lng', base + '_longitude');
          }
          candidates.push('lon', 'lng', 'longitude');

          // Find matching column (case-insensitive)
          let lonCol = null;
          for (const candidate of candidates) {
            const matched = columns.find(c => !used[c] && c.toLowerCase() === candidate.toLowerCase());
            if (matched) { lonCol = matched; break; }
          }

          if (lonCol) {
            return { lat: col, lon: lonCol };
          }
        }
        return null;
      }

      // Collect numeric columns from all datasets
      let numericColumns = [];

      // Parse a single CSV dataset and return its features
      function parseOneDataset(csvContent, datasetNumericCols) {
        const parsed = Papa.parse(csvContent, {
          header: true,
          skipEmptyLines: true,
          dynamicTyping: true
        });

        if (!parsed.data || parsed.data.length === 0) {
          return { features: [], columns: [], detectedType: null };
        }

        const columns = Object.keys(parsed.data[0]);
        const sampleRow = parsed.data[0];

        // Detect bin column type
        let detectedType = null;
        let detectedBinColumn = null;

        for (const col of columns) {
          const val = String(sampleRow[col] || '');

          if (isH3Index(val)) {
            detectedBinColumn = col;
            detectedType = 'h3';
            console.log('Detected H3 column:', col);
            break;
          }

          if (/geohash/i.test(col) && isGeohash(val)) {
            detectedBinColumn = col;
            detectedType = 'geohash';
            console.log('Detected geohash column:', col);
            break;
          }

          const geo = tryParseGeo(val);
          if (geo) {
            detectedBinColumn = col;
            detectedType = 'geojson';
            console.log('Detected GeoJSON/WKT column:', col);
            break;
          }
        }

        // Try lat/lon column detection if no spatial column found
        if (!detectedType) {
          const latLonPair = detectLatLonColumns(columns);
          if (latLonPair) {
            detectedType = 'latlon';
            detectedBinColumn = latLonPair.lat + '/' + latLonPair.lon;
            console.log('Detected lat/lon columns:', latLonPair.lat, latLonPair.lon);
          }
        }

        if (!detectedType) {
          return { features: [], columns: columns, detectedType: null };
        }

        // Convert data to features
        const features = [];

        for (const row of parsed.data) {
          let feature = null;

          if (detectedType === 'h3') {
            const rawH3 = row[detectedBinColumn];
            const h3Index = normalizeH3Index(rawH3);
            if (h3Index && h3.h3IsValid(h3Index)) {
              const [lat, lng] = h3.h3ToGeo(h3Index);
              feature = {
                h3Index: h3Index,
                center: [lng, lat],
                properties: { ...row }
              };
            }
          } else if (detectedType === 'geohash') {
            const hash = String(row[detectedBinColumn] || '').trim();
            if (isGeohash(hash)) {
              const geometry = geohashToPolygon(hash);
              const decoded = decodeGeohash(hash);
              feature = {
                geometry: geometry,
                center: [decoded.longitude, decoded.latitude],
                properties: { ...row }
              };
            }
          } else if (detectedType === 'geojson') {
            const val = String(row[detectedBinColumn] || '');
            const geo = tryParseGeo(val);
            if (geo) {
              let geometry;
              if (geo.type === 'Feature') {
                geometry = geo.geometry;
              } else if (geo.type === 'FeatureCollection' && geo.features.length > 0) {
                geometry = geo.features[0].geometry;
              } else {
                geometry = geo;
              }

              const center = getCentroid(geometry);
              feature = {
                geometry: geometry,
                center: center,
                properties: { ...row }
              };
            }
          } else if (detectedType === 'latlon') {
            const parts = detectedBinColumn.split('/');
            const lat = parseFloat(row[parts[0]]);
            const lon = parseFloat(row[parts[1]]);
            if (!isNaN(lat) && !isNaN(lon) && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
              feature = {
                center: [lon, lat],
                properties: { ...row }
              };
            }
          }

          if (feature) {
            features.push(feature);
          }
        }

        return { features, columns, detectedType, binCol: detectedBinColumn };
      }

      // Parse a GeoJSON dataset and return features
      function parseGeoJSONDataset(geojsonContent) {
        let geojson;
        try {
          geojson = JSON.parse(geojsonContent);
        } catch (e) {
          console.error('Failed to parse GeoJSON:', e);
          return { features: [], columns: [], detectedType: null };
        }

        let features = [];
        let rawFeatures = [];

        if (geojson.type === 'FeatureCollection') {
          rawFeatures = geojson.features || [];
        } else if (geojson.type === 'Feature') {
          rawFeatures = [geojson];
        } else if (geojson.type && geojson.coordinates) {
          rawFeatures = [{ type: 'Feature', geometry: geojson, properties: {} }];
        }

        for (const f of rawFeatures) {
          const geometry = f.geometry;
          if (!geometry) continue;
          const center = getCentroid(geometry);
          features.push({
            geometry: geometry,
            center: center,
            properties: f.properties || {}
          });
        }

        // Collect property keys as columns
        const columns = [];
        if (features.length > 0) {
          for (const key of Object.keys(features[0].properties)) {
            if (!columns.includes(key)) columns.push(key);
          }
        }

        return { features, columns, detectedType: 'geojson', binCol: null };
      }

      // Parse all datasets from window.datasets
      function parseData() {
        const datasetNames = Object.keys(window.datasets || {});
        if (datasetNames.length === 0) {
          console.error('No datasets found');
          return;
        }

        console.log('Parsing', datasetNames.length, 'datasets:', datasetNames);

        let allFeatures = [];
        let allColumns = [];
        let firstType = null;
        let firstBinCol = null;

        for (const name of datasetNames) {
          const ds = window.datasets[name];
          let result;

          if (ds.type === 'geojson') {
            result = parseGeoJSONDataset(ds.geojsonContent);
          } else {
            result = parseOneDataset(ds.csvContent, ds.numericColumns || []);
          }

          // Merge numeric columns
          for (const col of (ds.numericColumns || [])) {
            if (!numericColumns.includes(col)) numericColumns.push(col);
          }

          if (result.detectedType) {
            if (!firstType) {
              firstType = result.detectedType;
              firstBinCol = result.binCol;
            }
            datasetLayers[name] = {
              features: result.features,
              type: result.detectedType,
              binCol: result.binCol,
              visible: true,
              latlonStyle: 'column',
              columnRadius: 100,
              colorScheme: 'viridis',
              opacity: 0.8
            };
            allFeatures = allFeatures.concat(result.features);
            console.log('Dataset "' + name + '":', result.features.length, 'features of type', result.detectedType);
          } else {
            console.warn('Dataset "' + name + '": no spatial data detected');
          }

          // Merge columns
          for (const col of result.columns) {
            if (!allColumns.includes(col)) allColumns.push(col);
          }
        }

        if (!firstType) {
          console.error('No spatial data detected in any dataset');
          document.getElementById('bin-type').textContent = 'None found';
          return;
        }

        binType = firstType;
        binColumn = firstBinCol;
        document.getElementById('bin-type').textContent = firstType + ' (' + datasetNames.length + ' layer' + (datasetNames.length > 1 ? 's' : '') + ')';

        parsedData = allFeatures;
        document.getElementById('feature-count').textContent = allFeatures.length;
        console.log('Total:', allFeatures.length, 'features');

        // Populate value column selector
        populateValueColumns(allColumns);

        // Build layers panel if multiple datasets
        buildLayersPanel();
      }

      // Layer ordering — controls render order (last = on top for hover)
      let layerOrder = [];

      function buildLayersPanel() {
        const names = Object.keys(datasetLayers);
        if (names.length < 2) {
          document.getElementById('layers-group').style.display = 'none';
          return;
        }

        document.getElementById('layers-group').style.display = '';
        layerOrder = names.slice(); // initial order
        renderLayersList();
      }

      function renderLayersList() {
        const list = document.getElementById('layers-list');
        list.innerHTML = '';

        for (let i = 0; i < layerOrder.length; i++) {
          const name = layerOrder[i];
          const item = document.createElement('div');
          item.className = 'layer-item';
          item.dataset.layerName = name;
          if (name === activeLayerName) {
            item.style.borderColor = '#8be9fd';
          }

          // Click anywhere on the item (except checkbox) selects the layer
          item.addEventListener('click', (e) => {
            if (e.target.type === 'checkbox') return;
            selectActiveLayer(name);
          });

          const handle = document.createElement('span');
          handle.className = 'layer-drag-handle';
          handle.draggable = true;
          handle.textContent = '⠿';

          const cb = document.createElement('input');
          cb.type = 'checkbox';
          cb.checked = datasetLayers[name].visible;
          cb.id = 'layer-cb-' + name;
          cb.addEventListener('change', (e) => {
            e.stopPropagation();
            datasetLayers[name].visible = cb.checked;
            rebuildParsedData();
            updateLayers();
          });

          const lbl = document.createElement('label');
          lbl.textContent = name;

          item.appendChild(handle);
          item.appendChild(cb);
          item.appendChild(lbl);

          // Drag events on the handle only
          handle.addEventListener('dragstart', (e) => {
            e.dataTransfer.setData('text/plain', name);
            item.classList.add('dragging');
          });
          handle.addEventListener('dragend', () => {
            item.classList.remove('dragging');
            list.querySelectorAll('.drag-over').forEach(el => el.classList.remove('drag-over'));
          });
          item.addEventListener('dragover', (e) => {
            e.preventDefault();
            item.classList.add('drag-over');
          });
          item.addEventListener('dragleave', () => {
            item.classList.remove('drag-over');
          });
          item.addEventListener('drop', (e) => {
            e.preventDefault();
            item.classList.remove('drag-over');
            const draggedName = e.dataTransfer.getData('text/plain');
            if (draggedName === name) return;

            // Reorder
            const fromIdx = layerOrder.indexOf(draggedName);
            const toIdx = layerOrder.indexOf(name);
            layerOrder.splice(fromIdx, 1);
            layerOrder.splice(toIdx, 0, draggedName);

            renderLayersList();
            updateLayers();
          });

          list.appendChild(item);
        }
      }

      function rebuildParsedData() {
        let allFeatures = [];
        for (const name of Object.keys(datasetLayers)) {
          if (datasetLayers[name].visible) {
            allFeatures = allFeatures.concat(datasetLayers[name].features);
          }
        }
        parsedData = allFeatures;
        document.getElementById('feature-count').textContent = allFeatures.length;
        updateValueRange();
      }

      // Get rough centroid of a geometry
      function getCentroid(geometry) {
        if (!geometry || !geometry.coordinates) return null;

        function flattenCoords(coords) {
          if (typeof coords[0] === 'number') return [coords];
          return coords.flatMap(flattenCoords);
        }

        const flat = flattenCoords(geometry.coordinates);
        if (flat.length === 0) return null;

        const sum = flat.reduce((acc, c) => [acc[0] + c[0], acc[1] + c[1]], [0, 0]);
        return [sum[0] / flat.length, sum[1] / flat.length];
      }

      // Populate value column dropdown
      function populateValueColumns(columns) {
        const select = document.getElementById('value-column');
        select.innerHTML = '<option value="_count">Count (1 per feature)</option>';

        // Add numeric columns
        for (const col of numericColumns) {
          const option = document.createElement('option');
          option.value = col;
          option.textContent = col;
          select.appendChild(option);
        }

        // Also add any column that looks numeric in the actual data
        for (const col of columns) {
          if (numericColumns.includes(col)) continue;

          if (parsedData.length > 0) {
            const val = parsedData[0].properties[col];
            if (typeof val === 'number' || (typeof val === 'string' && !isNaN(parseFloat(val)))) {
              const option = document.createElement('option');
              option.value = col;
              option.textContent = col;
              select.appendChild(option);
            }
          }
        }

        // Select first meaningful numeric column (skip lat/lon/id columns)
        function isGoodValueCol(col) {
          const lower = col.toLowerCase();
          if (lower === 'lat' || lower === 'latitude' || lower === 'lon' || lower === 'lng' || lower === 'longitude') return false;
          if (lower.endsWith('_lat') || lower.endsWith('_latitude') || lower.endsWith('_lon') || lower.endsWith('_lng') || lower.endsWith('_longitude')) return false;
          if (lower === 'id' || lower.endsWith('_id') || lower.startsWith('id_')) return false;
          return true;
        }

        const bestCol = numericColumns.find(isGoodValueCol);
        if (bestCol) {
          select.value = bestCol;
          valueColumn = bestCol;
        } else if (numericColumns.length > 0) {
          select.value = numericColumns[0];
          valueColumn = numericColumns[0];
        } else {
          valueColumn = '_count';
        }

        updateValueRange();
      }

      // Update min/max values for current column
      function updateValueRange() {
        if (parsedData.length === 0) return;

        let min = Infinity, max = -Infinity;
        for (let i = 0; i < parsedData.length; i++) {
          let val;
          if (valueColumn === '_count') {
            val = 1;
          } else {
            val = parseFloat(parsedData[i].properties[valueColumn]);
          }
          if (!isNaN(val)) {
            if (val < min) min = val;
            if (val > max) max = val;
          }
        }

        if (min !== Infinity) {
          minValue = min;
          maxValue = max;
        } else {
          minValue = 0;
          maxValue = 1;
        }

        document.getElementById('legend-min').textContent = minValue.toFixed(1);
        document.getElementById('legend-max').textContent = maxValue.toFixed(1);

        updateLegendGradient();
      }

      // Update legend gradient
      function updateLegendGradient() {
        const scheme = document.getElementById('color-scheme').value;
        const colors = colorSchemes[scheme];
        const gradient = colors.map((c, i) => {
          const pct = (i / (colors.length - 1)) * 100;
          return `rgb(${c.join(',')}) ${pct}%`;
        }).join(', ');

        document.getElementById('legend-gradient').style.background = `linear-gradient(to right, ${gradient})`;
      }

      // Get color for value (returns [R, G, B, A])
      function getColor(value, scheme) {
        const colors = colorSchemes[scheme || 'viridis'];

        const range = maxValue - minValue || 1;
        const normalized = (value - minValue) / range;
        const clamped = Math.max(0, Math.min(1, normalized));

        const idx = clamped * (colors.length - 1);
        const lower = Math.floor(idx);
        const upper = Math.min(lower + 1, colors.length - 1);
        const t = idx - lower;

        return [
          Math.round(colors[lower][0] + (colors[upper][0] - colors[lower][0]) * t),
          Math.round(colors[lower][1] + (colors[upper][1] - colors[lower][1]) * t),
          Math.round(colors[lower][2] + (colors[upper][2] - colors[lower][2]) * t),
          255
        ];
      }

      // Get value for a feature
      function getValue(feature) {
        if (valueColumn === '_count') return 1;
        const val = parseFloat(feature.properties[valueColumn]);
        return isNaN(val) ? 0 : val;
      }

      // Initialize deck.gl
      function initDeck() {
        const basemap = document.getElementById('basemap').value;

        // Calculate initial view state from data
        let initialViewState = {
          longitude: 0,
          latitude: 0,
          zoom: 2,
          pitch: 45,
          bearing: 0
        };

        if (parsedData.length > 0) {
          let sumLng = 0, sumLat = 0, count = 0;
          let minLng = 180, maxLng = -180, minLat = 90, maxLat = -90;
          for (let i = 0; i < parsedData.length; i++) {
            const c = parsedData[i].center;
            if (!c) continue;
            sumLng += c[0]; sumLat += c[1]; count++;
            if (c[0] < minLng) minLng = c[0];
            if (c[0] > maxLng) maxLng = c[0];
            if (c[1] < minLat) minLat = c[1];
            if (c[1] > maxLat) maxLat = c[1];
          }
          if (count > 0) {
            const avgLng = sumLng / count;
            const avgLat = sumLat / count;

            const lngRange = maxLng - minLng;
            const latRange = maxLat - minLat;
            const range = Math.max(lngRange, latRange);

            let zoom = 12;
            if (range > 100) zoom = 2;
            else if (range > 50) zoom = 3;
            else if (range > 20) zoom = 4;
            else if (range > 10) zoom = 5;
            else if (range > 5) zoom = 6;
            else if (range > 1) zoom = 8;
            else if (range > 0.5) zoom = 10;
            else if (range > 0.1) zoom = 12;
            else if (range > 0.01) zoom = 14;

            initialViewState = {
              longitude: avgLng,
              latitude: avgLat,
              zoom: zoom,
              pitch: 45,
              bearing: 0
            };
          }
        }

        const layers = buildLayers();

        deckgl = new deck.DeckGL({
          container: 'deck-canvas',
          mapStyle: basemapStyles[basemap],
          initialViewState: initialViewState,
          controller: true,
          layers: layers,
          getTooltip: getTooltip
        });
      }

      // Build deck.gl layers — one per visible dataset, in layerOrder
      function buildLayers() {
        const elevationScale = parseFloat(document.getElementById('elevation-scale').value);
        const layers = [];

        const names = layerOrder.length > 0 ? layerOrder : Object.keys(datasetLayers);
        for (let i = 0; i < names.length; i++) {
          const name = names[i];
          const ds = datasetLayers[name];
          if (!ds.visible) continue;

          const dsType = ds.type;
          const features = ds.features;
          const idSuffix = '-' + i;
          const scheme = ds.colorScheme || 'viridis';
          const opacity = ds.opacity !== undefined ? ds.opacity : 0.8;

          if (dsType === 'h3') {
            layers.push(new deck.H3HexagonLayer({
              id: 'h3-layer' + idSuffix,
              data: features,
              pickable: true,
              wireframe: true,
              filled: true,
              extruded: true,
              opacity: opacity,
              getHexagon: d => d.h3Index,
              getElevation: d => getValue(d) * elevationScale,
              getFillColor: d => getColor(getValue(d), scheme),
              getLineColor: [255, 255, 255, 80],
              lineWidthMinPixels: 1
            }));

          } else if (dsType === 'latlon') {
            if (ds.latlonStyle === 'scatter') {
              layers.push(new deck.ScatterplotLayer({
                id: 'scatterplot-layer' + idSuffix,
                data: features,
                pickable: true,
                opacity: opacity,
                filled: true,
                radiusMinPixels: 2,
                radiusMaxPixels: 100,
                getPosition: d => d.center,
                getRadius: d => Math.max(1, getValue(d) * elevationScale),
                getFillColor: d => getColor(getValue(d), scheme),
                getLineColor: [255, 255, 255, 80],
                lineWidthMinPixels: 1
              }));
            } else {
              layers.push(new deck.ColumnLayer({
                id: 'column-layer' + idSuffix,
                data: features,
                pickable: true,
                opacity: opacity,
                extruded: true,
                diskResolution: 12,
                radius: ds.columnRadius || 100,
                getPosition: d => d.center,
                getElevation: d => getValue(d) * elevationScale,
                getFillColor: d => getColor(getValue(d), scheme),
                getLineColor: [255, 255, 255, 80],
                lineWidthMinPixels: 1
              }));
            }

          } else {
            // geojson/geohash polygons
            const geojsonData = {
              type: 'FeatureCollection',
              features: features.filter(f => f.geometry).map(f => ({
                type: 'Feature',
                geometry: f.geometry,
                properties: {
                  ...f.properties,
                  _value: getValue(f)
                }
              }))
            };

            layers.push(new deck.GeoJsonLayer({
              id: 'geojson-layer' + idSuffix,
              data: geojsonData,
              pickable: true,
              filled: true,
              extruded: true,
              wireframe: true,
              opacity: opacity,
              getElevation: f => f.properties._value * elevationScale,
              getFillColor: f => getColor(f.properties._value, scheme),
              getLineColor: [255, 255, 255, 80],
              lineWidthMinPixels: 1
            }));
          }
        }

        return layers;
      }

      // Update layers
      function updateLayers() {
        if (!deckgl) return;
        const layers = buildLayers();
        deckgl.setProps({ layers: layers });
      }

      // Get tooltip content
      function getTooltip({object}) {
        if (!object) return null;

        let html = '<div style="background: rgba(30,30,50,0.95); padding: 8px 12px; border-radius: 4px; font-size: 12px; color: #f8f8f2;">';

        if (object.h3Index) {
          // H3 feature
          const val = getValue(object);
          html += `<div style="font-weight: 600; color: #8be9fd; margin-bottom: 4px;">H3: ${object.h3Index}</div>`;
          html += `<div>Value: <span style="color: #50fa7b;">${val.toFixed(2)}</span></div>`;

          let count = 0;
          for (const key in object.properties) {
            if (count >= 3) break;
            if (key === binColumn) continue;
            html += `<div>${key}: <span style="color: #50fa7b;">${object.properties[key]}</span></div>`;
            count++;
          }
        } else if (object.center) {
          // Lat/lon feature
          const val = getValue(object);
          html += `<div style="font-weight: 600; color: #8be9fd; margin-bottom: 4px;">Value: ${val.toFixed(2)}</div>`;

          let count = 0;
          for (const key in object.properties) {
            if (count >= 4) break;
            html += `<div>${key}: <span style="color: #50fa7b;">${object.properties[key]}</span></div>`;
            count++;
          }
        } else if (object.properties) {
          // GeoJSON feature
          const val = object.properties._value !== undefined ? object.properties._value : 0;
          html += `<div style="font-weight: 600; color: #8be9fd; margin-bottom: 4px;">Value: ${val.toFixed(2)}</div>`;

          let count = 0;
          for (const key in object.properties) {
            if (key.startsWith('_')) continue;
            if (count >= 4) break;
            html += `<div>${key}: <span style="color: #50fa7b;">${object.properties[key]}</span></div>`;
            count++;
          }
        }

        html += '</div>';
        return { html };
      }

      // Setup event handlers
      function setupControls() {
        document.getElementById('value-column').addEventListener('change', (e) => {
          valueColumn = e.target.value;
          updateValueRange();
          updateLayers();
        });

        document.getElementById('elevation-scale').addEventListener('input', (e) => {
          document.getElementById('elevation-scale-value').textContent = e.target.value;
          updateLayers();
        });

        document.getElementById('opacity').addEventListener('input', (e) => {
          const val = parseFloat(e.target.value);
          document.getElementById('opacity-value').textContent = val.toFixed(2);
          if (activeLayerName && datasetLayers[activeLayerName]) {
            datasetLayers[activeLayerName].opacity = val;
          }
          updateLayers();
        });

        document.getElementById('color-scheme').addEventListener('change', (e) => {
          if (activeLayerName && datasetLayers[activeLayerName]) {
            datasetLayers[activeLayerName].colorScheme = e.target.value;
          }
          updateLegendGradient();
          updateLayers();
        });

        document.getElementById('basemap').addEventListener('change', (e) => {
          if (deckgl) {
            deckgl.setProps({ mapStyle: basemapStyles[e.target.value] });
          }
        });

        document.getElementById('latlon-style').addEventListener('change', (e) => {
          if (activeLayerName && datasetLayers[activeLayerName]) {
            datasetLayers[activeLayerName].latlonStyle = e.target.value;
          }
          const label = document.getElementById('elevation-scale-label');
          label.textContent = e.target.value === 'scatter' ? 'Radius' : 'Elevation Scale';
          document.getElementById('column-radius-group').style.display = e.target.value === 'scatter' ? 'none' : '';
          updateLayers();
        });

        document.getElementById('column-radius').addEventListener('input', (e) => {
          const val = parseInt(e.target.value);
          document.getElementById('column-radius-value').textContent = val;
          if (activeLayerName && datasetLayers[activeLayerName]) {
            datasetLayers[activeLayerName].columnRadius = val;
          }
          updateLayers();
        });
      }

      // Select a layer as active (updates controls to reflect its settings)
      function selectActiveLayer(name) {
        activeLayerName = name;
        const ds = datasetLayers[name];

        // Update latlon style control visibility
        if (ds && ds.type === 'latlon') {
          document.getElementById('latlon-style-group').style.display = '';
          document.getElementById('latlon-style').value = ds.latlonStyle || 'column';
          const label = document.getElementById('elevation-scale-label');
          label.textContent = ds.latlonStyle === 'scatter' ? 'Radius' : 'Elevation Scale';

          // Show column radius control when in column mode
          const showRadius = ds.latlonStyle !== 'scatter';
          document.getElementById('column-radius-group').style.display = showRadius ? '' : 'none';
          document.getElementById('column-radius').value = ds.columnRadius || 100;
          document.getElementById('column-radius-value').textContent = ds.columnRadius || 100;
        } else {
          document.getElementById('latlon-style-group').style.display = 'none';
          document.getElementById('column-radius-group').style.display = 'none';
          document.getElementById('elevation-scale-label').textContent = 'Elevation Scale';
        }

        // Update color scheme and opacity to active layer's values
        if (ds) {
          document.getElementById('color-scheme').value = ds.colorScheme || 'viridis';
          const opVal = ds.opacity !== undefined ? ds.opacity : 0.8;
          document.getElementById('opacity').value = opVal;
          document.getElementById('opacity-value').textContent = opVal.toFixed(2);
          updateLegendGradient();
        }

        // Highlight active layer in list
        document.querySelectorAll('.layer-item').forEach(el => {
          el.style.borderColor = el.dataset.layerName === name ? '#8be9fd' : 'transparent';
        });
      }

      // Initialize
      document.addEventListener('DOMContentLoaded', () => {
        parseData();

        // Select first layer as active
        const names = Object.keys(datasetLayers);
        if (names.length > 0) {
          selectActiveLayer(names[0]);
        } else if (binType === 'latlon') {
          document.getElementById('latlon-style-group').style.display = '';
        }

        initDeck();
        setupControls();
        updateLegendGradient();
      });
    </script>
  </body>
  </html>
  HTML

  # Replace placeholders
  $html = $html.subst('TITLE_PLACEHOLDER', $title, :g);
  $html = $html.subst('SCRIPT_TAGS_PLACEHOLDER', $script-tags);

  return $html;
}

=begin pod

=head1 NAME

Samaki::Plugout::DeckGLBin -- 3D spatial bin visualization using deck.gl

=head1 DESCRIPTION

Renders CSV data containing spatial bins as an interactive 3D visualization
using deck.gl. Bins are extruded vertically based on a numeric value column,
with color also mapped to value.

=head1 SUPPORTED COLUMN TYPES

The plugout auto-detects spatial data in the following formats:

=head2 H3 Hexagonal Indices

H3 cell indices in either hexadecimal (15 chars) or decimal format. Rendered
using deck.gl's native C<H3HexagonLayer>.

    h3,population
    8928308280fffff,15000
    89283082873ffff,12500

Decimal format (as exported by DuckDB/PostGIS):

    cell,count
    617549798007111679,19
    617549797987450879,10

=head2 Geohashes

Base32-encoded geohash strings (4-12 characters). Converted to rectangular
polygons.

    geohash,temperature
    u4pruydqqvj,22.5
    u4pruydqqvm,23.1

=head2 GeoJSON Geometry

JSON-encoded GeoJSON geometry objects, Features, or FeatureCollections.

    geometry,sales
    "{""type"":""Polygon"",""coordinates"":[[[0,0],[1,0],[1,1],[0,1],[0,0]]]}",5000

=head2 WKT (Well-Known Text)

OGC Well-Known Text geometry strings, including EWKT with SRID prefixes.

    shape,count
    POLYGON((0 0, 1 0, 1 1, 0 1, 0 0)),42

=head2 WKB (Well-Known Binary)

Hexadecimal-encoded WKB geometry, as exported from PostGIS.

    geom,value
    0101000020E6100000...,250

=head1 VALUE COLUMNS

Any numeric column can be used for height/color.

=end pod
