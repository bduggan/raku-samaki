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

=begin pod

=head1 NAME

Samaki::Plugin::Text -- Write text content to a file

=head1 DESCRIPTION

Write cell content to a text file. Supports special C<[link:pagename]> syntax for creating links to other Samaki pages.

=head1 OPTIONS

No specific options.

=head1 EXAMPLE

    -- text:notes.txt
    This is some text content.

    You can reference other pages: [link:otherpage]

Output: Creates C<notes.txt> with the content. When displayed, C<[link:otherpage]> is rendered as a clickable link that loads the "otherpage" notebook.

Example with interpolation:

    -- duck
    select 'Alice' as name, 30 as age;

    -- text:summary.txt
    The user 〈 cells(0).rows[0]<name> 〉 is 〈 cells(0).rows[0]<age> 〉 years old.

Output in C<summary.txt>:

    The user Alice is 30 years old.

=end pod
