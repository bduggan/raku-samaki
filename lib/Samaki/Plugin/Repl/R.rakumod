use Samaki::Plugin::Repl;

unit class Samaki::Plugin::Repl::R is Samaki::Plugin::Repl;

method name { "repl-R" }
method description { "Run the R repl and interact with it" }

has $.command = 'R';
