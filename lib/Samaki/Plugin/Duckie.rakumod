use Samaki::Plugin;
use Log::Async;
use Duckie;

unit class Samaki::Plugin::Duckie does Samaki::Plugin;

has $.name = 'duckie';
has $.description = 'Use in-line duckdb driver for queries';
has $.output-ext = 'csv';

method execute(:$cell, :$mode, :$page) {
 my $db = $cell.get-conf('db');
 self.info: "Executing duckie cell with db { $db // '<memory>' }";
 my $content = $cell.get-content(:$mode, :$page);
 my $duck = $db ?? Duckie.new(file => $db) !! Duckie.new;
 $!res = $duck.query($content);
 unless $!res {
   $!errors = $!res.Str;
   return;
 }
 $!output = self.output-duckie($!res);
}
