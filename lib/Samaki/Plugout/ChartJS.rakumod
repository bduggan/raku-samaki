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

  my $html-file = $data-dir.child("{$name}-chartjs.html");

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
      .column-selector select[multiple] {
        min-height: 60px;
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
        <button id="btn-bar">Bar</button>
        <button id="btn-line">Line</button>
        <button id="btn-scatter">Scatter</button>
        <button id="btn-pie">Pie Chart</button>
        <button id="btn-polar">Polar Area</button>
        <button id="btn-orientation">↔ Horizontal</button>
        <div class="column-selector">
          <label>Label:</label>
          <select id="label-column"></select>
        </div>
        <div class="column-selector">
          <label>Values:</label>
          <select id="value-column" multiple></select>
        </div>
        <div class="column-selector" id="time-format-selector" style="display: none;">
          <label>Date Format:</label>
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
        </div>
        <div class="column-selector" id="source-timezone-selector" style="display: none;">
          <label>Source TZ:</label>
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
        </div>
        <div class="column-selector" id="timezone-selector" style="display: none;">
          <label>Display TZ:</label>
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
        </div>
      </div>
      <div class="chart-container">
        <canvas id="myChart"></canvas>
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

      // Set initial chart type based on number of default values
      let currentChartType = defaultValues.length > 2 ? 'line' : 'bar';

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
        // Select all columns in defaultValues array by default
        if (defaultValues.includes(col)) {
          option2.selected = true;
        }
        valueSelect.appendChild(option2);
      });

      // Set default label selection
      labelSelect.value = '$default-label';

      console.log('=== ChartJS Debug ===');
      console.log('All Data:', allData);
      console.log('All Columns:', columns);
      console.log('Numeric Columns:', numericColumns);
      console.log('Datetime Columns:', datetimeColumns);
      console.log('Default Label:', '$default-label');
      console.log('Default Values:', defaultValues);

      const timeFormatSelect = document.getElementById('time-format');
      const timeFormatSelector = document.getElementById('time-format-selector');
      const sourceTimezoneSelect = document.getElementById('source-timezone');
      const sourceTimezoneSelector = document.getElementById('source-timezone-selector');
      const timezoneSelect = document.getElementById('timezone');
      const timezoneSelector = document.getElementById('timezone-selector');

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
            millisecond: 'MMM d, HH:mm:ss',
            second: 'MMM d, HH:mm:ss',
            minute: 'MMM d, HH:mm',
            hour: 'MMM d, HH:mm',
            day: 'MMM d, HH:mm',
            week: 'MMM d',
            month: 'MMM yyyy',
            quarter: 'MMM yyyy',
            year: 'yyyy'
          },
          'date-time-seconds': {
            millisecond: 'MMM d, HH:mm:ss.SSS',
            second: 'MMM d, HH:mm:ss',
            minute: 'MMM d, HH:mm:ss',
            hour: 'MMM d, HH:mm:ss',
            day: 'MMM d, HH:mm:ss',
            week: 'MMM d, HH:mm:ss',
            month: 'MMM yyyy',
            quarter: 'MMM yyyy',
            year: 'yyyy'
          },
          'date-only': {
            millisecond: 'MMM d, yyyy',
            second: 'MMM d, yyyy',
            minute: 'MMM d, yyyy',
            hour: 'MMM d, yyyy',
            day: 'MMM d, yyyy',
            week: 'MMM d, yyyy',
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
        const minDate = dates[0];
        const maxDate = dates[dates.length - 1];
        const rangeMs = maxDate - minDate;
        const rangeDays = rangeMs / (1000 * 60 * 60 * 24);
        const numPoints = dates.length;

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
          allSameDay,
          recommendedFormat
        });

        return {
          recommendedFormat,
          dateContextText,
          minDate,
          maxDate,
          allSameDay
        };
      }

      function getChartData(isScatter = false) {
        const labelCol = labelSelect.value;
        const selectedOptions = Array.from(valueSelect.selectedOptions);
        const valueCols = selectedOptions.map(opt => opt.value);

        if (valueCols.length === 0) {
          console.warn('No value columns selected');
          return { labels: [], datasets: [] };
        }

        console.log('Getting chart data for label="' + labelCol + '" values=' + JSON.stringify(valueCols) + ' scatter=' + isScatter);

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

        console.log('Labels:', labels);
        console.log('Datasets:', datasets.length);

        return {
          labels: labels,
          datasets: datasets
        };
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

        // Check if label column is datetime
        const labelCol = labelSelect.value;
        const isLabelDatetime = datetimeColumns.includes(labelCol);
        console.log('Label column "' + labelCol + '" is datetime:', isLabelDatetime);

        // Analyze time range and update UI for datetime labels
        let timeAnalysis = null;
        let selectedFormat = 'date-time'; // default
        let dateContextText = '';
        if (isLabelDatetime) {
          timeAnalysis = analyzeTimeRange(labelCol);
          timeFormatSelector.style.display = 'flex';
          sourceTimezoneSelector.style.display = 'flex';
          timezoneSelector.style.display = 'flex';

          // Determine which format to use
          if (timeFormatSelect.value === 'auto') {
            selectedFormat = timeAnalysis.recommendedFormat;
          } else {
            selectedFormat = timeFormatSelect.value;
          }

          // Save date context text for axis title
          dateContextText = timeAnalysis.dateContextText || '';
        } else {
          timeFormatSelector.style.display = 'none';
          sourceTimezoneSelector.style.display = 'none';
          timezoneSelector.style.display = 'none';
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
            scales.x = {
              type: 'time',
              adapters: {
                date: {
                  zone: selectedTimezone
                }
              },
              time: {
                displayFormats: displayFormats,
              },
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
            scales[labelAxis] = {
              type: 'time',
              adapters: {
                date: {
                  zone: selectedTimezone
                }
              },
              time: {
                displayFormats: displayFormats,
              },
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
                display: true,
                position: isRadial ? 'right' : 'top',
                labels: {
                  font: {
                    family: 'ui-monospace, monospace',
                    size: 12
                  }
                }
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

      // Set the initial active button
      if (initialChartType === 'line') {
        setActiveButton(document.getElementById('btn-line'));
      } else {
        setActiveButton(document.getElementById('btn-bar'));
      }

      // Button event listeners
      document.getElementById('btn-bar').addEventListener('click', function() {
        createChart('bar', currentIndexAxis);
        setActiveButton(this);
      });

      document.getElementById('btn-orientation').addEventListener('click', function() {
        // Toggle between horizontal and vertical
        currentIndexAxis = currentIndexAxis === 'x' ? 'y' : 'x';
        this.textContent = currentIndexAxis === 'x' ? '↔ Horizontal' : '↕ Vertical';
        createChart(currentChartType, currentIndexAxis);
      });

      document.getElementById('btn-line').addEventListener('click', function() {
        createChart('line', 'x');
        setActiveButton(this);
      });

      document.getElementById('btn-scatter').addEventListener('click', function() {
        createChart('scatter', 'x');
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

      timeFormatSelect.addEventListener('change', function() {
        createChart(currentChartType, currentIndexAxis);
      });

      sourceTimezoneSelect.addEventListener('change', function() {
        createChart(currentChartType, currentIndexAxis);
      });

      timezoneSelect.addEventListener('change', function() {
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

=begin pod

=head1 NAME

Samaki::Plugout::ChartJS -- Interactive charts using Chart.js

=head1 DESCRIPTION

Visualize CSV data as interactive charts in the browser. Supports bar, line, scatter, pie, and polar area charts with controls for switching chart types, selecting columns, and adjusting orientation. Datetime columns support timezone conversion and format options.

=end pod
