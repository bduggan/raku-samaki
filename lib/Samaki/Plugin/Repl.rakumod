use Samaki::Plugin;
use Terminal::ANSI::OO 't';
use Samaki::Conf;
use Time::Duration;
use Log::Async;

unit class Samaki::Plugin::Repl does Samaki::Plugin;

has $.start-time;

method name { !!! }
method description { !!! }
method command( --> List) { !!! }

method stream-output { True };
method add-env { %( NO_COLOR => 1, TERM => 'dumb' ) }
method output-ext { 'txt' }
method wrap { 'word' }

has $.promise;
has $.input-supplier = Supplier.new;
has Promise $!prompt;
has Promise $!ready .= new;
has $!ready-vow = $!ready.vow;
has $!proc;
has $!out;

method do-ready($pid, $proc, $timeout = Nil) {
  self.info: "started pid $pid " ~ ($timeout ?? "with timeout $timeout seconds" !! "");
  $!start-time = DateTime.now;
  sleep 0.01;
  $.output-stream.send: %( txt => [t.color(%COLORS<button>) => "[cancel]" ], meta => { action => 'kill_proc', :$proc } );
  $!ready-vow.keep(True);
  return $pid;
}

method do-done($res) {
  self.info: "-- done in " ~ duration( (DateTime.now - $!start-time).Int ) ~ ' --';
  given $res {
    if .signal { self.warn: "Process terminated with signal $^code" }
    if .exitcode { self.warn: "Process exited with code $^code" }
  }
}

method start-react-loop($proc, :$cell, :$out) {
  info "starting react loop";
  my $cwd = $cell.data-dir;
  my $env = %*ENV.clone;
  my $supply = $.input-supplier.Supply;
  for self.add-env.kv -> $k, $v { $env{$k} = $v; }
  $!promise = start react {
    whenever $proc.ready {
      info "proc is ready";
      self.do-ready($_, $proc);
    }
    whenever $proc.stdout.lines {
      self.stream: $_;
      $out.put($_) if $out;
    }
    whenever $proc.stderr.lines { $.output-stream.send: "ERR: $_"; sleep 0.01;}
    whenever $proc.start(:$cwd,:ENV($env)) { info "proc is done"; self.do-done($_); done; }
    whenever $supply {
      trace "sending to proc stdin: $_";
      $.output-stream.send: [ t.color(%COLORS<input>) => "[sending] $_" ],;
      $proc.put($_);
      trace "sent to proc stdin";
    }
  }
}

method execute(:$cell, :$mode, :$page, :$out) {
  my @cmd = self.command;
  my $content = $cell.get-content(:$mode, :$page).trim;
  if defined($.promise) || defined($!proc) {
    info "reusing existing REPL process";
  } else {
    info "executing process {@cmd.join(' ')}";
    # stream forever
    $!out = $cell.output-file.open(:a);
    $!proc = Proc::Async.new: |@cmd, :out, :err, :w;
    self.start-react-loop($!proc, :$cell, :out($!out));
    await $!ready; # wait for react loop to be ready
  }
  trace "Sending content to REPL:\n$content";
  for $content.trim.lines {
    $.input-supplier.emit("$_\n");
    sleep 0.5;
  }
}

method shutdown {
  info "shutdown called, proc defined: {$!proc.defined}";
  if $!proc {
    info "shutting down REPL process, promise status: {$.promise.status}";
    info "marking input supplier as done";
    $!input-supplier.done;
    info "input supplier done";
    try {
      # Close stdin to signal EOF
      info "closing stdin to send EOF";
      $!proc.close-stdin;
      info "stdin closed";
      with $.promise {
        info "waiting up to 2 seconds for process to exit";
        await Promise.anyof($_, Promise.in(2));
        info "wait completed, promise status: {$.promise.status}";
      }
      # If still running, send TERM signal
      if $.promise.status ~~ PromiseStatus::Planned {
        info "process still running after EOF, sending SIGTERM";
        $!proc.kill(SIGTERM);
        info "SIGTERM sent, waiting 1 second";
        await Promise.anyof($.promise, Promise.in(1));
        info "wait completed, promise status: {$.promise.status}";
      }
      # Last resort: SIGKILL
      if $.promise.status ~~ PromiseStatus::Planned {
        info "process still running after SIGTERM, sending SIGKILL";
        $!proc.kill(SIGKILL);
        info "SIGKILL sent";
      }
    }
    # Close output file
    if $!out {
      info "closing output file";
      $!out.close;
      info "output file closed";
    }
    info "setting proc to Nil";
    $!proc = Nil;
    info "shutdown complete";
  } else {
    info "shutdown called but no proc to shut down";
  }
}
