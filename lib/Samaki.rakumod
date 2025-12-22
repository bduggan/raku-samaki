use Terminal::ANSI::OO 't';
use Terminal::UI;
use Log::Async;
use Time::Duration;

use Samaki::Cell;
use Samaki::Page;
use Samaki::Events;
use Samaki::Plugins;
use Samaki::Plugouts;
use Samaki::Conf;
use Samaki::Utils;

unit class Samaki:ver<0.0.16>:api<1>:auth<zef:bduggan> does Samaki::Events;

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
        t.color(%COLORS<cell-type>) => $p<regex>.raku.fmt(' %-20s '),
        t.color(%COLORS<plugin-info>) => $p<name>.fmt('%20s : '),
        t.color(%COLORS<plugin-info>) => $p<desc> // '(no description)',
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
        t.color(%COLORS<cell-type>) => $p<regex>.raku.fmt(' %-20s '),
        t.color(%COLORS<plugin-info>) => $p<name>.fmt('%20s : '),
        t.color(%COLORS<plugin-info>) => $p<desc> // '(no description)',
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

multi method start-ui(Str :$page) {
  info "starting ui";
  self.start-ui: page => Samaki::Page.new(name => $page, :$.wkdir);
}

multi method start-ui(Samaki::Page :$page!) {
  $!current-page = $page;
  unless self.data-dir.IO.d {
    @!startup-log.push: "Creating data dir: " ~ self.data-dir;
    mkdir self.data-dir;
  }
  $.ui.setup: :2panes;
  (top, btm) = $.ui.panes;
  top.auto-scroll = False;
  btm.auto-scroll = False;
  self.show-page: $page;
  self.set-events;
  if @!startup-log {
    btm.put: $_ for @!startup-log;
    @!startup-log = ();
  }
  self.show-dir(self.data-dir, pane => btm, header => False);
  $.ui.interact;
  $.ui.shutdown;
  .shutdown with self.current-page;
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

  my @subdirs = reverse $dir.dir(test => { "$dir/$_".IO.d && !"$dir/$_".IO.basename.starts-with('.') }).sort: *.accessed;
  my %subs = @subdirs.map({.basename}).Set;
  my %shown = Set.new;

  my @pages = reverse $dir.IO.dir(test => { /'.' [ $suffix ] $$/ }).sort: *.accessed;
  for @pages -> $d {
    my $name = $d.basename.subst(/'.' $suffix/,'');
    my $title = "〜 { $name } 〜";
    my %meta =
      target_page => Samaki::Page.new( :$name, :path($d), :$.wkdir ),
      action => "load_page",
      data_dir => $.wkdir.child($name),
    ;
    my $width = pane.width;
    my @row = t.color(%COLORS<title>) => $title.fmt('%-40s');
    %shown{$name} = True;
    my $data-dir = $dir.child($name);
    my $file-count = 0;
    if $data-dir.d {
      $file-count = $data-dir.dir.elems;
      my $s = $file-count == 1 ?? '' !! 's';
      @row.push: t.color(%COLORS<info>) => "($file-count file{$s})".fmt('%-15s');
      $width -= 15;
    }

    @row.push: t.color(%COLORS<info>) => ago( (DateTime.now - $d.accessed).Int ).fmt("%{$width - 45}s");
    pane.put: @row, :%meta, :!scroll-ok;
  }

  my @others = $dir.IO.dir(test => { !/'.' [ $suffix ] $$/ && !.starts-with('.') }).sort: *.basename;
  for @others -> $path {
    next if %shown{$path.basename};
    if $path.IO.d {
      pane.put: [ t.color(%COLORS<yellow>) => ($path.basename ~ '/').fmt('%-40s'),
                  t.color(%COLORS<info>) => ago( (DateTime.now - $path.accessed).Int).fmt("%{$pane.width - 43}s") ],
                  meta => %(dir => $path, action => 'chdir')
    } else {
      my $color = %COLORS<datafile>;
      $color = %COLORS<inactive> if $highlight-samaki;
      pane.put: [ t.color($color) => $path.basename.fmt('%-40s'),
                  t.color(%COLORS<info>) => human-size($path.IO.s).fmt('%15s'),
                  t.color(%COLORS<info>) => ago( (DateTime.now - $path.accessed).Int).fmt("%{$pane.width - 43 - 15}s") ],
                  meta => %( :$path, action => "do_output", dir => $dir) :!scroll-ok;
    }
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

-- duck
select 'hello' as world;

-- duck
select 'earth' as planet;

-- llm
Which planet from the sun is 〈 cells(1).rows[0]<planet> 〉?

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

<img width="1143" height="1022" alt="Image" src="https://github.com/user-attachments/assets/8f03279a-c99a-4c46-b8f5-e2f198ed083c" />

<img width="1139" height="1020" alt="Image" src="https://github.com/user-attachments/assets/6581f5a9-0ec3-470c-a7f0-763488605d9a" />

=head1 FORMAT

A samaki page (or notebook) consists of two things

1. a text file, ending in .samaki

2. a directory containing data files.

The directory name will be the same as the basename of the file, and it
will be created if it doesn't exist.  e.g.

    taxi-data.samaki
    taxi-data/
       cell-0.csv
       cell-1.csv
       ... other data files ...

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

Cells may reference other cells by using angle brackets, as shown above:

    〈 cells(0).content 〉

alternatively, an ASCII equivalent `<<<` can be used:

    <<< cells(0).content >>>

Cells can be referenced by name or by number, e.g.

    〈 cells('the_answer').content 〉

refers to the contents of the above cell.  Also `c` and `cell` are synonyms for `cells`, and the
default Stringification will call `.content.trim`.  e.g.  this will also work:

    〈 c('the_answer') 〉

Calling `res` will return a C<Duckie::Result> object.  Calling `col`
uses `res` and `column-data` to return a list of values from a named column.

The API is still evolving, but at a minimum, it has the name of an output file;
plugins are responsible for writing to the output file.

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

=head1 INIT BLOCKS

A special type of cell that has no type can be used to run Raku code when the
page loads, like this:

   --
   my $p = 'mars';

   -- duck
   select * from planets where name = '〈 $p 〉';

The two dashes without a type indicate that this code should immediately
be evalutead.  There can be many of these blocks anywhere in the page.

=head1 PLUGINS

Plugin classes should do the `Samaki::Plugin` role, and at a minimum should
implement the `execute` method and have `name` and `description` attributes.
The usual `RAKULIB` directories are searched for plugins, so adding local plugins
is a matter of adding a new calss and placing it into this search path.

In addition to the strings above, a class definition may be placed directly
into the configuration file, and this definition can reference other plugins.

For instance, this defines a plugin called `python` for executing python code:


      / python / => class SamakiPython does Samaki::Plugin {
                      has $.name = 'samaki-python';
                      has $.description = 'run some python!';
                      method execute(:$cell, :$mode, :$page, :$out) {
                         my $content = $cell.get-content(:$mode, :$page);
                         $content ==> spurt("in.py");
                         shell "python in.py > out.py 2> errs.py";
                         $out.put: slurp "out.py";
                      }

Alternatively, the `Process` plugin provides a convenient way to run external
processes, and stream the results, so this will also work, and instead of temp files,
it will send code to stdin for python and put unbuffered output from stdout into the bottom pane:

    use Samaki::Plugin::Process;

    %*samaki-conf =
      plugins => [
      ...
        / python / => class SamakiPython does Samaki::Plugin::Process[
                       name => 'python',
                       cmd => 'python3' ] {
           has %.add-env = PYTHONUNBUFFERED => '1';
          },
      ...

See below for a list of plugins that come with samaki.

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

See below for a list of plugouts that come with samaki.

=head1 INCLUDED PLUGINS

The list below are plugins that come with samaki.

=head2 Samaki::Plugin::Duck

Run SQL queries using the duckdb executable.  i.e. the cell is sent to stdin
of the `duckdb` executable, and stdout is saved to a file.

=head2 Samaki::Plugin::Duckie

Send the contents of the cell to an inline duckdb driver.  For this and the
above, the first 100 rows are placed in the bottom row, and selecting
them will show that row in the top pane.

=head2 Samaki::Plugin::LLM

Send the contents of the cell to an llm which will be evaluted using L<LLM::DWIM>.

=head2 Samaki::Plugin::Raku

Send the contents to a separate process that is running raku.

=head2 Samaki::Plugin::Code

Evaluate code in the current raku process, in the context of the rest of the code blocks.

=head2 Samaki::Plugin::Text

Write the contents of a cell to a text file.

=head2 Samaki::Plugin::Repl::Raku

Write the contents to a running version of the raku repl, and keep it running.

=head2 Samaki::Plugin::Repl::Python

Ditto, but for python.

=head2 Samaki::Plugin::Bash

Execute the contents as a bash program.

=head2 Samaki::Plugin::HTML

Generate HTML from the contents.

=head2 Samaki::Plugin::Markdown

Generate HTML from markdown.

=head2 Samaki::Plugin::Postgres

Execute SQL queries against a Postgres database by sending queries to the psql command-line tool.

=head1 Included Plugouts

These plugouts are available by default, and included in the Samaki distribution:

=head2 Samaki::Plugout::DataTable

Show a csv in a web browser with column-sorting, pagination, and searching.

=head2 Samaki::Plugout::Duckview

Use the built-in summarization of duckdb to show a csv in the bottom pane.

=head2 Samaki::Plugout::HTML

Open a webbrowser with the content.

=head2 Samaki::Plugout::JSON

Show the (prettified) json in the bottom pane.

=head2 Samaki::Plugout::Plain

Display plain text in a web browser.

=head2 Samaki::Plugout::Geojson

Use leafpad to create an HTML page with the content, and open a web browser.

=head2 Samaki::Plugout::Raw

Call the system `open` or `xdg-open` whhch will open the file based on system
settings, and the file extension.

=head2 Samaki::Plugout::TJLess

Use `jless` to view json in a new `tmux` window.  (requires jless and tmux)

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

