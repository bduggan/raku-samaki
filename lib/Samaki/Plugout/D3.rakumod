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
    my @dimension-cols = @(%result<dimensions> // []);

    my $html-file = $data-dir.child("{$name}-d3.html");

    my $title = html-escape($data-dir.basename ~ " : " ~ $path.basename);

    # Prepare all data as JSON for JavaScript
    my $all-data-json = to-json(@rows);
    my $columns-json = to-json(@columns);
    my $numeric-columns-json = to-json(@numeric-cols);
    my $datetime-columns-json = to-json(@datetime-cols);
    my $default-values-json = to-json(@default-values);
    my $default-dimensions-json = to-json(@dimension-cols);
    my $default-label = html-escape($label-col);
    my $default-value = html-escape($value-col);

    my $html = Q:s:to/HTML/;
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>$title </title>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/moment.js/2.29.4/moment.min.js"></script>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/moment-timezone/0.5.43/moment-timezone-with-data.min.js"></script>
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
                padding: 10px;
                background: #fafbfc;
                border: 1px solid #e2e8f0;
                border-radius: 4px;
                display: flex;
                gap: 6px;
                flex-wrap: nowrap;
                align-items: center;
                font-size: 11px;
            }
            .control-item {
                display: flex;
                align-items: center;
                gap: 4px;
                height: 28px;
            }
            .control-label {
                font-size: 11px;
                color: #64748b;
                font-weight: 500;
            }
            .control-item select {
                padding: 4px 8px;
                font-family: ui-monospace, monospace;
                font-size: 11px;
                border: 1px solid #cbd5e1;
                border-radius: 3px;
                background: white;
                color: #2c3e50;
                min-width: 80px;
                height: 28px;
                box-sizing: border-box;
            }
            .orientation-icon {
                width: 28px;
                height: 28px;
                display: flex;
                align-items: center;
                justify-content: center;
                background: white;
                border: 1px solid #cbd5e1;
                border-radius: 3px;
                cursor: pointer;
                font-size: 16px;
                color: #64748b;
                user-select: none;
                transition: background 0.2s;
            }
            .orientation-icon:hover {
                background: #f1f5f9;
            }
            .values-container {
                display: flex;
                gap: 4px;
                align-items: center;
                flex-wrap: wrap;
            }
            .value-chip {
                padding: 4px 8px;
                background: white;
                border: 1px solid #cbd5e1;
                border-radius: 3px;
                font-size: 11px;
                color: #2c3e50;
                cursor: pointer;
                display: flex;
                align-items: center;
                gap: 4px;
                height: 28px;
                box-sizing: border-box;
                transition: background 0.2s;
            }
            .value-chip:hover {
                background: #fee;
            }
            .value-chip-remove {
                color: #ef4444;
                font-weight: bold;
            }
            .value-add {
                width: 28px;
                height: 28px;
                display: flex;
                align-items: center;
                justify-content: center;
                background: white;
                border: 1px solid #cbd5e1;
                border-radius: 3px;
                cursor: pointer;
                font-size: 16px;
                color: #64748b;
                user-select: none;
                transition: background 0.2s;
            }
            .value-add:hover {
                background: #f1f5f9;
            }
            .value-selector-dropdown {
                position: relative;
            }
            .value-selector-dropdown select {
                padding: 4px 8px;
                font-family: ui-monospace, monospace;
                font-size: 11px;
                border: 1px solid #cbd5e1;
                border-radius: 3px;
                background: white;
                color: #2c3e50;
                height: 28px;
                box-sizing: border-box;
            }
            .legend-box {
                position: absolute;
                top: 20px;
                right: 20px;
                max-width: 200px;
                max-height: 300px;
                overflow-y: auto;
                background: white;
                border: 1px solid #e2e8f0;
                border-radius: 4px;
                padding: 8px;
                font-size: 11px;
                box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            }
            .legend-item {
                display: flex;
                align-items: center;
                gap: 6px;
                margin-bottom: 4px;
            }
            .legend-color {
                width: 12px;
                height: 12px;
                border-radius: 2px;
                flex-shrink: 0;
            }
            .datetime-box {
                display: flex;
                align-items: center;
                gap: 4px;
            }
            .datetime-box select {
                padding: 4px 8px;
                font-family: ui-monospace, monospace;
                font-size: 11px;
                border: 1px solid #cbd5e1;
                border-radius: 3px;
                background: white;
                color: #2c3e50;
                height: 28px;
                box-sizing: border-box;
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
                <div class="control-item">
                    <select id="chart-type">
                        <option value="bar">Bar</option>
                        <option value="line">Line</option>
                        <option value="pie">Pie</option>
                        <option value="donut">Donut</option>
                        <option value="treemap">Treemap</option>
                        <option value="bubble">Bubble</option>
                    </select>
                </div>
                <div class="orientation-icon" id="orientation-icon">↔</div>
                <div class="control-item">
                    <span class="control-label">Label</span>
                    <select id="label-column"></select>
                </div>
                <div class="control-item">
                    <span class="control-label">Dim</span>
                    <div class="values-container" id="dimensions-container"></div>
                </div>
                <div class="control-item">
                    <span class="control-label">Values</span>
                    <div class="values-container" id="values-container">
                        <select id="value-column" multiple style="display: none;"></select>
                    </div>
                </div>
                <div class="datetime-box" id="datetime-box" style="display: none;">
                    <span class="control-label">Date</span>
                    <select id="time-format">
                        <option value="auto">Auto</option>
                        <option value="time-only">HH:mm</option>
                        <option value="time-seconds">HH:mm:ss</option>
                        <option value="date-time">MMM d, HH:mm</option>
                        <option value="date-time-seconds">MMM d, HH:mm:ss</option>
                        <option value="date-only">MMM d, yyyy</option>
                        <option value="month-year">MMM yyyy</option>
                        <option value="month-only">MMM</option>
                        <option value="year-only">yyyy</option>
                    </select>
                    <select id="source-timezone">
                        <option value="America/New_York">US/Eastern (ET)</option>
                        <option value="America/Chicago">US/Central (CT)</option>
                        <option value="America/Denver">US/Mountain (MT)</option>
                        <option value="America/Los_Angeles">US/Pacific (PT)</option>
                        <option value="America/Anchorage">US/Alaska (AKT)</option>
                        <option value="Pacific/Honolulu">US/Hawaii (HT)</option>
                        <option value="UTC">UTC</option>
                        <option value="Europe/London">Europe/London (GMT/BST)</option>
                        <option value="Europe/Paris">Europe/Paris (CET/CEST)</option>
                        <option value="Europe/Berlin">Europe/Berlin (CET/CEST)</option>
                        <option value="Europe/Rome">Europe/Rome (CET/CEST)</option>
                        <option value="Europe/Madrid">Europe/Madrid (CET/CEST)</option>
                        <option value="Asia/Tokyo">Asia/Tokyo (JST)</option>
                        <option value="Asia/Shanghai">Asia/Shanghai (CST)</option>
                        <option value="Asia/Singapore">Asia/Singapore (SGT)</option>
                        <option value="Australia/Sydney">Australia/Sydney (AEDT/AEST)</option>
                    </select>
                    <span class="control-label">to</span>
                    <select id="timezone">
                        <option value="America/New_York">US/Eastern (ET)</option>
                        <option value="America/Chicago">US/Central (CT)</option>
                        <option value="America/Denver">US/Mountain (MT)</option>
                        <option value="America/Los_Angeles">US/Pacific (PT)</option>
                        <option value="America/Anchorage">US/Alaska (AKT)</option>
                        <option value="Pacific/Honolulu">US/Hawaii (HT)</option>
                        <option value="UTC">UTC</option>
                        <option value="Europe/London">Europe/London (GMT/BST)</option>
                        <option value="Europe/Paris">Europe/Paris (CET/CEST)</option>
                        <option value="Europe/Berlin">Europe/Berlin (CET/CEST)</option>
                        <option value="Europe/Rome">Europe/Rome (CET/CEST)</option>
                        <option value="Europe/Madrid">Europe/Madrid (CET/CEST)</option>
                        <option value="Asia/Tokyo">Asia/Tokyo (JST)</option>
                        <option value="Asia/Shanghai">Asia/Shanghai (CST)</option>
                        <option value="Asia/Singapore">Asia/Singapore (SGT)</option>
                        <option value="Australia/Sydney">Australia/Sydney (AEDT/AEST)</option>
                    </select>
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
            const defaultDimensions = $default-dimensions-json;

            const container = d3.select('#chart');
            const tooltip = d3.select('.tooltip');

            let currentChartType = defaultValues.length > 2 ? 'line' : 'bar';
            let currentOrientation = 'vertical';
            let selectedValues = [...defaultValues];
            let selectedDimensions = defaultDimensions.length > 0 ? [defaultDimensions[0]] : [];

            // Populate column selectors
            const chartTypeSelect = document.getElementById('chart-type');
            const labelSelect = document.getElementById('label-column');
            const valueSelect = document.getElementById('value-column');
            const dimensionsContainer = document.getElementById('dimensions-container');
            const valuesContainer = document.getElementById('values-container');
            const orientationIcon = document.getElementById('orientation-icon');
            const timeFormatSelect = document.getElementById('time-format');
            const sourceTimezoneSelect = document.getElementById('source-timezone');
            const timezoneSelect = document.getElementById('timezone');
            const datetimeBox = document.getElementById('datetime-box');

            // Label dropdown gets all columns
            columns.forEach(col => {
                const option = document.createElement('option');
                option.value = col;
                option.textContent = col;
                labelSelect.appendChild(option);
            });

            // Value dropdown gets only numeric columns (hidden, used for chip management)
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

            // Set initial chart type
            chartTypeSelect.value = currentChartType;

            // Chip-based value selector
            function updateValueChips() {
                valuesContainer.querySelectorAll('.value-chip, .value-add, .value-selector-dropdown').forEach(el => el.remove());

                selectedValues.forEach(val => {
                    const chip = document.createElement('div');
                    chip.className = 'value-chip';
                    chip.innerHTML = val + ' <span class="value-chip-remove">×</span>';
                    chip.addEventListener('click', () => {
                        selectedValues = selectedValues.filter(v => v !== val);
                        updateValueChips();
                        Array.from(valueSelect.options).forEach(opt => {
                            opt.selected = selectedValues.includes(opt.value);
                        });
                        refreshChart();
                    });
                    valuesContainer.insertBefore(chip, valueSelect);
                });

                // Only show + button if there are columns available to add
                const availableValues = numericColumns.filter(col => !selectedValues.includes(col));
                if (availableValues.length > 0) {
                    const addBtn = document.createElement('div');
                    addBtn.className = 'value-add';
                    addBtn.textContent = '+';
                    addBtn.addEventListener('click', showValueSelector);
                    valuesContainer.insertBefore(addBtn, valueSelect);
                }
            }

            function showValueSelector() {
                const availableValues = numericColumns.filter(col => !selectedValues.includes(col));
                if (availableValues.length === 0) return;

                // Remove any existing dropdown
                const existingDropdown = valuesContainer.querySelector('.value-selector-dropdown');
                if (existingDropdown) {
                    existingDropdown.remove();
                    updateValueChips();
                    return;
                }

                // Hide the + button temporarily
                const addBtn = valuesContainer.querySelector('.value-add');
                if (addBtn) {
                    addBtn.style.display = 'none';
                }

                // Create dropdown
                const dropdownContainer = document.createElement('div');
                dropdownContainer.className = 'value-selector-dropdown';

                const select = document.createElement('select');
                const defaultOption = document.createElement('option');
                defaultOption.value = '';
                defaultOption.textContent = 'Add column...';
                select.appendChild(defaultOption);

                availableValues.forEach(col => {
                    const option = document.createElement('option');
                    option.value = col;
                    option.textContent = col;
                    select.appendChild(option);
                });

                select.addEventListener('change', function() {
                    if (this.value) {
                        selectedValues.push(this.value);
                        Array.from(valueSelect.options).forEach(opt => {
                            opt.selected = selectedValues.includes(opt.value);
                        });
                    }
                    updateValueChips();
                    refreshChart();
                });

                select.addEventListener('blur', function() {
                    updateValueChips();
                });

                dropdownContainer.appendChild(select);
                valuesContainer.insertBefore(dropdownContainer, valueSelect);

                // Auto-focus and open
                select.focus();
            }

            updateValueChips();

            // Chip-based dimension selector
            function updateDimensionChips() {
                dimensionsContainer.querySelectorAll('.value-chip, .value-add, .value-selector-dropdown').forEach(el => el.remove());

                selectedDimensions.forEach(dim => {
                    const chip = document.createElement('div');
                    chip.className = 'value-chip';
                    chip.innerHTML = dim + ' <span class="value-chip-remove">×</span>';
                    chip.addEventListener('click', () => {
                        selectedDimensions = selectedDimensions.filter(d => d !== dim);
                        updateDimensionChips();
                        refreshChart();
                    });
                    dimensionsContainer.appendChild(chip);
                });

                // Only show + button if there are dimensions available to add
                const availableDimensions = columns.filter(col =>
                    !selectedDimensions.includes(col) &&
                    col !== labelSelect.value &&
                    !selectedValues.includes(col)
                );

                if (availableDimensions.length > 0) {
                    const addBtn = document.createElement('div');
                    addBtn.className = 'value-add';
                    addBtn.textContent = '+';
                    addBtn.addEventListener('click', showDimensionSelector);
                    dimensionsContainer.appendChild(addBtn);
                }
            }

            function showDimensionSelector() {
                const availableDimensions = columns.filter(col =>
                    !selectedDimensions.includes(col) &&
                    col !== labelSelect.value &&
                    !selectedValues.includes(col)
                );
                if (availableDimensions.length === 0) return;

                // Remove any existing dropdown
                const existingDropdown = dimensionsContainer.querySelector('.value-selector-dropdown');
                if (existingDropdown) {
                    existingDropdown.remove();
                    updateDimensionChips();
                    return;
                }

                // Hide the + button temporarily
                const addBtn = dimensionsContainer.querySelector('.value-add');
                if (addBtn) {
                    addBtn.style.display = 'none';
                }

                // Create dropdown
                const dropdownContainer = document.createElement('div');
                dropdownContainer.className = 'value-selector-dropdown';

                const select = document.createElement('select');
                const defaultOption = document.createElement('option');
                defaultOption.value = '';
                defaultOption.textContent = 'Add dimension...';
                select.appendChild(defaultOption);

                availableDimensions.forEach(col => {
                    const option = document.createElement('option');
                    option.value = col;
                    option.textContent = col;
                    select.appendChild(option);
                });

                select.addEventListener('change', function() {
                    if (this.value) {
                        selectedDimensions.push(this.value);
                    }
                    updateDimensionChips();
                    refreshChart();
                });

                select.addEventListener('blur', function() {
                    updateDimensionChips();
                });

                dropdownContainer.appendChild(select);
                dimensionsContainer.appendChild(dropdownContainer);

                // Auto-focus and open
                select.focus();
            }

            updateDimensionChips();

            // Show/hide datetime controls based on label column
            function updateDatetimeControls() {
                const labelCol = labelSelect.value;
                const isDatetime = datetimeColumns.includes(labelCol);
                datetimeBox.style.display = isDatetime ? 'flex' : 'none';
            }

            // Parse datetime strings to Date objects with timezone handling
            function parseDatetime(dateStr, sourceTimezone, targetTimezone) {
                if (!dateStr) return null;

                // Use moment-timezone for proper timezone handling
                let m;
                if (sourceTimezone === 'UTC') {
                    m = moment.utc(dateStr, 'YYYY-MM-DD HH:mm:ss');
                } else {
                    m = moment.tz(dateStr, 'YYYY-MM-DD HH:mm:ss', sourceTimezone);
                }

                if (!m.isValid()) {
                    // Fallback to ISO parsing
                    const parsed = new Date(dateStr.replace(' ', 'T'));
                    return isNaN(parsed.getTime()) ? null : parsed;
                }

                // Convert to target timezone if different
                if (targetTimezone !== sourceTimezone) {
                    m = m.tz(targetTimezone);
                }

                return m.toDate();
            }

            // Format datetime based on user selection
            function formatDatetime(date, format) {
                if (!date || !(date instanceof Date)) return '';

                const m = moment(date);

                switch(format) {
                    case 'time-only':
                        return m.format('HH:mm');
                    case 'time-seconds':
                        return m.format('HH:mm:ss');
                    case 'date-time':
                        return m.format('MMM D, HH:mm');
                    case 'date-time-seconds':
                        return m.format('MMM D, HH:mm:ss');
                    case 'date-only':
                        return m.format('MMM D, YYYY');
                    case 'month-year':
                        return m.format('MMM YYYY');
                    case 'month-only':
                        return m.format('MMM');
                    case 'year-only':
                        return m.format('YYYY');
                    case 'auto':
                    default:
                        // Auto-detect based on time range (will be handled by existing smart formatter)
                        return null;
                }
            }

            // Set default timezones
            sourceTimezoneSelect.value = 'UTC';
            timezoneSelect.value = 'UTC';

            // Update datetime controls visibility
            updateDatetimeControls();

            function refreshChart() {
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
            }

            function getChartDataWithDimension(labelCol, valueCols, dimensionCols) {
                const isLabelDatetime = datetimeColumns.includes(labelCol);
                const sourceTimezone = sourceTimezoneSelect.value;
                const targetTimezone = timezoneSelect.value;

                // Group data by dimension key (combined dimension values)
                const dimensionKey = (row) =>
                    dimensionCols.map(dc => row[dc] || 'null').join('|');

                const groupedData = {};
                allData.forEach(row => {
                    const key = dimensionKey(row);
                    if (!groupedData[key]) {
                        groupedData[key] = {
                            rows: [],
                            dimensionValues: dimensionCols.map(dc => row[dc] || 'null')
                        };
                    }
                    groupedData[key].rows.push(row);
                });

                // Create series for each value column × dimension group
                const series = [];
                valueCols.forEach(valueCol => {
                    Object.keys(groupedData).forEach(dimKey => {
                        const group = groupedData[dimKey];

                        // Dataset label
                        let seriesName;
                        if (valueCols.length === 1 && dimensionCols.length === 1) {
                            seriesName = group.dimensionValues[0];  // "90146"
                        } else if (dimensionCols.length === 1) {
                            seriesName = valueCol + ': ' + group.dimensionValues[0];  // "num: 90146"
                        } else {
                            const dimParts = dimensionCols.map((dc, i) =>
                                dc + ': ' + group.dimensionValues[i]
                            ).join(', ');
                            seriesName = valueCol + ' (' + dimParts + ')';
                        }

                        const values = group.rows.map(row => ({
                            label: isLabelDatetime ? parseDatetime(row[labelCol], sourceTimezone, targetTimezone) : (row[labelCol] || ''),
                            labelStr: row[labelCol] || '',
                            value: parseFloat(row[valueCol]) || 0
                        }));

                        // Sort by label if datetime
                        if (isLabelDatetime) {
                            values.sort((a, b) => {
                                if (a.label instanceof Date && b.label instanceof Date) {
                                    return a.label - b.label;
                                }
                                return 0;
                            });
                        }

                        series.push({
                            name: seriesName,
                            values: values,
                            dimensionValues: group.dimensionValues
                        });
                    });
                });

                return series;
            }

            function getChartData() {
                const labelCol = labelSelect.value;
                const valueCols = selectedValues;
                const dimensionCols = selectedDimensions;

                if (!valueCols.length) return [];

                // If dimension selected, group by dimension
                if (dimensionCols.length > 0) {
                    return getChartDataWithDimension(labelCol, valueCols, dimensionCols);
                }

                const isLabelDatetime = datetimeColumns.includes(labelCol);
                const sourceTimezone = sourceTimezoneSelect.value;
                const targetTimezone = timezoneSelect.value;

                // For single value column, return simple array for pie/donut/treemap/bubble
                if (valueCols.length === 1) {
                    const data = allData.map(row => ({
                        label: isLabelDatetime ? parseDatetime(row[labelCol], sourceTimezone, targetTimezone) : (row[labelCol] || ''),
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
                        label: isLabelDatetime ? parseDatetime(row[labelCol], sourceTimezone, targetTimezone) : (row[labelCol] || ''),
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

                const format = timeFormatSelect.value;

                // If user selected a specific format, use it
                if (format !== 'auto') {
                    return function(d) {
                        return formatDatetime(d, format) || d3.timeFormat("%b %d, %H:%M")(d);
                    };
                }

                // Auto-detect based on time range
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

                        // X-axis label shows value columns (or dimension if present)
                        let xAxisLabel = seriesNames.join(', ');
                        if (selectedDimensions.length > 0) {
                            xAxisLabel = selectedValues.join(', ') + ' (by ' + selectedDimensions.join(', ') + ')';
                        }

                        svg.append('text')
                            .attr('x', width / 2)
                            .attr('y', height + margin.bottom - 10)
                            .attr('text-anchor', 'middle')
                            .style('font-size', '11px')
                            .style('fill', '#64748b')
                            .text(xAxisLabel);

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

                        // Add floating legend box
                        createLegendBox(data, colorScale);
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

                        // Y-axis label shows value columns (or dimension if present)
                        let yAxisLabel = seriesNames.join(', ');
                        if (selectedDimensions.length > 0) {
                            yAxisLabel = selectedValues.join(', ') + ' (by ' + selectedDimensions.join(', ') + ')';
                        }

                        svg.append('text')
                            .attr('transform', 'rotate(-90)')
                            .attr('x', -height / 2)
                            .attr('y', -margin.left + 15)
                            .attr('text-anchor', 'middle')
                            .style('font-size', '11px')
                            .style('fill', '#64748b')
                            .text(yAxisLabel);

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

                        // Add floating legend box
                        createLegendBox(data, colorScale);
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

                    // Y-axis label shows value columns (or dimension if present)
                    let yAxisLabel = seriesNames.join(', ');
                    if (selectedDimensions.length > 0) {
                        yAxisLabel = selectedValues.join(', ') + ' (by ' + selectedDimensions.join(', ') + ')';
                    }

                    svg.append('text')
                        .attr('transform', 'rotate(-90)')
                        .attr('x', -height / 2)
                        .attr('y', -margin.left + 15)
                        .attr('text-anchor', 'middle')
                        .style('font-size', '11px')
                        .style('fill', '#64748b')
                        .text(yAxisLabel);

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

                    // Add floating legend box
                    createLegendBox(data, colorScale);
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

            function createLegendBox(seriesData, colorScale) {
                // Remove existing legend box
                d3.select('.legend-box').remove();

                if (!seriesData || seriesData.length === 0) return;

                const legendBox = d3.select('#chart')
                    .append('div')
                    .attr('class', 'legend-box');

                seriesData.forEach(series => {
                    const legendItem = legendBox.append('div')
                        .attr('class', 'legend-item');

                    legendItem.append('div')
                        .attr('class', 'legend-color')
                        .style('background-color', colorScale(series.name));

                    legendItem.append('span')
                        .text(series.name);
                });
            }

            // Initialize chart
            refreshChart();

            // Chart type selector event listener
            chartTypeSelect.addEventListener('change', function() {
                currentChartType = this.value;
                refreshChart();
            });

            // Orientation icon event listener
            orientationIcon.addEventListener('click', function() {
                if (currentChartType === 'bar' || currentChartType === 'line') {
                    currentOrientation = currentOrientation === 'vertical' ? 'horizontal' : 'vertical';
                    this.textContent = currentOrientation === 'vertical' ? '↔' : '↕';
                    if (currentChartType === 'bar') {
                        createBarChart(currentOrientation === 'horizontal');
                    }
                }
            });

            // Column selector event listeners
            labelSelect.addEventListener('change', function() {
                updateDatetimeControls();
                refreshChart();
            });

            // Datetime control event listeners
            timeFormatSelect.addEventListener('change', refreshChart);
            sourceTimezoneSelect.addEventListener('change', refreshChart);
            timezoneSelect.addEventListener('change', refreshChart);
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

