NAME
====

Samaki::Plugin::Duckie -- Execute SQL queries using the Duckie inline driver

DESCRIPTION
===========

Execute SQL queries using the inline [Duckie](Duckie) driver, which provides Raku bindings to the DuckDB C API. This runs in the same process as Samaki, making it faster than the process-based Duck plugin.

For a process-based alternative, see [Samaki::Plugin::Duck](Samaki::Plugin::Duck).

Duckie supports user defined functions in raku via the udf's attribute. To use this, add a derived class in your config file. For example, this adds `parse_poly` as a UDF that converts a polyline string to GeoJSON:

    use Samaki::Plugin::Duckie;
    use Geo::Polyline;
    use JSON::Fast;

    ...
    / duckie / => class Samaki::Plugin::MyDuckie is Samaki::Plugin::Duckie {
                    has @.udfs = sub parse_poly (Str $poly --> Str ) {
                      to-json polyline-to-geojson( $poly, :unescape )<geometry>, :!pretty;
                    };
                  }
    ...

OPTIONS
=======

* `db` -- path to a duckdb database file. If not specified, an in-memory database is used.

EXAMPLE
=======

    -- duckie
    select 'hello' as greeting, 'world' as noun;

Output (CSV):

    greeting,noun
    hello,world

Example with a database file:

    -- duckie
    | db: mydata.duckdb
    select * from users limit 5;

