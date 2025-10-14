use Samaki::Plugin;
use Terminal::ANSI::OO 't';
use Samaki::Conf;
use Time::Duration;
use Log::Async;

unit class Samaki::Plugin::Repl does Samaki::Plugin;

has $.start-time;

method name { "raku-repl" }
method description { "Run raku in a separate process" }
method stream-output { True };
method output-ext { 'txt' }
method wrap { 'word' }

has $.promise;
has $.fifo-file = $*TMPDIR.child('repl-fifo');
has $.fifo;
has $.out-promise;

method start-repl {
  $.output-stream.send: "init repl";
  unlink $!fifo-file if $!fifo-file.IO.e;
  shell "mkfifo $!fifo-file";
  my $proc;
  $!promise = start {
    $.output-stream.send: "Starting REPL process " ~ $!fifo-file.IO.resolve.absolute;
    $proc = shell "raku --repl-mode=process < $!fifo-file", :out;
    $.output-stream.send: "done with promise";
  }
  sleep 0.5;
  $.output-stream.send: "starting output loop";
  $!out-promise = start {
    loop {
      my $buf = $proc.out.read;
      $.output-stream.send: "got : " ~ $buf.decode.raku;
    }
  }
  $!fifo = $!fifo-file.IO.open(:ra, :0out-buffer, :0in-buffer);
}

method execute(:$cell, :$mode, :$page, :$out) {
  unless defined($.promise) {
    self.start-repl;
  }
  my $input = $cell.get-content(:$mode, :$page).trim;
  $.output-stream.send: "sending to fifo: $input";
  $!fifo.put("$input") or die "could not write to fifo";
}

