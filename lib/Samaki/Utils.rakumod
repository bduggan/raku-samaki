unit module Samaki::Utils;
use Log::Async;

sub shell-open(IO::Path(Str) $rel) is export {
  # Check if shell-open is disabled (e.g., during batch runs)
  if $*SAMAKI-NO-SHELL-OPEN {
    info "shell-open disabled, skipping open for $rel";
    return 0;
  }

  my $file = $rel.resolve.absolute;
  info "calling open $file, in $*CWD";
  my $proc;
  given $*DISTRO {
    when /macos/ {
      $proc = shell <<open $file>>, :err, :out;
    }
    default {
      $proc = shell <<xdg-open $file>>, :err, :out;
    }
  }
  if $proc.err.slurp -> $err {
     warning "$_" for $err.lines;
  }
  if $proc.out.slurp -> $out {
    info "$_" for $out.lines;
  }
  $proc.exitcode;
}

sub html-escape($html) is export {
  return '' unless defined $html;
  $html.Str.subst('&', '&amp;', :g)
       .subst('<', '&lt;', :g)
       .subst('>', '&gt;', :g)
       .subst('"', '&quot;', :g)
       .subst("'", '&#39;', :g);
}

sub show-datum($d) is export {
  return 'Nil' unless defined $d;
  given $d {
    when Date | DateTime { $d.Str; }
    when Numeric { $d }
    default { $d.Str; }
  }
}

my $stream-log-level = 'quiet';

sub set-stream-log-level(Str $level) is export {
  info "Setting stream log level to $level";
  $stream-log-level = $level;
}

sub get-stream-log-level() is export {
  return $stream-log-level;
}

sub log-visible( $line-level) is export {
  return True unless $line-level.defined;
  # only supporting output-level = 'verbose', line-level = 'info' for now
  # output-level may be undefined or 'quiet'
  given $stream-log-level {
    when 'quiet' {
      return False;
    }
    when 'verbose' {
      return True if $line-level eq 'info';
      return False;
    }
  }
  return True;
}

