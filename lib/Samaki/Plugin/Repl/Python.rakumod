use Samaki::Plugin::Repl;

unit class Samaki::Plugin::Repl::Python is Samaki::Plugin::Repl;

method name { "repl-python" }
method description { "Run python in a separate process" }
method command( --> List) {
  self.script-command('python3', '-iu')
}

