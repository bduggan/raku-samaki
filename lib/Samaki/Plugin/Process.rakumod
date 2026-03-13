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

method add-env { %() }

method wrap { 'word' }

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
      $.output-stream.send: $_ if $.stream-output;
      $out.put($_) if $out;
      sleep 0.01;
    }
    whenever $proc.stderr.lines { self.warn: "$_"; sleep 0.01;}
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
  self.clear-output;
  if $cell.get-conf('stream') {
    $.stream-output = $cell.get-conf('stream') eq 'none' ?? False !! True;
  } else {
    my $default-stream-output = True;
    $default-stream-output = False if $cell.ext eq 'csv';
    $.stream-output = False;
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
    if $cell.output-file.IO andthen !(.e && (.s > 0)) {
        $.errors = "No output generated";
        return;
    }
    $out.close;
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

