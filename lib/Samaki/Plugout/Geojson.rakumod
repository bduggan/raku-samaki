use Samaki::Plugout;
use Samaki::Utils;
unit class Samaki::Plugout::Geojson does Samaki::Plugout;

has $.name = 'geojson';
has $.description = 'View geojson in a browser using leaflet';
has $.clear-before = False;

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
    my $content = slurp $path;
    my $temp-file = $*TMPDIR.add("geojson-viewer-{now.Rat}.html");
    
    my $html = Q:s:to/HTML/;
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>GeoJSON Viewer</title>
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        <style>
            body { margin: 0; padding: 0; }
            #map { height: 100vh; width: 100vw; }
        </style>
    </head>
    <body>
        <div id="map"></div>
        <script>
            const map = L.map('map');
            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                maxZoom: 19,
                attribution: '© OpenStreetMap contributors'
            }).addTo(map);

            const geojsonData = $content;
            const geojsonLayer = L.geoJSON(geojsonData).addTo(map);
            map.fitBounds(geojsonLayer.getBounds());
        </script>
    </body>
    </html>
    HTML

    spurt $temp-file, $html;
    shell-open "$temp-file";
}

=begin pod

=head1 NAME

Samaki::Plugout::Geojson -- Display GeoJSON on an interactive map

=head1 DESCRIPTION

Display GeoJSON output on an interactive Leaflet map in the browser.

=end pod
