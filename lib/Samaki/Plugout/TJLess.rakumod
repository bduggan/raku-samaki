use Samaki::Plugout;
use Samaki::Utils;
use JSON::Fast;

unit class Samaki::Plugout::TJLess does Samaki::Plugout;

has $.name = 'tjless';
has $.description = 'Use jless to view json in another tmux window';

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
  shell qq:to/SH/;
    tmux new-window -n jless-$name 'jless "$path"'
  SH
}

=begin pod

=head1 NAME

Samaki::Plugout::TJLess -- View JSON with jless in a tmux window

=head1 DESCRIPTION

Open JSON output in jless (an interactive JSON viewer) in a new tmux window.

=end pod

