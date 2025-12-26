use Samaki::Plugin;
use Terminal::ANSI::OO 't';
use Samaki::Conf;
use Time::Duration;

unit class Samaki::Plugin::File does Samaki::Plugin;
has $.name = 'file';
has $.description = 'Read a file';
has $.write-output = False;

sub format-size(Int $bytes) {
  return "0 B" if $bytes == 0;
  my @units = <B KB MB GB TB>;
  my $unit-index = 0;
  my $size = $bytes;
  while $size >= 1024 && $unit-index < @units.end {
    $size /= 1024;
    $unit-index++;
  }
  return $size < 10 ?? sprintf("%.2f %s", $size, @units[$unit-index]) !! sprintf("%.0f %s", $size, @units[$unit-index]);
}

sub format-datetime(Instant $instant) {
  my $seconds-ago = (DateTime.now.Instant - $instant).Int;
  ago($seconds-ago);
}

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  my IO::Path $filename = $cell.output-file;
  if $filename.IO.e {
    my $path = $filename.IO;
    my @lines;
    @lines.push: [ col('inactive') => 'File:'.fmt('%10s'), col('title') => ' ', col('text') => $path.relative ];
    @lines.push: [ col('inactive') => 'Size:'.fmt('%10s'), col('title') => ' ', col('data') => format-size($path.s) ];
    @lines.push: [ col('inactive') => 'Modified:'.fmt('%10s'), col('title') => ' ', col('data') => format-datetime($path.modified) ];
    @lines.push: [ col('inactive') => 'Accessed:'.fmt('%10s'), col('title') => ' ', col('data') => format-datetime($path.accessed) ];
    @lines.push: [ col('inactive') => 'Changed:'.fmt('%10s'), col('title') => ' ', col('data') => format-datetime($path.changed) ];
    @lines.push: [ col('inactive') => 'Mode:'.fmt('%10s'), col('title') => ' ', col('data') => sprintf("0%o", $path.mode) ];
    @lines.push: [ col('inactive') => 'Absolute:'.fmt('%10s'), col('title') => ' ', col('line') => $path.absolute ];

    for @lines -> $line {
      $.output-stream.send: %( txt => $line );
    }
  } else {
    $.output-stream.send: %( txt => [ col('error') => "file $filename not found" ] );
  }
}
