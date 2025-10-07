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

unit class Samaki:ver<0.0.1>:api<1>:auth<zef:bduggan> does Samaki::Events;

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
my $config-location = %*ENV<SAMAKI_CONF> // (%*ENV<XDG_HOME> // $*HOME).IO.child('.samaki.conf');

method data-dir {
  $.wkdir.child( $.current-page.name );
}

submethod TWEAK {
  unless $!wkdir.IO.d {
    @!startup-log.push: "Creating working directory at " ~ $!wkdir;
    mkdir $!wkdir
  }
  unless $!conf {
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
}

multi method show-page(Str $name) {
  self.show-page: Samaki::Page.new( :$name, :$.wkdir );
}

multi method show-page(Samaki::Page $page) {
  top.clear;
  btm.clear;
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
    pane.put: "$dir does not exist";
    return;
  }

  my @subdirs = reverse $dir.dir(test => { "$dir/$_".IO.d && !"$dir/$_".IO.basename.starts-with('.') }).sort: *.accessed;
  my %subs = @subdirs.map({.basename}).Set;
  my %shown = Set.new;

  my @pages = reverse $dir.IO.dir(test => { /'.' [ $suffix ] $$/ }).sort: *.basename;
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

Samaki -- Stitch together snippets of code and data

=head1 SYNOPSIS

=begin code

Usage:
  samaki [<wkdir>] -- Browse pages
  samaki [--wkdir[=Any]] new -- Open a new page for editing
  samaki edit <target> -- Edit a page with the given name
  samaki <file> -- Edit a file
  samaki reset-conf -- Reset the configuration to the default
  samaki conf -- Edit the configuration file

=end code

=head1 DESCRIPTION

Samaki is a system for writing queries and snippets of programs in multiple
languages in one file.  It's a bit like Jupyter notebooks (or R 
or Observable notebooks), but with multiple types of cells in one notebook.  It
has a plugin architecture for defining the types of cells, and for describing
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

2. run `samaki planets'

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

refers to the contents of the above cell.

The API is still evolving, but at a minimum, it has the name of an output file;
plugins are responsible for writing to the output file.

=head1 CONFIGURATION

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

=head1 USAGE

For help, type `samaki -h`.

Have fun!

=head1 TODO

A lot, especially more documentation.

Contributions are welcome!

=head1 AUTHOR

Brian Duggan (bduggan at matatu.org)

=end pod

