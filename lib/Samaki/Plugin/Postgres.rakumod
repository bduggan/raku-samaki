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

method execute(Samaki::Cell :$cell, Samaki::Page :$page, Str :$mode, IO::Handle :$out, :$pane, Str :$action) {
  my $db = $cell.get-conf('db');
  info "Executing psql cell";
  self.info: "db is { $db.IO.resolve }" if $db;
  my $timeout = $cell.get-conf('timeout') // $cell.timeout;
  my $cwd = $cell.data-dir;
  self.info: "Running in $cwd/";
  my $proc = $db ?? Proc::Async.new: <<$!executable -d $db --csv>>, :out, :err, :w
                 !!  Proc::Async.new: <<$!executable --csv>>, :out, :err, :w;
  my $input = $cell.get-content(:$mode, :$page);
  info "Sending input to process:\n" ~ $input;
  $!errors = Nil;
  $!output = Nil;

  try react {
      whenever $proc.ready { self.do-ready($_, $proc,$timeout); }
      whenever $proc.stderr.lines { self.warn: "$_"; }

      whenever $proc.stdout.lines {
        $out.put: $_;
        sleep 0.01; # let the UI breathe
      }
      whenever $proc.start(:$cwd) {
        self.do-done($_);
        done
      }
      whenever $proc.print($input) {
        $proc.close-stdin;
      }
      whenever Supply.interval(1) {
        self.info("elapsed time: $_ seconds") if $_ > 3 && $_ %% 5;
      }
      whenever Promise.in($timeout) {
        $.output-stream.send: "Timeout. Asking the process to stop";
        $proc.kill;
        whenever Promise.in(2) {
          $.output-stream.send: "timeout again, now forcing the process to stop";
          $proc.kill: SIGKILL
        }
      }
   }
   self.error("Execution failed: $_") with $!;
   $out.close;
   with $cell.output-file.IO {
     unless .e && (.s > 0) {
       $!errors = "No output generated";
       return;
     }
   }
   $!output = self.output-duckie($cell.output-file);
}
