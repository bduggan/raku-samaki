use Samaki::Page;
use Samaki::Plugins;

unit class Samaki::Share;

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
    my $cell-html = qq:to/HTML/;
        <div class="cell-container">
            <div class="cell-header">
                <span class="cell-type">{$cell.cell-type}</span>
                {$cell.name ne "cell-$idx" ?? qq[<span class="cell-name">: {$cell.name}</span>] !! ''}
            </div>
    HTML

    # Find output files for this cell
    my @outputs = self.find-outputs($cell);

    # Create tabs for input and outputs
    $cell-html ~= qq:to/HTML/;
            <div class="tab-headers">
                <button class="tab-button active" onclick="openTab(event, 'cell{$idx}_input')">Input</button>
    HTML

    for @outputs.kv -> $out-idx, $output {
        $cell-html ~= qq[        <button class="tab-button" onclick="openTab(event, 'cell{$idx}_out{$out-idx}')">{$output<name>}</button>\n];
    }

    $cell-html ~= qq:to/HTML/;
            </div>
            <div class="tab-contents">
                <div id="cell{$idx}_input" class="tab-content active">
                    <pre class="cell-content"><code>{self.escape-html($cell.content)}</code></pre>
                </div>
    HTML

    for @outputs.kv -> $out-idx, $output {
        $cell-html ~= qq[        <div id="cell{$idx}_out{$out-idx}" class="tab-content">\n];
        $cell-html ~= qq[            <div class="output-content">\n];
        $cell-html ~= self.render-output($output, $idx, $out-idx);
        $cell-html ~= qq[            </div>\n];
        $cell-html ~= qq[        </div>\n];
    }

    $cell-html ~= qq:to/HTML/;
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
    return qq:to/HTML/;
        <div id="map_cell{$cell-idx}_out{$out-idx}" class="geojson-map"></div>
        <script>
        (function() \{
            var map = L.map('map_cell{$cell-idx}_out{$out-idx}').setView([37.7749, -122.4194], 13);
            L.tileLayer('https://\{s\}.tile.openstreetmap.org/\{z\}/\{x\}/\{y\}.png', \{
                attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
            \}).addTo(map);

            var geojsonData = {$geojson-content};
            var geojsonLayer = L.geoJSON(geojsonData, \{
                onEachFeature: function(feature, layer) \{
                    if (feature.properties) \{
                        var popupContent = '<div class="geojson-popup">';
                        for (var key in feature.properties) \{
                            popupContent += '<strong>' + key + ':</strong> ' + feature.properties[key] + '<br>';
                        \}
                        popupContent += '</div>';
                        layer.bindPopup(popupContent);
                    \}
                \}
            \}).addTo(map);

            map.fitBounds(geojsonLayer.getBounds());
        \})();
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
    return qq:to/HTML/;
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>{$page-name} - Samaki</title>
            <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
            <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
            <style>
                * \{
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                \}

                body \{
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
                    background: #f5f5f7;
                    padding: 0.5rem;
                    line-height: 1.4;
                    font-size: 13px;
                \}

                .page-header \{
                    text-align: center;
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    color: white;
                    padding: 0.4rem;
                    margin-bottom: 0.5rem;
                    border-radius: 4px;
                \}

                .page-header h1 \{
                    font-size: 1.4rem;
                    font-weight: 600;
                    margin: 0;
                \}

                .cell-container \{
                    background: white;
                    border-radius: 4px;
                    box-shadow: 0 1px 3px rgba(0,0,0,0.1);
                    margin-bottom: 0.5rem;
                    overflow: hidden;
                \}

                .cell-header \{
                    padding: 0.3rem 0.5rem;
                    background: #f8f9fa;
                    border-bottom: 1px solid #e9ecef;
                    display: flex;
                    align-items: center;
                    gap: 0.5rem;
                \}

                .cell-type \{
                    display: inline-block;
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    color: white;
                    padding: 0.15rem 0.4rem;
                    border-radius: 3px;
                    font-size: 0.75rem;
                    text-transform: uppercase;
                    letter-spacing: 0.3px;
                    font-weight: 600;
                \}

                .cell-name \{
                    color: #495057;
                    font-size: 0.75rem;
                    font-style: italic;
                \}

                .tab-headers \{
                    display: flex;
                    gap: 2px;
                    background: #e9ecef;
                    padding: 2px;
                \}

                .tab-button \{
                    background: #f8f9fa;
                    border: none;
                    padding: 0.3rem 0.6rem;
                    cursor: pointer;
                    font-size: 0.75rem;
                    font-weight: 500;
                    color: #6c757d;
                    transition: all 0.15s ease;
                    border-radius: 2px;
                \}

                .tab-button:hover \{
                    background: #dee2e6;
                    color: #495057;
                \}

                .tab-button.active \{
                    background: white;
                    color: #667eea;
                    font-weight: 600;
                \}

                .tab-content \{
                    display: none;
                \}

                .tab-content.active \{
                    display: block;
                \}

                .cell-content \{
                    padding: 0.5rem;
                    background: #fafbfc;
                    border-left: 2px solid #667eea;
                    overflow-x: auto;
                    max-height: 300px;
                    overflow-y: auto;
                \}

                .cell-content code \{
                    font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
                    font-size: 0.75rem;
                    line-height: 1.3;
                    color: #2d3748;
                \}

                .output-content \{
                    padding: 0.5rem;
                    max-height: 400px;
                    overflow-y: auto;
                \}

                .geojson-map \{
                    width: 100%;
                    height: 350px;
                    border-radius: 3px;
                \}

                .table-container \{
                    overflow-x: auto;
                    max-height: 400px;
                    overflow-y: auto;
                \}

                .csv-table \{
                    width: 100%;
                    border-collapse: collapse;
                    background: white;
                    font-size: 0.7rem;
                \}

                .csv-table thead \{
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    color: white;
                    position: sticky;
                    top: 0;
                    z-index: 10;
                \}

                .csv-table th \{
                    padding: 0.3rem 0.4rem;
                    text-align: left;
                    font-weight: 600;
                    font-size: 0.7rem;
                    text-transform: uppercase;
                    letter-spacing: 0.3px;
                \}

                .csv-table td \{
                    padding: 0.25rem 0.4rem;
                    border-bottom: 1px solid #e9ecef;
                    font-size: 0.7rem;
                    white-space: nowrap;
                \}

                .csv-table tbody tr:hover \{
                    background: #f8f9fa;
                \}

                .text-output, .json-output \{
                    background: #fafbfc;
                    padding: 0.5rem;
                    border-left: 2px solid #28a745;
                    overflow-x: auto;
                    font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
                    font-size: 0.7rem;
                    line-height: 1.3;
                    max-height: 400px;
                    overflow-y: auto;
                \}

                .truncation-note \{
                    margin-top: 0.3rem;
                    padding: 0.3rem;
                    background: #fff3cd;
                    border-left: 2px solid #ffc107;
                    color: #856404;
                    font-size: 0.7rem;
                \}

                .geojson-popup \{
                    font-size: 0.75rem;
                    line-height: 1.4;
                \}

                footer \{
                    text-align: center;
                    color: #6c757d;
                    margin-top: 0.5rem;
                    font-size: 0.7rem;
                \}

                footer a \{
                    color: #667eea;
                    text-decoration: none;
                \}

                footer a:hover \{
                    text-decoration: underline;
                \}
            </style>
        </head>
        <body>
            <div class="page-header">
                <h1>〜 {$page-name} 〜</h1>
            </div>
    HTML
}

method html-footer() {
    return qq:to/HTML/;
            <footer>
                <a href="https://github.com/bduggan/raku-samaki">Samaki</a>
            </footer>
            <script>
                function openTab(evt, tabId) \{
                    // Get the clicked button's parent container to scope tab switching
                    var container = evt.currentTarget.closest('.cell-container');

                    // Hide all tab contents in this container
                    var tabContents = container.querySelectorAll('.tab-content');
                    for (var i = 0; i < tabContents.length; i++) \{
                        tabContents[i].classList.remove('active');
                    \}

                    // Remove active class from all tab buttons in this container
                    var tabButtons = container.querySelectorAll('.tab-button');
                    for (var i = 0; i < tabButtons.length; i++) \{
                        tabButtons[i].classList.remove('active');
                    \}

                    // Show the selected tab content and mark button as active
                    document.getElementById(tabId).classList.add('active');
                    evt.currentTarget.classList.add('active');
                \}
            </script>
        </body>
        </html>
    HTML
}
