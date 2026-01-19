use Samaki::Plugin::Process;

# For plugins, the first match determines the plugin
# that will handle a cell.
#
# For plugouts, all matches are shown when a file is selected.
#
%*samaki-conf =
  plugins => [
    / duckie / => 'Samaki::Plugin::Duckie',
    / duck /   => 'Samaki::Plugin::Duck',
    / llm  /   => 'Samaki::Plugin::LLM',
    / text /   => 'Samaki::Plugin::Text',
    / bash /   => 'Samaki::Plugin::Bash',
    / html /   => 'Samaki::Plugin::HTML',
    / file /   => 'Samaki::Plugin::File',
    / markdown / => 'Samaki::Plugin::Markdown',
    / 'raku-repl' / => 'Samaki::Plugin::Repl::Raku',
    / raku /   => 'Samaki::Plugin::Raku',
    / code /   => 'Samaki::Plugin::Code',
    / auto /   => 'Samaki::Plugin::Auto',
    / postgres / => 'Samaki::Plugin::Postgres',
    / 'R-repl' / => 'Samaki::Plugin::Repl::R',
    / 'python-repl' / => 'Samaki::Plugin::Repl::Python',
    / python / => class SamakiPython does Samaki::Plugin::Process[
                       name => 'python',
                       cmd => 'python3' ] {
                 has %.add-env = PYTHONUNBUFFERED => '1';
               }
  ],
  plugouts => [
    / csv  /   => 'Samaki::Plugout::Duckview',
    / csv  /   => 'Samaki::Plugout::DataTable',
    / csv  /   => 'Samaki::Plugout::ChartJS',
    / csv  /   => 'Samaki::Plugout::D3',
    / csv  /   => 'Samaki::Plugout::CSVGeo',
    / csv /    => 'Samaki::Plugout::DeckGLBin',
    / html /   => 'Samaki::Plugout::HTML',
    / txt  /   => 'Samaki::Plugout::Plain',
    / geojson / => 'Samaki::Plugout::Geojson',
    / json /    => 'Samaki::Plugout::JSON',
    / json /    => 'Samaki::Plugout::TJLess',
    / .*   /   => 'Samaki::Plugout::Raw',
  ]
;

