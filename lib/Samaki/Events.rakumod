unit role Samaki::Events;
use Terminal::ANSI::OO 't';
use Samaki::Page;
use Samaki::Conf;
use Log::Async;
use Samaki::Utils;

method show-page { ... }
method show-dir { ... }
method plugouts { ... }
method data-dir { ... } #= current data directory

method set-events {
  my (\ui) = $.ui;
  my (\top,\btm) = $.ui.panes;

  ui.bind: 'pane', 'o' => 'open-cell-output';
  top.on: open-cell-output => -> :%meta {
    btm.clear;
    my $page = %meta<page> // self.current-page;
    my $cell = %meta<cell> // $page.current-cell;
    with $cell.output-file -> $file {
      if $file.IO.e {
        btm.put: [ col('info') => "Opening output file ", col('link') => "[" ~ $file.IO.relative ~ "]" ];
        $.plugouts.dispatch($file, pane => btm, data-dir => self.data-dir, name => $cell.name );
      } else {
        btm.put: [ col('error') => "Output file " ~ col('link') ~ "[" ~ $file.IO.relative ~ "]" ~ col('error') ~ " does not exist.  Run the cell first." ];
      }
    } else {
      btm.put: "Cell has no output.";
    }
  };

  ui.bind: 'pane', 'e' => 'edit';

  ui.bind: 'v' => 'verbose-toggle';
  ui.on: verbose-toggle => {
    my $level = get-stream-log-level;
    my $new-level = $level eq 'quiet' ?? 'verbose' !! 'quiet';
    ui.alert: "output level: $new-level";
    set-stream-log-level($new-level);
  };

  $.ui.bind: 'pane', 's' => 'run-shell';
  top.on-sync: run-shell => -> :%meta {
    my $line = top.current-line-index;
    put t.text-reset;
    put t.clear-screen;
    put t.reset-scroll-region;
    $.ui.input.shutdown;
    shell "stty sane; tput cnorm";
    my $dir = self.wkdir;
    $dir = self.data-dir if self.current-page;
    indir $dir, {
      my $shell = %*ENV<SAMAKI_SHELL> // '/bin/bash';
      put "starting $shell in $dir.  Exit the shell to return to samaki.";
      try {
        my $proc = shell "$shell -i";
        debug "shell ($shell) exited with " ~ $proc.exit-code;
        CATCH {
          default {
            warning "error running shell: $_";
          }
        }
      }
    }
    $.ui.refresh: :hard;
    $.ui.input.init;
    top.select: $line;
  };

  top.on-sync: edit => -> :%meta {
    my $line = top.current-line-index;
    put t.text-reset;
    put t.clear-screen;
    put t.reset-scroll-region;
    sleep 0.1;
    my $page = %meta<page> // %meta<target_page> // self.current-page;
    without $page {
      $page = Samaki::Page.new(name => "new", wkdir => self.wkdir);
    }
    mkdir $page.data-dir unless $page.data-dir.d;
    indir $page.data-dir, {
      try shell <<$.editor "+$line" {$page.path.resolve.absolute}>>;
    }
    if $! {
        $.ui.panes[1].put: "error starting editor: $!";
    } else {
      $page.reload(plugins => $.plugins);
      self.show-page: $page;
      $.ui.refresh: :hard;
      top.select: $line;
    }
  };

  $.ui.bind: 'pane', 'r' => 'refresh';
  top.on: refresh => -> :%meta {
    my $line = top.current-line-index;
    my $page = %meta<page> // self.current-page;
    self.show-page($_) with $page;
    top.select: $line;
  };

  $.ui.bind: 'pane', 'm' => 'toggle-mode';
  top.on: toggle-mode => -> :%meta {
    my $line = top.current-line-index;
    my $page = %meta<page> // self.current-page;
    with $page && $page.mode {
      when 'eval' { $page.mode = 'raw' }
      when 'raw'  { $page.mode = 'eval' }
    }
    self.show-page($_) with $page;
    top.select: $line;
  }

  ui.bind: 'pane', 'c' => 'clear';
  top.on: clear => { top.clear; }
  btm.on: clear => { btm.clear; }

  top.on: select => -> :%meta {
    debug "Top pane action { %meta<action>.raku }";
    with %meta<action> {
      when 'run' | 'save' {
        my $cell = %meta<cell> or die "NO CELL";
        self.current-page.run-cell($cell, btm => btm, top => top, action => %meta<action>);
      }
      when 'load_page' {
        my $page = %meta<target_page> // Samaki::Page.new(name => %meta<page_name>, wkdir => %meta<wkdir>);
        top.clear;
        self.show-page: $page;
        with %meta<data_dir> -> $dir {
          self.show-dir($dir, pane => btm, header => False, :highlight-samaki);
        }
        # $.ui.refresh: :hard;
        top.select: 0;
      }
      when 'chdir' {
        self.wkdir = %meta<dir>;
        self.show-dir(%meta<dir>, :highlight-samaki);
      }
      when 'do_output' {
        my $name;
        my $data-dir;
        with self.current-page {
          $name = .current-cell.name // .cells[0].name;
          $data-dir = self.data-dir;
        } else {
          $name = "new-{now.Int}";
          $data-dir = $*TMPDIR;
        }

        with %meta<path> -> $path {
           $.plugouts.dispatch($path, pane => btm, :$data-dir, :$name,
           |%( %meta<plugout_name> ?? %( plugout_name => %meta<plugout_name>) !! %() )
         );
        } else {
          warning "missing path in meta, skipping plugout"
        }
      }

      when 'write_file' {
        indir self.data-dir, {
          %meta<content> ==> spurt %meta<file>;
        }
        top.put: "saved!"
      }

      default {
        info "Unknown action { %meta<action> }";
      }
    }
  }

  btm.on: select => -> :%meta {
    info "Bottom pane action { %meta<action>.raku }";
    with %meta<action> {
      when 'kill_proc' {
        with %meta<proc> -> $proc {
          info "Killing process { $proc.pid.result }";
          btm.put: "Killing process { $proc.pid.result }";
          $proc.kill;
        }
      }
      when 'do_output' {
        my $page = self.current-page;
        my $path = %meta<path> or die "missing path in output action";
        unless $page {
           $.plugouts.dispatch($path, pane => btm, data-dir => self.data-dir, name => "new-{now.Int}");
           return;
        }
        my $cell = $page.current-cell // $page.cells[0];
        $.plugouts.dispatch:
           $path, pane => btm, data-dir => self.data-dir, name => $cell.name,
           cell-content => $cell.last-content,
           cell-conf => $cell.conf,
           |%( %meta<plugout_name> ?? %( plugout_name => %meta<plugout_name>) !! %() )
      }
      when 'view_row' {
        top.clear;
        my $cols = %meta<cols>;
        my $row = %meta<row_data>;
        my $width = 50 min $cols.map(*.chars).max + 2;
        for @$cols Z, @$row -> ($c,$r) {
          top.put: [ t.color(%COLORS<info>) => "$c".fmt("%-{$width}s") ~ " : ", t.color(%COLORS<data>) => show-datum($r) ];
        }
        top.put: [ t.color(%COLORS<button>) => "[save to cols.txt] ",
                   t.color(%COLORS<data>) => $cols.join(',')
                 ],
                   meta => %( action => 'write_file', file => 'cols.txt', content => $cols.join(',') );
      }
      when 'exit_proc' {
        with %meta<proc> -> $proc {
          info "Closing stdin for process";
          $proc.put: "exit";
        }
      }
    }
  }

  $.ui.bind: 'pane', ']' => 'next-query';
  top.on: next-query => -> :%meta {
    my $page = %meta<page> // self.current-page;
    with %meta<cell> -> $cell {
      my $next = $cell.index + 1;
      $next = 0 if $next >= $page.cells;
      my $line = $page.mode eq 'eval'
        ?? $page.cells[$next].display-line
        !! $page.cells[$next].start-line + $page.title-height;
      top.select: $line;
    } else {
      top.select: $page.title-height;
    }
  }

  $.ui.bind: 'pane', '[' => 'prev-query';
  top.on: prev-query => -> :%meta {
    with %meta<page> -> $page {
      with %meta<cell> -> $cell {
        my $next = $cell.index - 1;
        $next = $page.cells.elems - 1 if $next < 0;
        my $line = $page.mode eq 'eval'
          ?? $page.cells[$next].display-line
          !! $page.cells[$next].start-line + $page.title-height;
        top.select: $line;
      } else {
        my $next = $page.cells.elems - 1;
        my $line = $page.mode eq 'eval'
          ?? $page.cells[$next].display-line
          !! $page.cells[$next].start-line + $page.title-height;
        top.select: $line;
      }
    }
  }

  $.ui.bind('pane', l => 'list-dir');
  top.on: list-dir => -> :%meta (:$dir, *%) { self.show-dir($dir || self.wkdir, :highlight-samaki) };
  btm.on: list-dir => -> :%meta (:$dir, *%) { self.show-dir($dir || self.data-dir, pane => btm, header => False) };

}


