NAME
====

Samaki::Plugin::Repl::Python -- Interactive Python REPL

DESCRIPTION
===========

Run an interactive Python REPL in a persistent session. State persists across cells, so variables and functions defined in one cell are available in subsequent cells.

OPTIONS
=======

* `delay` -- seconds to wait between sending lines (default: 1)

EXAMPLE
=======

    -- python-repl
    x = 42
    print(x)

    -- python-repl
    y = x * 2
    print(y)

Output:

    42
    84

