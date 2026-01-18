use Samaki::Plugout;
use Log::Async;

unit class Samaki::Plugout::Duckview does Samaki::Plugout;

has $.name = "duckview";
has $.description = "Use duckdb to summarize a csv file";

method execute(IO::Path :$path!) {
  state $width = qx[tput cols].trim.Int - 1;
  my $proc = Proc::Async.new('duckdb', '-c', ".maxwidth $width", '-c', "SELECT * FROM read_csv_auto('$path');", :out, :err);
  try {
    react {
      whenever $proc.stdout.lines {
        self.pane.put: $_;
      }
      whenever $proc.stderr.lines {
        self.pane.put: $_;
      }
      whenever $proc.start {
        self.pane.put: "Process terminated with signal $_" if .signal;
        self.pane.put: "Process exited with code $_" if .exitcode;
        self.pane.put: "-- done --";
        done
      }
    }
    CATCH {
      default {
        self.pane.put: "Error executing duckview plugout: $_";
        error "Error executing duckview plugout: $_";
      }
    }
  }
}

=begin pod

=head1 NAME

Samaki::Plugout::Duckview -- Display CSV data in the terminal using DuckDB

=head1 DESCRIPTION

Display CSV output in the terminal pane using the DuckDB CLI.

=end pod

