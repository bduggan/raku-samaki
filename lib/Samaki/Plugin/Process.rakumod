use Samaki::Plugin;
use Terminal::ANSI::OO 't';
use Samaki::Conf;
use Time::Duration;
use Log::Async;

unit role Samaki::Plugin::Process[
  :$name="unnamed",
  :$cmd = Nil,
] does Samaki::Plugin;

has $.start-time;

method name { $name }

method description { "Run $name in a separate process" }

method stream-output { True };

method add-env { %() }

method wrap { 'word' }

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

method do-react-loop($proc, :$cell, :$out) {
  info "starting react loop";
  my $cwd = $cell.data-dir;
  my $env = %*ENV.clone;
  for self.add-env.kv -> $k, $v { $env{$k} = $v; }
  react {
    whenever $proc.ready { info "proc is ready"; self.do-ready($_, $proc); }
    whenever $proc.stdout.lines { $.output-stream.send: $_; $out.put($_) if $out; sleep 0.01; }
    whenever $proc.stderr.lines { $.output-stream.send: "ERR: $_"; sleep 0.01;}
    whenever $proc.start(:$cwd,:$env) { info "proc is done"; self.do-done($_); done; }
  }
}

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  my @cmd = self.command;
  info "executing process {@cmd.join(' ')}";
  $cell.get-content(:$mode, :$page) ==> spurt self.tmpfile;
  my $proc = Proc::Async.new: |@cmd, :out, :err;
  self.do-react-loop($proc, :$cell, :$out);
}

method tmpfile {
  $*TMPDIR.child("/samaki-tmp-script")
}

method command( --> List) {
  $cmd, self.tmpfile
}

