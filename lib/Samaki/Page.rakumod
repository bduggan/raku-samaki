
use Log::Async;
use Terminal::ANSI::OO 't';
use Terminal::UI;

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
  has $.cu;

  method add-context {
    # declare these for codeunits
    multi c(Str $name) { cells($name); }
    multi c(Int $i) { cells($i); }
    multi cell(Str $name) { cells($name); }
    multi cell(Int $i) { cells($i); }
    multi cells(Int $i) { self.get-cell($i); }
    multi cells(Str $name) { self.get-cell($name); }
    sub current-page() { self }

    my $context = context;
    $!cu = CodeUnit.new(:$context,:keep-warnings);
  }

  submethod TWEAK {
    self.add-context;
  }

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
    $pane.put: [ col('error') => $lead ~ ($cell.cell-type ~ $error-msg).fmt('%-20s') ], :%meta;
    with $cell.errors {
      $pane.put([ col('cell-type') => "$leadchar ".indent(4), col('error') => $_ ], :%meta)
            for .lines;
    }
    my $line = 0;
    $pane.put([ col('cell-type') => "$leadchar ".indent(4) ~ $_.raku ], :%meta) for $cell.conf.list;
    $pane.put([ col('line') => ($line++).fmt('%3d '), col('cell-type') => "$leadchar ", col('inactive') => $_ ], :%meta)
          for $cell.source.lines;
  }

  method show-auto-cell(:$cell!, :$pane!, :$mode!, :$leadchar = '║', :%meta!) {
    $pane.put: [ col('interp') => '╔═'.indent(4) ], :%meta;
    self.show-cell-conf(:$cell, :$pane, :$leadchar, :%meta, color => 'interp');
    self.show-cell-body(:$cell, :$pane, :$mode, :$leadchar, :%meta, color => 'interp', lastchar => '╚');
  }

  method show-cell-conf(:$cell!, :$pane!, :$leadchar!, :%meta!, :$color = 'cell-type') {
    for $cell.conf.list {
      next if .key.starts-with('_');
      $pane.put([ col($color) => "$leadchar ".indent(4) ~ "$_" ], :%meta) 
    }
  }

  method show-cell-body(:$cell!, :$pane!, :$mode!, :$leadchar!, :%meta!, :$color = 'cell-type', :$lastchar = '└') {
    try {
       CATCH { default { $pane.put: [ t.red => "Error displaying cell: $_" ], :%meta } }
       my $*page = self;
       my $out = $cell.get-content(:$mode, page => self);
       if $cell.errors {
         $pane.put([ col($color) => "$leadchar ".indent(4), col('error') => "▶ $_" ], :%meta)
               for $cell.errors.lines;
       }
       for $cell.formatted-content-lines.kv -> $n, $line {
         $pane.put: [ col('line') => $n.fmt('%3d '), col($color) => ($n == $out.lines.elems - 1 ?? $lastchar !! "$leadchar "), |$line ], :%meta;
       }
    }
  }

  method show-valid-cell(:$cell!, :$pane!, :$mode!, :@actions!, :$leadchar!, :%meta!) {
    my $lead = "┌── ".indent(4);
    my $post = $cell.write-output ?? (' (' ~ $cell.ext ~ ')') !! "";
    $pane.put: [ col('cell-type') => $lead ~ ($cell.cell-type ~ $post).fmt('%-20s'), |@actions ], :%meta;
    self.show-cell-conf(:$cell, :$pane, :$leadchar, :%meta);
    self.show-cell-body(:$cell, :$pane, :$mode, :$leadchar, :%meta);
  }

  method maybe-load(:$plugins!) {
    return True if @!cells;
    self.load(:$plugins);
  }

  method reload(:$pane!, :$plugins!) {
    $!content = Nil;
    @!cells = ();
    self.load(:$plugins);
    self.add-context;
    self.show(:$pane, :$plugins);
  }

  method show(Terminal::UI::Pane:D :$pane!, :$plugins!) {
    my $mode = self.mode;
    my $page = self;
    if $mode eq 'raw' {
       $pane.put: [ col('raw') => "-- { self.name } --" ], :center, meta => %( :$page );
    } else {
       $pane.put: [ col('title') => "〜 { self.name } 〜" ], :center, meta => %( :$page );
    }
    unless self.load(:$plugins) {
      with $page.errors {
        $pane.put: 'sorry, got some errors!';
        $pane.put([ col('error') => $_ ], meta => :$page) for $page.errors.lines
      };
      if $page.content -> $c {
        $pane.put([ col('inactive') => ">$_" ], meta => :$page) for $c.lines;
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
                            $cell.write-output ??
                                (t.color(%COLORS<cell-name>) => " ➞  { $cell.name }.{ $cell.ext }")
                             !! (t.color(%COLORS<cell-name>) => " { $cell.name }");
            %meta = ( :$action, cell => $cell );
          }
        }
        %meta<page> = self;
        %meta<cell> = $cell;

        my $leadchar = '│';

        if !$cell.is-valid {
          self.show-invalid-cell(:$cell, :$pane, :$leadchar, :%meta);
        } elsif $cell.cell-type eq 'auto' {
          self.show-auto-cell(:$cell, :$pane, :$mode, :%meta);
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
    self.add-context;
    return False unless $content || self.path.IO.e;
    without $!content {
      with $content {
        info "loading from provided content";
        $!content = $content;
      } else {
        info "loading from file: {self.path}";
        $!content = self.path.IO.slurp;
      }
    }
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
        my $h = &warn.wrap: -> |q {
          warning "got a warning from code " ~ q.raku
        }
        $.cu.eval: @lines.join("\n");
        $h.restore;
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
      my @conf;
      with $<cell-header><cell-ext> -> $ext {
        %args<ext> = $ext.Str;
        @conf.push: ( '_ext' => $ext.Str );
      }
      while @lines[0] && @lines[0] ~~ &confline {
        @conf.push: ( $<confkey>.Str => $<confvalue>.Str );
        @lines.shift;
      }
      my $data-dir = self.data-dir;
      my $name = $cell-name // "cell-{+@!cells}";
      if $name ∈ $names {
        @lines.unshift: "--▶ Error: duplicate cell name '{ $name }' --\n";
      }
      $names{$name} = True;
      @!cells.push: Samaki::Cell.new:
        source => $block,
        :@conf, :$!wkdir, :$name, :$data-dir, :$cell-type,
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
            my $txt = $line<txt> // '';
            btm.put: $txt, meta => ($line<meta> // {}), wrap => ($cell.wrap // 'none');
          } else {
            btm.put: ($line // ''), wrap => $cell.wrap // 'none';
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
      $cell.shutdown;
    }
  }

}
