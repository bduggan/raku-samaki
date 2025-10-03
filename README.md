[![Actions Status](https://github.com/bduggan/raku-samaki/actions/workflows/linux.yml/badge.svg)](https://github.com/bduggan/raku-samaki/actions/workflows/linux.yml)
[![Actions Status](https://github.com/bduggan/raku-samaki/actions/workflows/macos.yml/badge.svg)](https://github.com/bduggan/raku-samaki/actions/workflows/macos.yml)

NAME
====

Samaki -- Stitch together snippets of code and data

SYNOPSIS
========

    Usage:
      samaki [<wkdir>] -- Browse pages
      samaki [--wkdir[=Any]] new -- Open a new page for editing
      samaki edit <target> -- Edit a page with the given name
      samaki <file> -- Edit a file
      samaki reset-conf -- Reset the configuration to the default
      samaki conf -- Edit the configuration file

DESCRIPTION
===========

Samaki is a system for writing queries and snippets of programs in multiple languages in one file. It's a bit like Jupyter notebooks (or R or Observable notebooks), but with multiple types of cells in one notebook. It has a plugin architecture for defining the types of cells, and for describing the types of output. Outputs from cells are serialized, often as CSV files. Cells can reference each others' content or output.

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

2. run `samaki planets'

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

    -- <cell type> [ : name ]?
    | conf-key 1 : conf-value 1
    | conf-key 2 : conf-value 2
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

Cells may reference other cells by using angle brackets, as shown above:

    〈 cells(0).content 〉

alternatively, an ASCII equivalent `<<<` can be used:

    <<< cells(0).content >>>

Cells can be referenced by name or by number, e.g.

    〈 cells('the_answer').content 〉

refers to the contents of the above cell.

The API is still evolving, but at a minimum, it has the name of an output file; plugins are responsible for writing to the output file.

CONFIGURATION
=============

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

PLUGINS
=======

Plugin classes should do the `Samaki::Plugin` role, and at a minimum should implement the `execute` method and have `name` and `description` attributes. The usual `RAKULIB` directories are searched for plugins, so adding local plugins is a matter of adding a new calss and placing it into this search path.

In addition to the strings above, a class definition may be placed directly into the configuration file, and this definition can reference other plugins.

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

Alternatively, the `Process` plugin provides a convenient way to run external processes, and stream the results, so this will also work, and instead of temp files, it will send code to stdin for python and put unbuffered output from stdout into the bottom pane:

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

PLUGOUTS
========

Output files are also matched against a sequence of regexes, and these can be used for visualizing or showing output.

These should also implement `execute` which has this signature:

    method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) { ... }

Plugouts are intended to either visualize or export data. The plugout for viewing an HTML file is basically:

    method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
      shell <<open $path>>;
    }

USAGE
=====

For help, type `samaki -h`.

Have fun!

TODO
====

A lot, especially more documentation.

Contributions are welcome!

AUTHOR
======

Brian Duggan (bduggan at matatu.org)

