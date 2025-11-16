use Samaki::Plugin::Repl;

unit class Samaki::Plugin::Repl::Raku is Samaki::Plugin::Repl;

method name { "repl-raku" }
method description { "Run raku in a separate process" }
method command( --> List) {
  ('script', '-qefc', "$*EXECUTABLE --repl-mode=process", '/dev/null')
}

