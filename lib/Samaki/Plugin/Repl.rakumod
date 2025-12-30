use Log::Async;

use Samaki::Conf;
use Samaki::Plugin;

unit role Samaki::Plugin::Repl[
  :$name="unnamed",
  :$cmd=Nil,
] does Samaki::Plugin;

has Proc::Async $.proc;
has Promise $.proc-promise;
has $!pid;
has $!line-delay-seconds = 1;

method command { $cmd }
method write-output { False }
method name { $name }
method description { "Run a REPL for $name" }

method start-repl($pane, :$cell) {
  self.stream: [col('info') => "starting repl for {$.name}"];
  $pane.stream: $!proc.stdout(:bin);
  $!proc-promise = start {
    react {
      whenever $!proc.ready {
        $!pid = $_;
      }
      whenever $!proc.start(cwd => $cell.data-dir) {
        info "proc exited for " ~ self.^name;
        $pane.put: "done";
        $!proc = Nil;
        $!pid = Nil;
        $pane.enable-selection;
      }
    }
  }
}

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  with $cell.get-conf('delay') -> $delay {
    $!line-delay-seconds = $delay;
    self.info: "Seconds between sending lines: $delay";
  }
  info "launching {$.name} repl";
  $!proc //= Proc::Async.new: :pty(:rows($pane.height), :cols($pane.width)), self.command;
  unless $!pid {
    self.start-repl($pane, :$cell);
  }
  my $input = $cell.get-content(:$mode, :$page).trim;
  for $input.lines -> $line {
    sleep $!line-delay-seconds;
    debug "sending line " ~ $line.raku;
    $!proc.put: $line;
  }
}

method shutdown {
  with $!proc -> $p {
    info "close stdin for " ~ self.^name;
    $!proc.close-stdin;
  }
  return without $.proc-promise;
  with $.proc-promise {
    await Promise.anyof($_, Promise.in(1));
  }
  if $.proc-promise.status ~~ PromiseStatus::Planned  && $!proc {
    info "sending SIGTERM for " ~ self.^name;
    $!proc.kill(SIGTERM);
    await Promise.anyof($.proc-promise, Promise.in(1));
  }
  if $.proc-promise.status ~~ PromiseStatus::Planned  && $!proc {
    info "sending SIGKILL for " ~ self.^name;
    $!proc.kill(SIGKILL);
    await Promise.anyof($.proc-promise, Promise.in(0.5));
  }
  $!proc = Nil;
}
