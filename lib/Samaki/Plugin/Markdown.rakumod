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
