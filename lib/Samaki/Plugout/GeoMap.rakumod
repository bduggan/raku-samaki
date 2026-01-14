use Samaki::Plugout;
use Samaki::Utils;
use Duck::CSV;
use JSON::Fast;
use Log::Async;

unit class Samaki::Plugout::GeoMap does Samaki::Plugout;

has $.name = 'geo-map';
has $.description = 'View CSV data with GeoJSON columns on an interactive map';
has $.clear-before = False;

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
  info "executing GeoMap with $path";

  # Read CSV
  my @rows = read-csv("$path");
  return unless @rows;

  # Get column names
  my @columns = @rows[0].keys.sort;

  # Detect GeoJSON columns
  my @geojson-columns = self!detect-geojson-columns(@rows, @columns);

  # Detect lat/lon column pairs
  my @latlon-pairs = self!detect-latlon-pairs(@columns);

  # Error handling: no GeoJSON or lat/lon found
  if @geojson-columns.elems == 0 && @latlon-pairs.elems == 0 {
    self.info("No GeoJSON columns or lat/lon pairs detected in CSV");
    return;
  }

  info "Detected GeoJSON columns: {@geojson-columns.join(', ')}" if @geojson-columns;
  info "Detected lat/lon pairs: {@latlon-pairs.map({ $_<lat> ~ '/' ~ $_<lon> }).join(', ')}" if @latlon-pairs;

  # Prepare data with colors and features
  my @prepared-rows = self!prepare-row-data(@rows, @columns, @geojson-columns, @latlon-pairs);

  # Convert to JSON for JavaScript
  my $data-json = self!rows-to-json(@prepared-rows, @columns, @geojson-columns);

  # Generate HTML file
  my $html-file = $data-dir.child("{$name}-geomap.html");
  my $title = html-escape($data-dir.basename ~ " : " ~ $name);

  # Build HTML content
  my $html = self!build-html($title, $data-json, @columns, @geojson-columns);

  # Write and open
  spurt $html-file, $html;
  info "opening $html-file";
  shell-open $html-file;
}

method !detect-geojson-columns(@rows, @columns) {
  my @geojson-cols;

  for @columns -> $col {
    my $has-valid-geojson = False;

    # Check first few rows for valid GeoJSON
    for @rows[^min(5, @rows.elems)] -> $row {
      my $val = $row{$col};
      next unless $val;

      try {
        my $json = from-json($val);
        if self!is-valid-geojson($json) {
          $has-valid-geojson = True;
          last;
        }
        CATCH {
          default { } # Silent failure for invalid JSON
        }
      }
    }

    @geojson-cols.push($col) if $has-valid-geojson;
  }

  return @geojson-cols;
}

method !detect-latlon-pairs(@columns) {
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

method !is-valid-geojson($data) {
  return False unless $data ~~ Hash;

  my $type = $data<type>;
  return False unless $type;

  # Valid GeoJSON types
  my @valid-types = <Feature FeatureCollection Point LineString Polygon
                     MultiPoint MultiLineString MultiPolygon GeometryCollection>;

  return False unless $type ~~ any(@valid-types);

  # For bare geometries, verify they have coordinates
  if $type ~~ any(<Point LineString Polygon MultiPoint MultiLineString MultiPolygon>) {
    return False unless $data<coordinates>;
  }

  return True;
}

method !prepare-row-data(@rows, @columns, @geojson-columns, @latlon-pairs) {
  my @color-palette = <
    #3b82f6 #ef4444 #10b981 #f59e0b #8b5cf6 #ec4899
    #14b8a6 #f97316 #6366f1 #84cc16 #06b6d4 #f43f5e
  >;

  my @prepared;

  for @rows.kv -> $idx, $row {
    my $color = @color-palette[$idx % @color-palette.elems];

    # Extract all GeoJSON features from all GeoJSON columns
    my @features;
    for @geojson-columns -> $col {
      my $val = $row{$col};
      next unless $val;

      try {
        my $json = from-json($val);
        if self!is-valid-geojson($json) {
          # Handle both Feature and FeatureCollection
          if $json<type> eq 'FeatureCollection' {
            @features.append($json<features>.Array);
          } elsif $json<type> eq 'Feature' {
            @features.push($json);
          } else {
            # Wrap bare geometry in Feature
            my %feature = (
              type => 'Feature',
              geometry => $json,
              properties => %()
            );
            @features.push(%feature);
            info "Row $idx, col $col: Added {$json<type>} geometry with coords: {$json<coordinates>.raku}";
          }
        }
        CATCH {
          default {
            warning "Row $idx, column $col: Invalid GeoJSON - $_";
          }
        }
      }
    }

    # Create Point features from lat/lon pairs
    for @latlon-pairs -> $pair {
      my $lat-val = $row{$pair<lat>};
      my $lon-val = $row{$pair<lon>};

      # Skip if either value is missing or not numeric
      next unless $lat-val.defined && $lon-val.defined;

      try {
        my $lat = +$lat-val;
        my $lon = +$lon-val;

        # Basic validation of coordinate ranges
        next unless -90 <= $lat <= 90;
        next unless -180 <= $lon <= 180;

        my %feature = (
          type => 'Feature',
          geometry => %(
            type => 'Point',
            coordinates => [$lon, $lat]  # GeoJSON uses [lon, lat] order
          ),
          properties => %(
            lat_col => $pair<lat>,
            lon_col => $pair<lon>
          )
        );
        @features.push(%feature);
        info "Row $idx: Added Point from {$pair<lat>}/{$pair<lon>}: [$lon, $lat]";
        CATCH {
          default {
            warning "Row $idx: Invalid lat/lon values in {$pair<lat>}/{$pair<lon>}";
          }
        }
      }
    }

    @prepared.push(%(
      index => $idx,
      color => $color,
      features => @features,
      data => $row
    ));
  }

  return @prepared;
}

method !rows-to-json(@prepared-rows, @columns, @geojson-columns) {
  my @json-rows;

  for @prepared-rows -> $prep {
    my %row-data = (
      index => $prep<index>,
      color => $prep<color>,
      features => $prep<features>,
      data => %()
    );

    # Include ALL columns in data (including GeoJSON columns)
    for @columns -> $col {
      my $val = $prep<data>{$col} // '';
      # Truncate long GeoJSON strings for display
      if $col ~~ any(@geojson-columns) && $val.chars > 100 {
        $val = $val.substr(0, 100) ~ '...';
      }
      %row-data<data>{$col} = $val;
    }

    @json-rows.push(%row-data);
  }

  return to-json(@json-rows);
}

method !build-html($title, $data-json, @columns, @geojson-columns) {
  # Include all columns in the table
  my $columns-json = to-json(@columns.Array);

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

      #tile-selector {
        padding: 5px 8px;
        font-family: inherit;
        font-size: 12px;
        border: 1px solid #e2e8f0;
        border-radius: 3px;
        background: white;
        cursor: pointer;
      }

      #tile-selector:hover {
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
          <option value="osm">OpenStreetMap</option>
          <option value="light">Light (Positron)</option>
          <option value="dark">Dark (Dark Matter)</option>
          <option value="satellite">Satellite</option>
          <option value="topo">Topographic</option>
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
      // Data from Raku
      const rowData = ROWDATA_PLACEHOLDER;
      const columns = COLUMNS_PLACEHOLDER;

      // Global state
      let map;
      let allLayerGroups = {};
      let currentSelection = null;
      let dataTable;
      let currentTileLayer;

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

      // Initialize on page load
      document.addEventListener('DOMContentLoaded', function() {
        initializeMap();
        initializeTable();
        setupEventHandlers();
      });

      // Map initialization
      function initializeMap() {
        map = L.map('map');

        // Add default tile layer
        currentTileLayer = L.tileLayer(tileProviders.osm.url, {
          maxZoom: tileProviders.osm.maxZoom,
          attribution: tileProviders.osm.attribution
        }).addTo(map);

        // Create layer groups for each row
        rowData.forEach(function(row) {
          const layerGroup = L.layerGroup();

          console.log('Row ' + row.index + ' has ' + row.features.length + ' features');
          row.features.forEach(function(feature) {
            console.log('  Feature type:', feature.type, 'Geometry:', feature.geometry ? feature.geometry.type : 'none');
            const geoLayer = L.geoJSON(feature, {
              style: {
                color: row.color,
                fillColor: row.color,
                fillOpacity: 0.3,
                weight: 2
              },
              pointToLayer: function(feature, latlng) {
                // Check if this is a Point geometry
                if (feature.geometry && feature.geometry.type === 'Point') {
                  // Create a custom colored icon for Point geometries
                  const markerIcon = L.divIcon({
                    className: 'custom-marker-icon',
                    html: '<div style="background-color: ' + row.color + '; width: 20px; height: 20px; border-radius: 50% 50% 50% 0; transform: rotate(-45deg); border: 2px solid white; box-shadow: 0 2px 4px rgba(0,0,0,0.3);"></div>',
                    iconSize: [24, 24],
                    iconAnchor: [12, 24],
                    popupAnchor: [0, -24]
                  });
                  return L.marker(latlng, { icon: markerIcon });
                } else {
                  // Use circle markers for other point-like features
                  return L.circleMarker(latlng, {
                    radius: 8,
                    fillColor: row.color,
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

            layerGroup.addLayer(geoLayer);
          });

          allLayerGroups[row.index] = layerGroup;
          layerGroup.addTo(map);
        });

        // Fit map to all features
        fitAllBounds();
      }

      function buildPopupContent(row, feature) {
        let html = '<div style="font-size: 11px;">';
        html += '<strong>Row ' + (row.index + 1) + '</strong><br>';

        // Add feature properties if they exist
        if (feature.properties) {
          for (let key in feature.properties) {
            html += key + ': ' + feature.properties[key] + '<br>';
          }
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
          colorSpan.style.backgroundColor = row.color;
          colorTd.appendChild(colorSpan);
          tr.appendChild(colorTd);

          // Row number cell
          const numTd = document.createElement('td');
          numTd.textContent = row.index + 1;
          tr.appendChild(numTd);

          // Data cells
          columns.forEach(function(col) {
            const td = document.createElement('td');
            td.textContent = row.data[col] || '';
            tr.appendChild(td);
          });

          tbody.appendChild(tr);
        });

        // Initialize DataTable
        dataTable = $('#dataTable').DataTable({
          pageLength: 10,
          searching: true,
          ordering: true
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
  $html = $html.subst('ROWDATA_PLACEHOLDER', $data-json);
  $html = $html.subst('COLUMNS_PLACEHOLDER', $columns-json);

  return $html;
}
