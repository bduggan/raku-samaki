use Samaki::Plugin;
use Samaki::Utils;
use Log::Async;
use Text::Markdown;
use Samaki::Conf;

unit class Samaki::Plugin::Markdown does Samaki::Plugin;

has $.name = 'markdown';
has $.description = 'Render markdown as HTML';
method output-ext { 'html' }

method execute(:$cell, :$mode, :$page) {
  my $md = Text::Markdown.new:
           $cell.get-content(:$mode, :$page);
  $md.to_html ==> spurt $cell.output-file;
  shell-open $cell.output-file;
}
