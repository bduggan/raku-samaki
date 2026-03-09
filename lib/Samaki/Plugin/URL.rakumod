use Samaki::Plugin;
use HTTP::Tiny;
use Log::Async;
use Samaki::Conf;

unit class Samaki::Plugin::URL does Samaki::Plugin;

has $.name = 'url';
has $.description = 'Fetch a URL';

method setup(Samaki::Conf :$conf) {
  info "Setting up URL plugin";
}

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  my Str $url = $cell.get-content(:$mode, :$page).trim;
  self.stream: [color('info') => "fetching url $url"];
  my $output-file = $cell.output-file;
  $out.close;
  my $http = HTTP::Tiny.new;
  my $response = quietly { $http.get($url) };
  unless $response<success> {
    $pane.put: "failed: $response<status> $response<reason>";
    return;
  }
  $output-file.spurt($response<content>);
  $pane.put: "done";
  self.stream: [color('info') => "wrote to file: " ~ $output-file.relative];
}

=begin pod

=head1 NAME

Samaki::Plugin::URL -- Fetch a URL using HTTP::Tiny

=head1 DESCRIPTION

Use HTTP::Tiny to fetch a url and write it into the output file.

=head1 CONFIGURATION

None.

=head1 EXAMPLE

    ```
    -- url:data.json
    https://example.com/data.json
    ```

This will write to data.json.  Note that the output file is take from the cell output name + extension.
 
=end pod
