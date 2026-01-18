use Samaki::Plugout;
use Log::Async;
use Duck::CSV;
use Samaki::Utils;

unit class Samaki::Plugout::HTML does Samaki::Plugout;

has $.name = 'html';
has $.description = 'Open an HTML file';
has $.clear-before = False;

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
  shell-open($path);
}

=begin pod

=head1 NAME

Samaki::Plugout::HTML -- Open HTML output in the browser

=head1 DESCRIPTION

Open an HTML output file directly in the default browser.

=end pod

