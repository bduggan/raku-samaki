use Samaki::Plugin;
use Terminal::ANSI::OO 't';
use Samaki::Conf;
use Time::Duration;
use JSON::Fast;

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

sub count-coordinates($coords) {
  return 0 unless $coords;
  return 1 if $coords ~~ Numeric;
  return $coords.elems if $coords[0] ~~ Numeric;
  return [+] $coords.map: &count-coordinates;
}

sub analyze-geojson($path) {
  my $json = from-json($path.slurp);
  my %info;

  %info<type> = $json<type> // 'Unknown';

  if $json<type> eq 'FeatureCollection' {
    %info<features> = $json<features>.elems;
    if $json<features>.elems > 0 {
      my @geom-types = $json<features>.map(*<geometry><type>).grep(*.defined).unique;
      %info<geometry-types> = @geom-types.join(', ');
      %info<total-coords> = [+] $json<features>.map({ count-coordinates($_<geometry><coordinates>) });
    }
  } elsif $json<type> eq 'Feature' {
    %info<geometry-type> = $json<geometry><type> // 'Unknown';
    %info<coords> = count-coordinates($json<geometry><coordinates>);
    %info<properties> = $json<properties>.keys.elems if $json<properties>;
  } elsif $json<geometry> {
    %info<geometry-type> = $json<geometry><type> // 'Unknown';
    %info<coords> = count-coordinates($json<geometry><coordinates>);
  } elsif $json<coordinates> {
    %info<coords> = count-coordinates($json<coordinates>);
  }

  return %info;
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
    @lines.push: [ col('inactive') => 'Absolute:'.fmt('%10s'), col('title') => ' ', col('line') => $path.absolute ];

    # Check if it's a GeoJSON file and small enough to parse
    if $path.extension eq 'geojson' && $path.s < 100 * 1024 {
      try {
        my %geo = analyze-geojson($path);
        if %geo<type> {
          @lines.push: [ col('title') => '' ];
          @lines.push: [ col('inactive') => 'GeoJSON:'.fmt('%10s'), col('title') => ' ', col('yellow') => %geo<type> ];

          if %geo<features>:exists {
            @lines.push: [ col('inactive') => 'Features:'.fmt('%10s'), col('title') => ' ', col('data') => ~%geo<features> ];
          }
          if %geo<geometry-types>:exists {
            @lines.push: [ col('inactive') => 'Geometry:'.fmt('%10s'), col('title') => ' ', col('data') => %geo<geometry-types> ];
          }
          if %geo<geometry-type>:exists {
            @lines.push: [ col('inactive') => 'Geometry:'.fmt('%10s'), col('title') => ' ', col('data') => %geo<geometry-type> ];
          }
          if %geo<total-coords>:exists {
            @lines.push: [ col('inactive') => 'Coords:'.fmt('%10s'), col('title') => ' ', col('data') => ~%geo<total-coords> ];
          }
          if %geo<coords>:exists {
            @lines.push: [ col('inactive') => 'Coords:'.fmt('%10s'), col('title') => ' ', col('data') => ~%geo<coords> ];
          }
          if %geo<properties>:exists {
            @lines.push: [ col('inactive') => 'Props:'.fmt('%10s'), col('title') => ' ', col('data') => ~%geo<properties> ];
          }
        }
        CATCH {
          default {
            @lines.push: [ col('error') => "Error parsing JSON: $_" ];
          }
        }
      }
    }

    for @lines -> $line {
      $.output-stream.send: %( txt => $line );
    }
  } else {
    $.output-stream.send: %( txt => [ col('error') => "file $filename not found" ] );
  }
}
