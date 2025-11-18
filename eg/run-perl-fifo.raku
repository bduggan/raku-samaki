#!/usr/bin/env raku

shell "rm -f raku-fifo";
shell "mkfifo raku-fifo";

#%*ENV<RAKUDO_LINE_EDITOR> = 'none';
#%*ENV<RAKUDO_DISABLE_MULTILINE> = 'true';

my $proc;

my $p = start {
  $proc = shell "perl -de1 < raku-fifo", :out;
  say "DONE";
}

say "starting react loop";
sleep 1;
start loop {
  my $buf = $proc.out.read;
  say "got : " ~ $buf.decode.raku;
}

say "opening fifos";

my $fifo = "raku-fifo".IO.open(:ra, :0out-buffer, :0in-buffer);

# $fifo.put(""); # Why is this necessary?

loop {
  sleep 1;
  my $cmd = prompt "command> ";
  last if !$cmd || $cmd.trim eq 'exit';
  $fifo.print("$cmd\n");
}

