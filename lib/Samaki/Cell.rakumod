#!raku

use Terminal::ANSI::OO 't';
use Log::Async;
use Duck::CSV;

use Samaki::Conf;
use Samaki::Plugins;

class Samaki::Cell {
  has Str $.page-name is required;
  has Str $.cell-type is required;
  has Str $.name is required;
  has IO::Path $.data-dir is required;
  has Str $.content;

  has $.wkdir is required;

  has $.res;    #= result set, if any.  usually Duckie::Result
  has $.output; #= displayed output.  string or array of lines
  has Str $.errors; #= errors during evaluation, execution or setup

  has $.index;       #= 1-based index of cell in page
  has $.start-line;  #= line number in page where cell starts

  has $.timeout = 5; #= default execution timeout in seconds

  has $.plugin handles <wrap stream-output output-stream output-ext>;

  has $.default-ext = 'csv';

  has @.conf;

  method is-valid {
    return False unless $!plugin;
    return True;
  }

  method get-conf($key) {
    @.conf.Hash{ $key };
  }

  method select-action {
    return 'run';
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

    multi cells(Int $i) {
      page.get-cell($i);
    }

    multi cells(Str $name) {
      page.get-cell($name);
    }

    my regex phrase { '〈' <( <-[〉]>* )> '〉' }
    my regex alt { '<<<' <( <( .*? )> )> '>>>' }

    my @pieces = $.content.split( / <phrase> | <alt> /, :v);
    info "Spliting { $.content }";
    info @pieces.raku;
    my $out;
    for @pieces -> $p {
      if $p.isa(Str) {
        $out ~= $p;
        next;
      }
      try {
        my $res = ($p<phrase> // $p<alt>).Str.EVAL;
        $out ~= $res;
        CATCH {
          default {
            $out ~= "¡¡ $p !!";
            $!errors ~= "Error evaluating $p : $_\n";
          }
        }
      }
    }
    $out;
  }

  method cell-dir {
    my $subdir = $.wkdir.child($.page-name);
    $subdir.mkdir unless $subdir.d;
    return $subdir;
  }

  method output-file {
    my $ext = self.get-conf('ext') || $.output-ext || $.default-ext;
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

  method execute(:$mode = 'eval', :$page!) {
    return without $!plugin;
    info "Executing cell of type { $.cell-type }";
    indir self.cell-dir, {
      info "In directory {self.cell-dir}";
      try {
        my $out;
        if $.plugin.write-output {
          $.plugin.stream:  txt => [ t.color(%COLORS<info>) => "Writing to ", t.color(%COLORS<link>) => "[" ~ self.output-file ~ "]" ],
                            meta => %( action => 'do_output', path => self.output-file );
          $out = self.output-file.open(:w) 
        } else {
          $.plugin.info: "Not writing output";
        }
        LEAVE {
          try { $out.close } if self.close-output-file && $out;
        }
        $.plugin.execute: cell => self, :$mode, :$page, :$out;
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
    $!plugin.line-meta($line, cell => self);
  }

  #| used to format content
  method line-format(Str $line) {
    return $line unless $!plugin;
    $!plugin.line-format($line, cell => self);
  }
}


