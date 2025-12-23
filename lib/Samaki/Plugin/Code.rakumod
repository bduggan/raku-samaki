use Samaki::Plugin;

unit class Samaki::Plugin::Code does Samaki::Plugin;

has $.name = 'code';
has $.description = 'Evaluate code in the same context as auto evaluated blocks';
has $.ext = 'text';

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  my $plug = self;
  my $*OUT = class {
    method print($a) {
      $out.print($a);
      $plug.stream: $a.trim;
    }
  }
  my $content = $cell.get-content(:$page, :$mode);
  my $res = $page.cu.eval: $content;
  with $res {
    $out.put($_);
    $plug.stream: $_;
  }
  with $page.cu.exception {
    self.warn("error -> $_") for .message.lines;
    $page.cu.exception = Nil;
  }
}

