use Samaki::Plugout;
use Log::Async;
use Duck::CSV;
use Samaki::Utils;

unit class Samaki::Plugout::Plain does Samaki::Plugout;

has $.name = 'plain';
has $.description = 'View plain text in a browser';
has $.clear-before = False;

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
  my $html-file = $data-dir.child("{$name}-plain.html");
  my $content = slurp $path;
  my $fh = open :w, $html-file;
  $fh.put: qq:to/HTML/;
  <!DOCTYPE html>
  <html>
  <pre style="white-space: pre-wrap; word-wrap: break-word;">
  { html-escape($content) }
  </pre>
  </html>
  HTML
  shell-open $html-file;
}

