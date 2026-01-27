NAME
====

Samaki::Plugin::Tmux -- Base class for tmux-based interactive plugins

SYNOPSIS
========

    # Create a subclass for a specific command
    use Samaki::Plugin::Tmux;

    unit class Samaki::Plugin::Tmux::MyCommand is Samaki::Plugin::Tmux;

    method name { "tmux-mycommand" }
    method description { "Run mycommand in a tmux pane" }
    has $.command = 'mycommand';

DESCRIPTION
===========

This role provides a base class for plugins that interact with commands running in tmux windows. Unlike the [Samaki::Plugin::Repl](Samaki::Plugin::Repl) plugins which use a PTY to capture output, this plugin uses tmux's control mode protocol to:

  * Create new tmux windows for running commands

  * Stream output from windows in real-time via %output notifications

  * Send input to windows using tmux send-keys

  * Maintain persistent sessions across cell executions

Key Features
------------

  * **Real tmux windows** - Each command runs in its own tmux window, visible in your tmux session and accessible via normal tmux window switching (C-b n/p).

  * **Multiple simultaneous sessions** - Different plugin instances maintain separate windows, allowing multiple independent sessions.

  * **Control mode streaming** - Output is streamed via tmux's control mode protocol, providing real-time updates without polling.

REQUIREMENTS
============

The user must be running samaki from within a tmux session. The plugin will error if the TMUX environment variable is not set.

OPTIONS
=======

  * `delay` -- Seconds to wait between sending lines (default: 0.1)

  * `window` -- Name of the tmux window to use. If not specified, uses the cell name. Multiple cells can share the same tmux window by specifying the same window name.

SEE ALSO
========

[Samaki::Plugin::Repl](Samaki::Plugin::Repl) - Alternative approach using PTY [Samaki::Plugin::Tmux::Bash](Samaki::Plugin::Tmux::Bash) - Bash shell example [Samaki::Plugin::Tmux::Python](Samaki::Plugin::Tmux::Python) - Python interpreter example

