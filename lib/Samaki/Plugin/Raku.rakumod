use Samaki::Plugin::Process;
use Log::Async;
use Duckie;

unit class Samaki::Plugin::Raku does Samaki::Plugin::Process[
  name => 'raku',
  cmd => 'raku' ];

has $.description = 'Run Raku in another process';

method stream-output { True };

=begin pod

=head1 NAME

Samaki::Plugin::Raku -- Execute Raku code in a separate process

=head1 DESCRIPTION

Execute Raku code in a separate process. Unlike the Code plugin which runs in the same process and shares state, this creates a new Raku process for each cell. This is a process-based plugin (uses L<Samaki::Plugin::Process>).

=head1 OPTIONS

No specific options.

=head1 EXAMPLE

    -- raku
    say "Hello from a separate process!";
    say π;

Output:

    Hello from a separate process!
    3.141592653589793

=end pod
