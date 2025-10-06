use Samaki::Plugout;
use Samaki::Utils;
use JSON::Fast;

unit class Samaki::Plugout::JSON does Samaki::Plugout;

has $.name = 'json';
has $.description = 'View json';

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
  my $from = from-json($path.slurp);
  for (to-json($from, :pretty).lines) {
    self.pane.put: "$_";
  }
}

