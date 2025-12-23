use Samaki::Plugin;
use Log::Async;

use Samaki::Conf;
use Samaki::Plugin::Process;

use NativeCall;

sub kill(int32, int32 --> int32) is native {*};

unit class Samaki::Plugin::Bash does Samaki::Plugin::Process;

has $.name = 'bash';
has $.description = 'Run bash with streaming output';

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  info "executing bash cell";
  my $cwd = $*CWD;
  my $proc = Proc::Async.new: 'bash', :out, :err, :w;
  my $input = $cell.get-content(:$mode, :$page);
  my $timeout = $cell.get-conf('timeout') // 300;
  my $pid;

  try react {
    whenever $proc.ready { $pid = self.do-ready($_, $proc,$timeout); }
    whenever $proc.stderr { self.warn: "$_"; }

    whenever $proc.stdout.lines {
      info "got line $_";
      sleep 0.01;
      $.output-stream.send: $_;
      $out.put($_) if $out;
    }
    whenever $proc.start( :$cwd ) {
      self.do-done($_);
      done
    }
    whenever $proc.print($input) {
      $proc.close-stdin;
    }
    whenever Supply.interval(1) {
      unless kill($pid, 0) == 0 {
        warning "Process $pid exited";
        done;
      }
      self.info: "waiting $_" if $_ > 1 && $_ %% 2;
    }
    whenever Promise.in($timeout) {
      self.warn: "killing pid $pid";
      $proc.kill;
      done;
    }
  }
  $out.close if $out;
  self.error("Execution failed: $_") with $!;
  if kill($pid, 0) == 0 {
    self.info: "Process $pid is still running, sending SIGKILL";
    kill($pid, 9);
  } else {
    self.info: "Process $pid has exited";
  }
}
