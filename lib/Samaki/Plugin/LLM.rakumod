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
   warning "LLM warning: {c.raku}";
 }

 with dwim($content) -> $res {
   $!output = $res;
   $out.put($res) if $out;
 }

 self.info: 'done';
 $h.restore;
}
