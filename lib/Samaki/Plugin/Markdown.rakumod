use Samaki::Plugin;
use Samaki::Utils;
use Log::Async;
use Markdown::Grammar;
use Samaki::Conf;

unit class Samaki::Plugin::Markdown does Samaki::Plugin;

has $.name = 'markdown';
has $.description = 'Render markdown as HTML';
method output-ext { 'html' }

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  from-markdown($cell.get-content(:$mode, :$page), to => 'html') ==> spurt $cell.output-file;
  shell-open $cell.output-file;
}

=begin pod

=head1 NAME

Samaki::Plugin::Markdown -- Render Markdown as HTML

=head1 DESCRIPTION

Convert Markdown content to HTML using L<Markdown::Grammar> and open it in the default browser.

=head1 OPTIONS

No specific options.

=head1 EXAMPLE

    -- markdown:doc.html
    # Hello, World!

    This is **Markdown** content with:

    * Lists
    * Links
    * _Emphasis_

Output: Creates C<doc.html> with rendered HTML and opens it in your default browser.

=end pod
