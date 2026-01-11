use Samaki::Plugout;
use Samaki::Utils;
use Duck::CSV;

unit class Samaki::Plugout::D3Chart does Samaki::Plugout;

has $.name = 'd3-chart';
has $.description = 'Display data using D3.js visualizations';
has $.clear-before = False;

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
    my @rows = read-csv("$path");
    return unless @rows;

    my @columns = @rows[0].keys.sort;

    # Intelligently detect label and value columns
    my ($label-col, $value-col) = self!detect-columns(@columns, @rows);

    # Extract data for the chart
    my @data;
    for @rows -> $row {
        @data.push: {
            label => $row{ $label-col } // '',
            value => ($row{ $value-col } // 0).Numeric
        };
    }

    my $html-file = $data-dir.child("{$name}-d3chart.html");

    my $title = html-escape($data-dir.basename ~ " : " ~ $name);
    my $data-json = to-json(@data);

    my $html = Q:s:to/HTML/;
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>$title </title>
        <script src="https://d3js.org/d3.v7.min.js"></script>
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
            #chart {
                width: 100%;
                height: 70vh;
                position: relative;
            }
            .bar {
                transition: fill 0.2s;
            }
            .bar:hover {
                fill: #e74c3c;
            }
            .axis text {
                font-family: ui-monospace, monospace;
                font-size: 11px;
            }
            .axis line, .axis path {
                stroke: #e2e8f0;
            }
            .arc {
                stroke: white;
                stroke-width: 2px;
                transition: opacity 0.2s;
            }
            .arc:hover {
                opacity: 0.8;
            }
            .tooltip {
                position: absolute;
                padding: 8px;
                background: rgba(0, 0, 0, 0.8);
                color: white;
                border-radius: 4px;
                font-size: 11px;
                pointer-events: none;
                opacity: 0;
                transition: opacity 0.2s;
            }
            .treemap-cell {
                stroke: white;
                stroke-width: 2px;
                transition: opacity 0.2s;
            }
            .treemap-cell:hover {
                opacity: 0.8;
            }
            .treemap-text {
                font-size: 10px;
                fill: white;
                pointer-events: none;
            }
            .bubble {
                stroke: white;
                stroke-width: 2px;
                transition: opacity 0.2s;
            }
            .bubble:hover {
                opacity: 0.8;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h2>$title </h2>
            <div class="controls">
                <button id="btn-bar-vertical" class="active">Vertical Bar</button>
                <button id="btn-bar-horizontal">Horizontal Bar</button>
                <button id="btn-pie">Pie Chart</button>
                <button id="btn-donut">Donut Chart</button>
                <button id="btn-treemap">Treemap</button>
                <button id="btn-bubble">Bubble Chart</button>
            </div>
            <div id="chart"></div>
            <div class="tooltip"></div>
        </div>
        <script>
            const data = $data-json;
            const container = d3.select('#chart');
            const tooltip = d3.select('.tooltip');

            const colorScale = d3.scaleOrdinal()
                .domain(data.map(d => d.label))
                .range(d3.schemeTableau10);

            function clearChart() {
                container.html('');
            }

            function createBarChart(horizontal = false) {
                clearChart();
                const margin = {top: 20, right: 30, bottom: horizontal ? 40 : 80, left: horizontal ? 120 : 60};
                const width = container.node().offsetWidth - margin.left - margin.right;
                const height = container.node().offsetHeight - margin.top - margin.bottom;

                const svg = container.append('svg')
                    .attr('width', width + margin.left + margin.right)
                    .attr('height', height + margin.top + margin.bottom)
                    .append('g')
                    .attr('transform', 'translate(' + margin.left + ',' + margin.top + ')');

                if (horizontal) {
                    const x = d3.scaleLinear()
                        .domain([0, d3.max(data, d => d.value)])
                        .range([0, width]);

                    const y = d3.scaleBand()
                        .domain(data.map(d => d.label))
                        .range([0, height])
                        .padding(0.2);

                    svg.append('g')
                        .call(d3.axisLeft(y))
                        .attr('class', 'axis');

                    svg.append('g')
                        .attr('transform', 'translate(0,' + height + ')')
                        .call(d3.axisBottom(x))
                        .attr('class', 'axis');

                    svg.selectAll('.bar')
                        .data(data)
                        .enter()
                        .append('rect')
                        .attr('class', 'bar')
                        .attr('x', 0)
                        .attr('y', d => y(d.label))
                        .attr('width', d => x(d.value))
                        .attr('height', y.bandwidth())
                        .attr('fill', d => colorScale(d.label))
                        .on('mouseover', (event, d) => showTooltip(event, d))
                        .on('mouseout', hideTooltip);
                } else {
                    const x = d3.scaleBand()
                        .domain(data.map(d => d.label))
                        .range([0, width])
                        .padding(0.2);

                    const y = d3.scaleLinear()
                        .domain([0, d3.max(data, d => d.value)])
                        .range([height, 0]);

                    svg.append('g')
                        .attr('transform', 'translate(0,' + height + ')')
                        .call(d3.axisBottom(x))
                        .attr('class', 'axis')
                        .selectAll('text')
                        .attr('transform', 'rotate(-45)')
                        .style('text-anchor', 'end');

                    svg.append('g')
                        .call(d3.axisLeft(y))
                        .attr('class', 'axis');

                    svg.selectAll('.bar')
                        .data(data)
                        .enter()
                        .append('rect')
                        .attr('class', 'bar')
                        .attr('x', d => x(d.label))
                        .attr('y', d => y(d.value))
                        .attr('width', x.bandwidth())
                        .attr('height', d => height - y(d.value))
                        .attr('fill', d => colorScale(d.label))
                        .on('mouseover', (event, d) => showTooltip(event, d))
                        .on('mouseout', hideTooltip);
                }
            }

            function createPieChart(innerRadius = 0) {
                clearChart();
                const width = container.node().offsetWidth;
                const height = container.node().offsetHeight;
                const radius = Math.min(width, height) / 2 - 40;

                const svg = container.append('svg')
                    .attr('width', width)
                    .attr('height', height)
                    .append('g')
                    .attr('transform', 'translate(' + width/2 + ',' + height/2 + ')');

                const pie = d3.pie()
                    .value(d => d.value)
                    .sort(null);

                const arc = d3.arc()
                    .innerRadius(innerRadius)
                    .outerRadius(radius);

                const arcs = svg.selectAll('.arc')
                    .data(pie(data))
                    .enter()
                    .append('g')
                    .attr('class', 'arc');

                arcs.append('path')
                    .attr('d', arc)
                    .attr('fill', d => colorScale(d.data.label))
                    .on('mouseover', (event, d) => showTooltip(event, d.data))
                    .on('mouseout', hideTooltip);

                // Add legend
                const legend = svg.selectAll('.legend')
                    .data(data)
                    .enter()
                    .append('g')
                    .attr('class', 'legend')
                    .attr('transform', (d, i) => 'translate(' + (radius + 20) + ',' + (-radius + i * 20) + ')');

                legend.append('rect')
                    .attr('width', 12)
                    .attr('height', 12)
                    .attr('fill', d => colorScale(d.label));

                legend.append('text')
                    .attr('x', 18)
                    .attr('y', 10)
                    .style('font-size', '10px')
                    .text(d => d.label.length > 20 ? d.label.substring(0, 20) + '...' : d.label);
            }

            function createTreemap() {
                clearChart();
                const width = container.node().offsetWidth;
                const height = container.node().offsetHeight;

                const root = d3.hierarchy({children: data})
                    .sum(d => d.value)
                    .sort((a, b) => b.value - a.value);

                d3.treemap()
                    .size([width, height])
                    .padding(2)
                    (root);

                const svg = container.append('svg')
                    .attr('width', width)
                    .attr('height', height);

                const cells = svg.selectAll('g')
                    .data(root.leaves())
                    .enter()
                    .append('g')
                    .attr('transform', d => 'translate(' + d.x0 + ',' + d.y0 + ')');

                cells.append('rect')
                    .attr('class', 'treemap-cell')
                    .attr('width', d => d.x1 - d.x0)
                    .attr('height', d => d.y1 - d.y0)
                    .attr('fill', d => colorScale(d.data.label))
                    .on('mouseover', (event, d) => showTooltip(event, d.data))
                    .on('mouseout', hideTooltip);

                cells.append('text')
                    .attr('class', 'treemap-text')
                    .attr('x', 4)
                    .attr('y', 14)
                    .text(d => {
                        const width = d.x1 - d.x0;
                        const label = d.data.label;
                        if (width < 50) return '';
                        return label.length > width / 6 ? label.substring(0, width / 6) + '...' : label;
                    });
            }

            function createBubbleChart() {
                clearChart();
                const width = container.node().offsetWidth;
                const height = container.node().offsetHeight;

                const svg = container.append('svg')
                    .attr('width', width)
                    .attr('height', height);

                const maxValue = d3.max(data, d => d.value);
                const radiusScale = d3.scaleSqrt()
                    .domain([0, maxValue])
                    .range([10, 80]);

                const simulation = d3.forceSimulation(data)
                    .force('x', d3.forceX(width / 2).strength(0.05))
                    .force('y', d3.forceY(height / 2).strength(0.05))
                    .force('collide', d3.forceCollide(d => radiusScale(d.value) + 2))
                    .on('tick', ticked);

                const bubbles = svg.selectAll('.bubble')
                    .data(data)
                    .enter()
                    .append('g')
                    .attr('class', 'bubble');

                bubbles.append('circle')
                    .attr('r', d => radiusScale(d.value))
                    .attr('fill', d => colorScale(d.label))
                    .on('mouseover', (event, d) => showTooltip(event, d))
                    .on('mouseout', hideTooltip);

                bubbles.append('text')
                    .attr('text-anchor', 'middle')
                    .attr('dy', '.3em')
                    .style('font-size', '10px')
                    .style('fill', 'white')
                    .style('pointer-events', 'none')
                    .text(d => {
                        const r = radiusScale(d.value);
                        const label = d.label;
                        if (r < 20) return '';
                        return label.length > r / 4 ? label.substring(0, r / 4) + '...' : label;
                    });

                function ticked() {
                    bubbles.attr('transform', d => 'translate(' + d.x + ',' + d.y + ')');
                }
            }

            function showTooltip(event, d) {
                tooltip
                    .style('opacity', 1)
                    .html('<strong>' + d.label + '</strong><br/>Value: ' + d.value)
                    .style('left', (event.pageX + 10) + 'px')
                    .style('top', (event.pageY - 10) + 'px');
            }

            function hideTooltip() {
                tooltip.style('opacity', 0);
            }

            // Initialize with vertical bar chart
            createBarChart(false);

            // Button event listeners
            document.getElementById('btn-bar-vertical').addEventListener('click', function() {
                createBarChart(false);
                setActiveButton(this);
            });

            document.getElementById('btn-bar-horizontal').addEventListener('click', function() {
                createBarChart(true);
                setActiveButton(this);
            });

            document.getElementById('btn-pie').addEventListener('click', function() {
                createPieChart(0);
                setActiveButton(this);
            });

            document.getElementById('btn-donut').addEventListener('click', function() {
                createPieChart(80);
                setActiveButton(this);
            });

            document.getElementById('btn-treemap').addEventListener('click', function() {
                createTreemap();
                setActiveButton(this);
            });

            document.getElementById('btn-bubble').addEventListener('click', function() {
                createBubbleChart();
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
    # JSON serialization for array of hashes
    my $items = @data.map({
        my $label = $_<label>.Str.subst('"', '\\"', :g).subst("\n", '\\n', :g);
        my $value = $_<value>;
        qq[\{"label":"$label","value":$value\}]
    }).join(', ');
    return "[$items]";
}
