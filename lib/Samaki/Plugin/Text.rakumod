use Samaki::Plugin;
use Log::Async;
use Terminal::ANSI::OO 't';
use Samaki::Conf;

unit class Samaki::Plugin::Text does Samaki::Plugin;

has $.name = 'text';
has $.description = 'Text cell, with optional links to other pages';

method select-action { 'save' }

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  $cell.output-file.spurt: $cell.get-content(:$mode, :$page);
  self.info: "Wrote text to " ~ $cell.output-file;
}

my regex page { <[a..zA..Z0..9]>+ }

method line-meta($text, :$cell) {
  if $text ~~ /'[link:' <page> ']'/ {
    return %( action => 'load_page', page_name => ~$<page>, wkdir => $cell.wkdir );
  }
  return %();
}

method line-format(Str $line) {
  return $line unless $line ~~ /'[link:' <page> ']'/;
  my @pieces = $line.split: / '[link:' <page> \] /, :v;
  my @out = @pieces.map: {
    when Match {
      t.color(%COLORS<title>) => "[〜 $<page> 〜]"
    }
    default {
      t.color("#ffffff") => $_
    }
  }
  @out;
}
