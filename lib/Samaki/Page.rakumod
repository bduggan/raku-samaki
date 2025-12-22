
use Log::Async;
use Terminal::ANSI::OO 't';

use Samaki::Plugins;
use Samaki::Cell;
use Samaki::Conf;
use Samaki::Utils;
use CodeUnit;

logger.untapped-ok = True;

subset PageName of Str where { /^^ <[a..zA..Z0..9_-]>+ $$/ };

class Samaki::Page {

  has IO::Path $.wkdir is required;
  has PageName $.name is required;
  has Str $.content;
  has $.suffix = 'samaki';
  has @.cells;
  has $.mode is rw = 'eval'; # or 'raw'
  has $.current-cell is rw;
  has Str $.errors;
  has $.cu = CodeUnit.new(:keep-warnings);

  method data-dir {
    $!wkdir.child(self.name);
  }

  multi method get-cell(Int $index) {
    return Nil if $index < 0 || $index >= @!cells.elems;
    $!current-cell = @!cells[$index];
    $!current-cell;
  }

  multi method get-cell(Str $name) {
    $!current-cell = @!cells.first({ .name eq $name });
    $!current-cell;
  }

  method path {
    $.wkdir.child(self.filename)
  }

  method filename {
    return $.name without $.suffix;
    $.name ~ '.' ~ $.suffix;
  }

  method save {
     $.content ==> spurt self.path;
  }

  sub count-lines($str, $pos) {
    return 0 if $pos == 0;
    my $before = $str.substr(0, $pos - 1);
    return +$before.lines + 1;
  }

  method title-height { 1 }

  method show-invalid-cell(:$cell!, :$pane!, :$leadchar!, :%meta!) {
    my $lead = "┌── ".indent(4);
    my $error-msg = $cell.cell-type ?? " [invalid: no plugin found]" !! " [invalid]";
    $pane.put: [ t.color(%COLORS<error>) => $lead ~ ($cell.cell-type ~ $error-msg).fmt('%-20s') ], :%meta;
    with $cell.errors {
      $pane.put([ col('cell-type') => "$leadchar ".indent(4), t.color(%COLORS<error>) => $_ ], :%meta) for .lines;
    }
    my $line = 0;
    $pane.put([ col('line') => ($line++).fmt('%3d '), col('cell-type') => "$leadchar ", t.color(%COLORS<inactive>) => $_ ], :%meta) for $cell.source.lines;
  }

  method show-auto-cell(:$cell!, :$pane!, :$mode!, :$leadchar!, :%meta!) {
    $pane.put: [ t.color(%COLORS<cell-type>) => '╌'.indent(4) ], :%meta;
    $pane.put([ t.color(%COLORS<cell-type>) => "$leadchar ".indent(4) ~ $_.raku ], :%meta) for $cell.conf.list;
    try {
       CATCH { default { $pane.put: [ t.red => "Error displaying cell: $_" ], :%meta } }
       my $*page = self;
       my $out = $cell.get-content(:$mode, page => self);
       if $cell.errors {
         $pane.put([ col('cell-type') => "$leadchar ".indent(4), t.color(%COLORS<error>) => "▶ $_" ], :%meta) for $cell.errors.lines;
       }
       for $out.lines.kv -> $n, $txt {
         my %line-meta = $cell.line-meta($txt);
         my $line = $cell.line-format($txt);
         my Pair $l = ($line.isa(Pair) ?? $line !! t.color(%COLORS<text>) => $line);
         $pane.put: [ col('line') => $n.fmt('%3d '), col('cell-type') => "$leadchar ", $l ], meta => %( :$cell, :self, |%line-meta );
       }
    }
  }

  method show-valid-cell(:$cell!, :$pane!, :$mode!, :@actions!, :$leadchar!, :%meta!) {
    my $lead = "┌── ".indent(4);
    my $post = ' (' ~ $cell.ext ~ ')';
    $pane.put: [ t.color(%COLORS<cell-type>) => $lead ~ ($cell.cell-type ~ $post).fmt('%-20s'), |@actions ], :%meta;
    $pane.put([ t.color(%COLORS<cell-type>) => "$leadchar ".indent(4) ~ $_.raku ], :%meta) for $cell.conf.list;
    try {
       CATCH { default { $pane.put: [ t.red => "Error displaying cell: $_" ], :%meta } }
       my $*page = self;
       my $out = $cell.get-content(:$mode, page => self);
       if $cell.errors {
         $pane.put([ col('cell-type') => "$leadchar ".indent(4), t.color(%COLORS<error>) => "▶ $_" ], :%meta) for $cell.errors.lines;
       }
       for $out.lines.kv -> $n, $txt {
         my %line-meta = $cell.line-meta($txt);
         my $line = $cell.line-format($txt);
         my Pair $l = ($line.isa(Pair) ?? $line !! t.color(%COLORS<text>) => $line);
         $pane.put: [ col('line') => $n.fmt('%3d '), col('cell-type') => ($n == $out.lines.elems - 1 ?? '└ ' !! "$leadchar "), $l ], meta => %( :$cell, :self, |%line-meta );
       }
    }
  }

  method maybe-load(:$plugins!) {
    return True if @!cells;
    self.load(:$plugins);
  }

  method reload(:$plugins!) {
    $!content = Nil;
    @!cells = ();
    self.load(:$plugins);
  }

  method show(:$pane, :$plugins!) {
    my $mode = self.mode;
    my $page = self;
    if $mode eq 'raw' {
       $pane.put: [ t.color(%COLORS<raw>) => "-- { self.name } --" ], :center, meta => %( :$page );
    } else {
       $pane.put: [ t.color(%COLORS<title>) => "〜 { self.name } 〜" ], :center, meta => %( :$page );
    }
    unless self.load(:$plugins) {
      with $page.errors {
        $pane.put: 'sorry, got some errors!';
        $pane.put([ t.color(%COLORS<error>) => $_ ], meta => :$page) for $page.errors.lines
      };
      if $page.content -> $c {
        $pane.put([ t.color(%COLORS<inactive>) => ">$_" ], meta => :$page) for $c.lines;
      }
      return;
    }
    with self.content {
      for self.cells -> $cell {
        $cell.display-line = $pane.lines.elems;

        my @actions;
        my %meta;
        if $cell.is-valid {
          my $select-action = $cell.select-action;
          if $select-action -> $action {
            @actions.push: t.color(%COLORS<button>) => " [$action]",
                           t.color(%COLORS<cell-name>) => " ➞  { $cell.name }.{ $cell.ext }";
            %meta = ( :$action, cell => $cell );
          }
        }
        %meta<page> = self;
        %meta<cell> = $cell;

        my $leadchar = '│';
        $leadchar =  '╎' if $cell.cell-type eq 'auto';

        if !$cell.is-valid {
          self.show-invalid-cell(:$cell, :$pane, :$leadchar, :%meta);
        } elsif $cell.cell-type eq 'auto' {
          self.show-auto-cell(:$cell, :$pane, :$mode, :$leadchar, :%meta);
        } else {
          self.show-valid-cell(:$cell, :$pane, :$mode, :@actions, :$leadchar, :%meta);
        }
      }
    } else {
      $pane.put: [ t.color('#666666') => "(blank page)" ], meta => %( :self );
    }
  }

  method load($content = Nil, :$plugins!) {
    info "loading page: {self.path}";
    return False unless $content || self.path.IO.e;
    $!content //= $content // self.path.IO.slurp;
    @!cells = ();
    if $! {
      error "failed to load page file: {self.path} - $!";
      $!errors = "failed to load page file: {self.path} - $!";
      return False;
    }
    my regex cell-type { \h* [ <[a..zA..Z]> <[a..zA..Z0..9_-]>* ]? \h* }
    my regex cell-ext { <[a..zA..Z0..9_-]>+ }
    my regex cell-name { <[a..zA..Z0..9_-]>+ }
    my @dashes = "─", "―", "⸺", "–", "—", "﹣", "－", '--',
                 '┌──','──','┌─', '━━','━━','┏━━','━━━','┏━━━';
    my regex dashes { @dashes }
    my regex cell-header { ^^ <dashes> \h* <cell-type> \h*  [ ':' \h*  <cell-name> [ '.' <cell-ext> ]? ]?  \h* $$ }
    my @indexes = $!content.lines.grep: { / <cell-header> / }, :k;
    @indexes.push: $!content.lines.elems;
    if @indexes[0] != 0 {
      error "page does not start with a cell";;
      $!errors = "malformed page file: {self.path} - does not start with a cell";
      return False;
    }
    my @ranges = @indexes.rotor( 2 => - 1);
    my @blocks = @ranges.map: -> ($s,$e) {
      die "out of range" if $e > $!content.lines;
      $!content.lines[$s..^$e].join("\n") ~ "\n";
    };

    unless @blocks > 0 {
      error "malformed page file: {self.path} - could not split cells";
      debug "content was : { $!content.raku }";
      $!errors = "malformed page file: {self.path} - could not split cells, got {+@blocks} blocks { @blocks[0].raku }";
      return False;
    }

    info "loading page {self.path}, cell count is w{+@blocks}";

    my regex confkey { \S+ }
    my regex confvalue { \V+ }
    my rule confline {^^ [ '|' | '│' ] \h* <confkey> \h* ':' \h* <confvalue> \h* $$ }

    my $index = 0;
    my SetHash $names;
    for @blocks.kv -> $block-index, $block {
      my ($cell-lead, @lines) = $block.lines;
      my $cell-type;
      my $cell-name;
      $cell-lead ~~ /<cell-header>/ or die "malformed cell header: $cell-lead";
      my $type = $<cell-header><cell-type>.Str;
      if $type && $type.trim.chars > 0 {
        $cell-type = $type.trim;
      } else {
        # this is an auto-eval cell, run it as we go
        debug "evaluating block " ~ @lines.join("\n");
        $.cu.eval: @lines.join("\n");
        my $content = @lines.join("\n") ~ "\n";
        with $.cu.exception {
          $content = "--▶ sorry! something went wrong --\n{.message }\n----\n$content";
          $.cu.exception = Nil;
        }
        $cell-type = 'auto';
        @!cells.push: Samaki::Cell.new:
          source => $block, :$!wkdir, :name('auto'),
          data-dir => self.data-dir,
          :$cell-type,
          index => $index++,
          :$content,
           start-line => @ranges[ $block-index ][0], page-name => $.name;
        next;
      }
      with $<cell-header><cell-name> -> $n {
        $cell-name = $n.Str.trim;
      }
      my %args;
      with $<cell-header><cell-ext> -> $ext {
        %args<default-ext> = $ext.Str;
      }
      my @conf;
      while @lines[0] && @lines[0] ~~ &confline {
        @conf.push: ( $<confkey>.Str => $<confvalue>.Str );
        @lines.shift;
      }
      my $data-dir = self.data-dir;
      my $name = $cell-name // "cell-{+@!cells}";
      if $name ∈ $names {
        $!errors = "duplicate cell name: $name";
        fail "duplicate cell name: $name" 
      }
      $names{$name} = True;
      @!cells.push: Samaki::Cell.new:
        source => $block,
        :@conf,
        :$!wkdir,
        :$name,
        :$data-dir,
        :$cell-type,
        content => (@lines.join("\n") ~ "\n"),
        index => $index++,
        start-line => @ranges[ $block-index ][0],
        page-name => $.name,
        |%args;
      @!cells.tail.load-plugin: :$plugins;
    }
    my $l = @!cells.tail.start-line;
    return True;
  }

  method run-cell(Samaki::Cell $cell!, :$btm, :$top, :$action) {
    my \btm := $btm;
    my \top := $top;
    btm.clear if $cell.clear-stream-before;

    unless $cell.is-valid {
      btm.put: "sorry, cell is not valid";
      return;
    }

    $!current-cell = $cell;

    my $running = start { $cell.execute: mode => self.mode, :page(self), pane => btm, :$action };
    if $cell.stream-output {
      my $streamer = start {
        loop {
          my $line = $cell.output-stream.receive;
          last unless $line.defined;
          if $line.isa(Hash) {
            next unless log-visible($line<level>);
            my $txt = $line<txt>;
            btm.put: $txt, meta => ($line<meta> // {}), wrap => ($cell.wrap // 'none');
          } else {
            btm.put: $line, wrap => $cell.wrap // 'none';
          }
        }
      }
    }
    await $running;

    with $cell.errors {
      btm.put([ t.red => $_ ] ) for .lines;
    }
    with $cell.output {
      given $cell.output.^name {
        when 'Str' {
          btm.put( $_, wrap => $cell.wrap ) for $cell.output.lines;
        }
        when 'Array' {
          for $cell.output<> -> $line {
            if $line.isa(Hash) {
              btm.put: $line<txt>, meta => $line<meta>;
            } else {
              btm.put: $line;
            }
          }
        }
        default {
          btm.put( $cell.output, wrap => $cell.wrap );
        }
      }
    }
  }

  method shutdown {
    debug "shutting down page {self.name}";
    for @!cells -> $cell {
      debug "shutting down cell { $cell.name }";
      $cell.shutdown;
    }
  }

}
