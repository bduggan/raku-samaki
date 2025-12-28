use Samaki::Plugin::Repl;
use Samaki::Conf;
use Log::Async;

unit class Samaki::Plugin::Repl::Raku does Samaki::Plugin;

method name { "repl-raku" }
method description { "Run the raku repl, and interact using a pty" }

has Proc::Async $!proc;
has Promise $!proc-promise;
has $!pid;
has $!line-delay-seconds = 1;

method start-repl($pane) {
  self.stream: [col('info') => "starting repl for {$.name}"];
  $pane.stream: $!proc.stdout(:bin);
  $!proc-promise = start {
    react {
      whenever $!proc.ready {
        $!pid = $_;
      }
      whenever $!proc.start {
        $pane.put: "done";
        $!pid = Nil;
        $pane.enable-selection;
      }
    }
  }
}

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  info "launching raku repl";
  $!proc //= Proc::Async.new: :pty(:rows($pane.height), :cols($pane.width)), 'raku';
  unless $!pid {
    self.start-repl($pane);
  }
  my $input = $cell.get-content(:$mode, :$page).trim;
  for $input.lines -> $line {
    sleep $!line-delay-seconds;
    info "sending line " ~ $line.raku;
    $!proc.put: $line;
  }
}

method shutdown {
  $!proc.put: "exit";
  sleep 0.1;
  info "kill proc $!pid";
  $!proc.kill;
}
