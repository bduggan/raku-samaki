unit class Samaki::Plugins;
use Samaki::Conf;
use Log::Async;

has @.rules;

method configure(Samaki::Conf $conf) {
  @.rules = $conf.plugins;
}

method get(Str $name) {
  my $found = @!rules.first: { my $r := .<regex>; $name ~~ $r };
  return $found<handler> if $found;
  fail "No suitable plugin found for name: $name";
}

method list-all {
  return @!rules.map: {
    %(
    regex => .<regex>,
    name => .<handler>.name,
    desc => .<handler>.description
    )
  }
}

