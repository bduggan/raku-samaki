#!raku

use Terminal::ANSI::OO 't';
use Log::Async;
use Duck::CSV;
use Duckie;

use Samaki::Conf;
use Samaki::Plugins;
use Samaki::Plugin::Auto;

class Samaki::Cell {
  has Str $.source;
  has Str $.page-name is required;
  has Str $.cell-type is required;
  has Str $.name is required;
  has IO::Path $.data-dir is required;
  has Str $.content;
  has Str $.last-content; #= last evaled content
  has $.wkdir is required;
  has $.res;          #= result set, if any.  usually Duckie::Result
  has $.output;       #= displayed output.  string or array of lines
  has Str $.errors;   #= errors during evaluation, execution or setup
  has $.index;        #= 1-based index of cell in page
  has $.start-line;   #= line number in page where cell starts
  has $.display-line is rw; #= line number in displayed pane where cell starts
  has $.timeout = 60; #= default execution timeout in seconds
  has $.plugin handles <wrap stream-output output-stream output-ext clear-stream-before select-action write-output>;

  has $.default-ext = 'csv';
  has @.conf;

  method TWEAK {
    $!plugin = Samaki::Plugin::Auto.new if $!cell-type eq 'auto';
  }

  method Str {
    self.content.trim;
  }

  method shutdown {
    return unless $.plugin;
    $.plugin.shutdown;
  }

  method is-valid {
    return True if $.cell-type eq 'auto';
    return False unless $!plugin;
    return True;
  }

  method get-conf($key) {
    @.conf.Hash{ $key };
  }

  method label-height {
    return 1;
  }

  method last-line {
    return $.start-line + $.content.lines - 1 + self.label-height;
  }

  method load-plugin(:$plugins!) {
    $!plugin = try $plugins.get: $!cell-type;
    if $! {
      $!errors = "Error loading plugin for cell type '{ $!cell-type }': $!";
      return;
    }
    unless $!plugin {
      $!errors = "No plugin found for cell type '{ $!cell-type }'";
      return;
    }
  }

  method get-content(Str :$mode = 'eval', :$page!) {
    return $.content unless $mode eq 'eval';

    my \page = $page;

    sub prev {
      page.get-cell($.index - 1)
    }

    multi c(Str $name) { cells($name); }
    multi c(Int $i) { cells($i); }
    multi cell(Str $name) { cells($name); }
    multi cell(Int $i) { cells($i); }
    multi cells(Int $i) { page.get-cell($i); }
    multi cells(Str $name) { page.get-cell($name); }

    my regex phrase { '〈' <( <-[〉]>* )> '〉' }
    my regex alt { '<<<' <( <( .*? )> )> '>>>' }

    my @pieces = $.content.split( / <phrase> | <alt> /, :v);
    info "Splitting { $.content }";
    info @pieces.raku;
    my $out;
    for @pieces -> $p {
      if $p.isa(Str) {
        $out ~= $p;
        next;
      }
      my $eval-str = ($p<phrase> // $p<alt>).Str;
      trace "calling EVAL with $eval-str";
      my $res = do {
        indir self.data-dir, { $page.cu.eval($eval-str) }
      }
      $out ~= ( $res // "");
      with $page.cu.exception {
        $out ~= " ▶$p◀ ";
        $!errors ~= "$p │ Sorry!\n " ~ .message.chomp ~ "\n";
        $page.cu.exception = Nil;
      }
    }
    $!last-content = $out;
    $out;
  }

  method cell-dir {
    my $subdir = $.wkdir.child($.page-name);
    $subdir.mkdir unless $subdir.d;
    return $subdir;
  }

  method ext {
    self.get-conf('ext') || $.output-ext || $.default-ext;
  }

  method output-file {
    my $ext = self.ext;
    self.cell-dir.child( self.name ~ "." ~ $ext);
  }

  #| Should the output file be closed after execution?
  method close-output-file {
    True
  }

  method data {
    my $file = self.output-file;
    fail "no output yet" unless $file && $file.e;
    return $file.slurp;
  }

  method rows {
    read-csv self.output-file;
  }

  method col($str, Bool :$csv) {
    with self.res.column-data($str) {
      return .join(',') if $csv;
      return $_;
    }
  }

  method res {
    my $file = self.output-file;
    my $db = Duckie.new;
    my $res = $db.query: "select * from read_csv('$file')";
    $res;
  }

  method execute(:$mode = 'eval', :$page!, :$pane!, :$action) {
    # $pane.put: "Executing cell { $.name } of type { $.cell-type }";
    $pane.put: [ col('info') => "Executing cell ", col('cell-name') => $.name, col('info') => " of type ", col('cell-type') => $.cell-type ];
    return without $!plugin;
    info "Executing cell of type { $.cell-type }";
    indir self.cell-dir, {
      info "In directory {self.cell-dir}";
      try {
        my IO::Handle $out;
        if $.plugin.write-output {
          if $.plugin.clear-stream-before {
            $.plugin.stream:  txt => [ t.color(%COLORS<info>) => "Writing to ", t.color(%COLORS<link>) => "[" ~ self.output-file.IO.relative ~ "]" ],
                              meta => %( action => 'do_output', path => self.output-file );
          }
          $out = self.output-file.open(:w) 
        } else {
          $.plugin.info: "Not writing output";
        }
        LEAVE {
          try { $out.close } if self.close-output-file && $out;
        }
        indir self.data-dir, {
          info "running plugin " ~ $.plugin.^name;
          $.plugin.execute: cell => self, :$mode, :$page, :$out, :$pane, :$action;
        }
        CATCH {
          default {
            $!errors = "Errors running { $.plugin.name } : $_";
            debug "Errors running { $.plugin.name }";
            debug "$_" for Backtrace.new.Str.lines;
            $!output = $!plugin.output;
            return;
          }
        }
      }
    }
    $!output = $!plugin.output;
    $!errors = $!plugin.errors;
    $!res = $!plugin.res;
  }

  #| used when writing out content
  method line-meta(Str $line) {
    return %() unless $!plugin;
    return %() if self.cell-type eq 'auto';
    $!plugin.line-meta($line, cell => self);
  }

  #| used to format content
  method line-format(Str $line) {
    return $line unless $!plugin;
    $!plugin.line-format($line, cell => self);
  }
}


