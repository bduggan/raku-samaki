unit class Samaki::Conf;
use Log::Async;
use Color;
use Terminal::ANSI::OO 't';

has $.file is required;
has $.plugins;
has $.plugouts;

# amber shades
my $white = '#FFFFFF';
my $mid = '#FFC005';
my $dark = '#997200';
my $cyan = '#00FFFF';
my $bright = $cyan;
my $dim-cyan = Color.new($cyan).darken(20);

my $base = Color.new($mid);

my $red = Color.new("#fc5a50");
my $yellow = Color.new('#ffff00');
my $grey = Color.new('#888888');
my $tea-green = Color.new('#CDE7B0');

our %COLORS is export = (
  prompt => $mid,
  error => $red.lighten(10),
  warn => $mid,
  info => $dark,
  cell-type => $mid,
  cell-name => $dim-cyan,
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
  text => $white,
  line => $dark,
  interp => Color.new("#BDD5EA"),
).map: { .key => .value.gist };

sub col($name) is export {
  t.color( %COLORS{ $name } )
}

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
