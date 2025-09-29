use Samaki::Plugin;
use Log::Async;
use LLM::DWIM;

unit class Samaki::Plugin::LLM does Samaki::Plugin;

has $.name = 'llm-dwim';
has $.description = 'Execute text using LLM::DWIM';
has $.output-ext = 'txt';

has $.wrap = 'word';

method execute(:$cell, :$mode, :$page, :$out) {
 info "Executing LLM cell";
 my Str $content = $cell.get-content(:$mode, :$page);
 my $h = &warn.wrap: -> |c {
   warning "LLM warning: {c.raku}";
 }

 with dwim($content) -> $res {
   $!output = $res;
   $out.put($res) if $out;
 }

 $h.restore;
}
