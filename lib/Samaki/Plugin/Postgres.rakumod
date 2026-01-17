use Samaki::Plugin::Process;
use Log::Async;
use Samaki::Conf;
use Terminal::ANSI::OO 't';

unit class Samaki::Plugin::Postgres does Samaki::Plugin::Process;

has $.name = 'postgres';
has $.description = 'Execute SQL queries using the postgres psql cli';
has $.executable = 'psql';
has $.version-info;
has $.output-ext = 'csv';

method setup(Samaki::Conf :$conf) {
  info "Setting up postgres plugin";
  $!version-info = qqx[$!executable --version 2>/dev/null].trim;
  die "could not find $!executable in path" unless $!version-info;
  info "version $!version-info";
}

method use-stdin { True }

method stream-stdout-to-pane { False }

method build-command(Samaki::Cell :$cell) {
  my $db = $cell.get-conf('db');
  info "Executing psql cell";
  self.info: "db is { $db.IO.resolve }" if $db;

  return $db ?? ($!executable, '-d', $db, '--csv')
             !! ($!executable, '--csv');
}

=begin pod

=head1 NAME

Samaki::Plugin::Postgres -- Execute SQL queries using PostgreSQL

=head1 DESCRIPTION

Execute SQL queries by spawning the C<psql> command-line executable as a separate process. Input is piped to stdin and output is captured from stdout as CSV. This is a process-based plugin (uses L<Samaki::Plugin::Process>).

=head1 OPTIONS

* `db` -- database name or connection string. If not specified, uses the default PostgreSQL connection.
* `timeout` -- maximum time in seconds to wait for query execution (default: 300)

=head1 EXAMPLE

    -- postgres
    select 'hello' as greeting, 'world' as noun;

Output (CSV):

    greeting,noun
    hello,world

Example with database name:

    -- postgres
    | db: mydb
    select * from users limit 5;

=end pod
