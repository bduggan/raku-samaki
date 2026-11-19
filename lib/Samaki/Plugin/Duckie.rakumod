use Samaki::Plugin;
use Log::Async;
use Duckie;

unit class Samaki::Plugin::Duckie does Samaki::Plugin;

has $.name = 'duckie';
has $.description = 'Use in-line duckdb driver for queries';
has $.output-ext = 'csv';

has @.udfs;

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
 my $db = $cell.get-conf('db');
 self.info: "Executing duckie cell with db { $db // '<memory>' }";
 my $content = $cell.get-content(:$mode, :$page);

 # UDF callbacks run Raku code, which crashes MoarVM if duckdb calls them from
 # one of its worker threads.  So only queries that mention a UDF are limited to
 # one thread; everything else keeps duckdb's default.
 my $uses-udf = so @.udfs.first: -> $udf { my $n = $udf.name; $content ~~ / :i << $n >> / };
 self.info: "Query calls a UDF, limiting duckdb to 1 thread" if $uses-udf;
 my $duck = $db
   ?? Duckie.new(file => $db, single-threaded => $uses-udf)
   !! Duckie.new(single-threaded => $uses-udf);

 for @.udfs -> $udf {
   $duck.register-raku-sub($udf);
 }

 # explicit override; don't raise this for cells that call a UDF
 if $cell.get-conf('threads') -> $threads {
   unless $threads ~~ /^ \d+ $/ && $threads > 0 {
     $!errors = "threads must be a positive integer, got '$threads'";
     return;
   }
   self.info: "Setting threads to $threads";
   $duck.query("set threads=$threads");
 }

 $duck.query("install spatial");
 $duck.query("load spatial");
 $!res = $duck.query($content);
 unless $!res {
   $!errors = $!res.Str;
   return;
 }
 $!output = self.output-duckie($!res);
 self.write-duckie($!res, :$out);
 $!output;
}

=begin pod

=head1 NAME

Samaki::Plugin::Duckie -- Execute SQL queries using the Duckie inline driver

=head1 DESCRIPTION

Execute SQL queries using the inline L<Duckie> driver, which provides Raku bindings to the DuckDB C API. This runs in the same process as Samaki, making it faster than the process-based Duck plugin.

For a process-based alternative, see L<Samaki::Plugin::Duck>.

Duckie supports user defined functions in raku via the udf's attribute.  To use this, add
a derived class in your config file. For example, this adds `parse_poly` as a UDF that
converts a polyline string to GeoJSON:

    use Samaki::Plugin::Duckie;
    use Geo::Polyline;
    use JSON::Fast;

    ...
    / duckie / => class Samaki::Plugin::MyDuckie is Samaki::Plugin::Duckie {
                    has @.udfs = sub parse_poly (Str $poly --> Str ) {
                      to-json polyline-to-geojson( $poly, :unescape )<geometry>, :!pretty;
                    };
                  }
    ...

=head1 OPTIONS

* `db` -- path to a duckdb database file. If not specified, an in-memory database is used.
* `threads` -- number of threads DuckDB may use. By default DuckDB's own default is used, except that a query which mentions a UDF is limited to a single thread, because UDF callbacks must run on the thread that issued the query (otherwise MoarVM aborts the whole process). Set this to override that. Don't raise it for queries that call a UDF.

=head1 EXAMPLE

    -- duckie
    select 'hello' as greeting, 'world' as noun;

Output (CSV):

    greeting,noun
    hello,world

Example with a database file:

    -- duckie
    | db: mydata.duckdb
    select * from users limit 5;

=end pod
