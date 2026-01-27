use Terminal::ANSI::OO 't';
use Terminal::UI;
use Terminal::WCWidth;
use Log::Async;
use Time::Duration;

use Samaki::Cell;
use Samaki::Page;
use Samaki::Events;
use Samaki::Plugins;
use Samaki::Plugouts;
use Samaki::Conf;
use Samaki::Utils;
use Samaki::Watcher;

unit class Samaki:ver<0.0.28>:api<1>:auth<zef:bduggan> does Samaki::Events;

has $.ui = Terminal::UI.new;
my \top := my $;
my \btm := my $;

has $.log = logger;
has @.startup-log;
has @.verbose-startup-log;

has $.conf;

has $.wkdir is rw = $*CWD;
has $.editor is rw;
has Samaki::Page $.current-page is rw;
has $.plugins = Samaki::Plugins.new;
has $.plugouts = Samaki::Plugouts.new;
has Str $.config-file;
has $.conf-errors;
has $.watcher;


my $base = %*ENV<XDG_CONFIG_HOME>.?IO // $*HOME.child('.config');
my $samaki-home = %*ENV<SAMAKI_HOME>.?IO // $base.child('samaki');
my $config-location = %*ENV<SAMAKI_CONFIG>.?IO // $samaki-home.child('samaki-conf.raku');

method data-dir {
  $.wkdir.child( $.current-page.name );
}

submethod TWEAK {
  unless $!wkdir.IO.d {
    @!startup-log.push: "Creating working directory at " ~ $!wkdir;
    mkdir $!wkdir
  }

  unless $!conf {
    unless $samaki-home.IO.d {
      @!startup-log.push: "Creating samaki config directory at " ~ $samaki-home;
      mkdir $samaki-home;
    }
    unless $config-location.IO.e {
      copy %?RESOURCES{ 'samaki-conf-default.raku' }.IO.Str, $config-location;
      @!startup-log.push: "copied fresh config file to $config-location";
    }
    $!config-file = $config-location.Str;
    die "could not open config file $!config-file" unless $!config-file.IO.e;
    @!verbose-startup-log.push: "Using config file " ~ $!config-file;
    info "Using config file " ~ $!config-file;
    $!conf = Samaki::Conf.new(file => $!config-file);
  }

  try {
    $!plugins.configure($!conf);
    @!verbose-startup-log.push: "Available plugins: ";
    for $!plugins.list-all -> $p {
      @!verbose-startup-log.push: [
        color('cell-type') => $p<regex>.raku.fmt(' %-20s '),
        color('plugin-info') => $p<name>.fmt('%20s : '),
        color('plugin-info') => $p<desc> // '(no description)',
      ];
    }
    CATCH {
      default {
        $!conf-errors = $_;
        @!startup-log.push: "Error configuring plugins: $_";
        error "Error configuring plugins: $_";
        note "startup errors: " ~ @!startup-log.join("\n");
        note "config file: " ~ $!config-file;
        exit;
        return;
      }
    }
  }

  try {
    $!plugouts.configure($!conf);
    @!verbose-startup-log.push: "Available plugouts: ";
    for $!plugouts.list-all -> $p {
      @!verbose-startup-log.push: [
        color('cell-type') => $p<regex>.raku.fmt(' %-20s '),
        color('plugin-info') => $p<name>.fmt('%20s : '),
        color('plugin-info') => $p<desc> // '(no description)',
      ];
    }
    CATCH {
      default {
        $!conf-errors = $_;
        @!startup-log.push: "Error configuring plugouts: $_";
        error "Error configuring plugouts: $_";
      }
    }
  }
}

multi method start-ui(Str :$page, Bool :$watch) {
  info "starting ui";
  self.start-ui: page => Samaki::Page.new(name => $page, :$.wkdir), :$watch;
}

multi method start-ui(Samaki::Page :$page!, Bool :$watch) {
  $!current-page = $page;
  $.ui.setup: ratios => [3,1];
  (top, btm) = $.ui.panes;
  top.auto-scroll = False;
  btm.auto-scroll = False;
  self.show-page: $page;
  self.set-events;
  if self.data-dir.IO.d {
    self.show-dir(self.data-dir, pane => btm, header => False);
  }
  unless $page.path.e {
    @!startup-log.push: "Use [e] to create {$page.name}";
  }
  if @!startup-log {
    btm.put: $_ for @!startup-log;
    @!startup-log = ();
  }
  if $watch {
    $!watcher = Samaki::Watcher.new: :$page, on-change =>
      -> $page {
          my $line = top.current-line-index;
          $page.reload(:$!plugins);
          info "file change detected, reloading page";
          self.show-page: $page;
          top.select: $line;
        };
    $!watcher.start;
  }
  $.ui.interact;
  .shutdown with self.current-page;
  $.ui.shutdown;
}

multi method start-ui('browse') {
   $.ui.setup: :2panes;
    (top, btm) = $.ui.panes;
    top.auto-scroll = False;
    btm.auto-scroll = False;
    self.set-events;
    if @!startup-log || @!verbose-startup-log {
      btm.put: $_ for @!startup-log;
      btm.put: $_ for @!verbose-startup-log;
      @!startup-log = ();
      @!verbose-startup-log = ();
    }
    self.show-dir($!wkdir, :highlight-samaki);
    $.ui.interact;
    $.ui.shutdown;
    .shutdown with self.current-page;
}

multi method show-page(Str $name) {
  self.show-page: Samaki::Page.new( :$name, :$.wkdir );
}

multi method show-page(Samaki::Page $page) {
  top.clear;
  $page.show(pane => top, :$!plugins);
  $!current-page = $page;
}

sub human-size($bytes) {
  return sprintf("%7d b", $bytes) if $bytes < 1024;
  my @units = <b kb mb gb tb pb eb zb yb>;
  my $exp = Int( log($bytes) / log(1024) );
  $exp = @units.elems - 1 if $exp >= @units.elems;
  my $size = $bytes / (1024 ** $exp);
  return sprintf("%5.1f %s", $size, @units[$exp]);
}

sub pad-width($str, $target-width, :$align = 'left') {
  my $current = wcswidth($str);
  if $current > $target-width {
    # Truncate to fit, accounting for display width
    my $truncated = '';
    my $width = 0;
    for $str.comb -> $char {
      my $char-width = wcwidth($char.ord);
      last if $width + $char-width > $target-width - 1;  # Leave room for ellipsis
      $truncated ~= $char;
      $width += $char-width;
    }
    return $truncated ~ '…' ~ (' ' x ($target-width - $width - 1));
  }
  my $padding = $target-width - $current;
  return $str if $padding <= 0;
  return $align eq 'left' ?? $str ~ (' ' x $padding) !! (' ' x $padding) ~ $str;
}

method show-dir(IO::Path $dir, :$suffix = 'samaki', :$pane = top, Bool :$header = True, Bool :$highlight-samaki) {
  my \pane := $pane;
  $dir = $!wkdir unless $dir;
  pane.clear;
  if $header {
    pane.put: [t.yellow => "$dir"], :center;
    pane.put: [t.white => "../"], meta => %(dir => $dir.parent, action => 'chdir'), :!scroll-ok;
  } else {
    pane.put: [t.yellow => $dir.basename ~ '/'], :center;
  }

  unless $dir && $dir.d {
    pane.put: "$dir does not exist.";
    pane.put: "";
    pane.put: "Run a query to create this working directory.";
    pane.put: "";
    pane.put: "Use 'e' to edit this page.";
    return;
  }

  my @subdirs = reverse $dir.dir(test => { "$dir/$_".IO.d && !"$dir/$_".IO.basename.starts-with('.') }).sort({.accessed});
  my %subs = @subdirs.map({.basename}).Set;
  my %shown = Set.new;

  my $width = pane.width;
  my $name-width = ($width * 0.60).Int;
  my $size-width = 10;
  my $date-width = $width - $name-width - $size-width - 2;  # 2 spaces between columns

  my @pages = reverse $dir.IO.dir(test => { /'.' [ $suffix ] $$/ }).sort({ .accessed });
  for @pages -> $d {
    my $name = $d.basename.subst(/'.' $suffix/,'');
    my $title = "〜 { $name } 〜";
    my %meta =
      target_page => Samaki::Page.new( :$name, :path($d), :$.wkdir ),
      action => "load_page",
      data_dir => $.wkdir.child($name),
    ;
    my $page-date-width = $date-width + $size-width + 1;  # pages don't show size, reclaim that space
    my @row = color('title') => pad-width($title, $name-width);
    %shown{$name} = True;
    my $data-dir = $dir.child($name);
    my $file-count = 0;
    if $data-dir.d {
      $file-count = $data-dir.dir.elems;
      my $s = $file-count == 1 ?? '' !! 's';
      @row.push: color('info') => " " ~ "($file-count file{$s})".fmt("%-{$size-width}s");
      $page-date-width -= $size-width + 1;
    }

    @row.push: color('date') => " " ~ ago( (DateTime.now - $d.accessed).Int, 1 ).fmt("%{$page-date-width}s");
    pane.put: @row, :%meta, :!scroll-ok;
  }

  my @others = reverse $dir.IO.dir(test => { !/'.' [ $suffix ] $$/ && !.starts-with('.') }).sort({.accessed});
  for @others -> $path {
    next if %shown{$path.basename};
    if $path.IO.d {
      my $dir-date-width = $date-width + $size-width + 1;  # directories don't show size
      pane.put: [ color('yellow') => pad-width($path.basename ~ '/', $name-width),
                  color('date') => " " ~ ago( (DateTime.now - $path.accessed).Int, 1).fmt("%{$dir-date-width}s") ],
                  meta => %(dir => $path, action => 'chdir')
    } else {
      my $color-name = $highlight-samaki ?? 'inactive' !! 'datafile';
      pane.put: [ color($color-name) => pad-width($path.basename, $name-width),
                  color('info') => " " ~ human-size($path.IO.s).fmt("%{$size-width}s"),
                  color('date') => " " ~ ago( (DateTime.now - $path.accessed).Int, 1).fmt("%{$date-width}s") ],
                  meta => %( :$path, action => "do_output", dir => $dir) :!scroll-ok;
    }
  }

  if @subdirs == @pages == @others == 0 {
    pane.put: "0 files found.";
  }

  pane.select(2);
}

method page-exists($name) {
  info "path is " ~ Samaki::Page.new( :$name, :$.wkdir ).path;
  Samaki::Page.new( :$name, :$.wkdir ).path.e;
}

method pages-exist {
  $!wkdir.IO.dir(test => { /'.' [ 'samaki' ] $$/ }).elems > 0;
}

=begin pod

=head1 NAME

Samaki -- Stich Associated Modes of Accessing and Keeping Information

=head1 SYNOPSIS

=begin code

Usage:
  sam            -- start the default UI, and browser the current directory
  sam <name>     -- start with the named samaki page or directory
  sam import <file> [--format=jupyter] -- import from another format to samaki
  sam export <name> [--format=html] -- export a samaki file to HTML (or other formats)
  sam conf       -- edit the configuration file ~/.samaki.conf
  sam reset-conf -- reset the configuration file to the default

Type `sam -h` for the full list of options.

=end code

=head1 DESCRIPTION

Samaki is a file format and tool for using multiple programming languages
in a single file.

It's a bit like Jupyter notebooks (or R or Observable notebooks), but with multiple
types of cells in one notebook and all the cells belong to a simple text file.
It has a plugin architecture for defining the types of cells, and for describing
the types of output.  Outputs from cells are serialized, often as CSV
files.  Cells can reference each others' content or output.

Some use cases for samaki include

* querying data from multiple sources

* trying out different programming languages

* reining in LLMs

Here's an example:

=begin code

-- duck:hello
select 'hello' as world;

-- duck:earth
select 'earth' as planet;

-- llm:planet.txt
Which planet from the sun is 〈 cells('earth').rows[0]<planet> 〉?

=end code

To use this:

1. save it as a file, e.g. "planets.samaki"

2. run `sam planets'

3. press 'm' to toggle between raw mode and rendered mode

4. highlight the second cell and press enter to run the query

5. press r to refresh the page, also press m to change the mode, and notice that it has changed to

    "Which planet from the sun is earth?"

6. highlight the third cell and press enter to run the LLM query

For more examples, check out the
L<eg/|https://github.com/bduggan/raku-samaki/tree/main/eg> directory.

Below is what the screen looks like during this interactive session before earth.csv
is created, when the cell is in raw mode:

=begin code

╔═════════════════════════════════════════════════════════════════════╗
╢                           -- planets --                             ║
║    ┌── duck (txt)           [run] ➞  hello.txt                      ║
║  0 │ select 'hello' as world;                                       ║
║  1 └                                                                ║
║    ┌── duck (csv)           [run] ➞  earth.csv                      ║
║  0 │ select 'earth' as planet;                                      ║
║  1 └                                                                ║
║    ┌── llm (txt)            [run] ➞  planet.txt                     ║
║  0 │ Which planet from the sun is 〈 cells(1).rows[0]<planet> 〉?   ║
║  1 └                                                                ║
║                                                                     ║
╟─────────────────────────────────────────────────────────────────────╢
║                       planets/                                      ║
║ planet.txt                 45 b         9 hours and 52 minutes ago  ║
║ hello.csv                  12 b            7 days and 18 hours ago  ║
║                                                                     ║
╚═════════════════════════════════════════════════════════════════════╝

=end code

=head1 FORMAT

A samaki page (or notebook) consists of two things

1. a text file, ending in .samaki

2. a directory containing data files.

The directory name will be the same as the basename of the file, and it
will be created if it doesn't exist.  e.g.

    planets.samaki
    planets/
       hello.txt
       earth.csv
       planet.txt

The samaki file is a text file divided into cells, each of which looks like this:

    -- <cell type> [ : <name> ['.' <ext>]? ]?
    | <conf-key 1> : <conf-value 1>
    | <conf-key 2> : <conf-value 2>
    [... cell content ..]

That is:

1. New cells are indicated with a line starting with two dashes and a space ("-- ")
   folowed by the type of the cell.  (Other similar unicode dashes like "─" can also be used)

2. The type of the cell should be a single word with alphanumeric characters.

3. An optional colon and name can give a name to the cell.
  
4. After the dashes, optional configuration options can be set as `name : value` pairs
   with a leading pipe symbol (`|`)

Another example: a cell named "the_answer" that runs a query and uses a duckdb file named life.duckdb

    -- duck : the_answer
    | file: life.duckdb

    select 42 as life_the_universe_and_everything

Running the cell above creates `the_answer.csv` in the data directory.  Note that
if the extension is omitted, it is assumed to be `.csv`.  `the_answer.csv` could
also have been written.

Angle brackets are interpolated into cell content.  For instance :

    〈 cells(0).content 〉

alternatively, an ASCII equivalent `<<<` can be used:

    <<< cells(0).content >>>

Cells can be referenced by name or by number, e.g.

    〈 cells('the_answer').content 〉

Also `c` and `cell` are synonyms for `cells`.  Also `out` and `src` refer
to the output and source for the cell respectively.  For instance:

    〈 c('the_answer').out 〉

Calling `res` will return a C<Duckie::Result> object for cells with CSV data.

The API is still evolving, suggestions are welcome!

=head1 CONFIGURATION

The configuration file for samaki is a raku file located at `~/.config/samaki/samaki-conf.raku`.
Environment variables `$SAMAKI_HOME` and `$SAMAKI_CONFIG` can be used to override
the directory and file name respectively.  Also `$XDG_CONFIG_HOME` is used if set.

Samaki is configured with a set of regular expressions which are used to determine
how to handle each cell.  The "type" of the cell above is matched against the
regexes, and whichever one matches first will be used to parse the input
and generate output.

Samaki comes with a default configuration file and some default plugins.  The default
configuration looks something like
this (see L<here|https://github.com/bduggan/raku-samaki/tree/main/resources/>
for the actual contents) :

    # samaki-conf.raku
    #
    %*samaki-conf =
      plugins => [
        / duck /   => 'Samaki::Plugin::Duck',
        / llm  /   => 'Samaki::Plugin::LLM',
        / text /   => 'Samaki::Plugin::Text',
        / bash /   => 'Samaki::Plugin::Bash',
        / html/    => 'Samaki::Plugin::HTML',
      ],
      plugouts => [
        / csv  /   => 'Samaki::Plugout::Duckview',
        / csv  /   => 'Samaki::Plugout::DataTable',
        / html /   => 'Samaki::Plugout::HTML',
        / .*   /   => 'Samaki::Plugout::Raw',
      ]
    ;

=head1 RELOADING

Starting sam with "--watch" will autoreload the page when the file is changed.

=head1 INIT BLOCKS

A special type of cell that has no type can be used to run Raku code when the
page loads, like this:

   --
   my $p = 'mars';

   -- duck
   select * from planets where name = '〈 $p 〉';

The two dashes without a type indicate that this code should immediately
be evaluated.  Blocks like this can be used throughout the page, and are
executed when the page loads, at the same time that interpolated code
is evaluated.

=head1 PLUGINS

Plugin classes should do the `Samaki::Plugin` role, and at a minimum should
implement the `execute` method and have `name` and `description` attributes.
The usual `RAKULIB` directories are searched for plugins, so adding local plugins
is a matter of adding a new calss and placing it into this search path.

When interacting with external programs, there are three (and probably more)
distinct ways to do this.  There is some redundancy in the plugins because
we offer more than one way to interact with external programs.  The three
ways that are currently abstracted across plugins are are

- using a native driver.  For instance, `Duckie` offers bindings to the C API
    for duckdb.

- by spawning an external process and using stdin/stdout/stderr to communicate.
    For instance, `duck` does this -- it runs the `duckdb` command, sends data on stdin
    and captures stdout/stderr.  This is abstracted in `Samaki::Plugin::Process`.

- by interacting with a command line REPL provided by another program and setting up
    a Pseudo-TTY to show what would go to the screen.   `Samaki::Plugin::Repl` does this,
      and `Samaki::Plugin::Repl::Python` is an example.

Of these methods, there are a few functional differences.

1. persistence: currently only the last one offers persistence -- i.e. definitions between
     cells will persist within the REPL process.  e.g. if one cell has `x=12`
     and another has `print(x)` then the second will print 12 if it is run after the first.
     The other plugins are executed once and are stateless.

2. output shown vs output saved: for native drivers the output that is shown on the screen
     is precisely what is stored.  The second one stores output in a file, but does not
     necessarily display it all.  This can be useful running programs that create large
     datasets.  There may be some inconsistency depending on the plugin, so consult the
     individual plugin's implementation to see what it does.

In addition to classes defined in code, class definitions may be placed directly
into the configuration file.

For instance, this snippet below is sufficient to implement a plugin called `python`
for executing python code, saving the result to a file for that cell:

      / python / => class SamakiPython does Samaki::Plugin {
                      has $.name = 'samaki-python';
                      has $.description = 'run some python!';
                      method execute(:$cell, :$mode, :$page, :$out) {
                         my $content = $cell.get-content(:$mode, :$page);
                         $content ==> spurt("in.py");
                         shell "python in.py > out.py 2> errs.py";
                         $out.put: slurp "out.py";
                      }

An even simpler version could make use of the Process base class described above:

    use Samaki::Plugin::Process;

    %*samaki-conf =
        / python / => class SamakiPython does Samaki::Plugin::Process[
                       name => 'python',
                       cmd => 'python3' ] {
           has %.add-env = PYTHONUNBUFFERED => '1';
          },

=head1 INCLUDED PLUGINS

The following plugins are included with samaki:

=begin table
Plugin                  | Type     | Description
========================|==========|============================================
Bash                    | Process  | Execute contents as a bash program
Code                    |          | Evaluate raku code in the current process
Duck                    | Process  | Run SQL queries via duckdb executable
Duckie                  | inline   | Run SQL queries via Duckie inline driver
File                    |          | Display file metadata and info
HTML                    |          | Generate HTML from contents
LLM                     | inline   | Send contents to LLM via LLM::DWIM
Markdown                | inline   | Generate HTML from markdown
Postgres                | Process  | Execute SQL via psql process
Raku                    | Process  | Run raku in a separate process
Repl::Raku              | Repl     | Interactive raku REPL (persistent session)
Repl::Python            | Repl     | Interactive python REPL (persistent session)
Repl::R                 | Repl     | Interactive R REPL (persistent session)
Text                    |          | Write contents to a text file
Tmux::Bash              |          | Run bash code in a new tmux window
Tmux::Python            |          | Run python code in a new tmux window
URL                     |          | Fetch a URL using curl
=end table

Plugin documentation:

* L<Bash|docs/lib/Samaki/Plugin/Bash.md>
* L<Code|docs/lib/Samaki/Plugin/Code.md>
* L<Duck|docs/lib/Samaki/Plugin/Duck.md>
* L<Duckie|docs/lib/Samaki/Plugin/Duckie.md>
* L<File|docs/lib/Samaki/Plugin/File.md>
* L<HTML|docs/lib/Samaki/Plugin/HTML.md>
* L<LLM|docs/lib/Samaki/Plugin/LLM.md>
* L<Markdown|docs/lib/Samaki/Plugin/Markdown.md>
* L<Postgres|docs/lib/Samaki/Plugin/Postgres.md>
* L<Raku|docs/lib/Samaki/Plugin/Raku.md>
* L<Repl::Raku|docs/lib/Samaki/Plugin/Repl/Raku.md>
* L<Repl::Python|docs/lib/Samaki/Plugin/Repl/Python.md>
* L<Repl::R|docs/lib/Samaki/Plugin/Repl/R.md>
* L<Text|docs/lib/Samaki/Plugin/Text.md>
* L<Text|docs/lib/Samaki/Plugin/URL.md>
* <Tmux::Bash|docs/lib/Samaki/Plugin/Tmux/Bash.md>
* <Tmux::Python|docs/lib/Samaki/Plugin/Tmux/Python.md>


=head1 PLUGIN OPTIONS

Options may be given using a vertical line after the name of the plugin like this:

  -- llm
  | model: claude

Options are plugin-specific.  See the documentation for each plugin for details.

=head1 PLUGOUTS

Output files are also matched against a sequence of regexes, and these can be
used for visualizing or showing output.

These should also implement `execute` which has this signature:

   method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) { ... }

Plugouts are intended to either visualize or export data.  The plugout for viewing
an HTML file is basically:

  method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
    shell <<open $path>>;
  }

=head1 INCLUDED PLUGOUTS

The following plugouts are included with samaki:

=begin table
Plugout                 | Description
========================|============================================
ChartJS                 | Display CSV as interactive charts in browser (via Chart.js)
CSVGeo                  | Display CSV that has geojson data using a map in browser (via leaflet)
D3                      | Display CSV as D3.js visualizations in browser
DataTable               | Display CSV in browser with sorting/pagination/search
DeckGLBin               | Display spatial bins (H3, geohash, GeoJSON) as 3D extrusions (via deck.gl)
Duckview                | Show CSV summary in bottom pane (via duckdb)
Geojson                 | Display GeoJSON on map in browser (via leaflet)
HTML                    | Open HTML content in browser
JSON                    | Display prettified JSON in bottom pane
Plain                   | Display plain text in browser
Raw                     | Open file with system default application
TJLess                  | View JSON in new tmux window (requires jless)
=end table

Plugout documentation:

* L<ChartJS|docs/lib/Samaki/Plugout/ChartJS.md>
* L<CSVGeo|docs/lib/Samaki/Plugout/CSVGeo.md>
* L<D3|docs/lib/Samaki/Plugout/D3.md>
* L<DataTable|docs/lib/Samaki/Plugout/DataTable.md>
* L<DeckGLBin|docs/lib/Samaki/Plugout/DeckGLBin.md>
* L<Duckview|docs/lib/Samaki/Plugout/Duckview.md>
* L<Geojson|docs/lib/Samaki/Plugout/Geojson.md>
* L<HTML|docs/lib/Samaki/Plugout/HTML.md>
* L<JSON|docs/lib/Samaki/Plugout/JSON.md>
* L<Plain|docs/lib/Samaki/Plugout/Plain.md>
* L<Raw|docs/lib/Samaki/Plugout/Raw.md>
* L<TJLess|docs/lib/Samaki/Plugout/TJLess.md>

=head1 IMPORTS/EXPORTS

An entire samaki page can be exported as HTML or imported from Jupyter.  This is
still evolving.  For now, for instance:

    sam export eg/planets

will generate a nice HTML page based on the samaki input.  It will embed output files into the HTML.

=head1 USAGE

Usage is described at the top.  For help, type `sam -h`.

Have fun!

=head1 BUGS

The backronym is a bit forced.  Here's another one: Simple Arrangements of Modules with Any Kind of Items

=head1 TODO

A lot, especially more documentation.

Contributions are welcome!

=head1 AUTHOR

Brian Duggan (bduggan at matatu.org)

=end pod

