use Samaki::Plugin::Tmux;

unit class Samaki::Plugin::Tmux::Python is Samaki::Plugin::Tmux;

method name { "tmux-python" }
method description { "Run Python in a tmux pane" }

has $.command = 'python3';

=begin pod

=head1 NAME

Samaki::Plugin::Tmux::Python -- Interactive Python in a tmux window

=head1 DESCRIPTION

Run an interactive Python interpreter in a persistent tmux window. State persists
across cells, and you can see and interact with the window directly in your tmux
session (switch with C-b n/p).

Unlike the Repl plugins which use a PTY to capture output, this plugin uses
tmux's control mode to stream output from a real tmux window. This allows you to
interact with the window directly (useful for debugging or manual intervention).

=head1 REQUIREMENTS

Must be run from within a tmux session.

=head1 OPTIONS

* `delay` -- seconds to wait between sending lines (default: 0.1)

=head1 EXAMPLE

    -- tmux-python
    x = 42
    print(f"The answer is {x}")

    -- tmux-python
    import math
    print(math.pi)

=end pod
