use Samaki::Plugin::Tmux;

unit class Samaki::Plugin::Tmux::Bash is Samaki::Plugin::Tmux;

method name { "tmux-bash" }
method description { "Run bash in a tmux pane" }

has $.command = 'bash';

=begin pod

=head1 NAME

Samaki::Plugin::Tmux::Bash -- Interactive Bash in a tmux window

=head1 DESCRIPTION

Run an interactive Bash shell in a persistent tmux window. State persists across cells.
Unlike the Repl plugins which use a PTY to capture output, this plugin uses
tmux's control mode protocol to stream output from a real tmux window.

Key features:

* Each session runs in its own tmux window (switch with C-b n/p)
* You can switch to the window and type commands manually if needed
* Output is streamed back to samaki in real-time via tmux control mode
* Multiple tmux plugin instances can run independent windows simultaneously

=head1 REQUIREMENTS

Must be run from within a tmux session.

=head1 OPTIONS

* `delay` -- seconds to wait between sending lines (default: 0.1)

=head1 EXAMPLE

    -- tmux-bash
    echo "hello world"
    pwd

    -- tmux-bash
    ls -la

=end pod
