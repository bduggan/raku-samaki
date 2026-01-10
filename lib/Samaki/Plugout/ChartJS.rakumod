use Samaki::Plugout;
use Samaki::Utils;
use Duck::CSV;

unit class Samaki::Plugout::ChartJS does Samaki::Plugout;

has $.name = 'chartjs';
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

    my $html-file = $data-dir.child("{$name}-chartjs.html");

    my $title = html-escape($data-dir.basename ~ " : " ~ $path.basename);
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
            .controls {
                margin-bottom: 15px;
                display: flex;
                gap: 8px;
            }
            .controls button {
                padding: 6px 12px;
                font-family: ui-monospace, monospace;
                font-size: 12px;
                background: #f1f5f9;
                border: 1px solid #e2e8f0;
                border-radius: 3px;
                cursor: pointer;
                color: #2c3e50;
            }
            .controls button:hover {
                background: #e2e8f0;
            }
            .controls button.active {
                background: #3b82f6;
                color: white;
                border-color: #3b82f6;
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
            <div class="controls">
                <button id="btn-vertical" class="active">Vertical Bar</button>
                <button id="btn-horizontal">Horizontal Bar</button>
                <button id="btn-pie">Pie Chart</button>
                <button id="btn-polar">Polar Area</button>
            </div>
            <div class="chart-container">
                <canvas id="myChart"></canvas>
            </div>
        </div>
        <script>
            const ctx = document.getElementById('myChart');
            let myChart;

            const chartData = {
                labels: $labels-json,
                datasets: [{
                    label: '$chart-label',
                    data: $values-json,
                    backgroundColor: 'rgba(54, 162, 235, 0.5)',
                    borderColor: 'rgba(54, 162, 235, 1)',
                    borderWidth: 1
                }]
            };

            function createChart(type, indexAxis = 'x') {
                if (myChart) {
                    myChart.destroy();
                }

                const isRadial = type === 'pie' || type === 'polarArea';

                // For pie and polar area charts, use multiple colors
                const data = JSON.parse(JSON.stringify(chartData)); // deep clone
                if (isRadial) {
                    const colors = [
                        'rgba(54, 162, 235, 0.5)', 'rgba(255, 99, 132, 0.5)',
                        'rgba(255, 206, 86, 0.5)', 'rgba(75, 192, 192, 0.5)',
                        'rgba(153, 102, 255, 0.5)', 'rgba(255, 159, 64, 0.5)',
                        'rgba(199, 199, 199, 0.5)', 'rgba(83, 102, 255, 0.5)',
                        'rgba(255, 99, 255, 0.5)', 'rgba(99, 255, 132, 0.5)'
                    ];
                    const colorArray = [];
                    for (let i = 0; i < data.labels.length; i++) {
                        colorArray.push(colors[i % colors.length]);
                    }
                    data.datasets[0].backgroundColor = colorArray;
                }

                myChart = new Chart(ctx, {
                    type: type,
                    data: data,
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        indexAxis: indexAxis,
                        scales: isRadial ? undefined : {
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
                                    maxRotation: indexAxis === 'x' ? 45 : 0,
                                    minRotation: indexAxis === 'x' ? 45 : 0
                                }
                            }
                        },
                        plugins: {
                            legend: {
                                display: true,
                                position: isRadial ? 'right' : 'top',
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
            }

            // Initialize with vertical bar chart
            createChart('bar', 'x');

            // Button event listeners
            document.getElementById('btn-vertical').addEventListener('click', function() {
                createChart('bar', 'x');
                setActiveButton(this);
            });

            document.getElementById('btn-horizontal').addEventListener('click', function() {
                createChart('bar', 'y');
                setActiveButton(this);
            });

            document.getElementById('btn-pie').addEventListener('click', function() {
                createChart('pie');
                setActiveButton(this);
            });

            document.getElementById('btn-polar').addEventListener('click', function() {
                createChart('polarArea');
                setActiveButton(this);
            });

            function setActiveButton(activeBtn) {
                document.querySelectorAll('.controls button').forEach(btn => {
                    btn.classList.remove('active');
                });
                activeBtn.classList.add('active');
            }
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
