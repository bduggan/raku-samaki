NAME
====

Samaki::Plugin::Code -- Evaluate Raku code in the current process

DESCRIPTION
===========

Evaluate Raku code in the same context as the page's auto-evaluated blocks (cells starting with just `--`). Variables and functions defined in other code cells or init blocks are available.

Unlike the Raku plugin which runs code in a separate process, this runs in the same process as Samaki itself, allowing shared state across code cells.

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

