use Samaki::Plugin::Repl;

unit class Samaki::Plugin::Repl::Python is Samaki::Plugin::Repl;

method name { "repl-python" }
method description { "Run the python repl and interact with it" }

has $.command = 'python3';
