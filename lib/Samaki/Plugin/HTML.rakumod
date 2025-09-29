use Samaki::Plugin;
use Samaki::Utils;
use Log::Async;
use Terminal::ANSI::OO 't';
use Samaki::Conf;

unit class Samaki::Plugin::HTML does Samaki::Plugin;

has $.name = 'html';
has $.description = 'Display some HTML';
method output-ext { 'html' }

method execute(:$cell, :$mode, :$page) {
  $cell.get-content(:$mode, :$page) ==> spurt $cell.output-file;
  shell-open $cell.output-file;
}
