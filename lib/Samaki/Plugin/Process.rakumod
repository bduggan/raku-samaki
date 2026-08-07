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
has @.stderr-lines;

method name { $name }

method description { "Run $name in a separate process" }

method add-env { %() }

method wrap { 'word' }

#| Stream output as it is produced, when the cell has no `stream` conf?
method default-stream-output(Samaki::Cell :$cell) { $cell.ext ne 'csv' }

method use-stdin { $use-stdin }

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
  $.output-stream.send: %( txt => [color('button') => "[cancel]" ], meta => { action => 'kill_proc', :$proc } );
  return $pid;
}

method do-done($res) {
  self.info: "-- done in " ~ duration( (DateTime.now - $!start-time).Int ) ~ ' --';
  my $failure;
  given $res {
    if .signal {
      self.warn: "Process terminated with signal $^code";
      $failure = "Process terminated with signal $^code";
    }
    if .exitcode {
      self.warn: "Process exited with code $^code";
      $failure = "Process exited with code $^code";
    }
  }
  with $failure {
    my $msg = $_;
    $msg ~= "\n" ~ @!stderr-lines.join("\n") if @!stderr-lines;
    $.errors = ($.errors // '') ~ $msg;
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
      $.output-stream.send: $_ if $.stream-output;
      $out.put($_) if $out;
      sleep 0.01;
    }
    whenever $proc.stderr.lines { self.warn: "$_"; @!stderr-lines.push: $_; sleep 0.01;}
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
  # confs
  my $timeout = $cell.get-conf('timeout') // $cell.timeout;
  with $cell.get-conf('scroll') -> $s {
    .auto-scroll = so ($s && $s ne <no off none>.any) with $pane;
  } else {
    .auto-scroll = True with $pane;
  }
  my $input = $cell.get-content(:$mode, :$page);
  $.errors = Nil;
  @!stderr-lines = ();
  self.clear-output;
  with $cell.get-conf('stream') -> $stream {
    $.stream-output = $stream ne 'none';
  } else {
    $.stream-output = self.default-stream-output(:$cell);
  }

  info "using " ~ (self.use-stdin ?? "stdin" !! "a temp file") ~ " for input";
  my @cmd = self.build-command(:$cell);
  info "executing process {@cmd.raku}";

  if self.use-stdin {
    my $proc = Proc::Async.new: |@cmd, :out, :err, :w;
    try {
      self.do-react-loop($proc, :$cell, :$out, :$input, :$timeout);
      CATCH { default { self.error("Execution failed: $_"); } }
    }
    $out.close;
    if $.errors {
      return;
    }
    # A command may exit 0 yet have failed (e.g. snowsql prints SQL errors to
    # stderr and still exits 0). Treat "no real output + stderr" as a failure.
    my $out-io = $cell.output-file.IO;
    my $out-size = $out-io.e ?? $out-io.s !! 0;
    # A "real" result needs more than a lone trailing newline. Some tools exit 0
    # yet only write diagnostics to stderr (e.g. snowsql on a SQL error), leaving
    # an empty or newline-only output file. Treat that as a failure and surface
    # the captured stderr.
    if $out-size <= 1 && @!stderr-lines {
        $.errors = @!stderr-lines.join("\n");
        return;
    }
    if $out-size == 0 {
        $.errors = "No output generated";
        return;
    }
    if $cell.ext eq 'csv' {
      self.set-output(self.output-duckie($cell.output-file));
    }
  } else {
    $input ==> spurt self.tmpfile;
    my $proc = Proc::Async.new: |@cmd, :out, :err;
    self.do-react-loop($proc, :$cell, :$out, :$timeout);
  }
}

method tmpfile {
  $*TMPDIR.child("/samaki-tmp-script")
}

=begin pod

=head1 NAME

Samaki::Plugin::Process -- Base role for process-based plugins

=head1 DESCRIPTION

This is a base role for plugins that execute code in a separate process. It provides common functionality for running external commands, handling input and output, and managing the process lifecycle. Specific language plugins (like Samaki::Plugin::Raku) can consume this role and provide language-specific details.

=head1 OPTIONS

=head2 timeout

Number of seconds to wait before killing the process. Default is 60 seconds.

=head2 scroll

Whether to auto-scroll the output pane. Default is True.  Set to "no", "off", or "none" to disable.

=end pod

