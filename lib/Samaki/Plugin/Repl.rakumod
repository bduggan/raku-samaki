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
has $!proc;
has Bool $.shutting-down = False;
has $.last-prompt;
has Promise $.prompt-promise = Promise.new;

method start-repl($pane) {
  trace "starting repl";
  $pane.clear with $pane;
  self.info: "init repl";
  unlink $!fifo-file if $!fifo-file.IO.e;
  trace "making fifo file at " ~ $!fifo-file.IO.resolve.absolute;
  shell "mkfifo $!fifo-file";
  $!fifo = $!fifo-file.IO.open(:ra, :0out-buffer, :0in-buffer);
  self.info: "Starting REPL process " ~ $!fifo-file.IO.resolve.absolute;
  trace "starting raku repl process";
  $!promise = start {
    $!proc = shell "raku --repl-mode=process < $!fifo-file", :out;
  }
  sleep 0.5;
  trace "starting output reader";
  $!out-promise = start {
    my regex prompt { '[' \d+ ']' }
    loop {
      trace "waiting for output chunk";
      my $raw = $!proc.out.read;
      trace "got output chunk " ~ $raw.decode.raku;
      last if !defined($raw);
      my $chunk = $raw.decode;
      if $chunk ~~ /<prompt>/ {
        $!last-prompt = $<prompt>.Str;
        $!prompt-promise.keep;
        $!prompt-promise = Promise.new;
      }

      if self.shutting-down {
        debug "shutting down, ignoring chunk: " ~ $chunk;
        last;
      } else {
        self.stream($chunk)
      }
      next;
    }
  }
}

method execute(:$cell, :$mode, :$page, :$out, :$pane) {
  $pane.auto-scroll = True with $pane;
  unless defined($.promise) {
    self.start-repl($pane);
  }
  my $input = $cell.get-content(:$mode, :$page).trim;
  unless $!last-prompt {
    my $timeout = Promise.in(10);
    await Promise.anyof($timeout, $!prompt-promise);
    unless $!last-prompt {
      die "Timeout waiting for REPL prompt (10 seconds)";
    }
  }
  for $input.lines {
    $.output-stream.send([ t.color(%COLORS<data>) => $_ ] );
    sleep 0.01;
  }
  $!fifo.put("$input") or die "could not write to fifo";
  sleep 1;
}

method shutdown {
  $!shutting-down = True;
  if defined($!fifo) {
    info "sending exit to REPL fifo";
    try $!fifo.put: "exit";
    $!fifo.close;
    $!fifo = Nil;
  }
  if defined($!fifo-file) && $!fifo-file.IO.e {
    info "Removing fifo file " ~ $!fifo-file.IO.resolve.absolute;
    unlink $!fifo-file;
    $!fifo-file = Nil;
  }
}

