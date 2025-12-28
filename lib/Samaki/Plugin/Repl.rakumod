use Log::Async;

use Samaki::Conf;
use Samaki::Plugin;

unit class Samaki::Plugin::Repl does Samaki::Plugin;

method name { ... }
method description { ... }

has Proc::Async $.proc;
has Promise $.proc-promise;
has $!pid;
has $!line-delay-seconds = 1;

has $.command = 'raku';

method write-output {
  False
}

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
  info "launching {$.name} repl";
  $!proc //= Proc::Async.new: :pty(:rows($pane.height), :cols($pane.width)), $.command;
  unless $!pid {
    self.start-repl($pane);
  }
  my $input = $cell.get-content(:$mode, :$page).trim;
  for $input.lines -> $line {
    sleep $!line-delay-seconds;
    debug "sending line " ~ $line.raku;
    $!proc.put: $line;
  }
}

method shutdown {
  .close-stdin with $.proc;
  return without $.proc-promise;
  with $.proc-promise {
    await Promise.anyof($_, Promise.in(2));
  }
  if $.proc-promise.status ~~ PromiseStatus::Planned {
    $!proc.kill(SIGTERM);
    await Promise.anyof($.proc-promise, Promise.in(1));
  }
  if $.proc-promise.status ~~ PromiseStatus::Planned {
    $!proc-promise.kill(SIGKILL);
    await Promise.anyof($.proc-promise, Promise.in(0.5));
  }
}
