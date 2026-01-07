NAME
====

Samaki::Plugin::Duckie -- Execute SQL queries using the Duckie inline driver

DESCRIPTION
===========

Execute SQL queries using the inline [Duckie](Duckie) driver, which provides Raku bindings to the DuckDB C API. This runs in the same process as Samaki, making it faster than the process-based Duck plugin.

For a process-based alternative, see [Samaki::Plugin::Duck](Samaki::Plugin::Duck).

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

