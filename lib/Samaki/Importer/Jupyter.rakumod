use JSON::Fast;

unit class Samaki::Importer::Jupyter;

method import-file(Str $nb-filename) {
    die "notebook should end in .ipynb" unless $nb-filename.ends-with('ipynb');

    my $in = from-json slurp $nb-filename;
    my @out = $in<cells>.map: *<source>;
    my @lines;

    for @out {
        @lines.push: "-- repl";
        @lines.push: .join("\n");
        @lines.push: "\n";
    }

    my $samaki-name = $nb-filename.subst('.ipynb', '.samaki');
    @lines.join("\n") ==> spurt $samaki-name;

    return $samaki-name;
}
