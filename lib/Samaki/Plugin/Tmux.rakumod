use Log::Async;

use Samaki::Conf;
use Samaki::Plugin;

unit role Samaki::Plugin::Tmux[
  :$name=Nil,
  :$cmd=Nil,
] does Samaki::Plugin;

method command { $cmd }

has Str $.tmux-pane-id is rw;
has Str $.tmux-window-id is rw;
has %!named-sessions;  # name => { pane-id => ..., window-id => ... }
has Proc::Async $!control-proc;
has Promise $!control-promise;
has $!line-delay-seconds = 0.1;
has $!buffer = '';
has $.initial-output-captured is rw = False;
has Supplier $!output-supplier;

method write-output { False }
method name { $name // $cmd }
method description { "Run a command in a tmux pane for " ~ self.name }

method check-tmux-session(--> Bool) {
  return %*ENV<TMUX>:exists && %*ENV<TMUX>.chars > 0;
}

method decode-tmux-output(Str $s --> Blob) {
  # tmux control mode escapes non-printable chars and backslash as octal \xxx
  # Convert the escaped string back to raw bytes
  my @bytes;
  my $i = 0;
  while $i < $s.chars {
    if $s.substr($i, 1) eq '\\' && $i + 3 < $s.chars {
      my $next3 = $s.substr($i + 1, 3);
      if $next3 ~~ /^ <[0..7]> ** 3 $/ {
        # Octal escape sequence
        @bytes.push: :8($next3);
        $i += 4;
        next;
      }
    }
    # Push ALL bytes of the UTF-8 encoded character, not just the first
    @bytes.append: $s.substr($i, 1).encode.list;
    $i++;
  }
  return Blob.new(@bytes);
}

method start-control-client($pane) {
  info "starting tmux control client";

  # Kill any existing control client first
  with $!control-proc {
    debug "killing old control client";
    try $!control-proc.kill(SIGTERM);
  }

  $!control-proc = Proc::Async.new(:w, 'tmux', '-C', 'attach');
  $!buffer = '';

  with $!output-supplier {
    $!output-supplier.done;
  }

  $!output-supplier = Supplier.new;
  $pane.stream: $!output-supplier.Supply;

  # Buffer for accumulating bytes until we have complete UTF-8 sequences
  my Buf $byte-buffer = Buf.new;

  $!control-proc.stdout(:bin).tap: -> $buf {
    # Accumulate bytes
    $byte-buffer.append: $buf;

    # Try to decode as much as possible, leaving incomplete UTF-8 at the end
    my $decoded = '';
    my $valid-end = 0;

    # Find the last position where we have valid UTF-8
    # by trying progressively shorter prefixes
    my $len = $byte-buffer.elems;
    while $len > 0 {
      my $try-buf = $byte-buffer.subbuf(0, $len);
      my $try-decode = try { $try-buf.decode('utf-8') };
      if $try-decode.defined {
        $decoded = $try-decode;
        $valid-end = $len;
        last;
      }
      $len--;
    }

    if $valid-end > 0 {
      # Remove the decoded portion from the buffer
      $byte-buffer = $byte-buffer.subbuf($valid-end);
      $!buffer ~= $decoded;
      self.process-control-output;
    }
  };

  $!control-proc.stderr.tap: -> $err {
    warning "tmux control stderr: $err";
  };

  $!control-promise = $!control-proc.start;

  # Give it time to connect
  sleep 0.3;

  # Enable output for our pane
  self.enable-pane-output;
}

method enable-pane-output {
  return without $!control-proc;
  return without $!tmux-pane-id;
  my $cmd = "refresh-client -A {$!tmux-pane-id}" ~ ':on';
  debug "enabling pane output: $cmd";
  $!control-proc.say: $cmd;
}

method process-control-output {
  # Process complete lines from buffer
  while $!buffer ~~ /^ (.*?) \n (.*)/ {
    my $line = ~$0;
    $!buffer = ~$1;

    # Parse %output notifications: %output %pane-id value
    if $line ~~ /^ '%output' \s+ ('%' \d+) \s+ (.*)/ {
      my $pane-id = ~$0;

      if $pane-id.defined && $!tmux-pane-id.defined && $pane-id eq $!tmux-pane-id && $.initial-output-captured {
        # Decode the octal-escaped output to raw bytes and emit to supplier
        my $bytes = self.decode-tmux-output(~$1);
        $!output-supplier.emit: $bytes;
      }
    } elsif $line ~~ /^ '%error'/ {
      warning "tmux control error: $line";
    }
  }
}

method create-tmux-window($samaki-pane, :$cell --> Str) {
  my $shared-name = $cell.?get-conf('name');
  my $window-name = $shared-name // $cell.name;

  # Create new window
  # -d: don't switch to the new window
  # -P: print info after creating
  # -F: format string for output (pane_id and window_id)
  # -n: window name
  my $proc = run 'tmux', 'new-window', '-d', '-P', '-F', '#{pane_id} #{window_id}',
                 '-n', $window-name, self.command, :out;
  my $output = $proc.out.slurp(:close).trim;
  my ($pane-id, $window-id) = $output.split(' ');
  info "created tmux window '$window-name': $window-id with pane: $pane-id";

  $!tmux-window-id = $window-id;

  if $shared-name {
    %!named-sessions{$shared-name} = { pane-id => $pane-id, window-id => $window-id };
  }

  return $pane-id;
}

method send-to-pane(Str $text) {
  return without $!tmux-pane-id;
  debug "sending to pane {$!tmux-pane-id}: {$text.raku}";
  # Use -l to send literal text (no key name lookup)
  run 'tmux', 'send-keys', '-t', $!tmux-pane-id, '-l', $text;
  run 'tmux', 'send-keys', '-t', $!tmux-pane-id, 'Enter';
}

method kill-window {
  info "maybe killing window";
  return unless self.window-exists;
  run 'tmux', 'kill-window', '-t', $!tmux-window-id;
}

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  # Check we're in tmux
  unless self.check-tmux-session {
    self.error: "Not in a tmux session. Please run samaki from within tmux.";
    return;
  }

  # Check for delay config
  with $cell.get-conf('delay') -> $delay {
    $!line-delay-seconds = $delay;
    self.info: "Seconds between sending lines: $delay";
  }

  info "launching {self.name} tmux session";

  # Reuse the existing window only when a shared name is configured and that
  # named session is recorded in the hash and its window still exists.
  # Otherwise always create a fresh window for this cell.
  my $shared-name = $cell.?get-conf('name');
  my $reuse = False;
  if $shared-name && %!named-sessions{$shared-name} {
    $!tmux-pane-id   = %!named-sessions{$shared-name}<pane-id>;
    $!tmux-window-id = %!named-sessions{$shared-name}<window-id>;
    $reuse = self.window-exists;
  }
  unless $reuse {
    $pane.clear;
    $!tmux-pane-id = self.create-tmux-window($pane, :$cell);
    self.stream: [color('info') => "started tmux window {$!tmux-window-id} (pane {$!tmux-pane-id}) for {self.name}"];
    self.stream: txt => [color('button') => "[exit]"], meta => %( action => 'plugin_call', method => 'kill-window', plugin => self );

    # Start the control client for output streaming
    self.start-control-client($pane);

    # Wait for initial prompt output to pass
    sleep 0.5;
    $.initial-output-captured = True;
  }

  # Send the cell content to the pane
  my $input = $cell.get-content(:$mode, :$page).trim;
  for $input.lines -> $line {
    sleep $!line-delay-seconds if $!line-delay-seconds > 0;
    debug "sending line: " ~ $line.raku;
    self.send-to-pane($line);
  }

  # Give time for output to be streamed
  sleep 0.5;
}

method window-exists(--> Bool) {
  return False without $!tmux-window-id;
  my $proc = run 'tmux', 'list-windows', '-a', '-F', '#{window_id}', :out;
  my @windows = $proc.out.slurp(:close).lines;
  return $!tmux-window-id ∈ @windows;
}

method shutdown {
  # Close the output supplier
  with $!output-supplier {
    $!output-supplier.done;
  }

  # Close the control client
  with $!control-proc {
    info "closing tmux control client";
    try $!control-proc.kill(SIGTERM);
    await Promise.anyof($!control-promise, Promise.in(1)) if $!control-promise;
  }

  # Kill the tmux window if it exists
  if $!tmux-window-id && self.window-exists {
    info "killing tmux window {$!tmux-window-id}";
    run 'tmux', 'kill-window', '-t', $!tmux-window-id;
  }

  $!tmux-pane-id = Nil;
  $!tmux-window-id = Nil;
  %!named-sessions = ();
  $!control-proc = Nil;
  $!output-supplier = Nil;
  $.initial-output-captured = False;
}

=begin pod

=head1 NAME

Samaki::Plugin::Tmux -- Base class for tmux-based interactive plugins

=head1 SYNOPSIS

    # Create a subclass for a specific command
    use Samaki::Plugin::Tmux;

    unit class Samaki::Plugin::Tmux::MyCommand is Samaki::Plugin::Tmux;

    method name { "tmux-mycommand" }
    method description { "Run mycommand in a tmux pane" }
    has $.command = 'mycommand';

=head1 DESCRIPTION

This role provides a base class for plugins that interact with commands
running in tmux windows. Unlike the L<Samaki::Plugin::Repl> plugins which use
a PTY to capture output, this plugin uses tmux's control mode protocol to:

=item Create new tmux windows for running commands
=item Stream output from windows in real-time via %output notifications
=item Send input to windows using tmux send-keys
=item Maintain persistent sessions across cell executions

=head2 Key Features

=item B<Real tmux windows> - Each command runs in its own tmux window, visible
in your tmux session and accessible via normal tmux window switching (C-b n/p).

=item B<Multiple simultaneous sessions> - Different plugin instances maintain
separate windows, allowing multiple independent sessions.

=item B<Control mode streaming> - Output is streamed via tmux's control mode
protocol, providing real-time updates without polling.

=head1 REQUIREMENTS

The user must be running samaki from within a tmux session. The plugin will
error if the TMUX environment variable is not set.

=head1 OPTIONS

=item C<delay> -- Seconds to wait between sending lines (default: 0.1)

=item C<name> -- Name of the tmux window to use. By default each cell creates
a new tmux window. When C<name> is set, all cells with the same name share a
single tmux window (creating it on first use).

=head1 SEE ALSO

L<Samaki::Plugin::Repl> - Alternative approach using PTY
L<Samaki::Plugin::Tmux::Bash> - Bash shell example
L<Samaki::Plugin::Tmux::Python> - Python interpreter example

=end pod
