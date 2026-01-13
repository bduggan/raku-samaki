use Samaki::Plugout;
use Samaki::Utils;
use Duck::CSV;
use Log::Async;

unit class Samaki::Plugout::ChartJS does Samaki::Plugout;

has $.name = 'chartjs';
has $.description = 'Display data as a bar chart using Chart.js';
has $.clear-before = False;

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
    my @rows = read-csv("$path");
    return unless @rows;

    my @columns = @rows[0].keys.sort;

    # Intelligently detect label and value columns
    my %result = self!detect-columns(@columns, @rows);
    my $label-col = %result<label>;
    my $value-col = %result<value>;
    my @numeric-cols = @(%result<numeric>);

    my $html-file = $data-dir.child("{$name}-chartjs.html");

    my $title = html-escape($data-dir.basename ~ " : " ~ $path.basename);

    # Prepare all data as JSON for JavaScript
    my $all-data-json = self!prepare-data-json(@rows, @columns);
    my $columns-json = to-json(@columns);
    my $numeric-columns-json = to-json(@numeric-cols);
    my $default-label = html-escape($label-col);
    my $default-value = html-escape($value-col);

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
                flex-wrap: wrap;
                align-items: center;
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
            .column-selector {
                display: flex;
                align-items: center;
                gap: 4px;
                font-size: 12px;
            }
            .column-selector label {
                color: #64748b;
                font-weight: 500;
            }
            .column-selector select {
                padding: 6px 8px;
                font-family: ui-monospace, monospace;
                font-size: 12px;
                background: white;
                border: 1px solid #e2e8f0;
                border-radius: 3px;
                color: #2c3e50;
                cursor: pointer;
            }
            .column-selector select:hover {
                border-color: #cbd5e1;
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
                <div class="column-selector">
                    <label>Label:</label>
                    <select id="label-column"></select>
                </div>
                <div class="column-selector">
                    <label>Value:</label>
                    <select id="value-column"></select>
                </div>
            </div>
            <div class="chart-container">
                <canvas id="myChart"></canvas>
            </div>
        </div>
        <script>
            const ctx = document.getElementById('myChart');
            let myChart;
            let currentChartType = 'bar';
            let currentIndexAxis = 'x';

            // All data from CSV
            const allData = $all-data-json;
            const columns = $columns-json;
            const numericColumns = $numeric-columns-json;

            // Populate column selectors
            const labelSelect = document.getElementById('label-column');
            const valueSelect = document.getElementById('value-column');

            // Label dropdown gets all columns
            columns.forEach(col => {
                const option1 = document.createElement('option');
                option1.value = col;
                option1.textContent = col;
                labelSelect.appendChild(option1);
            });

            // Value dropdown gets only numeric columns
            numericColumns.forEach(col => {
                const option2 = document.createElement('option');
                option2.value = col;
                option2.textContent = col;
                valueSelect.appendChild(option2);
            });

            // Set default selections
            labelSelect.value = '$default-label';
            valueSelect.value = '$default-value';

            console.log('=== ChartJS Debug ===');
            console.log('All Data:', allData);
            console.log('All Columns:', columns);
            console.log('Numeric Columns:', numericColumns);
            console.log('Default Label:', '$default-label');
            console.log('Default Value:', '$default-value');

            function getChartData() {
                const labelCol = labelSelect.value;
                const valueCol = valueSelect.value;

                console.log('Getting chart data for label="' + labelCol + '" value="' + valueCol + '"');

                const labels = allData.map(row => row[labelCol] || '');
                const values = allData.map(row => {
                    const val = row[valueCol] || '0';
                    // Try to parse as number, prefer integer if no decimal
                    let numVal = Number(val);
                    if (isNaN(numVal)) {
                        numVal = 0;
                    } else if (Number.isInteger(numVal)) {
                        numVal = parseInt(val, 10);
                    }
                    console.log('  Row value: "' + val + '" -> parsed: ' + numVal + ' (type: ' + typeof numVal + ')');
                    return numVal;
                });

                console.log('Labels:', labels);
                console.log('Values:', values);

                return {
                    labels: labels,
                    datasets: [{
                        label: valueCol,
                        data: values,
                        backgroundColor: 'rgba(54, 162, 235, 0.5)',
                        borderColor: 'rgba(54, 162, 235, 1)',
                        borderWidth: 1
                    }]
                };
            }

            function createChart(type, indexAxis = 'x') {
                if (myChart) {
                    myChart.destroy();
                }

                currentChartType = type;
                currentIndexAxis = indexAxis;

                const isRadial = type === 'pie' || type === 'polarArea';

                // Get fresh data based on selected columns
                const data = getChartData();

                // For pie and polar area charts, use multiple colors
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
                                    },
                                    precision: 0,
                                    callback: function(value) {
                                        if (Number.isInteger(value)) {
                                            return value;
                                        }
                                        return value.toFixed(2);
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

            // Column selector event listeners
            labelSelect.addEventListener('change', function() {
                createChart(currentChartType, currentIndexAxis);
            });

            valueSelect.addEventListener('change', function() {
                createChart(currentChartType, currentIndexAxis);
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
    # Strategy: Score columns based on cardinality and data type characteristics
    # Label column: prefer low cardinality non-numeric columns
    # Value column: MUST be numeric, prefer integers, avoid floats and ID-like columns
    # Only column name pattern used: avoid columns ending in _id

    my %col-info;

    for @columns -> $col {
        my @values = @rows.map({ $_{ $col } }).grep: *.defined;
        next unless @values;

        my $cardinality = @values.unique.elems;
        my $total = @values.elems;

        # Analyze column name patterns - only check for _id suffix
        my $col-lc = $col.lc;
        my $name-is-id = $col-lc ~~ /_id$/;

        # Analyze data type characteristics
        my $numeric-count = 0;
        my $integer-count = 0;
        my $long-numeric-count = 0;  # IDs tend to be long numbers

        for @values -> $val {
            my $str-val = $val.Str;
            if $str-val ~~ /^ \-? \d+ $/ {
                # Integer
                $numeric-count++;
                $integer-count++;
                $long-numeric-count++ if $str-val.chars > 5;
            } elsif $str-val ~~ /^ \-? \d+ \. \d+ $/ {
                # Float
                $numeric-count++;
            }
        }

        my $is-numeric = $numeric-count > $total * 0.8;
        my $is-integer = $integer-count > $total * 0.8;
        my $is-float = $is-numeric && !$is-integer;
        my $looks-like-id = $is-numeric && ($cardinality == $total || $long-numeric-count > $total * 0.5);

        %col-info{ $col } = {
            cardinality => $cardinality,
            is-numeric => $is-numeric,
            is-integer => $is-integer,
            is-float => $is-float,
            looks-like-id => $looks-like-id,
            name-is-id => $name-is-id,
        };
    }

    # Only score columns that have info
    my @valid-columns = %col-info.keys.sort;
    return (@valid-columns[0], @valid-columns[1] // @valid-columns[0]) unless @valid-columns;

    # Score columns for label selection
    # Lower score is better
    my %label-scores;
    for @valid-columns -> $col {
        my $info = %col-info{ $col };
        my $score = $info<cardinality>.Numeric;  # Base score is cardinality

        # Column name patterns
        $score += 2000 if $info<name-is-id>;            # Never select _id columns

        # Data type penalties
        $score += 1500 if $info<looks-like-id>;         # Strongly avoid ID-like data
        $score += 600 if $info<is-float>;               # Avoid floats
        $score -= 100 if !$info<is-numeric>;            # Prefer non-numeric

        %label-scores{ $col } = $score;
    }

    # Score columns for value selection - ONLY numeric columns allowed
    # Lower score is better
    my %value-scores;
    my @numeric-columns = @valid-columns.grep({ %col-info{ $_ }<is-numeric> });

    for @numeric-columns -> $col {
        my $info = %col-info{ $col };
        # Cardinality matters less for values (they typically have higher cardinality)
        my $score = $info<cardinality>.Numeric / 10;  # Reduced weight

        # Column name patterns
        $score += 2000 if $info<name-is-id>;            # Never select _id columns

        # Data type penalties and preferences
        $score += 1500 if $info<looks-like-id>;         # Strongly avoid ID-like data
        $score += 1000 if $info<is-float>;              # Strongly avoid floats (coordinates, decimals)
        $score -= 500 if $info<is-integer>;             # Strongly prefer integers

        %value-scores{ $col } = $score;
    }

    # Debug output
    debug "=== Column Detection Debug ===";
    debug "Numeric columns only: " ~ @numeric-columns.join(', ');
    for @valid-columns -> $col {
        my $info = %col-info{ $col };
        debug "Column: $col";
        debug "  Cardinality: {$info<cardinality> // 'N/A'}";
        debug "  Is Numeric: {$info<is-numeric> // False}";
        debug "  Is Integer: {$info<is-integer> // False}";
        debug "  Is Float: {$info<is-float> // False}";
        debug "  Looks Like ID: {$info<looks-like-id> // False}";
        debug "  Name ends _id: {$info<name-is-id> // False}";
        debug "  Label Score: {%label-scores{ $col } // 'N/A'}";
        debug "  Value Score: {%value-scores{ $col } // 'N/A'}";
    }

    # Select best label and value columns
    my $label-col = @valid-columns.sort({ %label-scores{ $_ } })[0];
    # Value must be numeric and different from label
    my $value-col = @numeric-columns.grep({ $_ ne $label-col }).sort({ %value-scores{ $_ } })[0]
                 // @numeric-columns[0]  # If label isn't numeric, pick best numeric
                 // $label-col;          # Fallback if no numeric columns

    debug "Selected Label: $label-col";
    debug "Selected Value: $value-col";
    debug "=== End Debug ===";

    return {
        label => $label-col,
        value => $value-col,
        numeric => @numeric-columns
    };
}

method !prepare-data-json(@rows, @columns) {
    # Convert all data to JSON format for JavaScript
    my $rows-json = @rows.map(-> $row {
        my $pairs = @columns.map(-> $col {
            my $key = $col.Str.subst('"', '\\"', :g);
            my $val = ($row{ $col } // '').Str.subst('"', '\\"', :g).subst("\n", '\\n', :g);
            qq["$key": "$val"]
        }).join(', ');
        "\{$pairs\}"
    }).join(",\n    ");
    return "[\n    $rows-json\n]";
}

sub to-json(@data) {
    # Simple JSON array serialization
    my $items = @data.map({
        my $escaped = $_.Str.subst('"', '\\"', :g).subst("\n", '\\n', :g);
        qq["$escaped"]
    }).join(', ');
    return "[$items]";
}
