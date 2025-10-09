unit role Samaki::Plugout;
use Samaki::Conf;
use Terminal::ANSI::OO 't';

has $.pane is rw;
has $.output; # optional: string or array
method clear-before { True }

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) { ... }

method setup { }

method info(Str $what) {
  self.pane.put: [t.color(%COLORS<info>) => $what]
}
