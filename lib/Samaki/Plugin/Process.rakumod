use Samaki::Plugin;
use Terminal::ANSI::OO 't';
use Samaki::Conf;
use Time::Duration;
use Log::Async;

unit role Samaki::Plugin::Process[
  :$name="unnamed",
  :$cmd = Nil,
  :$args = [],
  Bool :$use-stdin = False
] does Samaki::Plugin;

has $.start-time;

method name { $name }

method description { "Run $name in a separate process" }

has Bool $.stream-output = True;

method add-env { %() }

method wrap { 'word' }

method use-stdin { $use-stdin }

method stream-stdout-to-pane { True }

method build-command(Samaki::Cell :$cell) {
  die "missing cmd parameter" unless $cmd;
  my @cmd = ($cmd);
  if $args.elems {
    @cmd.push( |$args );
  }
  return @cmd if $use-stdin;
  @cmd.push( self.tmpfile.Str );
  @cmd;
}

method do-ready($pid, $proc, $timeout = Nil) {
  self.info: "started pid $pid " ~ ($timeout ?? "with timeout $timeout seconds" !! "");
  $!start-time = DateTime.now;
  sleep 0.01;
  $.output-stream.send: %( txt => [t.color(%COLORS<button>) => "[cancel]" ], meta => { action => 'kill_proc', :$proc } );
  return $pid;
}

method do-done($res) {
  self.info: "-- done in " ~ duration( (DateTime.now - $!start-time).Int ) ~ ' --';
  given $res {
    if .signal { self.warn: "Process terminated with signal $^code" }
    if .exitcode { self.warn: "Process exited with code $^code" }
  }
}

method do-react-loop($proc, :$cell, :$out, :$input, :$timeout) {
  info "starting react loop";
  my $cwd = $cell.data-dir;
  my $env = %*ENV.clone;
  for self.add-env.kv -> $k, $v { $env{$k} = $v; }
  react {
    whenever $proc.ready { info "proc is ready"; self.do-ready($_, $proc, $timeout); }
    whenever $proc.stdout.lines {
      $.output-stream.send: $_ if self.stream-stdout-to-pane;
      $out.put($_) if $out;
      sleep 0.01;
    }
    whenever $proc.stderr.lines { $.output-stream.send: "ERR: $_"; self.warn: "$_"; sleep 0.01;}
    whenever $proc.start(:$cwd,:$env) { info "proc is done"; self.do-done($_); done; }
    if $input {
      whenever $proc.print($input) {
        $proc.close-stdin;
      }
    }
    if $timeout {
      whenever Supply.interval(1) {
        self.info("elapsed time: $_ seconds") if $_ > 3 && $_ %% 5;
      }
      whenever Promise.in($timeout) {
        $.output-stream.send: "Timeout. Asking the process to stop";
        $proc.kill;
        whenever Promise.in(2) {
          $.output-stream.send: "timeout again, now forcing the process to stop";
          $proc.kill: SIGKILL
        }
      }
    }
  }
}

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  my $timeout = $cell.get-conf('timeout') // $cell.timeout;
  my $input-content = $cell.get-content(:$mode, :$page);
  $.errors = Nil;
  self.clear-output;

  if self.use-stdin {
    info "using stdin";
    my @cmd = self.build-command(:$cell);
    info "executing process {@cmd.raku}";
    my $proc = Proc::Async.new: |@cmd, :out, :err, :w;
    with $cell.get-conf('stream') -> $s {
      $!stream-output = $s ne 'none';
    } else {
      $!stream-output = True;
    }

    try {
      self.do-react-loop($proc, :$cell, :$out, input => $input-content, :$timeout);
      CATCH { default { self.error("Execution failed: $_"); } }
    }
    self.error("Execution failed: $_") with $!;
    $out.close;

    with $cell.output-file.IO {
      unless .e && (.s > 0) {
        $.errors = "No output generated";
        return;
      }
    }
    if self.output-ext eq 'csv' {
      self.set-output(self.output-duckie($cell.output-file));
    }
  } else {
    # Temp file-based execution (default)
    my @cmd = self.build-command(:$cell);
    info "executing process {@cmd.raku}";
    info "writing input to temp file " ~ self.tmpfile.Str;
    $input-content ==> spurt self.tmpfile;
    my $proc = Proc::Async.new: |@cmd, :out, :err;
    self.do-react-loop($proc, :$cell, :$out, :$timeout);
  }
}

method tmpfile {
  $*TMPDIR.child("/samaki-tmp-script")
}

