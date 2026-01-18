use Samaki::Plugout;
use Samaki::Utils;

unit class Samaki::Plugout::Raw does Samaki::Plugout;

has $.name = 'raw';
has $.description = 'Open the file using the system open or xdg-open';
has $.clear-before = False;

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
  shell-open $path;
}

=begin pod

=head1 NAME

Samaki::Plugout::Raw -- Open output with the system default application

=head1 DESCRIPTION

Open the output file using the system's default application (via C<open> on macOS or C<xdg-open> on Linux).

=end pod

