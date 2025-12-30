use Samaki::Plugin::Process;
use Samaki::Plugin::Repl;

%*samaki-conf =
  plugins => [
    /^ duckie $/      => 'Samaki::Plugin::Duckie',
    /^ duck $/        => 'Samaki::Plugin::Duck',
    / llm  /          => 'Samaki::Plugin::LLM',
    / text /          => 'Samaki::Plugin::Text',
    / bash /          => 'Samaki::Plugin::Bash',
    / html /          => 'Samaki::Plugin::HTML',
    / file /          => 'Samaki::Plugin::File',
    / markdown /      => 'Samaki::Plugin::Markdown',

    / 'repl-raku' /   => 'Samaki::Plugin::Repl::Raku',
    / raku /          => 'Samaki::Plugin::Raku',

    / code /          => 'Samaki::Plugin::Code',
    / 'repl-python' / => 'Samaki::Plugin::Repl::Python',
    / 'repl-R' /      => 'Samaki::Plugin::Repl::R',

    / 'repl-duck' /  => Samaki::Plugin::Repl[ :cmd<duckdb> ],

    / python /       => class SamakiPython does Samaki::Plugin::Process[
                       name => 'python',
                       cmd => 'python3' ] {
                         has %.add-env = PYTHONUNBUFFERED => '1';
                       }
  ],
  plugouts => [
    / csv  /   => 'Samaki::Plugout::Duckview',
    / csv  /   => 'Samaki::Plugout::DataTable',
    / html /   => 'Samaki::Plugout::HTML',
    / txt  /   => 'Samaki::Plugout::Plain',
    / geojson / => 'Samaki::Plugout::Geojson',
    / json /    => 'Samaki::Plugout::JSON',
    / .*   /    => 'Samaki::Plugout::Raw',
  ]
;

