[![Actions Status](https://github.com/bduggan/raku-samaki/actions/workflows/linux.yml/badge.svg)](https://github.com/bduggan/raku-samaki/actions/workflows/linux.yml)
[![Actions Status](https://github.com/bduggan/raku-samaki/actions/workflows/macos.yml/badge.svg)](https://github.com/bduggan/raku-samaki/actions/workflows/macos.yml)

NAME
====

Samaki -- Stich Associated Modes of Accessing and Keeping Information

SYNOPSIS
========

    Usage:
      sam            -- start the default UI, and browser the current directory
      sam <name>     -- start with the named samaki page or directory
      sam import <file> [--format=jupyter] -- import from another format to samaki
      sam export <name> [--format=html] -- export a samaki file to HTML (or other formats)
      sam conf       -- edit the configuration file ~/.samaki.conf
      sam reset-conf -- reset the configuration file to the default

    Type `sam -h` for the full list of options.

DESCRIPTION
===========

Samaki is a file format and tool for using multiple programming languages in a single file.

It's a bit like Jupyter notebooks (or R or Observable notebooks), but with multiple types of cells in one notebook and all the cells belong to a simple text file. It has a plugin architecture for defining the types of cells, and for describing the types of output. Outputs from cells are serialized, often as CSV files. Cells can reference each others' content or output.

Some use cases for samaki include

* querying data from multiple sources

* trying out different programming languages

* reining in LLMs

Here's an example:

    -- duck
    select 'hello' as world;

    -- duck
    select 'earth' as planet;

    -- llm
    Which planet from the sun is 〈 cells(1).rows[0]<planet> 〉?

To use this:

1. save it as a file, e.g. "planets.samaki"

2. run `sam planets'

3. press 'm' to toggle between raw mode and rendered mode

4. highlight the second cell and press enter to run the query

5. press r to refresh the page, also press m to change the mode, and notice that it has changed to

    "Which planet from the sun is earth?"

6. highlight the third cell and press enter to run the LLM query

For more examples, check out the [eg/](https://github.com/bduggan/raku-samaki/tree/main/eg) directory.

<img width="1143" height="1022" alt="Image" src="https://github.com/user-attachments/assets/8f03279a-c99a-4c46-b8f5-e2f198ed083c" />

<img width="1139" height="1020" alt="Image" src="https://github.com/user-attachments/assets/6581f5a9-0ec3-470c-a7f0-763488605d9a" />

FORMAT
======

A samaki page (or notebook) consists of two things

1. a text file, ending in .samaki

2. a directory containing data files.

The directory name will be the same as the basename of the file, and it will be created if it doesn't exist. e.g.

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

1. New cells are indicated with a line starting with two dashes and a space ("-- ") folowed by the type of the cell. (Other similar unicode dashes like "─" can also be used)

2. The type of the cell should be a single word with alphanumeric characters.

3. An optional colon and name can give a name to the cell.

4. After the dashes, optional configuration options can be set as `name : value` pairs with a leading pipe symbol (`|`)

Another example: a cell named "the_answer" that runs a query and uses a duckdb file named life.duckdb

    -- duck : the_answer
    | file: life.duckdb

    select 42 as life_the_universe_and_everything

Running the cell above creates `the_answer.csv` in the data directory. Note that if the extension is omitted, it is assumed to be `.csv`. `the_answer.csv` could also have been written.

Cells may reference other cells by using angle brackets, as shown above:

    〈 cells(0).content 〉

alternatively, an ASCII equivalent `<<<` can be used:

    <<< cells(0).content >>>

Cells can be referenced by name or by number, e.g.

    〈 cells('the_answer').content 〉

refers to the contents of the above cell. Also `c` and `cell` are synonyms for `cells`, and the default Stringification will call `.content.trim`. e.g. this will also work:

    〈 c('the_answer') 〉

Calling `res` will return a `Duckie::Result` object. Calling `col` uses `res` and `column-data` to return a list of values from a named column.

The API is still evolving, but at a minimum, it has the name of an output file; plugins are responsible for writing to the output file.

CONFIGURATION
=============

The configuration file for samaki is a raku file located at `~/.config/samaki/samaki-conf.raku`. Environment variables `$SAMAKI_HOME` and `$SAMAKI_CONFIG` can be used to override the directory and file name respectively. Also `$XDG_CONFIG_HOME` is used if set.

Samaki is configured with a set of regular expressions which are used to determine how to handle each cell. The "type" of the cell above is matched against the regexes, and whichever one matches first will be used to parse the input and generate output.

Samaki comes with a default configuration file and some default plugins. The default configuration looks something like this (see [here](https://github.com/bduggan/raku-samaki/tree/main/resources/) for the actual contents) :

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

RELOADING
=========

Starting sam with "--watch" will autoreload the page when the file is changed.

INIT BLOCKS
===========

A special type of cell that has no type can be used to run Raku code when the page loads, like this:

    --
    my $p = 'mars';

    -- duck
    select * from planets where name = '〈 $p 〉';

The two dashes without a type indicate that this code should immediately be evalutead. There can be many of these blocks anywhere in the page.

PLUGINS
=======

Plugin classes should do the `Samaki::Plugin` role, and at a minimum should implement the `execute` method and have `name` and `description` attributes. The usual `RAKULIB` directories are searched for plugins, so adding local plugins is a matter of adding a new calss and placing it into this search path.

When interacting with external programs, there are three (and probably more) distinct ways to do this. There is some redundancy in the plugins because we offer more than one way to interact with external programs. The three ways that are currently abstracted across plugins are are

- using a native driver. For instance, `Duckie` offers bindings to the C API for duckdb.

- by spawning an external process and using stdin/stdout/stderr to communicate. For instance, `duck` does this -- it runs the `duckdb` command, sends data on stdin and captures stdout/stderr. This is abstracted in `Samaki::Plugin::Process`.

- by interacting with a command line REPL provided by another program and setting up a Pseudo-TTY to show what would go to the screen. `Samaki::Plugin::Repl` does this, and `Samaki::Plugin::Repl::Python` is an example.

Of these methods, there are a few functional differences.

1. persistence: currently only the last one offers persistence -- i.e. definitions between cells will persist within the REPL process. e.g. if one cell has `x=12` and another has `print(x)` then the second will print 12 if it is run after the first. The other plugins are executed once and are stateless.

2. output shown vs output saved: for native drivers the output that is shown on the screen is precisely what is stored. The second one stores output in a file, but does not necessarily display it all. This can be useful running programs that create large datasets. There may be some inconsistency depending on the plugin, so consult the individual plugin's implementation to see what it does.

In addition to classes defined in code, class definitions may be placed directly into the configuration file.

For instance, this snippet below is sufficient to implement a plugin called `python` for executing python code, saving the result to a file for that cell:

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

INCLUDED PLUGINS
================

The following plugins are included with samaki:

<table class="pod-table">
<thead><tr>
<th>Plugin</th> <th>Type</th> <th>Description</th>
</tr></thead>
<tbody>
<tr> <td>Bash</td> <td>Process</td> <td>Execute contents as a bash program</td> </tr> <tr> <td>Code</td> <td></td> <td>Evaluate raku code in the current process</td> </tr> <tr> <td>Duck</td> <td>Process</td> <td>Run SQL queries via duckdb executable</td> </tr> <tr> <td>Duckie</td> <td>inline</td> <td>Run SQL queries via L&lt;Duckie&gt; inline driver</td> </tr> <tr> <td>File</td> <td></td> <td>Display file metadata and info</td> </tr> <tr> <td>HTML</td> <td></td> <td>Generate HTML from contents</td> </tr> <tr> <td>LLM</td> <td>inline</td> <td>Send contents to LLM via L&lt;LLM::DWIM&gt;</td> </tr> <tr> <td>Markdown</td> <td>inline</td> <td>Generate HTML from markdown via L&lt;Markdown::Grammar&gt;</td> </tr> <tr> <td>Postgres</td> <td>Process</td> <td>Execute SQL via psql process</td> </tr> <tr> <td>Raku</td> <td>Process</td> <td>Run raku in a separate process</td> </tr> <tr> <td>Repl::Raku</td> <td>Repl</td> <td>Interactive raku REPL (persistent session)</td> </tr> <tr> <td>Repl::Python</td> <td>Repl</td> <td>Interactive python REPL (persistent session)</td> </tr> <tr> <td>Repl::R</td> <td>Repl</td> <td>Interactive R REPL (persistent session)</td> </tr> <tr> <td>Text</td> <td></td> <td>Write contents to a text file</td> </tr>
</tbody>
</table>

Plugin documentation:

* [Bash](docs/lib/Samaki/Plugin/Bash.md)

PLUGIN OPTIONS
==============

When choosing a plugin, options may be given which are specific to the plugin, like

    -- llm
    | model: claude

But there are some options that apply to all plugins. They are

* ext -- choose an extension for the filename.

    | ext: csv

Equivalent to name.csv

* out -- suppress output

    | out: none

PLUGOUTS
========

Output files are also matched against a sequence of regexes, and these can be used for visualizing or showing output.

These should also implement `execute` which has this signature:

    method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) { ... }

Plugouts are intended to either visualize or export data. The plugout for viewing an HTML file is basically:

    method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
      shell <<open $path>>;
    }

INCLUDED PLUGOUTS
=================

The following plugouts are included with samaki:

<table class="pod-table">
<thead><tr>
<th>Plugout</th> <th>Description</th>
</tr></thead>
<tbody>
<tr> <td>DataTable</td> <td>Display CSV in browser with sorting/pagination/search</td> </tr> <tr> <td>Duckview</td> <td>Show CSV summary in bottom pane (via duckdb)</td> </tr> <tr> <td>Geojson</td> <td>Display GeoJSON on map in browser (via leaflet)</td> </tr> <tr> <td>HTML</td> <td>Open HTML content in browser</td> </tr> <tr> <td>JSON</td> <td>Display prettified JSON in bottom pane</td> </tr> <tr> <td>Plain</td> <td>Display plain text in browser</td> </tr> <tr> <td>Raw</td> <td>Open file with system default application</td> </tr> <tr> <td>TJLess</td> <td>View JSON in new tmux window (requires jless)</td> </tr>
</tbody>
</table>

IMPORTS/EXPORTS
===============

An entire samaki page can be exported as HTML or imported from Jupyter. This is still evolving. For now, for instance:

    sam export eg/planets

will generate a nice HTML page based on the samaki input. It will embed output files into the HTML.

USAGE
=====

Usage is described at the top. For help, type `sam -h`.

Have fun!

BUGS
====

The backronym is a bit forced. Here's another one: Simple Arrangements of Modules with Any Kind of Items

TODO
====

A lot, especially more documentation.

Contributions are welcome!

AUTHOR
======

Brian Duggan (bduggan at matatu.org)

