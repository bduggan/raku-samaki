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

sub extract-bounds($coords, $bounds) {
  return unless $coords;

  # If we hit a coordinate pair [lon, lat]
  if $coords ~~ List && $coords.elems >= 2 && $coords[0] ~~ Numeric && $coords[1] ~~ Numeric {
    my ($lon, $lat) = $coords[0], $coords[1];
    $bounds<min-lon> min= $lon;
    $bounds<max-lon> max= $lon;
    $bounds<min-lat> min= $lat;
    $bounds<max-lat> max= $lat;
  } else {
    # Recurse into nested arrays
    extract-bounds($_, $bounds) for $coords.list;
  }
}

sub analyze-geojson($path) {
  my $json = from-json($path.slurp);
  my %info;
  my %bounds = min-lon => Inf, max-lon => -Inf, min-lat => Inf, max-lat => -Inf;

  %info<type> = $json<type> // 'Unknown';

  if $json<type> eq 'FeatureCollection' {
    %info<features> = $json<features>.elems;
    if $json<features>.elems > 0 {
      # Collect geometry types and their counts
      my $geom-bag = bag $json<features>.map(*<geometry><type>).grep(*.defined);
      if $geom-bag {
        %info<geometry-types> = $geom-bag.pairs.sort(*.key).map({ .key ~ " (" ~ .value ~ ")" }).join(', ');
      }
      %info<total-coords> = [+] $json<features>.map({ count-coordinates($_<geometry><coordinates>) });

      # Collect all property names and their counts across all features
      my $prop-bag = bag gather for $json<features>.list -> $feature {
        if $feature<properties> {
          take $_ for $feature<properties>.keys;
        }
      }
      if $prop-bag {
        %info<property-names> = $prop-bag.pairs.sort(*.key).map({ .key ~ " (" ~ .value ~ ")" }).list;
      }

      # Extract bounding box
      for $json<features>.list -> $feature {
        extract-bounds($feature<geometry><coordinates>, %bounds) if $feature<geometry><coordinates>;
      }
    }
  } elsif $json<type> eq 'Feature' {
    %info<geometry-type> = $json<geometry><type> // 'Unknown';
    %info<coords> = count-coordinates($json<geometry><coordinates>);
    if $json<properties> {
      %info<property-names> = $json<properties>.keys.sort.map({ $_ ~ " (1)" }).list;
    }
    extract-bounds($json<geometry><coordinates>, %bounds) if $json<geometry><coordinates>;
  } elsif $json<geometry> {
    %info<geometry-type> = $json<geometry><type> // 'Unknown';
    %info<coords> = count-coordinates($json<geometry><coordinates>);
    extract-bounds($json<geometry><coordinates>, %bounds) if $json<geometry><coordinates>;
  } elsif $json<coordinates> {
    %info<coords> = count-coordinates($json<coordinates>);
    extract-bounds($json<coordinates>, %bounds);
  }

  # Add bounds if we found any coordinates
  if %bounds<min-lon> != Inf {
    %info<bounds> = %bounds;
  }

  return %info;
}

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  my IO::Path $path = $cell.output-file;
  if $path.e {
    my @lines;
    self.stream:  txt => [ color('info') => "file:".fmt('%10s'), color('link') => "[" ~ $path.relative ~ "]" ],
                  meta => %( action => 'do_output', :$path  );
    @lines.push: [ color('inactive') => 'Size:'.fmt('%10s'), color('title') => ' ', color('data') => format-size($path.s) ];
    @lines.push: [ color('inactive') => 'Modified:'.fmt('%10s'), color('title') => ' ', color('data') => format-datetime($path.modified) ];
    @lines.push: [ color('inactive') => 'Accessed:'.fmt('%10s'), color('title') => ' ', color('data') => format-datetime($path.accessed) ];
    @lines.push: [ color('inactive') => 'Changed:'.fmt('%10s'), color('title') => ' ', color('data') => format-datetime($path.changed) ];
    @lines.push: [ color('inactive') => 'Absolute:'.fmt('%10s'), color('title') => ' ', color('line') => $path.absolute ];

    # Check if it's a GeoJSON file and small enough to parse
    if $path.extension eq 'geojson' && $path.s < 100 * 1024 {
      try {
        my %geo = analyze-geojson($path);
        if %geo<type> {
          @lines.push: [ color('title') => '' ];
          @lines.push: [ color('inactive') => 'GeoJSON:'.fmt('%10s'), color('title') => ' ', color('yellow') => %geo<type> ];

          if %geo<features>:exists {
            @lines.push: [ color('inactive') => 'Features:'.fmt('%10s'), color('title') => ' ', color('data') => ~%geo<features> ];
          }
          if %geo<geometry-types>:exists {
            @lines.push: [ color('inactive') => 'Geometry:'.fmt('%10s'), color('title') => ' ', color('data') => %geo<geometry-types> ];
          }
          if %geo<geometry-type>:exists {
            @lines.push: [ color('inactive') => 'Geometry:'.fmt('%10s'), color('title') => ' ', color('data') => %geo<geometry-type> ];
          }
          if %geo<total-coords>:exists {
            @lines.push: [ color('inactive') => 'Coords:'.fmt('%10s'), color('title') => ' ', color('data') => ~%geo<total-coords> ];
          }
          if %geo<coords>:exists {
            @lines.push: [ color('inactive') => 'Coords:'.fmt('%10s'), color('title') => ' ', color('data') => ~%geo<coords> ];
          }
          if %geo<property-names>:exists {
            @lines.push: [ color('inactive') => 'Props:'.fmt('%10s'), color('title') => ' ', color('data') => %geo<property-names>.join(', ') ];
          }
          if %geo<bounds>:exists {
            my $b = %geo<bounds>;
            my $bbox = sprintf("lon: [%.4f, %.4f] lat: [%.4f, %.4f]",
              $b<min-lon>, $b<max-lon>, $b<min-lat>, $b<max-lat>);
            @lines.push: [ color('inactive') => 'Bounds:'.fmt('%10s'), color('title') => ' ', color('data') => $bbox ];
          }
        }
        CATCH {
          default {
            @lines.push: [ color('error') => "Error parsing JSON: $_" ];
          }
        }
      }
    }

    for @lines -> $line {
      $.output-stream.send: %( txt => $line );
    }
  } else {
    $.output-stream.send: %( txt => [ color('error') => "file $path not found" ] );
  }
}

=begin pod

=head1 NAME

Samaki::Plugin::File -- Display file metadata and information

=head1 DESCRIPTION

Display metadata about a file that already exists in the data directory. For GeoJSON files, also displays geometry information.

=head1 OPTIONS

No specific options.

=head1 EXAMPLE

    -- file:mydata.csv

Output displays file metadata:

    file:      [mydata.csv]
    Size:      1.2 KB
    Modified:  3 hours ago
    Accessed:  1 minute ago
    Changed:   3 hours ago
    Absolute:  /full/path/to/data/mydata.csv

For GeoJSON files:

    -- file:boundaries.geojson

    GeoJSON:   FeatureCollection
    Features:  42
    Geometry:  Polygon (42)
    Coords:    1234
    Bounds:    lon: [-122.5, -122.3] lat: [37.7, 37.9]

=end pod
