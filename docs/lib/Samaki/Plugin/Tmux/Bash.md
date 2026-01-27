NAME
====

Samaki::Plugin::Tmux::Bash -- Interactive Bash in a tmux window

DESCRIPTION
===========

Run an interactive Bash shell in a persistent tmux window. State persists across cells. Unlike the Repl plugins which use a PTY to capture output, this plugin uses tmux's control mode protocol to stream output from a real tmux window.

Key features:

* Each session runs in its own tmux window (switch with C-b n/p) * You can switch to the window and type commands manually if needed * Output is streamed back to samaki in real-time via tmux control mode * Multiple tmux plugin instances can run independent windows simultaneously

REQUIREMENTS
============

Must be run from within a tmux session.

OPTIONS
=======

* `delay` -- seconds to wait between sending lines (default: 0.1)

EXAMPLE
=======

    -- tmux-bash
    echo "hello world"
    pwd

    -- tmux-bash
    ls -la

