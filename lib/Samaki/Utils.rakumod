unit module Samaki::Utils;
use Log::Async;

sub shell-open(IO::Path(Str) $rel) is export {
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

