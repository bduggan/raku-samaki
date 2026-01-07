use Samaki::Plugin;
use Samaki::Utils;
use Log::Async;
use Terminal::ANSI::OO 't';
use Samaki::Conf;

unit class Samaki::Plugin::HTML does Samaki::Plugin;

has $.name = 'html';
has $.description = 'Display some HTML';
method output-ext { 'html' }

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  $cell.get-content(:$mode, :$page) ==> spurt $cell.output-file;
  shell-open $cell.output-file;
}

=begin pod

=head1 NAME

Samaki::Plugin::HTML -- Display HTML content in browser

=head1 DESCRIPTION

Write cell content to an HTML file and open it in the default browser.

=head1 OPTIONS

No specific options.

=head1 EXAMPLE

    -- html:page.html
    <html>
      <body>
        <h1>Hello, World!</h1>
        <p>This is HTML content.</p>
      </body>
    </html>

Output: Creates C<page.html> and opens it in your default browser.

=end pod
