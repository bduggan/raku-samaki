NAME
====

Samaki::Plugin::Raku -- Execute Raku code in a separate process

DESCRIPTION
===========

Execute Raku code in a separate process. Unlike the Code plugin which runs in the same process and shares state, this creates a new Raku process for each cell. This is a process-based plugin (uses [Samaki::Plugin::Process](Samaki::Plugin::Process)).

OPTIONS
=======

No specific options.

EXAMPLE
=======

    -- raku
    say "Hello from a separate process!";
    say π;

Output:

    Hello from a separate process!
    3.141592653589793

