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
method clear-stream-before { False }

has $.promise;
has $.fifo-file = $*TMPDIR.child('repl-fifo');
has $.fifo;
has $.out-promise;

method start-repl($pane) {
  $pane.clear;
  self.info: "init repl";
  unlink $!fifo-file if $!fifo-file.IO.e;
  shell "mkfifo $!fifo-file";
  $!fifo = $!fifo-file.IO.open(:ra, :0out-buffer, :0in-buffer);
  my $proc;
  self.info: "Starting REPL process " ~ $!fifo-file.IO.resolve.absolute;
  $!promise = start {
    $proc = shell "raku --repl-mode=process < $!fifo-file", :out;
  }
  sleep 0.5;
  $!out-promise = start {
    my regex prompt { '[' \d+ ']' }
    loop {
      my $raw = $proc.out.read;
      last if !defined($raw);
      my $chunk = $raw.decode;
      self.stream($chunk);
      next;
    }
  }
}

method execute(:$cell, :$mode, :$page, :$out, :$pane) {
  $pane.auto-scroll = True;
  unless defined($.promise) {
    self.start-repl($pane);
  }
  my $input = $cell.get-content(:$mode, :$page).trim;
  for $input.lines {
    $.output-stream.send([ t.color(%COLORS<data>) => $_ ] );
    sleep 0.01;
  }
  $!fifo.put("$input") or die "could not write to fifo";
  sleep 1;
}

