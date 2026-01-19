NAME
====

Samaki::Plugout::DeckGLBin -- 3D spatial bin visualization using deck.gl

DESCRIPTION
===========

Renders CSV data containing spatial bins as an interactive 3D visualization using deck.gl. Bins are extruded vertically based on a numeric value column, with color also mapped to value.

SUPPORTED COLUMN TYPES
======================

The plugout auto-detects spatial data in the following formats:

H3 Hexagonal Indices
--------------------

H3 cell indices in either hexadecimal (15 chars) or decimal format. Rendered using deck.gl's native `H3HexagonLayer`.

    h3,population
    8928308280fffff,15000
    89283082873ffff,12500

Decimal format (as exported by DuckDB/PostGIS):

    cell,count
    617549798007111679,19
    617549797987450879,10

Geohashes
---------

Base32-encoded geohash strings (4-12 characters). Converted to rectangular polygons.

    geohash,temperature
    u4pruydqqvj,22.5
    u4pruydqqvm,23.1

GeoJSON Geometry
----------------

JSON-encoded GeoJSON geometry objects, Features, or FeatureCollections.

    geometry,sales
    "{""type"":""Polygon"",""coordinates"":[[[0,0],[1,0],[1,1],[0,1],[0,0]]]}",5000

WKT (Well-Known Text)
---------------------

OGC Well-Known Text geometry strings, including EWKT with SRID prefixes.

    shape,count
    POLYGON((0 0, 1 0, 1 1, 0 1, 0 0)),42

WKB (Well-Known Binary)
-----------------------

Hexadecimal-encoded WKB geometry, as exported from PostGIS.

    geom,value
    0101000020E6100000...,250

VALUE COLUMNS
=============

Any numeric column can be used for height/color.

