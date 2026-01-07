NAME
====

Samaki::Plugin::File -- Display file metadata and information

DESCRIPTION
===========

Display metadata about a file that already exists in the data directory. For GeoJSON files, also displays geometry information.

OPTIONS
=======

No specific options.

EXAMPLE
=======

    -- file:mydata.csv

Output displays file metadata:

    file:      [mydata.csv]
    Size:      1.2 KB
    Modified:  3 hours ago
    Accessed:  1 minute ago
    Changed:   3 hours ago
    Absolute:  /full/path/to/data/mydata.csv

For GeoJSON files:

    -- file:boundaries.geojson

    GeoJSON:   FeatureCollection
    Features:  42
    Geometry:  Polygon (42)
    Coords:    1234
    Bounds:    lon: [-122.5, -122.3] lat: [37.7, 37.9]

