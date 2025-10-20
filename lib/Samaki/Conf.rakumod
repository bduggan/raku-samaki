unit class Samaki::Conf;
use Log::Async;
use Color;
use Color::Scheme;

has $.file is required;
has $.plugins;
has $.plugouts;

# amber shades
my $bright = '#FFE599';
my $mid = '#FFC005';
my $dark = '#997200';

my $base = Color.new($mid);
my @palette = color-scheme($base, 'analogous');

my $red = Color.new("#fc5a50");
my $yellow = Color.new('#ffff00');
my $grey = Color.new('#888888');

our %COLORS is export = (
  prompt => $mid,
  error => $red.lighten(10),
  warn => $bright,
  info => $dark,
  cell-type => $mid,
  cell-name => $bright,
  plugin-info => $mid,
  raw => $mid,
  title => $bright,
  button => $bright,
  link => $bright,
  data => $mid,
  unknown => $dark,
  datafile => $mid,
  inactive => $dark,
  yellow => $bright,
  normal => $mid,
  input => $bright,
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
