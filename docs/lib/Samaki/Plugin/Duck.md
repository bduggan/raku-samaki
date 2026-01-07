NAME
====

Samaki::Plugin::Duck -- Execute SQL queries using the duckdb CLI

DESCRIPTION
===========

Execute SQL queries by spawning the `duckdb` command-line executable as a separate process. Input is piped to stdin and output is captured from stdout. This is a process-based plugin (uses [Samaki::Plugin::Process](Samaki::Plugin::Process)).

For an inline driver alternative, see [Samaki::Plugin::Duckie](Samaki::Plugin::Duckie).

OPTIONS
=======

* `db` -- path to a duckdb database file. If not specified, an in-memory database is used. * `timeout` -- maximum time in seconds to wait for query execution (default: 300)

EXAMPLE
=======

    -- duck
    select 'hello' as greeting, 'world' as noun;

Output (CSV):

    greeting,noun
    hello,world

Example with a database file:

    -- duck
    | db: mydata.duckdb
    select * from users limit 5;

