NAME
====

Samaki::Plugin::Repl::Raku -- Interactive Raku REPL

DESCRIPTION
===========

Run an interactive Raku REPL in a persistent session. State persists across cells, so variables and functions defined in one cell are available in subsequent cells.

OPTIONS
=======

* `delay` -- seconds to wait between sending lines (default: 1)

EXAMPLE
=======

    -- raku-repl
    say "hello, world"

    -- raku-repl
    my $n = 2¹²⁷ - 1;
    $n

    -- raku-repl
    say is-prime( $n )

Output:

    hello, world
    170141183460469231731687303715884105727
    True

