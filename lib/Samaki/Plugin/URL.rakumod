use Samaki::Plugin;
use HTTP::Tiny;
use Log::Async;
use Samaki::Conf;

unit class Samaki::Plugin::URL does Samaki::Plugin;

has $.name = 'url';
has $.description = 'Fetch a URL';

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  my Str $url = $cell.get-content(:$mode, :$page).trim;
  self.stream: [color('info') => "fetching url $url"];
  my $output-file = $cell.output-file;
  $out.close;
  my $proc = Proc::Async.new: 'curl', $url, '-o', $output-file, '--fail';
  my $exit-status;
  $pane.stream: $proc.stderr(:bin);
  react {
    whenever $proc.stdout {
      $pane.put: "$_";
    }
    whenever $proc.ready {
      info "started curl for $url, pid $_";
    }
    whenever $proc.start(cwd => $cell.data-dir) {
      info "curl exited for $url";
      $exit-status = .exitcode;
      $pane.put: "done";
    }
  }
  return unless $exit-status == 0;
  self.stream: [color('info') => "wrote to file: " ~ $output-file.relative ];
}

