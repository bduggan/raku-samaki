use JSON::Fast;

unit class Samaki::Importer::Jupyter;

method import-file(Str $nb-filename) {
    die "notebook should end in .ipynb" unless $nb-filename.ends-with('ipynb');

    my $in = from-json slurp $nb-filename;
    my @lines;
    for $in<cells><> {
      @lines.push: "-- " ~ (.<cell_type> // 'text');
      for .<source><> {
        @lines.push: .trim-trailing;
      }
    }

    my $samaki-name = $nb-filename.subst('.ipynb', '.samaki');
    @lines.join("\n") ==> spurt $samaki-name;

    return $samaki-name;
}
