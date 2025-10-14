unit class Samaki::Conf;
use Log::Async;
use Color;
use Color::Scheme;

has $.file is required;
has $.plugins;
has $.plugouts;

# Amber
my $base = Color.new("#ffbf00");
my @palette = color-scheme($base, 'analogous');
my @more = @palette.map({ .lighten(30) });
my @range = (0..20).map({ $base.lighten($_ * 2) });
@palette = ( |@palette, |@more );

my $red = Color.new("#fc5a50");
my $yellow = Color.new('#ffff00');
my $grey = Color.new('#888888');

our %COLORS is export = (
  prompt => @range[5],
  error => $red,
  warn => @palette[9],
  info => $grey,
  cell-type => $base,
  cell-name => $yellow.darken(20),
  plugin-info => @palette[1],
  raw => @palette[2],
  title => $base,
  button => @palette[4],
  data => @range[19],
  unknown => @palette[6],
  datafile => @palette[7],
  inactive => $grey,
  yellow => $yellow,
  link => $yellow,
  normal => $base,
  input => @palette[3],
).map: { .key => .value.gist };

multi method load-handler(Str $handler-class) {
  my $handler;
  try {
    require ::($handler-class);
    $handler = ::($handler-class).new;
    CATCH {
        fail "could not load handler module: $handler-class: $_";
    }
  }
  try {
    $handler.setup(:conf(self)) if $handler.can('setup');
    CATCH {
      default {
        fail "could not setup handler module: $handler-class: $_";
      }
    }
  }
  $handler;
}

multi method load-handler($handler) {
  return $handler if $handler.defined;
  return $handler.new;
}

submethod TWEAK {
  die "Config file does not exist: { $!file }" unless $!file.IO.e;
  my %*samaki-conf;
  try {
    $!file.IO.slurp.EVAL;
    CATCH {
      default {
        die "Could not load config file: { $!file }: $_";
        fail $_;
      }
    }
  }
  $!plugins = self.load-rules: %*samaki-conf<plugins> // [];
  $!plugouts = self.load-rules: %*samaki-conf<plugouts> // [];
}

method load-rules(@rules) {
  return @rules.map: {
    my $regex = .key;
    my $handler-class = .value;
    my $handler = self.load-handler($handler-class);
    %( :$regex, :$handler );
  }
}
