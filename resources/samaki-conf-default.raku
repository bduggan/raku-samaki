use Samaki::Plugin::Process;

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
    / raku /   => 'Samaki::Plugin::Raku',
    / code /   => 'Samaki::Plugin::Code',
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
    / html /   => 'Samaki::Plugout::HTML',
    / txt  /   => 'Samaki::Plugout::Plain',
    / geojson / => 'Samaki::Plugout::Geojson',
    / json /    => 'Samaki::Plugout::JSON',
    / .*   /   => 'Samaki::Plugout::Raw',
  ]
;

