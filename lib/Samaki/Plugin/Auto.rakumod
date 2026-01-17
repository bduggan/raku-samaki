unit class Samaki::Plugin::Auto;

# This is a special type of cell for executing code when the page loads,
# the cell is not executed by a user triggered event.

has $.name = 'auto';
has $.description = 'Auto eval code that can be reused later';
has $.output-ext = Nil;

method select-action { }

method execute(:$cell,:$mode,:$page) {
  die "auto cell is not to be executed; contents are eval'ed inline";
}

method shutdown { }

