#!raku

use Terminal::ANSI::OO 't';
use Log::Async;
use Duck::CSV;
use Duckie;
use JSON::Fast;

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
  has @.formatted-content-lines;

  has $!ext;
  has @.conf;

  my regex phrase { '〈' <( <-[〉]>* )> '〉' }
  my regex alt { '<<<' <( <( .*? )> )> '>>>' }

  method TWEAK {
    $!plugin = Samaki::Plugin::Auto.new if $!cell-type eq 'auto';
  }

  method is-auto {
    return $.cell-type eq 'auto';
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

  #| Get the source content of the cell, with interpolated parts evaluated
  method src {
    self.get-content
  }

  method get-content(Str :$mode = 'eval', :$page = $*page) {

    @!formatted-content-lines = [];

    my $text-color = self.is-auto ?? 'interp' !! 'text';
    unless $mode eq 'eval' {
      # @!formatted-content-lines should contain content but with highlgihting for interpolated parts
      for $.content.lines {
        my @pieces = $_.split( / <phrase> | <alt> /, :v);
        my @out;
        @out.push: color($text-color) => '';
        for @pieces -> $p {
          if $p.isa(Str) {
            @out.push($p);
          } else {
            my $eval-str = ($p<phrase> // $p<alt>).Str;
            @out.push: color('interp') => "〈" ~ $eval-str ~ "〉";
            @out.push: color($text-color) => '';
          }
        }
        @!formatted-content-lines.push(@out);
      }
      return $.content 
    }

    my \page = $page;

    sub prev {
      page.get-cell($.index - 1)
    }

    my $all-content;
    for $.content.lines.kv -> $line-number, $content-line {
      my $out;
      my @formatted;
      @formatted.push: color($text-color) => '';
      my @pieces = $content-line.split( / <phrase> | <alt> /, :v);
      my @extra-lines;
      for @pieces -> $p {
        if $p.isa(Str) {
          $out ~= $p;
          @formatted.push($p);
          next;
        }
        my $eval-str = ($p<phrase> // $p<alt>).Str;
        trace "calling EVAL with $eval-str";
        try {
          my $res = do {
            self.maybe-make-data-dir;
            my $wrapped = &warn.wrap({ warning "$_" } );
            LEAVE { $wrapped.restore; }
            indir self.data-dir, { $page.cu.eval($eval-str) }
          }
          $out ~= ( $res // "");
          if $res.?lines > 1 {
            @formatted.push( color('interp') => $res.lines[0] );
            for $res.lines.skip {
              @extra-lines.push: color('interp') => $_;
            }
          } else { 
            @formatted.push: color('interp') => ($res // "").Str;
          }
          @formatted.push: color('text') => '';
          with $page.cu.exception {
            $out ~= " ❰$p❱ ";
            @formatted.push(color('error') => "❰" ~ $eval-str ~ "❱ ");
            $!errors ~= "sorry (line $line-number)): " ~ .message.chomp ~ "\n";
            $page.cu.exception = Nil;
          }
          CATCH {
            default {
              $out ~= " ❰$p❱ ";
              @formatted.push(color('error') => " ❰" ~ $eval-str ~ "❱");
              $!errors ~= "sorry: $_\n";
            }
          }
        }
      }
      $out ~= "\n";
      @!formatted-content-lines.push(@formatted);
      if @extra-lines {
        @!formatted-content-lines.append(@extra-lines);
      }
      $all-content ~= $out;
    }
    $!last-content = $all-content;
    $all-content;
  }

  method cell-dir(Bool :$create = False) {
    my $subdir = $.wkdir.child($.page-name);
    if $create && !$subdir.d {
      $subdir.mkdir;
    }
    return $subdir;
  }

  method ext {
    # either a configured ext or it comes from the plugin, or csv as a last resort
    self.get-conf('_ext') || $!ext || $.output-ext || "csv";
  }

  method maybe-make-data-dir {
    $.data-dir.mkdir unless $.data-dir.d;
  }

  method output-file(Bool :$create = False) {
    my $ext = self.ext;
    self.cell-dir(:$create).child( self.name ~ "." ~ $ext);
  }

  #| Should the output file be closed after execution?
  method close-output-file {
    True
  }

  method out {
    my $file = self.output-file;
    fail "no output yet" unless $file && $file.e;
    return $file.slurp.trim;
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
    given self.ext {
      when 'csv' {
        my $file = self.output-file;
        my $db = Duckie.new;
        my $res = $db.query: "select * from read_csv('$file')";
        return $res;
      }
      when 'json' {
        return from-json slurp self.output-file;
      }
      default {
        return self.output-file.slurp;
      }
    }
  }

  method execute(:$mode = 'eval', :$page!, :$pane!, :$action) {
    $!plugin.errors = Nil;
    $!errors = Nil;
    # $pane.put: "Executing cell { $.name } of type { $.cell-type }";
    $pane.put: [ color('info') => "Executing cell ", color('cell-name') => $.name, color('info') => " of type ", color('cell-type') => $.cell-type ];
    return without $!plugin;
    info "Executing cell of type { $.cell-type }";
    indir self.cell-dir(:create), {
      info "In directory {self.cell-dir}";
      try {
        my IO::Handle $out;
        if $.plugin.write-output && !(self.get-conf('out') // '' eq 'none') {
          if $.plugin.clear-stream-before {
            $.plugin.stream:  txt => [ color('info') => "Writing to ", color('link') => "[" ~ self.output-file.IO.relative ~ "]" ],
                              meta => %( action => 'do_output', path => self.output-file );
          }
          info "writing to " ~ self.output-file.basename;
          $out = self.output-file.open(:w) 
        } else {
          $.plugin.info: "Not writing output";
        }
        LEAVE {
          try { $out.close } if self.close-output-file && $out;
        }
        self.maybe-make-data-dir;
        indir self.data-dir, {
          info "running plugin " ~ $.plugin.^name;
          $.plugin.clear-output;
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


}


