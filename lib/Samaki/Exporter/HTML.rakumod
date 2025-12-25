use Samaki::Page;
use Samaki::Plugins;

unit class Samaki::Exporter::HTML;

has $.page;
has $.plugins;
has $.output-path;

method generate-html() {
    my $html = self.html-header();

    for $.page.cells.kv -> $idx, $cell {
        $html ~= self.render-cell($cell, $idx);
    }

    $html ~= self.html-footer();
    return $html;
}

method render-cell($cell, $idx) {
    # Find output files for this cell
    my @outputs = self.find-outputs($cell);

    # Determine if first output should be active by default
    my $show-output-first = @outputs.elems > 0;

    my $is-auto = $cell.cell-type eq 'auto';
    my $cell-type-class = $is-auto ?? 'cell-type-auto' !! 'cell-type';

    my $cell-html = qq:to/HTML/;
        <div class="cell-container">
            <div class="cell-main">
                <div class="tab-contents">
                    <div id="cell{$idx}_input" class="tab-content {$show-output-first ?? '' !! 'active'}">
                        <pre class="cell-content"><code>{self.escape-html($cell.content)}</code></pre>
                    </div>
    HTML

    for @outputs.kv -> $out-idx, $output {
        my $active-class = ($show-output-first && $out-idx == 0) ?? 'active' !! '';
        $cell-html ~= qq[            <div id="cell{$idx}_out{$out-idx}" class="tab-content {$active-class}">\n];
        $cell-html ~= qq[                <div class="output-content">\n];
        $cell-html ~= self.render-output($output, $idx, $out-idx);
        $cell-html ~= qq[                </div>\n];
        $cell-html ~= qq[            </div>\n];
    }

    $cell-html ~= qq:to/HTML/;
                </div>
            </div>
            <div class="cell-sidebar">
                <div class="cell-meta">
                    <span class="cell-name">{$cell.name}</span>
                    <span class="{$cell-type-class}">{$cell.cell-type}</span>
                </div>
                <div class="tab-nav">
                    <button class="tab-link {$show-output-first ?? '' !! 'active'}" onclick="openTab(event, 'cell{$idx}_input')">src</button>
    HTML

    for @outputs.kv -> $out-idx, $output {
        my $active-class = ($show-output-first && $out-idx == 0) ?? 'active' !! '';
        my $output-label = $output<ext> // 'out';
        $cell-html ~= qq[                <button class="tab-link {$active-class}" onclick="openTab(event, 'cell{$idx}_out{$out-idx}')">{$output-label}</button>\n];
    }

    $cell-html ~= qq:to/HTML/;
                </div>
            </div>
        </div>
    HTML

    return $cell-html;
}

method find-outputs($cell) {
    my @outputs;
    my $output-file = $cell.output-file;

    if $output-file.e {
        @outputs.push: %(
            name => $output-file.basename,
            path => $output-file,
            ext => $output-file.extension,
        );
    }

    return @outputs;
}

method render-output($output, $cell-idx, $out-idx) {
    my $path = $output<path>;
    my $ext = $output<ext>;

    given $ext {
        when 'geojson' {
            return self.render-geojson($path, $cell-idx, $out-idx);
        }
        when 'csv' {
            return self.render-csv($path);
        }
        when 'json' {
            return self.render-json($path);
        }
        when 'html' {
            return $path.slurp;
        }
        when 'txt' {
            return qq[<pre class="text-output">{self.escape-html($path.slurp)}</pre>];
        }
        default {
            return qq[<pre class="text-output">{self.escape-html($path.slurp)}</pre>];
        }
    }
}

method render-geojson($path, $cell-idx, $out-idx) {
    my $geojson-content = $path.slurp;
    return Q:s:to/HTML/;
        <div id="map_cell{$cell-idx}_out{$out-idx}" class="geojson-map"></div>
        <script>
        (function() {
            var map = L.map('map_cell{$cell-idx}_out{$out-idx}').setView([37.7749, -122.4194], 13);
            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
            }).addTo(map);

            var geojsonData = $geojson-content;
            var geojsonLayer = L.geoJSON(geojsonData, {
                onEachFeature: function(feature, layer) {
                    if (feature.properties) {
                        var popupContent = '<div class="geojson-popup">';
                        for (var key in feature.properties) {
                            popupContent += '<strong>' + key + ':</strong> ' + feature.properties[key] + '<br>';
                        }
                        popupContent += '</div>';
                        layer.bindPopup(popupContent);
                    }
                }
            }).addTo(map);

            map.fitBounds(geojsonLayer.getBounds());
        })();
        </script>
    HTML
}

method render-csv($path) {
    my @lines = $path.lines;
    return '' unless @lines;

    my $header = @lines.shift;
    my @headers = $header.split(',').map(*.trim);

    my $html = qq:to/HTML/;
        <div class="table-container">
            <table class="csv-table">
                <thead>
                    <tr>
    HTML

    for @headers -> $h {
        $html ~= qq[                        <th>{self.escape-html($h)}</th>\n];
    }

    $html ~= qq:to/HTML/;
                    </tr>
                </thead>
                <tbody>
    HTML

    my $row-count = 0;
    for @lines -> $line {
        last if $row-count++ >= 1000; # Limit to 1000 rows
        my @cells = $line.split(',').map(*.trim);
        $html ~= "                    <tr>\n";
        for @cells -> $c {
            $html ~= qq[                        <td>{self.escape-html($c)}</td>\n];
        }
        $html ~= "                    </tr>\n";
    }

    $html ~= qq:to/HTML/;
                </tbody>
            </table>
        </div>
    HTML

    if @lines > 1000 {
        $html ~= qq[<p class="truncation-note">Showing first 1000 of {@lines + 1} rows</p>];
    }

    return $html;
}

method render-json($path) {
    my $json = $path.slurp;
    return qq[<pre class="json-output"><code>{self.escape-html($json)}</code></pre>];
}

method escape-html(Str $text) {
    return '' without $text;
    $text.trans(
        ['&',     '<',    '>',    '"',      "'"] =>
        ['&amp;', '&lt;', '&gt;', '&quot;', '&#39;']
    );
}

method html-header() {
    my $page-name = $.page.name;
    return Q:s:to/HTML/;
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>$page-name </title>
            <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
            <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
            <style>
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }

                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
                    background: #f5f5f7;
                    padding: 0.5rem;
                    line-height: 1.4;
                    font-size: 13px;
                }

                .page-header {
                    text-align: center;
                    background: #162461;
                    color: white;
                    padding: 0.4rem;
                    margin-bottom: 0.5rem;
                    border-radius: 4px;
                }

                .page-header h1 {
                    font-size: 1.4rem;
                    font-weight: 600;
                    margin: 0;
                }

                .cell-container {
                    background: white;
                    border-bottom: 1px solid #e5e7eb;
                    border-left: 1px solid #d1d5db;
                    border-right: 1px solid #d1d5db;
                    position: relative;
                    font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
                    display: flex;
                    align-items: flex-start;
                }

                .cell-container:first-of-type {
                    border-top: 1px solid #d1d5db;
                }

                .cell-main {
                    flex: 1;
                    min-width: 0;
                }

                .cell-sidebar {
                    background: #fafbfc;
                    border-left: 1px solid #e5e7eb;
                    padding: 0.3rem 0.4rem;
                    flex-shrink: 0;
                    display: flex;
                    flex-direction: column;
                    gap: 0.25rem;
                    min-width: 140px;
                }

                .cell-meta {
                    display: flex;
                    align-items: center;
                    gap: 0.3rem;
                    flex-wrap: nowrap;
                }

                .cell-type {
                    display: inline-block;
                    color: #9ca3af;
                    padding: 0.1rem 0.25rem;
                    border-radius: 2px;
                    font-size: 0.6rem;
                    text-transform: lowercase;
                    letter-spacing: 0.02em;
                    font-weight: 500;
                    border: 1px solid #e5e7eb;
                    white-space: nowrap;
                    flex-shrink: 0;
                }

                .cell-type-auto {
                    display: inline-block;
                    color: #9ca3af;
                    padding: 0.1rem 0.25rem;
                    border-radius: 2px;
                    font-size: 0.6rem;
                    text-transform: lowercase;
                    letter-spacing: 0.02em;
                    font-weight: 500;
                    border: 1px dashed #d1d5db;
                    white-space: nowrap;
                    flex-shrink: 0;
                }

                .cell-name {
                    color: #6b7280;
                    font-size: 0.6rem;
                    font-style: italic;
                    white-space: nowrap;
                    overflow: hidden;
                    text-overflow: ellipsis;
                    flex: 1;
                    min-width: 0;
                }

                .tab-nav {
                    display: flex;
                    gap: 0.2rem;
                    align-items: center;
                }

                .tab-link {
                    background: white;
                    border: 1px solid #e5e7eb;
                    border-radius: 3px;
                    padding: 0.2rem 0.4rem;
                    cursor: pointer;
                    font-size: 0.6rem;
                    font-weight: 400;
                    color: #6b7280;
                    transition: all 0.15s ease;
                    text-decoration: none;
                    white-space: nowrap;
                }

                .tab-link:hover {
                    color: #374151;
                    background: #f9fafb;
                    border-color: #d1d5db;
                }

                .tab-link.active {
                    color: white;
                    font-weight: 500;
                    background: #162461;
                    border-color: #162461;
                }

                .tab-contents {
                    position: relative;
                }

                .tab-content {
                    display: none;
                }

                .tab-content.active {
                    display: block;
                }

                .cell-content {
                    padding: 0.5rem 0.5rem 0.5rem 1.5rem;
                    background: #fafbfc;
                    overflow-x: auto;
                    max-height: 300px;
                    overflow-y: auto;
                }

                .cell-content code {
                    font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
                    font-size: 0.75rem;
                    line-height: 1.3;
                    color: #2d3748;
                }

                .output-content {
                    padding: 0.5rem 0.5rem 0.5rem 1.5rem;
                    max-height: 400px;
                    overflow-y: auto;
                }

                .geojson-map {
                    width: 100%;
                    height: 350px;
                    border-radius: 3px;
                }

                .table-container {
                    overflow-x: auto;
                    max-height: 400px;
                    overflow-y: auto;
                }

                .csv-table {
                    width: 100%;
                    border-collapse: collapse;
                    background: white;
                    font-size: 0.7rem;
                }

                .csv-table thead {
                    background: #142368;
                    color: white;
                    position: sticky;
                    top: 0;
                    z-index: 10;
                }

                .csv-table th {
                    padding: 0.3rem 0.4rem;
                    text-align: left;
                    font-weight: 600;
                    font-size: 0.7rem;
                    text-transform: uppercase;
                    letter-spacing: 0.3px;
                }

                .csv-table td {
                    padding: 0.25rem 0.4rem;
                    border-bottom: 1px solid #e9ecef;
                    font-size: 0.7rem;
                    white-space: nowrap;
                }

                .csv-table tbody tr:hover {
                    background: #f8f9fa;
                }

                .text-output, .json-output {
                    background: #fafbfc;
                    padding: 0.5rem 0.5rem 0.5rem 1.5rem;
                    overflow-x: auto;
                    font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
                    font-size: 0.7rem;
                    line-height: 1.3;
                    max-height: 400px;
                    overflow-y: auto;
                }

                .truncation-note {
                    margin-top: 0.3rem;
                    padding: 0.3rem;
                    background: #fff3cd;
                    border: 1px solid #ffc107;
                    color: #856404;
                    font-size: 0.7rem;
                }

                .geojson-popup {
                    font-size: 0.75rem;
                    line-height: 1.4;
                }

                footer {
                    text-align: center;
                    color: #6c757d;
                    margin-top: 0.5rem;
                    font-size: 0.7rem;
                }

                footer a {
                    color: #162461;
                    text-decoration: none;
                }

                footer a:hover {
                    text-decoration: underline;
                }
            </style>
        </head>
        <body>
            <div class="page-header">
                <h1>〜 $page-name 〜</h1>
            </div>
    HTML
}

method html-footer() {
    return Q:s:to/HTML/;
            <footer>
                <a href="https://github.com/bduggan/raku-samaki">Samaki</a>
            </footer>
            <script>
                function openTab(evt, tabId) {
                    // Get the clicked button's parent container to scope tab switching
                    var container = evt.currentTarget.closest('.cell-container');

                    // Hide all tab contents in this container
                    var tabContents = container.querySelectorAll('.tab-content');
                    for (var i = 0; i < tabContents.length; i++) {
                        tabContents[i].classList.remove('active');
                    }

                    // Remove active class from all tab buttons in this container
                    var tabButtons = container.querySelectorAll('.tab-link');
                    for (var i = 0; i < tabButtons.length; i++) {
                        tabButtons[i].classList.remove('active');
                    }

                    // Show the selected tab content and mark button as active
                    document.getElementById(tabId).classList.add('active');
                    evt.currentTarget.classList.add('active');
                }
            </script>
        </body>
        </html>
    HTML
}
