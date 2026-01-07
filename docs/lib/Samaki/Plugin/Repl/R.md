NAME
====

Samaki::Plugin::Repl::R -- Interactive R REPL

DESCRIPTION
===========

Run an interactive R REPL in a persistent session. State persists across cells, so variables and functions defined in one cell are available in subsequent cells.

OPTIONS
=======

* `delay` -- seconds to wait between sending lines (default: 1)

EXAMPLE
=======

    -- R-repl
    x <- c(1, 2, 3, 4, 5)
    mean(x)

    -- R-repl
    y <- x * 2
    sum(y)

Output:

    [1] 3
    [1] 30

