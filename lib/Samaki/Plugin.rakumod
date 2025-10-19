unit role Samaki::Plugin;

use Terminal::ANSI::OO 't';
use Prettier::Table;
use Duckie;
use Duckie::Result;
use Samaki::Conf;
use Log::Async;
use Samaki::Cell;
use Samaki::Page;

method name { ... }
method description { ... }

#| Action to run when the cell is selected
method select-action { 'run' }

#| Wrap words?
method wrap { 'none' }

#| Stream output as it is produced?
method stream-output { True }

#| Clear the output pane before running?
method clear-stream-before { True }

method setup(Samaki::Conf :$conf) { }

#| Default extension for output files
method output-ext { '' }

#| Write output to file?
method write-output { True }

has $.output; # Str or array
has Channel $.output-stream = Channel.new;

multi method stream(:$txt!, :$meta) {
  self.stream: %( :$txt, :$meta )
}

multi method stream($stuff) {
  $!output-stream.send: $stuff;
}

method info(Str $what) {
  self.stream: [t.color(%COLORS<info>) => $what]
}

method error(Str $what) {
  self.stream: [t.color(%COLORS<error>) => $what]
}

method warn(Str $what) {
  self.stream: [t.color(%COLORS<warn>) => $what]
}

#| Run shutdown actions
method shutdown {
}

has Str $.errors;
has $.res;

method line-meta(Str $line) {
  %();
}

method line-format(Str $line) {
  $line;
}
 
method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  ... 
}

sub format-cell($cell) {
  given $cell.^name {
    when 'Str' { $cell.fmt('%-15s ') }
    when 'Int' { $cell.fmt('%-15d ') }
    when 'Num' { $cell.fmt('%-15.4f ') }
    when 'Date' { $cell.yyyy-mm-dd }
    when 'DateTime' { $cell.truncated-to('second').Str }
    when 'Bool' { $cell ?? 'true'.fmt('%-15s ') !! 'false'.fmt('%-15s ') }
    when 'Nil' { 'NULL' }
    default  { $cell.raku.fmt('%-15s ') }
  }
}

sub format-row(@row) {
  @row.map({ format-cell($_) })
}

multi method output-duckie(Duckie::Result $result-set, :$max-rows = 100) {
  my $table = Prettier::Table.new(
    field-names => $result-set.column-names,
    align => 'l',
  );
  my $row-count = $result-set.row-count;
  my $cols = $result-set.column-names;
  my @row-data;
  my $i = 0;
  my $truncated = False;
  for $result-set.rows(:arrays) -> @row {
    @row-data.push: @row;
    $table.add-row(format-row(@row));
    if ++$i > $max-rows {
      $truncated = True;
      last;
    }
  }

  my sub pl(Int $count,Str $str) { $count ~ ' ' ~ $str ~ ($count == 1 ?? '' !! 's') }

  my @lines = ( pl($row-count,'row') ~ ', ' ~ pl($cols.elems,'column') );
  my $row = 0;
  for $table.gist.lines -> $txt {
    if $row == 1 { # columns
      @lines.push: %( :$txt, meta => %( action => 'view_row', row_data => [ '' xx @$cols ] , :$cols ) );
      next;
    }
    if $row < 3 { # header
       @lines.push: $txt;
       next;
    }
    @lines.push: %( :$txt, meta => %( action => 'view_row', row_data => @row-data[$row - 3], :$cols ) );
    NEXT { $row++ }
  }
  if $truncated {
    @lines.push: "... output truncated from $row-count to $max-rows rows ...";
  }
  return @lines;
}

multi method output-duckie(IO::Path $path) {
  $!res = Duckie.new.query("select * from read_csv('{$path}');");
  self.stream:
    txt => [ t.color(%COLORS<normal>) => 'wrote to ', t.color(%COLORS<button>) => "[{ $path.basename }]" ],
    meta => %( action => 'do_output', :$path );

  return self.output-duckie($!res);
}

