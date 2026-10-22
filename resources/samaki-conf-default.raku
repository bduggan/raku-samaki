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
    # / llm  /   => 'Samaki::Plugin::LLM', # install LLM::DWIM to use this
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
    # CSVGeo's tile menu defaults to the OpenFreeMap styles (positron,
    # bright, liberty, dark, fiord).  Add others via
    #   / csv / => Samaki::Plugout::CSVGeo.new(
    #     tile-providers => %( positron => %( ... ),
    #       light => %( label => 'Light (CARTO Positron)',
    #         url => 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
    #         attribution => '© OpenStreetMap contributors © CARTO', max-zoom => 19 ),
    #       'mapbox-streets' => %(
    #         url => 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}{r}',
    #         token => %*ENV<MAPBOX_TOKEN>, token-url-param => 'access_token',
    #         token-required => True, tile-size => 512, zoom-offset => -1 ) ) )
    # See "CONFIGURING TILE PROVIDERS" in the CSVGeo docs.
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

