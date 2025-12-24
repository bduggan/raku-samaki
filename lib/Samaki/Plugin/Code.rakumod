use Samaki::Plugin;
use Log::Async;

unit class Samaki::Plugin::Code does Samaki::Plugin;

has $.name = 'code';
has $.description = 'Evaluate code in the same context as auto evaluated blocks';
has $.output-ext = 'text';

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  my $plug = self;
  my $*OUT = class {
    method print($a) {
      $out.print($a);
      $plug.stream: $a.trim;
    }
  }
  my $content = $cell.get-content(:$page, :$mode);
  info "evaluating " ~ $content.raku;
  my $h = &warn.wrap: -> |q {
    warning "got a warning from code " ~ q.raku;
    self.warn('warning -> ' ~ q.Str);
  };
  my $res = $page.cu.eval: $content;
  info "done";
  with $res {
    $out.put($_);
    $plug.stream: $_;
  }
  with $page.cu.exception {
    self.warn("error -> $_") for .message.lines;
    $page.cu.exception = Nil;
  }
  for $page.cu.warnings -> $w {
    info "got warnings from code " ~ $w.raku;
  }
  $h.restore;
}

