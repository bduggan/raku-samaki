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
