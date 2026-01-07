use Samaki::Plugin;
use Log::Async;
use LLM::DWIM;
use Samaki::Conf;
use Terminal::ANSI::OO 't';

unit class Samaki::Plugin::LLM does Samaki::Plugin;

has $.name = 'llm-dwim';
has $.description = 'Execute text using LLM::DWIM';

has $.wrap = 'word';

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
 info "Executing LLM cell";
 my Str $content = $cell.get-content(:$mode, :$page);
 my $h = &warn.wrap: -> |c {
   self.warn($_) for c.Str.lines;
   warning "LLM warning: {c.raku}";
 }

 with dwim($content) -> $res {
   $!output = $res;
   $out.put($res) if $out;
 } else {
   self.warn: "errors, could not reach llm: ";
   with (.?exception) {
      self.warn($_) for .gist.lines
   } else {
     self.warn: "error " ~ .raku;
   }

 }

 self.info: 'done';
 $h.restore;
}

=begin pod

=head1 NAME

Samaki::Plugin::LLM -- Send prompts to an LLM

=head1 DESCRIPTION

Send cell content to a Large Language Model using L<LLM::DWIM>. The LLM provider and model are configured via environment variables (see LLM::DWIM documentation).

=head1 OPTIONS

No specific options.

=head1 EXAMPLE

    -- llm
    How many roads must a man walk down, before you call him a man?

Output:

    The answer, my friend, is blowin' in the wind.

Example with interpolation:

    -- duck
    select 'earth' as planet;

    -- llm
    Which planet from the sun is 〈 cells(0).rows[0]<planet> 〉?

Output:

    Earth is the third planet from the sun.

=end pod
