unit role Samaki::Plugout;

has $.pane is rw;
has $.output; # optional: string or array
method clear-before { True }

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) { ... }

method setup { }
