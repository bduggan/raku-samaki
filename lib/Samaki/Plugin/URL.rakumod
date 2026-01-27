use Samaki::Plugin;
use HTTP::Tiny;
use Log::Async;
use Samaki::Conf;

unit class Samaki::Plugin::URL does Samaki::Plugin;

has $.name = 'url';
has $.description = 'Fetch a URL';
has $version-info;

method setup(Samaki::Conf :$conf) {
  info "Setting up URL plugin";
  $!version-info = qqx[curl --version 2>/dev/null].trim.split("\n").[0];
  die "could not find curl in path" unless $!version-info;
  info "version $!version-info";
}

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

=begin pod

=head1 NAME

Samaki::Plugin::URL -- Fetch a URL using curl

=head1 DESCRIPTION

Use curl to fetch a url and write it into the output file.

=head1 CONFIGURATION

None.

=head1 EXAMPLE

    ```
    -- url:data.json
    https://example.com/data.json
    ```

This will write to data.json.  Note that the output file is take from the cell output name + extension.
 
=end pod
