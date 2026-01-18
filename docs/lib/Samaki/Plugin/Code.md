NAME
====

Samaki::Plugin::Code -- Evaluate Raku code in the current process

DESCRIPTION
===========

Evaluate Raku code in the same context as the page's auto-evaluated blocks (cells starting with just `--`). Variables and functions defined in other code cells or init blocks are available.

Note that these cells run _after_ the auto cells and the interpolated cells, so defining variables etc, can't be done here for use in those cells.

OPTIONS
=======

No specific options.

EXAMPLE
=======

    -- code
    my $a = 12;

    -- code
    $a + 1;

Output:

    13

