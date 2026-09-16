NAME
====

Samaki::Plugout::CSVGeo -- Display CSV data or GeoJSON files on an interactive map

DESCRIPTION
===========

Visualize CSV data containing geographic columns or GeoJSON files on an interactive map.

For CSV files: displays with a synchronized data table. Auto-detects lat/lon pairs, GeoJSON, WKT, WKB, and encoded polyline (polyline5/polyline6) formats in columns.

For GeoJSON files: displays with a collapsible JSON tree viewer for exploring the structure.

Includes map tile options, color palettes, and linked selection between map features and table rows. Multiple datasets can be loaded simultaneously with tabbed navigation.

CONFIGURING TILE PROVIDERS
==========================

A configuration for tile provideres can be added in the config file like so:

    use Samaki::Plugout::CSVGeo;

    %*samaki-conf =
      ...
      plugouts => [
        / csv|geojson / => Samaki::Plugout::CSVGeo.new(
          tile-providers => %(
            positron => %(
              label => 'Positron',
              style => 'https://tiles.openfreemap.org/styles/positron',
              attribution => '© OpenFreeMap © OpenMapTiles © OpenStreetMap contributors',
            ),
            ...
            'mapbox-streets' => %(
              label => 'Mapbox Streets',
              url => 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}{r}',
              attribution => '© Mapbox © OpenStreetMap contributors',
              max-zoom => 19, tile-size => 512, zoom-offset => -1,
              token => %*ENV<MAPBOX_TOKEN>,
              token-url-param => 'access_token',
              token-required => True,
            ),
          )
        ),
        ...
      ]
    ;

The built-in default is available as `%Samaki::Plugout::CSVGeo::DEFAULT-TILE-PROVIDERS`.

