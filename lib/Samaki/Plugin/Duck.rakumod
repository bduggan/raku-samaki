use Samaki::Plugin::Process;
use Log::Async;
use Samaki::Conf;
use Terminal::ANSI::OO 't';
use Duckie;

unit class Samaki::Plugin::Duck does Samaki::Plugin::Process;

has $.name = 'duckdb';
has $.description = 'Execute SQL queries using the duckdb cli';
has $.executable = 'duckdb';
has $.version-info;
has $.output-ext = 'csv';

method setup(Samaki::Conf :$conf) {
  info "Setting up duck plugin";
  $!version-info = qqx[$!executable --version 2>/dev/null].trim;
  die "could not find $!executable in path" unless $!version-info;
  info "version $!version-info";
}

method use-stdin { True }

method stream-stdout-to-pane { False }

method build-command(Samaki::Cell :$cell) {
  my $db = $cell.get-conf('db');
  info "Executing duck cell";
  self.info: "Executing duckdb with db {$db // '<memory>'}";
  self.info: "db is { $db.IO.resolve }" if $db;
  my $cwd = $cell.data-dir;
  self.info: "Running in $cwd/";

  return $db ?? ($!executable, $db, '--batch', '--csv')
             !! ($!executable, '--batch', '--csv');
}

=begin pod

=head1 NAME

Samaki::Plugin::Duck -- Execute SQL queries using the duckdb CLI

=head1 DESCRIPTION

Execute SQL queries by spawning the C<duckdb> command-line executable as a separate process. Input is piped to stdin and output is captured from stdout. This is a process-based plugin (uses L<Samaki::Plugin::Process>).

For an inline driver alternative, see L<Samaki::Plugin::Duckie>.

=head1 OPTIONS

* `db` -- path to a duckdb database file. If not specified, an in-memory database is used.
* `timeout` -- maximum time in seconds to wait for query execution (default: 300)

=head1 EXAMPLE

    -- duck
    select 'hello' as greeting, 'world' as noun;

Output (CSV):

    greeting,noun
    hello,world

Example with a database file:

    -- duck
    | db: mydata.duckdb
    select * from users limit 5;

=end pod
