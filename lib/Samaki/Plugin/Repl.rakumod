use Samaki::Plugin;
use Terminal::ANSI::OO 't';
use Samaki::Conf;
use Time::Duration;
use Log::Async;

unit role Samaki::Plugin::Repl[
  :$name="unnamed",
  :$cmd = Nil,
] does Samaki::Plugin;

has $.start-time;

method name { $name }

method description { "Run $name in a separate process" }

method stream-output { True };

method add-env { %() }

method output-ext { 'txt' }

method wrap { 'word' }

has $.promise;
has $.input-supplier = Supplier.new;

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

method start-react-loop($proc, :$cell, :$out) {
  info "starting react loop";
  my $cwd = $cell.data-dir;
  my $env = %*ENV.clone;
  my $supply = $.input-supplier.Supply;
  for self.add-env.kv -> $k, $v { $env{$k} = $v; }
  $!promise = start react {
    whenever $proc.ready { info "proc is ready"; self.do-ready($_, $proc); }
    whenever $proc.stdout {
      $.output-stream.send("$_\n");
      $out.put($_) if $out;
    }
    whenever $proc.stderr.lines { $.output-stream.send: "ERR: $_"; sleep 0.01;}
    whenever $proc.start(:$cwd,:$env) { info "proc is done"; self.do-done($_); done; }
    whenever $supply {
      $.output-stream.send: [ t.color(%COLORS<input>) => "$_" ],;
      $proc.print($_);
    }
    # maybe we need to close-stdin and call done at some point
  }
}

method execute(:$cell, :$mode, :$page, :$out) {
  my @cmd = self.command;
  info "executing process {@cmd.join(' ')}";
  my $content = $cell.get-content(:$mode, :$page).trim;
  unless defined($.promise) {
    # stream forever
    my $out2 = $cell.output-file.open(:a);
    my $proc = Proc::Async.new: |@cmd, :out, :err, :w;
    self.start-react-loop($proc, :$cell, :out($out2));
    sleep 2;
  }
  for $content.trim.lines {
     $.input-supplier.emit("$_\n");
     sleep 0.5;
  }
}

method command( --> List) {
  <<raku --repl-mode=process>>
}

