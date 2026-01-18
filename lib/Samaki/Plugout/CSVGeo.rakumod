use Samaki::Plugout;
use Samaki::Utils;
use Duck::CSV;
use JSON::Fast;
use Log::Async;

unit class Samaki::Plugout::CSVGeo does Samaki::Plugout;

has $.name = 'csv-geo';
has $.description = 'View CSV data with GeoJSON columns on an interactive map';
has $.clear-before = False;

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
  info "executing CSVGeo with $path";

  # Read CSV
  my @rows = read-csv("$path");
  return unless @rows;

  # Get column names
  my @columns = @rows[0].keys.sort;

  # Detect lat/lon column pairs (still useful for lat/lon columns)
  my @latlon-pairs = self.detect-latlon-pairs(@columns);

  info "Detected lat/lon pairs: {@latlon-pairs.map({ $_<lat> ~ '/' ~ $_<lon> }).join(', ')}" if @latlon-pairs;

  # Read the raw CSV content
  my $csv-content = slurp $path;

  # Prepare metadata for JavaScript
  my $latlon-pairs-json = to-json(@latlon-pairs);

  # Generate HTML file
  my $html-file = $data-dir.child("{$name}-csv-geo.html");
  my $title = html-escape($data-dir.basename ~ " : " ~ $name);

  # Build HTML content
  my $html = self.build-html($title, $csv-content, $latlon-pairs-json);

  # Write and open
  spurt $html-file, $html;
  info "opening $html-file";
  shell-open $html-file;
}


method detect-latlon-pairs(@columns) {
  my @pairs;
  my %used-cols;

  for @columns -> $col {
    next if %used-cols{$col};

    # Check if this is a latitude column
    my $col-lc = $col.lc;
    my $is-lat = $col-lc eq 'lat'
              || $col-lc eq 'latitude'
              || $col ~~ /'_lat' $/
              || $col ~~ /'_latitude' $/;

    next unless $is-lat;

    # Try to find matching longitude column
    # Extract base name (e.g., "start_lat" -> "start")
    my $base = $col;
    $base ~~ s/_?lat(itude)?$//;

    # Try to find matching longitude column with various patterns
    my $lon-col;
    my @candidates;
    if $base {
      @candidates = ($base ~ '_lon', $base ~ '_lng', $base ~ '_longitude');
    }
    @candidates.append('lon', 'lng', 'longitude');

    for @candidates -> $candidate {
      if $candidate ~~ any(@columns) && !%used-cols{$candidate} {
        $lon-col = $candidate;
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


method build-html($title, $csv-content, $latlon-pairs-json) {
  # Escape the CSV content for embedding in HTML/JavaScript
  # Need to escape backslashes, quotes, and newlines for JavaScript string literals
  my $csv-escaped = $csv-content.trans(['\\', '"', "\n", "\r"] => ['\\\\', '\\"', '\\n', '']);

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

      #map {
        height: 100%;
        width: 100%;
      }

      #controls {
        position: absolute;
        top: 10px;
        left: 50px;
        z-index: 1000;
        background: white;
        padding: 8px 12px;
        border-radius: 4px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.2);
        display: flex;
        gap: 8px;
        align-items: center;
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
      }

      #show-all-btn:hover {
        background: #2563eb;
      }

      #tile-selector, #palette-selector {
        padding: 5px 8px;
        font-family: inherit;
        font-size: 12px;
        border: 1px solid #e2e8f0;
        border-radius: 3px;
        background: white;
        cursor: pointer;
      }

      #tile-selector:hover, #palette-selector:hover {
        border-color: #cbd5e1;
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
        overflow: auto;
        padding: 20px;
        background: white;
        min-height: 100px;
      }

      h2 {
        margin: 0 0 15px 0;
        color: #2c3e50;
        font-size: 18px;
        font-weight: 500;
      }

      #dataTable {
        width: 100% !important;
        font-size: 12px;
      }

      #dataTable thead th {
        background-color: #f1f5f9;
        color: #2c3e50;
        padding: 8px 6px;
      }

      #dataTable tbody td {
        padding: 6px;
      }

      #dataTable tbody tr {
        cursor: pointer;
      }

      #dataTable tbody tr:hover {
        background-color: #f1f5f9;
      }

      #dataTable tbody tr.selected {
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

      .custom-marker-icon {
        background: transparent;
        border: none;
      }
    </style>
  </head>
  <body>
    <div id="map-container">
      <div id="map"></div>
      <div id="controls">
        <button id="show-all-btn">Show All</button>
        <select id="tile-selector">
          <option value="osm" selected>OpenStreetMap</option>
          <option value="light">Light (Positron)</option>
          <option value="dark">Dark (Dark Matter)</option>
          <option value="satellite">Satellite</option>
          <option value="topo">Topographic</option>
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
      </div>
    </div>

    <div id="divider"></div>

    <div id="table-container">
      <h2>TITLE_PLACEHOLDER</h2>
      <table id="dataTable" class="display">
        <thead>
          <tr>
            <th>Color</th>
            <th>#</th>
          </tr>
        </thead>
        <tbody>
        </tbody>
      </table>
    </div>

    <script>
      // CSV data and metadata from Raku
      const csvContent = "CSV_CONTENT_PLACEHOLDER";
      const latlonPairs = LATLON_PAIRS_PLACEHOLDER;

      // Load wkx and Buffer from the browserified bundle
      const wkx = require('wkx');
      const Buffer = require('buffer').Buffer;

      // Parse CSV and build row data
      let rowData = [];
      let columns = [];
      let geoColumns = [];

      // Try to parse a value as geo data using wkx
      function tryParseGeo(value, debug) {
        if (!value || typeof value !== 'string') return null;
        const trimmed = value.trim();
        if (!trimmed) return null;

        // First try: if it's valid JSON with geo keywords, use it directly
        try {
          const json = JSON.parse(trimmed);
          const jsonStr = JSON.stringify(json).toLowerCase();
          const hasGeoKeywords = jsonStr.includes('feature') ||
                                 jsonStr.includes('coordinates') ||
                                 jsonStr.includes('geometry') ||
                                 jsonStr.includes('polygon') ||
                                 jsonStr.includes('point') ||
                                 jsonStr.includes('linestring');

          if (hasGeoKeywords) {
            if (debug) console.log('✓ Detected as GeoJSON (direct)');
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
            // Otherwise, just return it and let Leaflet handle it
            return json;
          }
        } catch (e) {
          // Not valid JSON, continue to other parsers
        }

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
              if (debug) console.log('✓ Parsed as', parser.name);
              return result;
            }
          } catch (e) {
            if (debug) console.log('✗', parser.name, 'failed:', e.message);
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
          let foundGeo = false;
          for (let i = 0; i < sampleSize; i++) {
            const val = rows[i][col];
            if (!val) continue;

            // Enable debug for first value in each column
            const debug = i === 0;
            if (debug) {
              console.log('\n--- Column:', col, '---');
              console.log('Sample length:', val.length);
            }

            const parsed = tryParseGeo(val, debug);
            if (parsed) {
              detected.push(col);
              foundGeo = true;
              console.log('✓ Column "' + col + '" detected as geo data');
              break;
            }
          }

          if (!foundGeo) {
            const firstVal = rows[0][col];
            if (firstVal && firstVal.length > 50) {
              console.log('✗ Column "' + col + '" not detected (sample: ' + firstVal.substring(0, 50) + '...)');
            }
          }
        }

        console.log('\n=== Detection Complete ===');
        console.log('Found', detected.length, 'geo columns:', detected.join(', '));
        return detected;
      }

      function parseCSVData() {
        const parsed = Papa.parse(csvContent, {
          header: true,
          skipEmptyLines: true
        });

        if (!parsed.data || parsed.data.length === 0) {
          console.error('No CSV data parsed');
          return;
        }

        // Get columns from the first row
        columns = Object.keys(parsed.data[0]);

        // Detect geo columns using wkx
        geoColumns = detectGeoColumns(parsed.data, columns);

        // Build rowData array
        parsed.data.forEach(function(row, index) {
          const rowObj = {
            index: index,
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

            try {
              const geojson = tryParseGeo(val);
              if (!geojson) return;

              // Handle different GeoJSON types
              if (geojson.type === 'Feature') {
                rowObj.features.push(geojson);
              } else if (geojson.type === 'FeatureCollection') {
                geojson.features.forEach(function(f) {
                  rowObj.features.push(f);
                });
              } else if (geojson.type && geojson.coordinates) {
                // Bare geometry - wrap in Feature
                rowObj.features.push({
                  type: 'Feature',
                  geometry: geojson,
                  properties: {}
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
      }

      // Global state
      let map;
      let allLayerGroups = {};
      let currentSelection = null;
      let dataTable;
      let currentTileLayer;
      let currentPalette = 'muted';

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

      // Helper function to get color for a row index
      function getColorForRow(rowIndex) {
        const palette = colorPalettes[currentPalette];
        return palette[rowIndex % palette.length];
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
        parseCSVData();
        initializeMap();
        initializeTable();
        setupEventHandlers();
      });

      // Map initialization
      function initializeMap() {
        map = L.map('map');

        // Add default tile layer (OpenStreetMap)
        currentTileLayer = L.tileLayer(tileProviders.osm.url, {
          maxZoom: tileProviders.osm.maxZoom,
          attribution: tileProviders.osm.attribution
        }).addTo(map);

        // Create layer groups for each row
        rowData.forEach(function(row) {
          const layerGroup = L.layerGroup();

          row.features.forEach(function(feature) {
            const color = getColorForRow(row.index);
            const geoLayer = L.geoJSON(feature, {
              style: {
                color: color,
                fillColor: color,
                fillOpacity: 0.3,
                weight: 2
              },
              pointToLayer: function(feature, latlng) {
                // Check if this is a Point geometry
                if (feature.geometry && feature.geometry.type === 'Point') {
                  // Create a custom colored icon for Point geometries
                  const markerIcon = L.divIcon({
                    className: 'custom-marker-icon',
                    html: '<div style="background-color: ' + color + '; width: 20px; height: 20px; border-radius: 50% 50% 50% 0; transform: rotate(-45deg); border: 2px solid white; box-shadow: 0 2px 4px rgba(0,0,0,0.3);"></div>',
                    iconSize: [24, 24],
                    iconAnchor: [12, 24],
                    popupAnchor: [0, -24]
                  });
                  return L.marker(latlng, { icon: markerIcon });
                } else {
                  // Use circle markers for other point-like features
                  return L.circleMarker(latlng, {
                    radius: 8,
                    fillColor: color,
                    color: '#ffffff',
                    weight: 2,
                    opacity: 1,
                    fillOpacity: 0.8
                  });
                }
              }
            });

            // Add popup with row data
            const popupContent = buildPopupContent(row, feature);
            geoLayer.bindPopup(popupContent);

            // Add click handler to select and scroll to corresponding table row
            geoLayer.on('click', function(e) {
              selectRowFromMap(row.index);
            });

            layerGroup.addLayer(geoLayer);
          });

          allLayerGroups[row.index] = layerGroup;
          layerGroup.addTo(map);
        });

        // Fit map to all features
        fitAllBounds();
      }

      function buildPopupContent(row, feature) {
        let html = '<div style="font-size: 11px; max-width: 300px;">';
        html += '<strong>Row ' + (row.index + 1) + '</strong><br><br>';

        // Show first few key/value pairs from the row data
        let count = 0;
        const maxFields = 5;
        const maxValueLength = 50;

        for (let key in row.data) {
          if (count >= maxFields) break;

          // Skip geo columns
          if (geoColumns.includes(key)) continue;

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
            if (layer.getBounds) {
              allBounds.push(layer.getBounds());
            } else if (layer.getLatLng) {
              const latlng = layer.getLatLng();
              allBounds.push(L.latLngBounds([latlng, latlng]));
            }
          });
        });

        if (allBounds.length > 0) {
          const bounds = allBounds[0];
          allBounds.slice(1).forEach(function(b) {
            bounds.extend(b);
          });
          map.fitBounds(bounds, { padding: [20, 20] });
        } else {
          map.setView([0, 0], 2);
        }
      }

      // Table initialization
      function initializeTable() {
        // Build table header
        const thead = document.querySelector('#dataTable thead tr');
        columns.forEach(function(col) {
          const th = document.createElement('th');
          th.textContent = col;
          thead.appendChild(th);
        });

        // Build table body
        const tbody = document.querySelector('#dataTable tbody');
        rowData.forEach(function(row) {
          const tr = document.createElement('tr');
          tr.dataset.rowIndex = row.index;

          // Color indicator cell
          const colorTd = document.createElement('td');
          const colorSpan = document.createElement('span');
          colorSpan.className = 'color-indicator';
          colorSpan.style.backgroundColor = getColorForRow(row.index);
          colorTd.appendChild(colorSpan);
          tr.appendChild(colorTd);

          // Row number cell
          const numTd = document.createElement('td');
          numTd.textContent = row.index + 1;
          tr.appendChild(numTd);

          // Data cells
          columns.forEach(function(col) {
            const td = document.createElement('td');
            const cellValue = row.data[col] || '';

            // Check if this column contains geo data
            if (geoColumns.includes(col) && cellValue) {
              // Show summary instead of full geo data
              const summary = summarizeGeoData(cellValue);
              const summarySpan = document.createElement('span');
              summarySpan.textContent = summary;
              summarySpan.style.fontStyle = 'italic';
              summarySpan.style.color = '#666';

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
                // Convert to GeoJSON before copying
                const geojson = tryParseGeo(cellValue);
                if (geojson) {
                  copyToClipboard(JSON.stringify(geojson, null, 2));
                } else {
                  copyToClipboard(cellValue);
                }
                copyBtn.textContent = '✓';
                setTimeout(function() {
                  copyBtn.textContent = '📋';
                }, 1000);
              };

              td.appendChild(summarySpan);
              td.appendChild(copyBtn);
            } else {
              td.textContent = cellValue;
            }

            tr.appendChild(td);
          });

          tbody.appendChild(tr);
        });

        // Initialize DataTable
        dataTable = $('#dataTable').DataTable({
          pageLength: 10,
          searching: true,
          ordering: true,
          createdRow: function(row, data, dataIndex) {
            // Preserve the data-row-index attribute
            const originalIndex = rowData[dataIndex].index;
            $(row).attr('data-row-index', originalIndex);
          }
        });
      }

      // Event handlers
      function setupEventHandlers() {
        // Row click handler
        $('#dataTable tbody').on('click', 'tr', function() {
          const rowIndex = parseInt($(this).data('row-index'));
          selectRow(rowIndex);
        });

        // Show all button
        document.getElementById('show-all-btn').addEventListener('click', function() {
          showAll();
        });

        // Tile provider selector
        document.getElementById('tile-selector').addEventListener('change', function(e) {
          switchTileProvider(e.target.value);
        });

        // Palette selector
        document.getElementById('palette-selector').addEventListener('change', function(e) {
          switchPalette(e.target.value);
        });

        // Divider drag handler
        setupDividerDrag();
      }

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

      function switchPalette(paletteKey) {
        if (!colorPalettes[paletteKey]) return;

        currentPalette = paletteKey;

        // Check if this is a border-based palette
        const borderStyle = borderPalettes[paletteKey];
        const isBorderPalette = !!borderStyle;

        // Update all map features
        Object.keys(allLayerGroups).forEach(function(rowIndex) {
          const layerGroup = allLayerGroups[rowIndex];
          const newColor = getColorForRow(parseInt(rowIndex));

          layerGroup.eachLayer(function(layer) {
            // For geoJSON layers that contain multiple sub-layers, iterate through them
            if (layer.eachLayer) {
              layer.eachLayer(function(subLayer) {
                // Check if sublayer is a marker
                if (subLayer.setIcon && subLayer.options && subLayer.options.icon) {
                  const oldIcon = subLayer.options.icon;
                  if (oldIcon.options && oldIcon.options.className === 'custom-marker-icon') {
                    const markerBorder = isBorderPalette ? borderStyle.borderColor : '#ffffff';
                    const newIcon = L.divIcon({
                      className: 'custom-marker-icon',
                      html: '<div style="background-color: ' + newColor + '; width: 20px; height: 20px; border-radius: 50% 50% 50% 0; transform: rotate(-45deg); border: 2px solid ' + markerBorder + '; box-shadow: 0 2px 4px rgba(0,0,0,0.3);"></div>',
                      iconSize: [24, 24],
                      iconAnchor: [12, 24],
                      popupAnchor: [0, -24]
                    });
                    subLayer.setIcon(newIcon);
                  }
                }
                // Update sublayer style for circle markers, polygons, lines, etc.
                else if (subLayer.setStyle) {
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
            // Check if this layer itself is a direct marker (not wrapped in geoJSON)
            else if (layer.setIcon && layer.options && layer.options.icon) {
              const oldIcon = layer.options.icon;
              if (oldIcon.options && oldIcon.options.className === 'custom-marker-icon') {
                const markerBorder = isBorderPalette ? borderStyle.borderColor : '#ffffff';
                const newIcon = L.divIcon({
                  className: 'custom-marker-icon',
                  html: '<div style="background-color: ' + newColor + '; width: 20px; height: 20px; border-radius: 50% 50% 50% 0; transform: rotate(-45deg); border: 2px solid ' + markerBorder + '; box-shadow: 0 2px 4px rgba(0,0,0,0.3);"></div>',
                  iconSize: [24, 24],
                  iconAnchor: [12, 24],
                  popupAnchor: [0, -24]
                });
                layer.setIcon(newIcon);
              }
            }
            // Update the layer's style for direct polygons, lines, etc. (not wrapped in geoJSON)
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
        });

        // Update table color indicators
        document.querySelectorAll('.color-indicator').forEach(function(indicator, index) {
          if (index < rowData.length) {
            indicator.style.backgroundColor = getColorForRow(rowData[index].index);
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

      function selectRow(rowIndex) {
        // Update table selection
        $('#dataTable tbody tr').removeClass('selected');
        $('#dataTable tbody tr[data-row-index="' + rowIndex + '"]').addClass('selected');

        // Hide all layers
        Object.values(allLayerGroups).forEach(function(lg) {
          lg.remove();
        });

        // Show only selected row's layer
        const selectedLayer = allLayerGroups[rowIndex];
        if (selectedLayer) {
          selectedLayer.addTo(map);

          // Fit bounds to selected features
          const bounds = [];
          selectedLayer.eachLayer(function(layer) {
            if (layer.getBounds) {
              bounds.push(layer.getBounds());
            } else if (layer.getLatLng) {
              const latlng = layer.getLatLng();
              bounds.push(L.latLngBounds([latlng, latlng]));
            }
          });

          if (bounds.length > 0) {
            const combinedBounds = bounds[0];
            bounds.slice(1).forEach(function(b) {
              combinedBounds.extend(b);
            });
            map.fitBounds(combinedBounds, { padding: [50, 50] });
          }
        }

        currentSelection = rowIndex;
      }

      function selectRowFromMap(rowIndex) {
        $('#dataTable tbody tr').removeClass('selected');

        const dataRowIndex = rowData.findIndex(function(r) { return r.index === rowIndex; });
        if (dataRowIndex < 0) return;

        const dt = dataTable;
        const pageLength = dt.page.len();
        const pageNumber = Math.floor(dataRowIndex / pageLength);

        dt.page(pageNumber).draw('page');

        setTimeout(function() {
          const $targetRow = $('#dataTable tbody tr[data-row-index="' + rowIndex + '"]');
          if ($targetRow.length > 0) {
            $targetRow.addClass('selected');
            const rowElement = $targetRow[0];
            if (rowElement) {
              rowElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
          }
        }, 200);

        currentSelection = rowIndex;
      }

      function showAll() {
        // Clear table selection
        $('#dataTable tbody tr').removeClass('selected');

        // Show all layers
        Object.values(allLayerGroups).forEach(function(lg) {
          lg.addTo(map);
        });

        // Fit to all bounds
        fitAllBounds();

        currentSelection = null;
      }
    </script>
  </body>
  </html>
  HTML

  # Replace placeholders with actual values
  $html = $html.subst('TITLE_PLACEHOLDER', $title, :g);
  $html = $html.subst('CSV_CONTENT_PLACEHOLDER', $csv-escaped);
  $html = $html.subst('LATLON_PAIRS_PLACEHOLDER', $latlon-pairs-json);

  return $html;
}

=begin pod

=head1 NAME

Samaki::Plugout::CSVGeo -- Display CSV data on an interactive map

=head1 DESCRIPTION

Visualize CSV data containing geographic columns on an interactive map with a synchronized data table. Auto-detects lat/lon pairs, GeoJSON, WKT, and WKB formats. Includes map tile options, color palettes, and linked selection between map features and table rows.

=end pod
