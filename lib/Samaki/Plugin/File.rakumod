use Samaki::Plugin;
unit class Samaki::Plugin::File does Samaki::Plugin;
has $.name = 'file';
has $.description = 'Read a file';
has $.write-output = False;

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  my IO::Path $filename = $cell.output-file;
  if $filename.IO.e {
    $!output = "found file : " ~ $filename.relative;
  } else {
    $!output = "file $filename not found";
  }
}
