use Samaki::Plugin::Repl;
use Samaki::Conf;
use Log::Async;

unit class Samaki::Plugin::Repl::Raku is Samaki::Plugin::Repl;

method name { "repl-raku" }
method description { "Run the raku repl, and interact using a pty" }

has $.command = 'raku';

