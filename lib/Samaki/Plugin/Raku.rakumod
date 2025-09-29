use Samaki::Plugin::Process;
use Log::Async;
use Duckie;

unit class Samaki::Plugin::Raku does Samaki::Plugin::Process[
  name => 'raku',
  cmd => 'raku' ];

has $.description = 'Run Raku in another process';

method stream-output { True };

