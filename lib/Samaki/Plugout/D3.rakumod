use Samaki::Plugout;
use Samaki::Utils;
use Samaki::Plugout::Common;
use Duckie;
use Log::Async;
use JSON::Fast;

unit class Samaki::Plugout::D3 does Samaki::Plugout does Samaki::Plugout::Common;

has $.name = 'd3';
has $.description = 'Display data using D3.js visualizations';
has $.clear-before = False;

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
    my $res = Duckie.new.query("select * from read_csv('$path')");
    my @rows = $res.rows;
    my @column-types = $res.column-types;
    return unless @rows;

    my @columns = $res.column-names;

    # Intelligently detect label and value columns
    my %result = self.detect-columns(@columns, @rows, :@column-types);
    my $label-col = %result<label>;
    my $value-col = %result<value>;
    my @default-values = @(%result<values>);
    my @numeric-cols = @(%result<numeric>);
    my @datetime-cols = @(%result<datetime>);

    my $html-file = $data-dir.child("{$name}-d3.html");

    my $title = html-escape($data-dir.basename ~ " : " ~ $path.basename);

    # Prepare all data as JSON for JavaScript
    my $all-data-json = to-json(@rows);
    my $columns-json = to-json(@columns);
    my $numeric-columns-json = to-json(@numeric-cols);
    my $datetime-columns-json = to-json(@datetime-cols);
    my $default-values-json = to-json(@default-values);
    my $default-label = html-escape($label-col);
    my $default-value = html-escape($value-col);

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
            .column-selector {
                display: flex;
                align-items: center;
                gap: 4px;
            }
            .column-selector label {
                font-size: 11px;
                color: #64748b;
                font-weight: 500;
            }
            .column-selector select {
                padding: 4px 8px;
                font-family: ui-monospace, monospace;
                font-size: 11px;
                border: 1px solid #e2e8f0;
                border-radius: 3px;
                background: white;
                color: #2c3e50;
                min-width: 120px;
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
            .line {
                fill: none;
                stroke-width: 2px;
            }
            .line-dot {
                stroke: white;
                stroke-width: 2px;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h2>$title </h2>
            <div class="controls">
                <button id="btn-bar">Bar</button>
                <button id="btn-line">Line</button>
                <button id="btn-pie">Pie Chart</button>
                <button id="btn-donut">Donut Chart</button>
                <button id="btn-treemap">Treemap</button>
                <button id="btn-bubble">Bubble Chart</button>
                <button id="btn-orientation">↔ Horizontal</button>
                <div class="column-selector">
                  <label>Label:</label>
                  <select id="label-column"></select>
                </div>
                <div class="column-selector">
                  <label>Values:</label>
                  <select id="value-column" multiple></select>
                </div>
            </div>
            <div id="chart"></div>
            <div class="tooltip"></div>
        </div>
        <script>
            // All data from CSV
            const allData = $all-data-json;
            const columns = $columns-json;
            const numericColumns = $numeric-columns-json;
            const datetimeColumns = $datetime-columns-json;
            const defaultValues = $default-values-json;

            const container = d3.select('#chart');
            const tooltip = d3.select('.tooltip');

            let currentChartType = defaultValues.length > 2 ? 'line' : 'bar';
            let currentOrientation = 'vertical';

            // Populate column selectors
            const labelSelect = document.getElementById('label-column');
            const valueSelect = document.getElementById('value-column');

            // Label dropdown gets all columns
            columns.forEach(col => {
                const option = document.createElement('option');
                option.value = col;
                option.textContent = col;
                labelSelect.appendChild(option);
            });

            // Value dropdown gets only numeric columns
            numericColumns.forEach(col => {
                const option = document.createElement('option');
                option.value = col;
                option.textContent = col;
                if (defaultValues.includes(col)) {
                    option.selected = true;
                }
                valueSelect.appendChild(option);
            });

            // Set default label selection
            labelSelect.value = '$default-label';

            // Set initial active button
            if (currentChartType === 'line') {
                setActiveButton(document.getElementById('btn-line'));
            } else {
                setActiveButton(document.getElementById('btn-bar'));
            }

            // Parse datetime strings to Date objects
            function parseDatetime(dateStr) {
                if (!dateStr) return null;
                // Try parsing YYYY-MM-DD HH:mm:ss format
                const parsed = new Date(dateStr.replace(' ', 'T'));
                return isNaN(parsed.getTime()) ? null : parsed;
            }

            function getChartData() {
                const labelCol = labelSelect.value;
                const valueCols = Array.from(valueSelect.selectedOptions).map(opt => opt.value);

                if (!valueCols.length) return [];

                const isLabelDatetime = datetimeColumns.includes(labelCol);

                // For single value column, return simple array for pie/donut/treemap/bubble
                if (valueCols.length === 1) {
                    const data = allData.map(row => ({
                        label: isLabelDatetime ? parseDatetime(row[labelCol]) : (row[labelCol] || ''),
                        labelStr: row[labelCol] || '',
                        value: parseFloat(row[valueCols[0]]) || 0
                    }));

                    // Sort by label if datetime
                    if (isLabelDatetime) {
                        data.sort((a, b) => {
                            if (a.label instanceof Date && b.label instanceof Date) {
                                return a.label - b.label;
                            }
                            return 0;
                        });
                    }

                    return data;
                }

                // For multiple values, return array suitable for multi-series charts
                const series = valueCols.map(col => ({
                    name: col,
                    values: allData.map(row => ({
                        label: isLabelDatetime ? parseDatetime(row[labelCol]) : (row[labelCol] || ''),
                        labelStr: row[labelCol] || '',
                        value: parseFloat(row[col]) || 0
                    }))
                }));

                // Sort each series by label if datetime
                if (isLabelDatetime) {
                    series.forEach(s => {
                        s.values.sort((a, b) => {
                            if (a.label instanceof Date && b.label instanceof Date) {
                                return a.label - b.label;
                            }
                            return 0;
                        });
                    });
                }

                return series;
            }

            function clearChart() {
                container.html('');
            }

            // Smart datetime formatter that adapts to the time range
            function createSmartDateTimeFormat(dates) {
                if (!dates || dates.length === 0) return d3.timeFormat("%b %d, %H:%M");

                const extent = d3.extent(dates);
                const range = extent[1] - extent[0];

                // Less than a day: show time
                if (range < 24 * 60 * 60 * 1000) {
                    return d3.timeFormat("%H:%M");
                }
                // Less than a month: show date and time
                else if (range < 30 * 24 * 60 * 60 * 1000) {
                    return d3.timeFormat("%b %d, %H:%M");
                }
                // Less than a year: show date
                else if (range < 365 * 24 * 60 * 60 * 1000) {
                    return d3.timeFormat("%b %d");
                }
                // More than a year: show month and year
                else {
                    return d3.timeFormat("%b %Y");
                }
            }

            function createBarChart(horizontal = false) {
                clearChart();
                const data = getChartData();
                if (!data.length) return;

                const labelCol = labelSelect.value;
                const isLabelDatetime = datetimeColumns.includes(labelCol);

                // Increase bottom margin for datetime labels to prevent cutoff
                const bottomMargin = horizontal ? 40 : (isLabelDatetime ? 120 : 100);
                const margin = {top: 20, right: 30, bottom: bottomMargin, left: horizontal ? 120 : 60};
                const width = container.node().offsetWidth - margin.left - margin.right;
                const height = container.node().offsetHeight - margin.top - margin.bottom;

                const svg = container.append('svg')
                    .attr('width', width + margin.left + margin.right)
                    .attr('height', height + margin.top + margin.bottom)
                    .append('g')
                    .attr('transform', 'translate(' + margin.left + ',' + margin.top + ')');

                // Check if multiple series
                const multiSeries = data[0] && data[0].name !== undefined;

                if (multiSeries) {
                    // Multiple value columns - grouped bars
                    const labels = data[0].values.map(d => d.label);
                    const seriesNames = data.map(d => d.name);

                    const colorScale = d3.scaleOrdinal()
                        .domain(seriesNames)
                        .range(d3.schemeTableau10);

                    if (horizontal) {
                        const maxValue = d3.max(data, series => d3.max(series.values, d => d.value));
                        const x = d3.scaleLinear()
                            .domain([0, maxValue])
                            .range([0, width]);

                        const y0 = d3.scaleBand()
                            .domain(labels)
                            .range([0, height])
                            .padding(0.2);

                        const y1 = d3.scaleBand()
                            .domain(seriesNames)
                            .range([0, y0.bandwidth()])
                            .padding(0.05);

                        svg.append('g')
                            .call(d3.axisLeft(y0))
                            .attr('class', 'axis');

                        svg.append('g')
                            .attr('transform', 'translate(0,' + height + ')')
                            .call(d3.axisBottom(x))
                            .attr('class', 'axis');

                        // Add axis labels
                        let yLabel = labelCol;
                        if (isLabelDatetime && labels[0] instanceof Date) {
                            const dates = labels.map(d => d.toISOString().split('T')[0]);
                            const uniqueDates = [...new Set(dates)];
                            if (uniqueDates.length === 1) {
                                yLabel = labelCol + ' (' + d3.timeFormat('%b %d, %Y')(labels[0]) + ')';
                            }
                        }

                        svg.append('text')
                            .attr('transform', 'rotate(-90)')
                            .attr('x', -height / 2)
                            .attr('y', -margin.left + 15)
                            .attr('text-anchor', 'middle')
                            .style('font-size', '11px')
                            .style('fill', '#64748b')
                            .text(yLabel);

                        svg.append('text')
                            .attr('x', width / 2)
                            .attr('y', height + margin.bottom - 10)
                            .attr('text-anchor', 'middle')
                            .style('font-size', '11px')
                            .style('fill', '#64748b')
                            .text(seriesNames.join(', '));

                        data.forEach(series => {
                            svg.selectAll('.bar-' + series.name)
                                .data(series.values)
                                .enter()
                                .append('rect')
                                .attr('class', 'bar')
                                .attr('x', 0)
                                .attr('y', d => y0(d.label) + y1(series.name))
                                .attr('width', d => x(d.value))
                                .attr('height', y1.bandwidth())
                                .attr('fill', colorScale(series.name))
                                .on('mouseover', (event, d) => showTooltip(event, series.name + ': ' + d.value))
                                .on('mouseout', hideTooltip);
                        });
                    } else {
                        const maxValue = d3.max(data, series => d3.max(series.values, d => d.value));
                        const x0 = d3.scaleBand()
                            .domain(labels)
                            .range([0, width])
                            .padding(0.2);

                        const x1 = d3.scaleBand()
                            .domain(seriesNames)
                            .range([0, x0.bandwidth()])
                            .padding(0.05);

                        const y = d3.scaleLinear()
                            .domain([0, maxValue])
                            .range([height, 0]);

                        const xAxis = d3.axisBottom(x0);

                        // For datetime labels, show fewer ticks and use smart formatting
                        if (isLabelDatetime) {
                            // Show at most 8 ticks for readability
                            const tickInterval = Math.max(1, Math.floor(labels.length / 8));
                            const tickValues = labels.filter((_, i) => i % tickInterval === 0);
                            xAxis.tickValues(tickValues);

                            if (labels[0] instanceof Date) {
                                // Use D3's smart multi-scale formatter for Date objects
                                xAxis.tickFormat(createSmartDateTimeFormat(labels));
                            } else {
                                // For string labels, use simpler format
                                xAxis.tickFormat(d => {
                                    const dateStr = data[0].values.find(v => v.label === d)?.labelStr;
                                    if (dateStr) {
                                        const parts = dateStr.split(' ');
                                        if (parts.length === 2) {
                                            const [datePart, timePart] = parts;
                                            const [y, m, day] = datePart.split('-');
                                            const [h, min] = timePart.split(':');
                                            return day + ' ' + h + ':' + min;
                                        }
                                    }
                                    return d;
                                });
                            }
                        }

                        svg.append('g')
                            .attr('transform', 'translate(0,' + height + ')')
                            .call(xAxis)
                            .attr('class', 'axis')
                            .selectAll('text')
                            .attr('transform', 'rotate(-45)')
                            .style('text-anchor', 'end');

                        svg.append('g')
                            .call(d3.axisLeft(y))
                            .attr('class', 'axis');

                        // Add axis labels
                        let xLabel = labelCol;
                        if (isLabelDatetime && labels[0] instanceof Date) {
                            const dates = labels.map(d => d.toISOString().split('T')[0]);
                            const uniqueDates = [...new Set(dates)];
                            if (uniqueDates.length === 1) {
                                xLabel = labelCol + ' (' + d3.timeFormat('%b %d, %Y')(labels[0]) + ')';
                            }
                        }

                        svg.append('text')
                            .attr('x', width / 2)
                            .attr('y', height + margin.bottom - 10)
                            .attr('text-anchor', 'middle')
                            .style('font-size', '11px')
                            .style('fill', '#64748b')
                            .text(xLabel);

                        svg.append('text')
                            .attr('transform', 'rotate(-90)')
                            .attr('x', -height / 2)
                            .attr('y', -margin.left + 15)
                            .attr('text-anchor', 'middle')
                            .style('font-size', '11px')
                            .style('fill', '#64748b')
                            .text(seriesNames.join(', '));

                        data.forEach(series => {
                            svg.selectAll('.bar-' + series.name)
                                .data(series.values)
                                .enter()
                                .append('rect')
                                .attr('class', 'bar')
                                .attr('x', d => x0(d.label) + x1(series.name))
                                .attr('y', d => y(d.value))
                                .attr('width', x1.bandwidth())
                                .attr('height', d => height - y(d.value))
                                .attr('fill', colorScale(series.name))
                                .on('mouseover', (event, d) => showTooltip(event, series.name + ': ' + d.value))
                                .on('mouseout', hideTooltip);
                        });
                    }
                } else {
                    // Single value column
                    const valueCol = Array.from(valueSelect.selectedOptions).map(opt => opt.value)[0];
                    const colorScale = d3.scaleOrdinal()
                        .domain(data.map(d => d.label))
                        .range(d3.schemeTableau10);

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

                        // Add axis labels
                        const allLabels = data.map(d => d.label);
                        let yLabel = labelCol;
                        if (isLabelDatetime && allLabels[0] instanceof Date) {
                            const dates = allLabels.map(d => d.toISOString().split('T')[0]);
                            const uniqueDates = [...new Set(dates)];
                            if (uniqueDates.length === 1) {
                                yLabel = labelCol + ' (' + d3.timeFormat('%b %d, %Y')(allLabels[0]) + ')';
                            }
                        }

                        svg.append('text')
                            .attr('transform', 'rotate(-90)')
                            .attr('x', -height / 2)
                            .attr('y', -margin.left + 15)
                            .attr('text-anchor', 'middle')
                            .style('font-size', '11px')
                            .style('fill', '#64748b')
                            .text(yLabel);

                        svg.append('text')
                            .attr('x', width / 2)
                            .attr('y', height + margin.bottom - 10)
                            .attr('text-anchor', 'middle')
                            .style('font-size', '11px')
                            .style('fill', '#64748b')
                            .text(valueCol);

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

                        const xAxis = d3.axisBottom(x);

                        // For datetime labels, show fewer ticks and use smart formatting
                        if (isLabelDatetime) {
                            const allLabels = data.map(d => d.label);
                            const tickInterval = Math.max(1, Math.floor(allLabels.length / 8));
                            const tickValues = allLabels.filter((_, i) => i % tickInterval === 0);
                            xAxis.tickValues(tickValues);

                            if (allLabels[0] instanceof Date) {
                                // Use D3's smart multi-scale formatter for Date objects
                                xAxis.tickFormat(createSmartDateTimeFormat(allLabels));
                            } else {
                                // For string labels, use simpler format
                                xAxis.tickFormat(d => {
                                    const dateStr = data.find(item => item.label === d)?.labelStr;
                                    if (dateStr) {
                                        const parts = dateStr.split(' ');
                                        if (parts.length === 2) {
                                            const [datePart, timePart] = parts;
                                            const [y, m, day] = datePart.split('-');
                                            const [h, min] = timePart.split(':');
                                            return day + ' ' + h + ':' + min;
                                        }
                                    }
                                    return d;
                                });
                            }
                        }

                        svg.append('g')
                            .attr('transform', 'translate(0,' + height + ')')
                            .call(xAxis)
                            .attr('class', 'axis')
                            .selectAll('text')
                            .attr('transform', 'rotate(-45)')
                            .style('text-anchor', 'end');

                        svg.append('g')
                            .call(d3.axisLeft(y))
                            .attr('class', 'axis');

                        // Add axis labels
                        const allLabels = data.map(d => d.label);
                        let xLabel = labelCol;
                        if (isLabelDatetime && allLabels[0] instanceof Date) {
                            const dates = allLabels.map(d => d.toISOString().split('T')[0]);
                            const uniqueDates = [...new Set(dates)];
                            if (uniqueDates.length === 1) {
                                xLabel = labelCol + ' (' + d3.timeFormat('%b %d, %Y')(allLabels[0]) + ')';
                            }
                        }

                        svg.append('text')
                            .attr('x', width / 2)
                            .attr('y', height + margin.bottom - 10)
                            .attr('text-anchor', 'middle')
                            .style('font-size', '11px')
                            .style('fill', '#64748b')
                            .text(xLabel);

                        svg.append('text')
                            .attr('transform', 'rotate(-90)')
                            .attr('x', -height / 2)
                            .attr('y', -margin.left + 15)
                            .attr('text-anchor', 'middle')
                            .style('font-size', '11px')
                            .style('fill', '#64748b')
                            .text(valueCol);

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
            }

            function createLineChart() {
                clearChart();
                const data = getChartData();
                if (!data.length) return;

                const labelCol = labelSelect.value;
                const isLabelDatetime = datetimeColumns.includes(labelCol);

                // Increase bottom margin for datetime labels
                const bottomMargin = isLabelDatetime ? 100 : 60;
                const margin = {top: 20, right: 100, bottom: bottomMargin, left: 60};
                const width = container.node().offsetWidth - margin.left - margin.right;
                const height = container.node().offsetHeight - margin.top - margin.bottom;

                const svg = container.append('svg')
                    .attr('width', width + margin.left + margin.right)
                    .attr('height', height + margin.top + margin.bottom)
                    .append('g')
                    .attr('transform', 'translate(' + margin.left + ',' + margin.top + ')');

                // Check if multiple series
                const multiSeries = data[0] && data[0].name !== undefined;

                if (multiSeries) {
                    // Multiple value columns
                    const seriesNames = data.map(d => d.name);
                    const allLabels = data[0].values.map(d => d.label);

                    const colorScale = d3.scaleOrdinal()
                        .domain(seriesNames)
                        .range(d3.schemeTableau10);

                    // Use time scale for datetime, point scale otherwise
                    let x;
                    if (isLabelDatetime && allLabels[0] instanceof Date) {
                        x = d3.scaleTime()
                            .domain(d3.extent(allLabels))
                            .range([0, width]);
                    } else {
                        x = d3.scalePoint()
                            .domain(allLabels)
                            .range([0, width]);
                    }

                    const allValues = data.flatMap(series => series.values.map(d => d.value));
                    const y = d3.scaleLinear()
                        .domain([0, d3.max(allValues)])
                        .range([height, 0]);

                    const xAxis = d3.axisBottom(x);
                    if (isLabelDatetime && allLabels[0] instanceof Date) {
                        // Use D3's smart multi-scale formatter
                        xAxis.tickFormat(createSmartDateTimeFormat(allLabels));
                    }

                    svg.append('g')
                        .attr('transform', 'translate(0,' + height + ')')
                        .call(xAxis)
                        .attr('class', 'axis')
                        .selectAll('text')
                        .attr('transform', 'rotate(-45)')
                        .style('text-anchor', 'end');

                    svg.append('g')
                        .call(d3.axisLeft(y))
                        .attr('class', 'axis');

                    // Add axis labels
                    let xLabel = labelCol;
                    if (isLabelDatetime && allLabels[0] instanceof Date) {
                        // Check if all dates are on the same day
                        const dates = allLabels.map(d => d.toISOString().split('T')[0]);
                        const uniqueDates = [...new Set(dates)];
                        if (uniqueDates.length === 1) {
                            xLabel = labelCol + ' (' + d3.timeFormat('%b %d, %Y')(allLabels[0]) + ')';
                        }
                    }

                    svg.append('text')
                        .attr('x', width / 2)
                        .attr('y', height + margin.bottom - 10)
                        .attr('text-anchor', 'middle')
                        .style('font-size', '11px')
                        .style('fill', '#64748b')
                        .text(xLabel);

                    svg.append('text')
                        .attr('transform', 'rotate(-90)')
                        .attr('x', -height / 2)
                        .attr('y', -margin.left + 15)
                        .attr('text-anchor', 'middle')
                        .style('font-size', '11px')
                        .style('fill', '#64748b')
                        .text(seriesNames.join(', '));

                    const line = d3.line()
                        .x(d => x(d.label))
                        .y(d => y(d.value));

                    data.forEach(series => {
                        svg.append('path')
                            .datum(series.values)
                            .attr('class', 'line')
                            .attr('d', line)
                            .attr('stroke', colorScale(series.name));

                        svg.selectAll('.dot-' + series.name)
                            .data(series.values)
                            .enter()
                            .append('circle')
                            .attr('class', 'line-dot')
                            .attr('cx', d => x(d.label))
                            .attr('cy', d => y(d.value))
                            .attr('r', 4)
                            .attr('fill', colorScale(series.name))
                            .on('mouseover', (event, d) => showTooltip(event, series.name + ': ' + d.value))
                            .on('mouseout', hideTooltip);
                    });

                    // Add legend
                    const legend = svg.selectAll('.legend')
                        .data(seriesNames)
                        .enter()
                        .append('g')
                        .attr('class', 'legend')
                        .attr('transform', (d, i) => 'translate(' + (width + 10) + ',' + (i * 20) + ')');

                    legend.append('rect')
                        .attr('width', 12)
                        .attr('height', 12)
                        .attr('fill', d => colorScale(d));

                    legend.append('text')
                        .attr('x', 18)
                        .attr('y', 10)
                        .style('font-size', '10px')
                        .text(d => d);
                } else {
                    // Single value column
                    const allLabels = data.map(d => d.label);
                    const valueCol = Array.from(valueSelect.selectedOptions).map(opt => opt.value)[0];

                    // Use time scale for datetime, point scale otherwise
                    let x;
                    if (isLabelDatetime && allLabels[0] instanceof Date) {
                        x = d3.scaleTime()
                            .domain(d3.extent(allLabels))
                            .range([0, width]);
                    } else {
                        x = d3.scalePoint()
                            .domain(allLabels)
                            .range([0, width]);
                    }

                    const y = d3.scaleLinear()
                        .domain([0, d3.max(data, d => d.value)])
                        .range([height, 0]);

                    const xAxis = d3.axisBottom(x);
                    if (isLabelDatetime && allLabels[0] instanceof Date) {
                        // Use D3's smart multi-scale formatter
                        xAxis.tickFormat(createSmartDateTimeFormat(allLabels));
                    }

                    svg.append('g')
                        .attr('transform', 'translate(0,' + height + ')')
                        .call(xAxis)
                        .attr('class', 'axis')
                        .selectAll('text')
                        .attr('transform', 'rotate(-45)')
                        .style('text-anchor', 'end');

                    svg.append('g')
                        .call(d3.axisLeft(y))
                        .attr('class', 'axis');

                    // Add axis labels
                    let xLabel = labelCol;
                    if (isLabelDatetime && allLabels[0] instanceof Date) {
                        // Check if all dates are on the same day
                        const dates = allLabels.map(d => d.toISOString().split('T')[0]);
                        const uniqueDates = [...new Set(dates)];
                        if (uniqueDates.length === 1) {
                            xLabel = labelCol + ' (' + d3.timeFormat('%b %d, %Y')(allLabels[0]) + ')';
                        }
                    }

                    svg.append('text')
                        .attr('x', width / 2)
                        .attr('y', height + margin.bottom - 10)
                        .attr('text-anchor', 'middle')
                        .style('font-size', '11px')
                        .style('fill', '#64748b')
                        .text(xLabel);

                    svg.append('text')
                        .attr('transform', 'rotate(-90)')
                        .attr('x', -height / 2)
                        .attr('y', -margin.left + 15)
                        .attr('text-anchor', 'middle')
                        .style('font-size', '11px')
                        .style('fill', '#64748b')
                        .text(valueCol);

                    const line = d3.line()
                        .x(d => x(d.label))
                        .y(d => y(d.value));

                    svg.append('path')
                        .datum(data)
                        .attr('class', 'line')
                        .attr('d', line)
                        .attr('stroke', '#3b82f6');

                    svg.selectAll('.dot')
                        .data(data)
                        .enter()
                        .append('circle')
                        .attr('class', 'line-dot')
                        .attr('cx', d => x(d.label))
                        .attr('cy', d => y(d.value))
                        .attr('r', 4)
                        .attr('fill', '#3b82f6')
                        .on('mouseover', (event, d) => showTooltip(event, d))
                        .on('mouseout', hideTooltip);
                }
            }

            function createPieChart(innerRadius = 0) {
                clearChart();
                const data = getChartData();
                if (!data.length) return;

                // For multi-series, just use the first series
                let chartData = data[0] && data[0].values ? data[0].values : data;

                // Convert Date labels to strings for categorical charts
                chartData = chartData.map(d => ({
                    label: d.label instanceof Date ? d.labelStr : d.label,
                    labelStr: d.labelStr,
                    value: d.value
                }));

                const width = container.node().offsetWidth;
                const height = container.node().offsetHeight;
                const radius = Math.min(width, height) / 2 - 40;

                const svg = container.append('svg')
                    .attr('width', width)
                    .attr('height', height)
                    .append('g')
                    .attr('transform', 'translate(' + width/2 + ',' + height/2 + ')');

                const colorScale = d3.scaleOrdinal()
                    .domain(chartData.map(d => d.label))
                    .range(d3.schemeTableau10);

                const pie = d3.pie()
                    .value(d => d.value)
                    .sort(null);

                const arc = d3.arc()
                    .innerRadius(innerRadius)
                    .outerRadius(radius);

                const arcs = svg.selectAll('.arc')
                    .data(pie(chartData))
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
                    .data(chartData)
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
                const data = getChartData();
                if (!data.length) return;

                // For multi-series, just use the first series
                let chartData = data[0] && data[0].values ? data[0].values : data;

                // Convert Date labels to strings for categorical charts
                chartData = chartData.map(d => ({
                    label: d.label instanceof Date ? d.labelStr : d.label,
                    labelStr: d.labelStr,
                    value: d.value
                }));

                const width = container.node().offsetWidth;
                const height = container.node().offsetHeight;

                const colorScale = d3.scaleOrdinal()
                    .domain(chartData.map(d => d.label))
                    .range(d3.schemeTableau10);

                const root = d3.hierarchy({children: chartData})
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
                const data = getChartData();
                if (!data.length) return;

                // For multi-series, just use the first series
                let chartData = data[0] && data[0].values ? data[0].values : data;

                // Convert Date labels to strings for categorical charts
                chartData = chartData.map(d => ({
                    label: d.label instanceof Date ? d.labelStr : d.label,
                    labelStr: d.labelStr,
                    value: d.value
                }));

                const width = container.node().offsetWidth;
                const height = container.node().offsetHeight;

                const svg = container.append('svg')
                    .attr('width', width)
                    .attr('height', height);

                const colorScale = d3.scaleOrdinal()
                    .domain(chartData.map(d => d.label))
                    .range(d3.schemeTableau10);

                const maxValue = d3.max(chartData, d => d.value);
                const radiusScale = d3.scaleSqrt()
                    .domain([0, maxValue])
                    .range([10, 80]);

                const simulation = d3.forceSimulation(chartData)
                    .force('x', d3.forceX(width / 2).strength(0.05))
                    .force('y', d3.forceY(height / 2).strength(0.05))
                    .force('collide', d3.forceCollide(d => radiusScale(d.value) + 2))
                    .on('tick', ticked);

                const bubbles = svg.selectAll('.bubble')
                    .data(chartData)
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
                    .style('font-size', '11px')
                    .style('font-weight', '600')
                    .style('fill', '#2c3e50')
                    .style('stroke', 'white')
                    .style('stroke-width', '3px')
                    .style('paint-order', 'stroke')
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
                const text = typeof d === 'string' ? d : ('<strong>' + d.label + '</strong><br/>Value: ' + d.value);
                tooltip
                    .style('opacity', 1)
                    .html(text)
                    .style('left', (event.pageX + 10) + 'px')
                    .style('top', (event.pageY - 10) + 'px');
            }

            function hideTooltip() {
                tooltip.style('opacity', 0);
            }

            function setActiveButton(activeBtn) {
                document.querySelectorAll('.controls button').forEach(btn => {
                    btn.classList.remove('active');
                });
                activeBtn.classList.add('active');
            }

            // Initialize chart
            if (currentChartType === 'line') {
                createLineChart();
            } else {
                createBarChart(false);
            }

            // Button event listeners
            document.getElementById('btn-bar').addEventListener('click', function() {
                currentChartType = 'bar';
                createBarChart(currentOrientation === 'horizontal');
                setActiveButton(this);
            });

            document.getElementById('btn-orientation').addEventListener('click', function() {
                if (currentChartType === 'bar' || currentChartType === 'line') {
                    currentOrientation = currentOrientation === 'vertical' ? 'horizontal' : 'vertical';
                    this.textContent = currentOrientation === 'vertical' ? '↔ Horizontal' : '↕ Vertical';
                    if (currentChartType === 'bar') {
                        createBarChart(currentOrientation === 'horizontal');
                    }
                }
            });

            document.getElementById('btn-line').addEventListener('click', function() {
                currentChartType = 'line';
                createLineChart();
                setActiveButton(this);
            });

            document.getElementById('btn-pie').addEventListener('click', function() {
                currentChartType = 'pie';
                createPieChart(0);
                setActiveButton(this);
            });

            document.getElementById('btn-donut').addEventListener('click', function() {
                currentChartType = 'donut';
                createPieChart(80);
                setActiveButton(this);
            });

            document.getElementById('btn-treemap').addEventListener('click', function() {
                currentChartType = 'treemap';
                createTreemap();
                setActiveButton(this);
            });

            document.getElementById('btn-bubble').addEventListener('click', function() {
                currentChartType = 'bubble';
                createBubbleChart();
                setActiveButton(this);
            });

            // Column selector event listeners
            labelSelect.addEventListener('change', function() {
                if (currentChartType === 'bar') {
                    createBarChart(currentOrientation === 'horizontal');
                } else if (currentChartType === 'line') {
                    createLineChart();
                } else if (currentChartType === 'pie') {
                    createPieChart(0);
                } else if (currentChartType === 'donut') {
                    createPieChart(80);
                } else if (currentChartType === 'treemap') {
                    createTreemap();
                } else if (currentChartType === 'bubble') {
                    createBubbleChart();
                }
            });

            valueSelect.addEventListener('change', function() {
                if (currentChartType === 'bar') {
                    createBarChart(currentOrientation === 'horizontal');
                } else if (currentChartType === 'line') {
                    createLineChart();
                } else if (currentChartType === 'pie') {
                    createPieChart(0);
                } else if (currentChartType === 'donut') {
                    createPieChart(80);
                } else if (currentChartType === 'treemap') {
                    createTreemap();
                } else if (currentChartType === 'bubble') {
                    createBubbleChart();
                }
            });
        </script>
    </body>
    </html>
    HTML

    spurt $html-file, $html;
    shell-open $html-file;
}

=begin pod

=head1 NAME

Samaki::Plugout::D3 -- Interactive charts using D3.js

=head1 DESCRIPTION

Visualize CSV data as interactive charts in the browser using D3.js. Supports bar, line, pie, donut, treemap, and bubble charts with controls for switching chart types, selecting columns, and adjusting orientation.

=end pod

