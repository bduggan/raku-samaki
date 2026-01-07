NAME
====

Samaki::Plugin::Postgres -- Execute SQL queries using PostgreSQL

DESCRIPTION
===========

Execute SQL queries by spawning the `psql` command-line executable as a separate process. Input is piped to stdin and output is captured from stdout as CSV. This is a process-based plugin (uses [Samaki::Plugin::Process](Samaki::Plugin::Process)).

OPTIONS
=======

* `db` -- database name or connection string. If not specified, uses the default PostgreSQL connection. * `timeout` -- maximum time in seconds to wait for query execution (default: 300)

EXAMPLE
=======

    -- postgres
    select 'hello' as greeting, 'world' as noun;

Output (CSV):

    greeting,noun
    hello,world

Example with database name:

    -- postgres
    | db: mydb
    select * from users limit 5;

