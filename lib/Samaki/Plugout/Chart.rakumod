use Samaki::Plugout;
use Samaki::Utils;
use Duck::CSV;

unit class Samaki::Plugout::Chart does Samaki::Plugout;

has $.name = 'chart';
has $.description = 'Display data as a bar chart using Chart.js';
has $.clear-before = False;

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
    my @rows = read-csv("$path");
    return unless @rows;

    my @columns = @rows[0].keys.sort;

    # Intelligently detect label and value columns
    my ($label-col, $value-col) = self!detect-columns(@columns, @rows);

    # Extract data for the chart
    my @labels = @rows.map: { $_{ $label-col } // '' };
    my @values = @rows.map: { ($_{ $value-col } // 0).Numeric };

    my $html-file = $data-dir.child("{$name}-chart.html");

    my $title = html-escape($data-dir.basename ~ " : " ~ $name);
    my $labels-json = to-json(@labels);
    my $values-json = to-json(@values);
    my $chart-label = html-escape($value-col);

    my $html = Q:s:to/HTML/;
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>$title </title>
        <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.js"></script>
        <style>
            body {
                font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                margin: 0;
                padding: 20px;
                background-color: #f8f9fa;
                color: #2c3e50;
            }
            .container {
                max-width: 1400px;
                margin: 0 auto;
                padding: 20px;
                background: white;
                border-radius: 4px;
                box-shadow: 0 1px 2px rgba(0,0,0,0.05);
            }
            h2 {
                margin: 0 0 20px 0;
                color: #2c3e50;
                font-size: 18px;
                font-weight: 500;
            }
            .chart-container {
                position: relative;
                height: 70vh;
                width: 100%;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h2>$title </h2>
            <div class="chart-container">
                <canvas id="myChart"></canvas>
            </div>
        </div>
        <script>
            const ctx = document.getElementById('myChart');

            new Chart(ctx, {
                type: 'bar',
                data: {
                    labels: $labels-json,
                    datasets: [{
                        label: '$chart-label',
                        data: $values-json,
                        backgroundColor: 'rgba(54, 162, 235, 0.7)',
                        borderColor: 'rgba(54, 162, 235, 1)',
                        borderWidth: 1
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        y: {
                            beginAtZero: true,
                            ticks: {
                                font: {
                                    family: 'ui-monospace, monospace',
                                    size: 11
                                }
                            }
                        },
                        x: {
                            ticks: {
                                font: {
                                    family: 'ui-monospace, monospace',
                                    size: 11
                                },
                                maxRotation: 45,
                                minRotation: 45
                            }
                        }
                    },
                    plugins: {
                        legend: {
                            display: true,
                            labels: {
                                font: {
                                    family: 'ui-monospace, monospace',
                                    size: 12
                                }
                            }
                        }
                    }
                }
            });
        </script>
    </body>
    </html>
    HTML

    spurt $html-file, $html;
    shell-open $html-file;
}

method !detect-columns(@columns, @rows) {
    # Strategy: Find the best label column and the best value column
    # Label column: likely to be named 'name', 'label', 'tag', 'category', or is non-numeric
    # Value column: likely to be named 'count', 'value', 'amount', 'total', or is numeric

    my $label-col;
    my $value-col;

    # Look for common label column names
    my @label-patterns = <name label tag category type key id>;
    for @label-patterns -> $pattern {
        my @matches = @columns.grep: *.lc.contains($pattern);
        if @matches {
            $label-col = @matches[0];
            last;
        }
    }

    # Look for common value column names
    my @value-patterns = <count value amount total sum number quantity>;
    for @value-patterns -> $pattern {
        my @matches = @columns.grep: *.lc.contains($pattern);
        if @matches {
            $value-col = @matches[0];
            last;
        }
    }

    # Fallback: if we didn't find columns by name, detect by content
    unless $label-col && $value-col {
        for @columns -> $col {
            # Sample the first few non-empty rows to check if column is numeric
            my @sample = @rows[^min(10, @rows.elems)].map({ $_{ $col } }).grep: *.defined;
            next unless @sample;

            my $numeric-count = @sample.grep(*.Numeric).elems;
            my $is-numeric = $numeric-count > @sample.elems * 0.8;  # 80% threshold

            if $is-numeric && !$value-col {
                $value-col = $col;
            } elsif !$is-numeric && !$label-col {
                $label-col = $col;
            }
        }
    }

    # Final fallback: use first two columns
    $label-col //= @columns[0];
    $value-col //= @columns[1] // @columns[0];

    return ($label-col, $value-col);
}

sub to-json(@data) {
    # Simple JSON array serialization
    my $items = @data.map({
        my $escaped = $_.Str.subst('"', '\\"', :g).subst("\n", '\\n', :g);
        qq["$escaped"]
    }).join(', ');
    return "[$items]";
}
