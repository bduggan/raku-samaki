use Samaki::Plugout;
use Samaki::Utils;

unit class Samaki::Plugout::Raw does Samaki::Plugout;

has $.name = 'raw';
has $.description = 'Open the file using the system open or xdg-open';
has $.clear-before = False;

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
  shell-open $path;
}

