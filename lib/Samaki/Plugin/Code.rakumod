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

=begin pod

=head1 NAME

Samaki::Plugin::Code -- Evaluate Raku code in the current process

=head1 DESCRIPTION

Evaluate Raku code in the same context as the page's auto-evaluated blocks (cells starting with just `--`). Variables and functions defined in other code cells or init blocks are available.

Unlike the Raku plugin which runs code in a separate process, this runs in the same process as Samaki itself, allowing shared state across code cells.

=head1 OPTIONS

No specific options.

=head1 EXAMPLE

    -- code
    my $a = 12;

    -- code
    $a + 1;

Output:

    13

=end pod

