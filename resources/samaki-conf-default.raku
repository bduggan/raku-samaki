use Samaki::Plugin::Process;

%*samaki-conf =
  plugins => [
    / duck /   => 'Samaki::Plugin::Duck',
    / llm  /   => 'Samaki::Plugin::LLM',
    / text /   => 'Samaki::Plugin::Text',
    / bash /   => 'Samaki::Plugin::Bash',
    / html /   => 'Samaki::Plugin::HTML',
    / raku /   => 'Samaki::Plugin::Raku',
    / python / => class SamakiPython does Samaki::Plugin::Process[
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
    / .*   /   => 'Samaki::Plugout::Raw',
  ]
;

