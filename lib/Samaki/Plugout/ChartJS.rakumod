use Samaki::Plugout;
use Samaki::Utils;
use Samaki::Plugout::Common;
use Duckie;
use Log::Async;
use JSON::Fast;

unit class Samaki::Plugout::ChartJS does Samaki::Plugout does Samaki::Plugout::Common;

has $.name = 'chartjs';
has $.description = 'Display data as a bar chart using Chart.js';
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

  my $html-file = $data-dir.child("{$name}-chartjs.html");

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

  # Get timezone detection JavaScript
  my $timezone-detection-js = self.timezone-detection-js;

  my $html = Q:s:to/HTML/;
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$title </title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/moment@2.29.4/moment.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/moment-timezone@0.5.43/builds/moment-timezone-with-data.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-moment@1.0.1/dist/chartjs-adapter-moment.min.js"></script>
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
        flex-wrap: wrap;
        align-items: center;
        font-size: 11px;
      }
      .control-item {
        display: flex;
        align-items: center;
        gap: 4px;
        height: 28px;
      }
      .control-item select {
        padding: 4px 6px;
        font-family: ui-monospace, monospace;
        font-size: 11px;
        background: white;
        border: 1px solid #cbd5e1;
        border-radius: 3px;
        color: #2c3e50;
        cursor: pointer;
        height: 28px;
      }
      .control-item select:hover {
        border-color: #94a3b8;
      }
      .control-label {
        color: #64748b;
        font-size: 11px;
        font-weight: 500;
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
      }
      .orientation-icon:hover {
        background: #f8f9fa;
        border-color: #94a3b8;
      }
      .values-container {
        display: flex;
        align-items: center;
        gap: 4px;
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
      }
      .value-chip:hover {
        background: #fee;
        border-color: #fbb;
      }
      .value-chip-remove {
        color: #94a3b8;
        font-weight: bold;
      }
      .value-add {
        padding: 4px 8px;
        background: white;
        border: 1px solid #cbd5e1;
        border-radius: 3px;
        font-size: 11px;
        color: #64748b;
        cursor: pointer;
        height: 28px;
        display: flex;
        align-items: center;
      }
      .value-add:hover {
        background: #f0fdf4;
        border-color: #86efac;
      }
      .value-selector-popup {
        position: absolute;
        background: white;
        border: 1px solid #cbd5e1;
        border-radius: 3px;
        box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        padding: 4px;
        z-index: 1000;
        max-height: 200px;
        overflow-y: auto;
      }
      .value-option {
        padding: 4px 8px;
        cursor: pointer;
        font-size: 11px;
      }
      .value-option:hover {
        background: #f1f5f9;
      }
      .datetime-box {
        display: flex;
        align-items: center;
        gap: 4px;
        height: 28px;
      }
      .datetime-box select {
        padding: 4px 6px;
        font-family: ui-monospace, monospace;
        font-size: 11px;
        background: white;
        border: 1px solid #cbd5e1;
        border-radius: 3px;
        color: #2c3e50;
        cursor: pointer;
        height: 28px;
      }
      .chart-container {
        position: relative;
        height: 70vh;
        width: 100%;
      }
      .legend-box {
        position: absolute;
        top: 10px;
        right: 10px;
        background: rgba(255, 255, 255, 0.95);
        border: 1px solid #e2e8f0;
        border-radius: 4px;
        padding: 8px;
        max-height: 300px;
        max-width: 200px;
        overflow-y: auto;
        font-family: ui-monospace, monospace;
        font-size: 11px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        z-index: 100;
      }
      .legend-item {
        display: flex;
        align-items: center;
        gap: 6px;
        padding: 3px 0;
        line-height: 1.3;
      }
      .legend-color {
        width: 12px;
        height: 12px;
        border-radius: 2px;
        flex-shrink: 0;
      }
      .legend-label {
        color: #2c3e50;
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
            <option value="scatter">Scatter</option>
            <option value="pie">Pie</option>
            <option value="polarArea">Polar</option>
          </select>
        </div>
        <div class="orientation-icon" id="orientation-icon" title="Toggle orientation">↔</div>
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
            <option value="date-time">MMM D, HH:mm</option>
            <option value="date-time-seconds">MMM D, HH:mm:ss</option>
            <option value="date-only">MMM D, yyyy</option>
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
            <option value="Europe/Amsterdam">Europe/Amsterdam (CET/CEST)</option>
            <option value="Europe/Brussels">Europe/Brussels (CET/CEST)</option>
            <option value="Europe/Zurich">Europe/Zurich (CET/CEST)</option>
            <option value="Asia/Tokyo">Asia/Tokyo (JST)</option>
            <option value="Asia/Shanghai">Asia/Shanghai (CST)</option>
            <option value="Asia/Hong_Kong">Asia/Hong_Kong (HKT)</option>
            <option value="Asia/Singapore">Asia/Singapore (SGT)</option>
            <option value="Asia/Dubai">Asia/Dubai (GST)</option>
            <option value="Asia/Kolkata">Asia/Mumbai (IST)</option>
            <option value="Australia/Sydney">Australia/Sydney (AEST/AEDT)</option>
            <option value="Australia/Melbourne">Australia/Melbourne (AEST/AEDT)</option>
            <option value="Australia/Perth">Australia/Perth (AWST)</option>
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
            <option value="Europe/Amsterdam">Europe/Amsterdam (CET/CEST)</option>
            <option value="Europe/Brussels">Europe/Brussels (CET/CEST)</option>
            <option value="Europe/Zurich">Europe/Zurich (CET/CEST)</option>
            <option value="Asia/Tokyo">Asia/Tokyo (JST)</option>
            <option value="Asia/Shanghai">Asia/Shanghai (CST)</option>
            <option value="Asia/Hong_Kong">Asia/Hong_Kong (HKT)</option>
            <option value="Asia/Singapore">Asia/Singapore (SGT)</option>
            <option value="Asia/Dubai">Asia/Dubai (GST)</option>
            <option value="Asia/Kolkata">Asia/Mumbai (IST)</option>
            <option value="Australia/Sydney">Australia/Sydney (AEST/AEDT)</option>
            <option value="Australia/Melbourne">Australia/Melbourne (AEST/AEDT)</option>
            <option value="Australia/Perth">Australia/Perth (AWST)</option>
          </select>
          <select id="time-unit">
            <option value="auto">Auto</option>
            <option value="millisecond">Millisecond</option>
            <option value="second">Second</option>
            <option value="minute">Minute</option>
            <option value="hour">Hour</option>
            <option value="day">Day</option>
            <option value="week">Week</option>
            <option value="month">Month</option>
            <option value="quarter">Quarter</option>
            <option value="year">Year</option>
          </select>
        </div>
      </div>
      <div class="chart-container">
        <canvas id="myChart"></canvas>
        <div class="legend-box" id="legend-box" style="display: none;"></div>
      </div>
    </div>
    <script>
      const ctx = document.getElementById('myChart');
      let myChart;
      let currentIndexAxis = 'x';

      // All data from CSV
      const allData = $all-data-json;
      const columns = $columns-json;
      const numericColumns = $numeric-columns-json;
      const datetimeColumns = $datetime-columns-json;
      const defaultValues = $default-values-json;
      const defaultDimensions = $default-dimensions-json;

      // Set initial chart type based on number of default values
      let currentChartType = defaultValues.length > 2 ? 'line' : 'bar';

      // Populate column selectors
      const labelSelect = document.getElementById('label-column');
      const valueSelect = document.getElementById('value-column');
      const valuesContainer = document.getElementById('values-container');
      const dimensionsContainer = document.getElementById('dimensions-container');
      const chartTypeSelect = document.getElementById('chart-type');
      const orientationIcon = document.getElementById('orientation-icon');
      const legendBox = document.getElementById('legend-box');

      // Track selected values and dimensions
      let selectedValues = [];
      let selectedDimensions = defaultDimensions.length > 0 ? [defaultDimensions[0]] : [];

      // Update value chips display
      function updateValueChips() {
        // Clear existing chips except the hidden select
        valuesContainer.querySelectorAll('.value-chip, .value-add, .value-selector-popup').forEach(el => el.remove());

        // Add chip for each selected value
        selectedValues.forEach(val => {
          const chip = document.createElement('div');
          chip.className = 'value-chip';
          chip.innerHTML = val + ' <span class="value-chip-remove">×</span>';
          chip.addEventListener('click', () => {
            selectedValues = selectedValues.filter(v => v !== val);
            updateValueChips();
            // Update hidden select
            Array.from(valueSelect.options).forEach(opt => {
              opt.selected = selectedValues.includes(opt.value);
            });
            createChart(currentChartType, currentIndexAxis);
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

      // Show value selector popup
      function showValueSelector(event) {
        // Remove existing popup if any
        document.querySelectorAll('.value-selector-popup').forEach(el => el.remove());

        const popup = document.createElement('div');
        popup.className = 'value-selector-popup';
        popup.style.top = (event.target.offsetTop + event.target.offsetHeight + 2) + 'px';
        popup.style.left = event.target.offsetLeft + 'px';

        numericColumns.forEach(col => {
          if (!selectedValues.includes(col)) {
            const option = document.createElement('div');
            option.className = 'value-option';
            option.textContent = col;
            option.addEventListener('click', () => {
              selectedValues.push(col);
              updateValueChips();
              // Update hidden select
              Array.from(valueSelect.options).forEach(opt => {
                opt.selected = selectedValues.includes(opt.value);
              });
              popup.remove();
              createChart(currentChartType, currentIndexAxis);
            });
            popup.appendChild(option);
          }
        });

        valuesContainer.appendChild(popup);

        // Close popup when clicking outside
        setTimeout(() => {
          document.addEventListener('click', function closePopup(e) {
            if (!popup.contains(e.target) && e.target !== event.target) {
              popup.remove();
              document.removeEventListener('click', closePopup);
            }
          });
        }, 0);
      }

      // Label dropdown gets all columns
      columns.forEach(col => {
        const option1 = document.createElement('option');
        option1.value = col;
        option1.textContent = col;
        labelSelect.appendChild(option1);
      });

      // Value dropdown gets only numeric columns (hidden, used for tracking)
      numericColumns.forEach(col => {
        const option2 = document.createElement('option');
        option2.value = col;
        option2.textContent = col;
        // Select all columns in defaultValues array by default
        if (defaultValues.includes(col)) {
          option2.selected = true;
          selectedValues.push(col);
        }
        valueSelect.appendChild(option2);
      });

      // Initialize value chips
      updateValueChips();

      // Chip-based dimension selector
      function updateDimensionChips() {
        dimensionsContainer.querySelectorAll('.value-chip, .value-add, .value-selector-popup').forEach(el => el.remove());

        selectedDimensions.forEach(dim => {
          const chip = document.createElement('div');
          chip.className = 'value-chip';
          chip.innerHTML = dim + ' <span class="value-chip-remove">×</span>';
          chip.addEventListener('click', () => {
            selectedDimensions = selectedDimensions.filter(d => d !== dim);
            updateDimensionChips();
            createChart(currentChartType, currentIndexAxis);
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

      function showDimensionSelector(event) {
        const availableDimensions = columns.filter(col =>
          !selectedDimensions.includes(col) &&
          col !== labelSelect.value &&
          !selectedValues.includes(col)
        );
        if (availableDimensions.length === 0) return;

        // Remove existing popup if any
        document.querySelectorAll('.value-selector-popup').forEach(el => el.remove());

        const popup = document.createElement('div');
        popup.className = 'value-selector-popup';
        popup.style.top = (event.target.offsetTop + event.target.offsetHeight + 2) + 'px';
        popup.style.left = event.target.offsetLeft + 'px';

        availableDimensions.forEach(col => {
          const option = document.createElement('div');
          option.className = 'value-option';
          option.textContent = col;
          option.addEventListener('click', () => {
            selectedDimensions.push(col);
            updateDimensionChips();
            popup.remove();
            createChart(currentChartType, currentIndexAxis);
          });
          popup.appendChild(option);
        });

        dimensionsContainer.appendChild(popup);

        // Close popup when clicking outside
        setTimeout(() => {
          document.addEventListener('click', function closePopup(e) {
            if (!popup.contains(e.target)) {
              popup.remove();
              document.removeEventListener('click', closePopup);
            }
          });
        }, 0);
      }

      // Initialize dimension chips
      updateDimensionChips();

      // Set default label selection
      labelSelect.value = '$default-label';

      // Set initial chart type
      chartTypeSelect.value = currentChartType;

      console.log('=== ChartJS Debug ===');
      console.log('All Data:', allData);
      console.log('All Columns:', columns);
      console.log('Numeric Columns:', numericColumns);
      console.log('Datetime Columns:', datetimeColumns);
      console.log('Default Label:', '$default-label');
      console.log('Default Values:', defaultValues);

      const timeFormatSelect = document.getElementById('time-format');
      const sourceTimezoneSelect = document.getElementById('source-timezone');
      const timezoneSelect = document.getElementById('timezone');
      const timeUnitSelect = document.getElementById('time-unit');
      const datetimeBox = document.getElementById('datetime-box');

$timezone-detection-js

      // Map format types to display format strings
      function getDisplayFormats(formatType) {
        const formats = {
          'time-only': {
            millisecond: 'HH:mm:ss.SSS',
            second: 'HH:mm:ss',
            minute: 'HH:mm',
            hour: 'HH:mm',
            day: 'HH:mm',
            week: 'HH:mm',
            month: 'HH:mm',
            quarter: 'HH:mm',
            year: 'HH:mm'
          },
          'time-seconds': {
            millisecond: 'HH:mm:ss.SSS',
            second: 'HH:mm:ss',
            minute: 'HH:mm:ss',
            hour: 'HH:mm:ss',
            day: 'HH:mm:ss',
            week: 'HH:mm:ss',
            month: 'HH:mm:ss',
            quarter: 'HH:mm:ss',
            year: 'HH:mm:ss'
          },
          'date-time': {
            millisecond: 'MMM D, HH:mm:ss',
            second: 'MMM D, HH:mm:ss',
            minute: 'MMM D, HH:mm',
            hour: 'MMM D, HH:mm',
            day: 'MMM D, HH:mm',
            week: 'MMM D',
            month: 'MMM yyyy',
            quarter: 'MMM yyyy',
            year: 'yyyy'
          },
          'date-time-seconds': {
            millisecond: 'MMM D, HH:mm:ss.SSS',
            second: 'MMM D, HH:mm:ss',
            minute: 'MMM D, HH:mm:ss',
            hour: 'MMM D, HH:mm:ss',
            day: 'MMM D, HH:mm:ss',
            week: 'MMM D, HH:mm:ss',
            month: 'MMM yyyy',
            quarter: 'MMM yyyy',
            year: 'yyyy'
          },
          'date-only': {
            millisecond: 'MMM D, yyyy',
            second: 'MMM D, yyyy',
            minute: 'MMM D, yyyy',
            hour: 'MMM D, yyyy',
            day: 'MMM D, yyyy',
            week: 'MMM D, yyyy',
            month: 'MMM yyyy',
            quarter: 'MMM yyyy',
            year: 'yyyy'
          },
          'month-year': {
            millisecond: 'MMM yyyy',
            second: 'MMM yyyy',
            minute: 'MMM yyyy',
            hour: 'MMM yyyy',
            day: 'MMM yyyy',
            week: 'MMM yyyy',
            month: 'MMM yyyy',
            quarter: 'MMM yyyy',
            year: 'yyyy'
          },
          'month-only': {
            millisecond: 'MMM',
            second: 'MMM',
            minute: 'MMM',
            hour: 'MMM',
            day: 'MMM',
            week: 'MMM',
            month: 'MMM',
            quarter: 'MMM',
            year: 'MMM'
          },
          'year-only': {
            millisecond: 'yyyy',
            second: 'yyyy',
            minute: 'yyyy',
            hour: 'yyyy',
            day: 'yyyy',
            week: 'yyyy',
            month: 'yyyy',
            quarter: 'yyyy',
            year: 'yyyy'
          }
        };
        return formats[formatType];
      }

      // Helper to parse datetime strings consistently using moment.js
      function parseDateTime(dateStr, sourceTimezone, targetTimezone) {
        if (!dateStr) return null;

        // Parse datetime string in source timezone
        let m;
        if (sourceTimezone === 'UTC') {
          m = moment.utc(dateStr, 'YYYY-MM-DD HH:mm:ss');
        } else {
          m = moment.tz(dateStr, 'YYYY-MM-DD HH:mm:ss', sourceTimezone);
        }

        if (!m.isValid()) return null;

        // Convert to target timezone if different
        if (targetTimezone !== sourceTimezone) {
          m = m.tz(targetTimezone);
        }

        return m.toDate();
      }

      // Analyze datetime data and determine best format
      function analyzeTimeRange(labelCol) {
        if (!datetimeColumns.includes(labelCol)) {
          return null;
        }

        const sourceTimezone = sourceTimezoneSelect.value;
        const targetTimezone = timezoneSelect.value;
        const dates = allData.map(row => parseDateTime(row[labelCol], sourceTimezone, targetTimezone)).filter(d => d && !isNaN(d.getTime()));
        if (dates.length === 0) {
          return null;
        }

        dates.sort((a, b) => a - b);

        // Get unique dates to handle dimensional data correctly
        const uniqueDates = [...new Set(dates.map(d => d.getTime()))].map(t => new Date(t));
        uniqueDates.sort((a, b) => a - b);

        const minDate = uniqueDates[0];
        const maxDate = uniqueDates[uniqueDates.length - 1];
        const rangeMs = maxDate - minDate;
        const rangeDays = rangeMs / (1000 * 60 * 60 * 24);
        const numPoints = dates.length;

        // Calculate average spacing between consecutive UNIQUE time points
        let totalSpacingMs = 0;
        for (let i = 1; i < uniqueDates.length; i++) {
          totalSpacingMs += uniqueDates[i] - uniqueDates[i - 1];
        }
        const avgSpacingMs = uniqueDates.length > 1 ? totalSpacingMs / (uniqueDates.length - 1) : rangeMs;
        const avgSpacingSeconds = avgSpacingMs / 1000;
        const avgSpacingMinutes = avgSpacingSeconds / 60;
        const avgSpacingHours = avgSpacingMinutes / 60;
        const avgSpacingDays = avgSpacingHours / 24;

        // Determine recommended time unit based on average spacing
        let recommendedUnit;
        if (avgSpacingSeconds < 1) {
          recommendedUnit = 'millisecond';
        } else if (avgSpacingSeconds < 60) {
          recommendedUnit = 'second';
        } else if (avgSpacingMinutes < 60) {
          recommendedUnit = 'minute';
        } else if (avgSpacingHours < 24) {
          recommendedUnit = 'hour';
        } else if (avgSpacingDays < 7) {
          recommendedUnit = 'day';
        } else if (avgSpacingDays < 30) {
          recommendedUnit = 'week';
        } else if (avgSpacingDays < 90) {
          recommendedUnit = 'month';
        } else if (avgSpacingDays < 365) {
          recommendedUnit = 'quarter';
        } else {
          recommendedUnit = 'year';
        }

        // Check if all dates are on the same day
        const allSameDay = dates.every(d =>
          d.getFullYear() === minDate.getFullYear() &&
          d.getMonth() === minDate.getMonth() &&
          d.getDate() === minDate.getDate()
        );

        // Helper to format duration
        function formatDuration(ms) {
          const seconds = Math.floor(ms / 1000);
          const minutes = Math.floor(seconds / 60);
          const hours = Math.floor(minutes / 60);
          const days = Math.floor(hours / 24);

          if (days > 0) return days + 'd';
          if (hours > 0) return hours + 'h';
          if (minutes > 0) return minutes + 'm';
          return seconds + 's';
        }

        // Heuristics for choosing time format
        let recommendedFormat;
        let dateContextText = '';

        if (allSameDay) {
          // All on same day - show time only
          const rangeHours = rangeMs / (1000 * 60 * 60);
          if (rangeHours < 1) {
            recommendedFormat = 'time-seconds';
          } else {
            recommendedFormat = 'time-only';
          }
          // Show just the date
          dateContextText = minDate.toLocaleDateString('en-US', {
            year: 'numeric',
            month: 'short',
            day: 'numeric'
          });
        } else if (rangeDays < 1) {
          // Less than a day
          recommendedFormat = 'date-time';
        } else if (rangeDays < 7) {
          // Less than a week
          recommendedFormat = numPoints > 50 ? 'date-only' : 'date-time';
          const minStr = minDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
          const maxStr = maxDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
          const duration = formatDuration(rangeMs);
          dateContextText = minStr + ' to ' + maxStr + ', ' + duration;
        } else if (rangeDays < 31) {
          // Less than a month
          recommendedFormat = 'date-only';
          const minStr = minDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
          const maxStr = maxDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
          const duration = formatDuration(rangeMs);
          dateContextText = minStr + ' to ' + maxStr + ', ' + duration;
        } else if (rangeDays < 90) {
          // Less than 3 months
          recommendedFormat = numPoints > 100 ? 'date-only' : 'date-only';
          const minStr = minDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
          const maxStr = maxDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
          const duration = formatDuration(rangeMs);
          dateContextText = minStr + ' to ' + maxStr + ', ' + duration;
        } else if (rangeDays < 365) {
          // Less than a year
          recommendedFormat = numPoints > 50 ? 'month-year' : 'date-only';
          const minStr = minDate.toLocaleDateString('en-US', { month: 'short', year: 'numeric' });
          const maxStr = maxDate.toLocaleDateString('en-US', { month: 'short', year: 'numeric' });
          const duration = formatDuration(rangeMs);
          dateContextText = minStr + ' to ' + maxStr + ', ' + duration;
        } else {
          // More than a year
          recommendedFormat = numPoints > 50 ? 'year-only' : 'month-year';
          const minStr = minDate.toLocaleDateString('en-US', { month: 'short', year: 'numeric' });
          const maxStr = maxDate.toLocaleDateString('en-US', { month: 'short', year: 'numeric' });
          const duration = formatDuration(rangeMs);
          dateContextText = minStr + ' to ' + maxStr + ', ' + duration;
        }

        console.log('Time analysis:', {
          minDate: minDate.toISOString(),
          maxDate: maxDate.toISOString(),
          rangeDays,
          numPoints,
          uniquePoints: uniqueDates.length,
          allSameDay,
          recommendedFormat,
          recommendedUnit,
          avgSpacingHours: avgSpacingHours.toFixed(2),
          avgSpacingMinutes: avgSpacingMinutes.toFixed(2)
        });

        return {
          recommendedFormat,
          recommendedUnit,
          dateContextText,
          minDate,
          maxDate,
          allSameDay
        };
      }

      // Helper: convert datetime label
      function convertDatetimeLabel(dateStr, sourceTimezone, targetTimezone) {
        if (!dateStr) return '';
        let m;
        if (sourceTimezone === 'UTC') {
          m = moment.utc(dateStr, 'YYYY-MM-DD HH:mm:ss');
        } else {
          m = moment.tz(dateStr, 'YYYY-MM-DD HH:mm:ss', sourceTimezone);
        }
        if (!m.isValid()) return dateStr;
        if (targetTimezone !== sourceTimezone) {
          m = m.tz(targetTimezone);
        }
        return m.format('YYYY-MM-DD HH:mm:ss');
      }

      // Helper: create scatter data from values
      function createScatterData(values, labels, labelCol) {
        const isLabelDatetime = datetimeColumns.includes(labelCol);
        const isLabelNumeric = numericColumns.includes(labelCol);
        const sourceTimezone = sourceTimezoneSelect.value;
        const targetTimezone = timezoneSelect.value;

        return values.map((y, i) => {
          let x;
          if (isLabelDatetime) {
            const parsed = parseDateTime(labels[i], sourceTimezone, targetTimezone);
            x = parsed ? parsed.getTime() : i;
          } else if (isLabelNumeric) {
            x = Number(labels[i]);
            if (isNaN(x)) x = i;
          } else {
            x = i;
          }
          return { x, y };
        });
      }

      function getChartData(isScatter = false) {
        const labelCol = labelSelect.value;
        const valueCols = Array.from(valueSelect.selectedOptions).map(opt => opt.value);
        const dimensionCols = selectedDimensions;

        if (valueCols.length === 0) {
          console.warn('No value columns selected');
          return { labels: [], datasets: [] };
        }

        console.log('Getting chart data for label="' + labelCol + '" values=' + JSON.stringify(valueCols) + ' dimensions=' + JSON.stringify(dimensionCols) + ' scatter=' + isScatter);

        // No dimension → use current behavior
        if (dimensionCols.length === 0) {
          return getChartDataNoDimensions(isScatter, labelCol, valueCols);
        }

        // WITH DIMENSIONS:
        // 1. Group data by dimension key (combined dimension values)
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

        // 2. Collect all unique labels across all groups
        const allLabelValues = new Set();
        Object.values(groupedData).forEach(group => {
          group.rows.forEach(row => allLabelValues.add(row[labelCol]));
        });

        // 3. Sort labels (datetime-aware)
        let sortedLabels = Array.from(allLabelValues);
        if (datetimeColumns.includes(labelCol)) {
          const sourceTimezone = sourceTimezoneSelect.value;
          const targetTimezone = timezoneSelect.value;
          sortedLabels.sort((a, b) => {
            const dateA = parseDateTime(a, sourceTimezone, targetTimezone) || new Date(0);
            const dateB = parseDateTime(b, sourceTimezone, targetTimezone) || new Date(0);
            return dateA - dateB;
          });
          // Convert to target timezone format
          sortedLabels = sortedLabels.map(dateStr =>
            convertDatetimeLabel(dateStr, sourceTimezone, targetTimezone)
          );
        }

        // 4. Create datasets: one per (valueCol × dimensionGroup)
        const colorPalette = [
          { bg: 'rgba(54, 162, 235, 0.5)', border: 'rgba(54, 162, 235, 1)' },
          { bg: 'rgba(255, 99, 132, 0.5)', border: 'rgba(255, 99, 132, 1)' },
          { bg: 'rgba(75, 192, 192, 0.5)', border: 'rgba(75, 192, 192, 1)' },
          { bg: 'rgba(255, 206, 86, 0.5)', border: 'rgba(255, 206, 86, 1)' },
          { bg: 'rgba(153, 102, 255, 0.5)', border: 'rgba(153, 102, 255, 1)' },
          { bg: 'rgba(255, 159, 64, 0.5)', border: 'rgba(255, 159, 64, 1)' },
          { bg: 'rgba(199, 199, 199, 0.5)', border: 'rgba(199, 199, 199, 1)' },
          { bg: 'rgba(83, 102, 255, 0.5)', border: 'rgba(83, 102, 255, 1)' }
        ];

        const datasets = [];
        let colorIndex = 0;

        valueCols.forEach(valueCol => {
          Object.keys(groupedData).forEach(dimKey => {
            const group = groupedData[dimKey];
            const colors = colorPalette[colorIndex % colorPalette.length];
            colorIndex++;

            // Dataset label: dimension value, with value column name if multiple selected
            let datasetLabel;
            if (valueCols.length === 1) {
              // Single value column: just show dimension value (e.g., "90146")
              datasetLabel = group.dimensionValues[0];
            } else {
              // Multiple value columns: show both (e.g., "num: 90146")
              datasetLabel = valueCol + ': ' + group.dimensionValues[0];
            }

            // Build data lookup for this group
            const groupDataMap = {};
            group.rows.forEach(row => {
              const labelValue = row[labelCol];
              const convertedLabel = datetimeColumns.includes(labelCol) ?
                convertDatetimeLabel(labelValue, sourceTimezoneSelect.value, timezoneSelect.value) :
                labelValue;
              groupDataMap[convertedLabel] = row[valueCol];
            });

            // Create data array matching sortedLabels
            const values = sortedLabels.map(label => {
              const val = groupDataMap[label];
              if (val === undefined || val === null) return null;
              let numVal = Number(val);
              return isNaN(numVal) ? 0 : numVal;
            });

            datasets.push({
              label: datasetLabel,
              data: isScatter ? createScatterData(values, sortedLabels, labelCol) : values,
              backgroundColor: colors.bg,
              borderColor: colors.border,
              borderWidth: 1,
              spanGaps: true
            });
          });
        });

        console.log('Labels:', sortedLabels.length, 'Datasets:', datasets.length);

        return { labels: sortedLabels, datasets: datasets };
      }

      // Preserve existing logic for backward compatibility
      function getChartDataNoDimensions(isScatter, labelCol, valueCols) {
        // Check if label column is datetime
        const isLabelDatetime = datetimeColumns.includes(labelCol);
        const isLabelNumeric = numericColumns.includes(labelCol);

        // Create array of data with indices for sorting
        let dataWithIndices = allData.map((row, idx) => ({ row, idx }));

        // Sort and convert datetime labels
        let labels;
        if (isLabelDatetime) {
          const sourceTimezone = sourceTimezoneSelect.value;
          const targetTimezone = timezoneSelect.value;
          dataWithIndices.sort((a, b) => {
            const dateA = parseDateTime(a.row[labelCol], sourceTimezone, targetTimezone) || new Date(0);
            const dateB = parseDateTime(b.row[labelCol], sourceTimezone, targetTimezone) || new Date(0);
            return dateA - dateB;
          });
          // Convert datetime strings from source to target timezone for display
          labels = dataWithIndices.map(item => {
            const dateStr = item.row[labelCol];
            if (!dateStr) return '';
            let m;
            if (sourceTimezone === 'UTC') {
              m = moment.utc(dateStr, 'YYYY-MM-DD HH:mm:ss');
            } else {
              m = moment.tz(dateStr, 'YYYY-MM-DD HH:mm:ss', sourceTimezone);
            }
            if (!m.isValid()) return dateStr;
            if (targetTimezone !== sourceTimezone) {
              m = m.tz(targetTimezone);
            }
            return m.format('YYYY-MM-DD HH:mm:ss');
          });
        } else {
          labels = dataWithIndices.map(item => item.row[labelCol] || '');
        }

        // Color palette for multiple datasets
        const colorPalette = [
          { bg: 'rgba(54, 162, 235, 0.5)', border: 'rgba(54, 162, 235, 1)' },
          { bg: 'rgba(255, 99, 132, 0.5)', border: 'rgba(255, 99, 132, 1)' },
          { bg: 'rgba(75, 192, 192, 0.5)', border: 'rgba(75, 192, 192, 1)' },
          { bg: 'rgba(255, 206, 86, 0.5)', border: 'rgba(255, 206, 86, 1)' },
          { bg: 'rgba(153, 102, 255, 0.5)', border: 'rgba(153, 102, 255, 1)' },
          { bg: 'rgba(255, 159, 64, 0.5)', border: 'rgba(255, 159, 64, 1)' },
          { bg: 'rgba(199, 199, 199, 0.5)', border: 'rgba(199, 199, 199, 1)' },
          { bg: 'rgba(83, 102, 255, 0.5)', border: 'rgba(83, 102, 255, 1)' }
        ];

        // Create a dataset for each selected value column
        const datasets = valueCols.map((valueCol, index) => {
          const colors = colorPalette[index % colorPalette.length];

          if (isScatter) {
            // For scatter charts, create {x, y} data points
            const scatterData = dataWithIndices.map((item, i) => {
              // Get Y value (from value column)
              const yVal = item.row[valueCol] || '0';
              let y = Number(yVal);
              if (isNaN(y)) y = 0;

              // Get X value (from label column)
              let x;
              if (isLabelDatetime) {
                // Use the datetime label converted to timestamp
                const sourceTimezone = sourceTimezoneSelect.value;
                const targetTimezone = timezoneSelect.value;
                const dateStr = item.row[labelCol];
                const parsed = parseDateTime(dateStr, sourceTimezone, targetTimezone);
                x = parsed ? parsed.getTime() : i;
              } else if (isLabelNumeric) {
                const xVal = item.row[labelCol] || '0';
                x = Number(xVal);
                if (isNaN(x)) x = i;
              } else {
                // For non-numeric labels, use the index
                x = i;
              }

              return { x, y };
            });

            return {
              label: valueCol,
              data: scatterData,
              backgroundColor: colors.bg,
              borderColor: colors.border,
              pointRadius: 5,
              pointHoverRadius: 7
            };
          } else {
            // Standard format for other chart types
            const values = dataWithIndices.map(item => {
              const val = item.row[valueCol] || '0';
              let numVal = Number(val);
              if (isNaN(numVal)) {
                numVal = 0;
              } else if (Number.isInteger(numVal)) {
                numVal = parseInt(val, 10);
              }
              return numVal;
            });

            return {
              label: valueCol,
              data: values,
              backgroundColor: colors.bg,
              borderColor: colors.border,
              borderWidth: 1
            };
          }
        });

        console.log('Labels:', labels.length, 'Datasets:', datasets.length);

        return {
          labels: labels,
          datasets: datasets
        };
      }

      // Update custom legend box
      function updateLegend(datasets) {
        const dimensionCols = selectedDimensions;

        if (dimensionCols.length === 0 || datasets.length <= 1) {
          legendBox.style.display = 'none';
          return;
        }

        legendBox.style.display = 'block';
        let html = '';
        datasets.forEach(dataset => {
          const color = dataset.borderColor || dataset.backgroundColor;
          html += '<div class="legend-item">';
          html += '<div class="legend-color" style="background-color: ' + color + ';"></div>';
          html += '<div class="legend-label">' + dataset.label + '</div>';
          html += '</div>';
        });
        legendBox.innerHTML = html;
      }

      function createChart(type, indexAxis = 'x') {
        if (myChart) {
          myChart.destroy();
        }

        currentChartType = type;
        currentIndexAxis = indexAxis;

        const isRadial = type === 'pie' || type === 'polarArea';
        const isScatter = type === 'scatter';

        // Get fresh data based on selected columns
        const data = getChartData(isScatter);

        // Update custom legend
        updateLegend(data.datasets);

        // Check if label column is datetime
        const labelCol = labelSelect.value;
        const isLabelDatetime = datetimeColumns.includes(labelCol);
        console.log('Label column "' + labelCol + '" is datetime:', isLabelDatetime);

        // Analyze time range and update UI for datetime labels
        let timeAnalysis = null;
        let selectedFormat = 'date-time'; // default
        let selectedUnit = null;
        let dateContextText = '';
        if (isLabelDatetime) {
          timeAnalysis = analyzeTimeRange(labelCol);
          datetimeBox.style.display = 'flex';

          // Determine which format to use
          if (timeFormatSelect.value === 'auto') {
            selectedFormat = timeAnalysis.recommendedFormat;
          } else {
            selectedFormat = timeFormatSelect.value;
          }

          // Determine which unit to use
          if (timeUnitSelect.value === 'auto') {
            selectedUnit = timeAnalysis.recommendedUnit;
          } else {
            selectedUnit = timeUnitSelect.value;
          }

          console.log('Selected time unit:', selectedUnit, '(from', timeUnitSelect.value + ')');

          // Save date context text for axis title
          dateContextText = timeAnalysis.dateContextText || '';
        } else {
          datetimeBox.style.display = 'none';
        }

        // For pie and polar area charts with a single dataset, use multiple colors per slice
        if (isRadial && data.datasets.length === 1) {
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

        // Build scales configuration
        let scales;
        const isLabelNumeric = numericColumns.includes(labelCol);
        if (isRadial) {
          scales = undefined;
        } else if (isScatter) {
          // Scatter charts need special handling for x-axis
          scales = {};

          // Configure x-axis for scatter
          if (isLabelDatetime) {
            // Time scale for datetime columns
            const displayFormats = getDisplayFormats(selectedFormat);
            const selectedTimezone = timezoneSelect.value;
            const tzAbbr = moment().tz(selectedTimezone).format('z');
            let axisTitle = labelCol + ' (' + tzAbbr + ')';
            if (dateContextText) {
              axisTitle += ' : ' + dateContextText;
            }
            const timeConfig = {
              displayFormats: displayFormats,
              round: true,
            };

            // Add unit if determined
            if (selectedUnit) {
              timeConfig.unit = selectedUnit;
              timeConfig.minUnit = selectedUnit;
            }

            console.log('Scatter X-axis time config:', timeConfig);

            scales.x = {
              type: 'time',
              adapters: {
                date: {
                  zone: selectedTimezone
                }
              },
              time: timeConfig,
              title: {
                display: true,
                text: axisTitle,
                font: {
                  family: 'ui-monospace, monospace',
                  size: 12,
                  weight: 'bold'
                }
              },
              ticks: {
                source: 'auto',
                autoSkip: true,
                font: {
                  family: 'ui-monospace, monospace',
                  size: 11
                },
                maxRotation: 45,
                minRotation: 45
              }
            };
          } else {
            // Linear scale for scatter x-axis
            scales.x = {
              type: 'linear',
              title: {
                display: true,
                text: labelCol,
                font: {
                  family: 'ui-monospace, monospace',
                  size: 12,
                  weight: 'bold'
                }
              },
              ticks: {
                font: {
                  family: 'ui-monospace, monospace',
                  size: 11
                }
              }
            };
          }

          // Configure y-axis for scatter
          const selectedOptions = Array.from(valueSelect.selectedOptions);
          const valueCols = selectedOptions.map(opt => opt.value);
          const valueAxisLabel = valueCols.length === 1 ? valueCols[0] : 'Value';

          scales.y = {
            type: 'linear',
            title: {
              display: true,
              text: valueAxisLabel,
              font: {
                family: 'ui-monospace, monospace',
                size: 12,
                weight: 'bold'
              }
            },
            ticks: {
              font: {
                family: 'ui-monospace, monospace',
                size: 11
              }
            }
          };
        } else {
          // Determine which axis is for labels (category/time axis)
          const labelAxis = indexAxis === 'x' ? 'x' : 'y';
          const valueAxis = indexAxis === 'x' ? 'y' : 'x';

          scales = {};

          // Configure label axis (x for vertical bar, y for horizontal bar)
          if (isLabelDatetime) {
            // Time scale for datetime columns
            const displayFormats = getDisplayFormats(selectedFormat);
            const selectedTimezone = timezoneSelect.value;
            // Build axis title: label (timezone) : range
            const tzAbbr = moment().tz(selectedTimezone).format('z');
            let axisTitle = labelCol + ' (' + tzAbbr + ')';
            if (dateContextText) {
              axisTitle += ' : ' + dateContextText;
            }
            const timeConfig = {
              displayFormats: displayFormats,
              round: true,
            };

            // Add unit if determined
            if (selectedUnit) {
              timeConfig.unit = selectedUnit;
              timeConfig.minUnit = selectedUnit;
            }

            console.log('Chart time config:', timeConfig);

            scales[labelAxis] = {
              type: 'time',
              adapters: {
                date: {
                  zone: selectedTimezone
                }
              },
              time: timeConfig,
              title: {
                display: true,
                text: axisTitle,
                font: {
                  family: 'ui-monospace, monospace',
                  size: 12,
                  weight: 'bold'
                }
              },
              ticks: {
                source: 'auto',
                autoSkip: true,
                font: {
                  family: 'ui-monospace, monospace',
                  size: 11
                },
                maxRotation: labelAxis === 'x' ? 45 : 0,
                minRotation: labelAxis === 'x' ? 45 : 0
              }
            };
          } else {
            // Regular category scale
            scales[labelAxis] = {
              title: {
                display: true,
                text: labelCol,
                font: {
                  family: 'ui-monospace, monospace',
                  size: 12,
                  weight: 'bold'
                }
              },
              ticks: {
                font: {
                  family: 'ui-monospace, monospace',
                  size: 11
                },
                maxRotation: labelAxis === 'x' ? 45 : 0,
                minRotation: labelAxis === 'x' ? 45 : 0
              }
            };
          }

          // Configure value axis (y for vertical bar, x for horizontal bar)
          const selectedOptions = Array.from(valueSelect.selectedOptions);
          const valueCols = selectedOptions.map(opt => opt.value);
          const valueAxisLabel = valueCols.length === 1 ? valueCols[0] : 'Value';

          scales[valueAxis] = {
            beginAtZero: true,
            title: {
              display: true,
              text: valueAxisLabel,
              font: {
                family: 'ui-monospace, monospace',
                size: 12,
                weight: 'bold'
              }
            },
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
          };
        }

        myChart = new Chart(ctx, {
          type: type,
          data: data,
          options: {
            responsive: true,
            maintainAspectRatio: false,
            indexAxis: indexAxis,
            scales: scales,
            plugins: {
              legend: {
                display: false
              },
              tooltip: {
                enabled: true,
                callbacks: {
                  title: function(context) {
                    if (isLabelDatetime && context.length > 0) {
                      const label = context[0].label;
                      const targetTimezone = timezoneSelect.value;
                      // Label is already in target timezone, just parse and format nicely
                      let m;
                      if (targetTimezone === 'UTC') {
                        m = moment.utc(label, 'YYYY-MM-DD HH:mm:ss');
                      } else {
                        m = moment.tz(label, 'YYYY-MM-DD HH:mm:ss', targetTimezone);
                      }
                      if (m.isValid()) {
                        return m.format('MMM D, YYYY, HH:mm:ss z');
                      }
                    }
                    return context[0].label;
                  }
                }
              }
            }
          }
        });
      }

      // Initialize: default to line chart if many values selected, otherwise bar chart
      const initialChartType = defaultValues.length > 2 ? 'line' : 'bar';
      createChart(initialChartType, 'x');

      // Chart type dropdown event listener
      chartTypeSelect.addEventListener('change', function() {
        const type = this.value;
        createChart(type, currentIndexAxis);
      });

      // Orientation icon event listener
      orientationIcon.addEventListener('click', function() {
        // Toggle between horizontal and vertical
        currentIndexAxis = currentIndexAxis === 'x' ? 'y' : 'x';
        this.textContent = currentIndexAxis === 'x' ? '↔' : '↕';
        this.title = currentIndexAxis === 'x' ? 'Switch to vertical' : 'Switch to horizontal';
        createChart(currentChartType, currentIndexAxis);
      });

      // Column selector event listeners
      labelSelect.addEventListener('change', function() {
        createChart(currentChartType, currentIndexAxis);
      });

      timeFormatSelect.addEventListener('change', function() {
        createChart(currentChartType, currentIndexAxis);
      });

      sourceTimezoneSelect.addEventListener('change', function() {
        createChart(currentChartType, currentIndexAxis);
      });

      timezoneSelect.addEventListener('change', function() {
        createChart(currentChartType, currentIndexAxis);
      });

      timeUnitSelect.addEventListener('change', function() {
        createChart(currentChartType, currentIndexAxis);
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

Samaki::Plugout::ChartJS -- Interactive charts using Chart.js

=head1 DESCRIPTION

Visualize CSV data as interactive charts in the browser. Supports bar, line, scatter, pie, and polar area charts with controls for switching chart types, selecting columns, and adjusting orientation. Datetime columns support timezone conversion and format options.

=end pod
