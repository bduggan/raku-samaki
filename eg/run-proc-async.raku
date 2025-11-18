#!/usr/bin/env raku

%*ENV<RAKUDO_LINE_EDITOR> = 'none';
%*ENV<RAKUDO_DISABLE_MULTILINE> = 'true';

# note: in the terminal
#
# $ raku --repl-mode=process
# Welcome to Rakudo™ v2025.08.
# Implementing the Raku® Programming Language v6.d.
# Built on MoarVM version 2025.08.
#
# To exit type 'exit' or '^D'
# [0] >
#
# but with proc-async, the "To exit.." does not show up without
# some input first.

my $proc = Proc::Async.new( |<raku --repl-mode=process>, :out, :w );

say "starting react loop";
my $promise = start react {
  whenever $proc.ready { say "process ready, pid $_" }
  whenever $proc.stdout(:bin) { say "OUT: " ~ .raku; say "decoded: " ~ .decode('utf-8') }
  whenever $proc.start { say "done: $_" }
}

sleep 2;

#$proc.put: ""; # why is this necessary?

loop {
  say "waiting 1 second";
  sleep 1;
  say "done";
  my $cmd = prompt "command> ";
  if !$cmd || $cmd.trim eq 'exit' {
    $proc.put: "exit\n";
    last;
  }
  await $proc.put: "$cmd";
}

await $promise;
