unit module Samaki::Utils;

sub shell-open($file) is export {
  given $*DISTRO {
    when /macos/ {
      shell "open '$file' 2>/dev/null";
    }
    default {
      shell "xdg-open '$file' 2>/dev/null";
    }
  }
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

