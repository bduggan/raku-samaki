NAME
====

Samaki::Plugin::Process -- Base role for process-based plugins

DESCRIPTION
===========

This is a base role for plugins that execute code in a separate process. It provides common functionality for running external commands, handling input and output, and managing the process lifecycle. Specific language plugins (like Samaki::Plugin::Raku) can consume this role and provide language-specific details.

OPTIONS
=======

timeout
-------

Number of seconds to wait before killing the process. Default is 60 seconds.

scroll
------

Whether to auto-scroll the output pane. Default is True. Set to "no", "off", or "none" to disable.

