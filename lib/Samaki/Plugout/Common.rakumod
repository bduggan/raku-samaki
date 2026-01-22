use Log::Async;

unit role Samaki::Plugout::Common;

method debug($msg) {
    debug($msg) if %*ENV<SAMAKI_DEBUG>;
}

method timezone-detection-js() {
    return Q:to/JS/;
      // Rebuild timezone dropdowns with offsets and abbreviations
      function rebuildTimezoneDropdown(selectElement) {
        // Get all original timezone values
        const allTimezones = Array.from(selectElement.options).map(opt => opt.value);

        // Group by offset
        const offsetGroups = {};
        allTimezones.forEach(tz => {
          const m = moment.tz(tz);
          const offset = m.utcOffset();
          const abbr = m.format('z');

          if (!offsetGroups[offset]) {
            offsetGroups[offset] = {
              timezones: [],
              abbrs: new Set()
            };
          }
          offsetGroups[offset].timezones.push(tz);
          offsetGroups[offset].abbrs.add(abbr);
        });

        // Sort by offset
        const sortedOffsets = Object.keys(offsetGroups).map(Number).sort((a, b) => b - a);

        // Clear and rebuild dropdown
        selectElement.innerHTML = '';

        sortedOffsets.forEach(offset => {
          const group = offsetGroups[offset];
          const firstTz = group.timezones[0];
          const hours = Math.floor(Math.abs(offset) / 60);
          const minutes = Math.abs(offset) % 60;
          const sign = offset >= 0 ? '+' : '-';
          const offsetStr = sign + String(hours).padStart(2, '0') + (minutes > 0 ? ':' + String(minutes).padStart(2, '0') : '');

          // Combine abbreviations
          const abbrStr = Array.from(group.abbrs).join('/');

          // Create option with format: "+01 CET/CEST (Europe/Paris)"
          const option = document.createElement('option');
          option.value = firstTz;
          option.textContent = offsetStr + ' ' + abbrStr + ' (' + firstTz + ')';
          selectElement.appendChild(option);
        });
      }

      rebuildTimezoneDropdown(sourceTimezoneSelect);
      rebuildTimezoneDropdown(timezoneSelect);

      // Set destination timezone to browser's timezone
      const browserTimezone = moment.tz.guess();
      if (browserTimezone) {
        // Find the option that contains this timezone
        Array.from(timezoneSelect.options).some(option => {
          if (option.value === browserTimezone) {
            timezoneSelect.value = browserTimezone;
            console.log('Set destination timezone to browser timezone:', browserTimezone);
            return true;
          }
        });
      }

      // Detect and set default source timezone from data using moment
      if (datetimeColumns.length > 0 && allData.length > 0) {
        const firstDatetimeCol = datetimeColumns[0];
        const firstValue = allData[0][firstDatetimeCol];
        if (firstValue) {
          // Use moment.parseZone to preserve the original timezone offset
          const m = moment.parseZone(firstValue);
          if (m.isValid()) {
            const offset = m.utcOffset();
            console.log('Detected offset from data:', offset, 'minutes');

            // Try to find a timezone in our dropdown that matches this offset at this date/time
            const availableTimezones = Array.from(sourceTimezoneSelect.options).map(opt => opt.value);
            let foundMatch = false;

            for (const tz of availableTimezones) {
              // Check what offset this timezone has at the parsed date/time
              const tzOffset = moment.tz(m.format('YYYY-MM-DD HH:mm:ss'), tz).utcOffset();
              if (tzOffset === offset) {
                sourceTimezoneSelect.value = tz;
                console.log('Detected timezone from data:', tz, '(offset =', offset, 'minutes)');
                foundMatch = true;
                break;
              }
            }

            if (!foundMatch) {
              console.log('No matching timezone found in dropdown for offset', offset);
            }
          }
        }
      }
    JS
}

method detect-columns(@columns, @rows, :@column-types) {
  # DuckDB numeric types:
  # Integer types: TINYINT SMALLINT INTEGER BIGINT UTINYINT USMALLINT UINTEGER UBIGINT HUGEINT UHUGEINT
  # Float types: FLOAT DOUBLE DECIMAL

  # Strategy: Score columns based on cardinality and DuckDB data types
  # Label column: prefer low cardinality non-numeric columns
  # Value column: MUST be numeric, prefer integers, avoid floats and ID-like columns
  # Only column name pattern used: avoid columns ending in _id

  my %type-map;
  for @columns Z @column-types -> ($col, $type) {
    %type-map{$col} = $type;
  }

  my %col-info;

  for @columns -> $col {
    my @values = @rows.map({ $_{ $col } }).grep: *.defined;
    next unless @values;

    my $cardinality = @values.unique.elems;
    my $total = @values.elems;

    # Analyze column name patterns - only check for _id suffix
    my $col-lc = $col.lc;
    my $name-is-id = $col-lc ~~ /_id$/;

    # Use DuckDB type information
    my $type = %type-map{$col} // 'VARCHAR';
    my $is-integer = $type ~~ /^ [ TINYINT | SMALLINT | INTEGER | BIGINT | UTINYINT | USMALLINT | UINTEGER | UBIGINT | HUGEINT | UHUGEINT ] $/;
    my $is-float = $type ~~ /^ [ FLOAT | DOUBLE | DECIMAL ] $/;
    my $is-numeric = $is-integer || $is-float;
    my $is-datetime = $type ~~ /^ [ DATE | TIME | TIMESTAMP ] /;

    # Check if looks like an ID (all unique values)
    my $looks-like-id = $is-numeric && ($cardinality == $total);

    %col-info{ $col } = {
      cardinality => $cardinality,
      is-numeric => $is-numeric,
      is-integer => $is-integer,
      is-float => $is-float,
      is-datetime => $is-datetime,
      looks-like-id => $looks-like-id,
      name-is-id => $name-is-id,
      type => $type,
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

    # Penalize single-value columns (useless as labels)
    $score += 1000 if $info<cardinality> == 1;

    # Column name patterns
    $score += 2000 if $info<name-is-id>;      # Never select _id columns

    # Data type penalties
    $score += 1500 if $info<looks-like-id>;     # Strongly avoid ID-like data
    $score += 600 if $info<is-float>;         # Avoid floats
    $score -= 100 if !$info<is-numeric>;      # Prefer non-numeric

    %label-scores{ $col } = $score;
  }

  # Score columns for value selection - ONLY numeric columns allowed (excluding datetime)
  # Exclude columns ending in _id or ID
  # Lower score is better
  # Prefer HIGH cardinality columns (amounts, distances, etc.)
  my %value-scores;
  my @numeric-columns = @valid-columns.grep({
    my $col-lc = $_.lc;
    %col-info{ $_ }<is-numeric> &&
    !%col-info{ $_ }<is-datetime> &&
    $col-lc !~~ /_id$/ &&
    $col-lc !~~ /id$/
  });

  for @numeric-columns -> $col {
    my $info = %col-info{ $col };
    my $cardinality = $info<cardinality>.Numeric;
    my $total = @rows.elems;

    # Start with negative cardinality (high cardinality = low score = better)
    my $score = -$cardinality;

    # Strong penalties for ID-like data (all values unique)
    $score += 5000 if $info<looks-like-id>;

    # Penalize very low cardinality (e.g., passenger_count with values 1,2,3,4)
    # These are categorical-like and not good default values
    $score += 2000 if $cardinality < 10;

    %value-scores{ $col } = $score;
  }

  # Score columns for dimension selection
  # Lower score = better dimension candidate
  my %dimension-scores;
  for @valid-columns -> $col {
    my $info = %col-info{ $col };
    my $cardinality = $info<cardinality>.Numeric;
    my $score = 0;

    # Ideal cardinality: 2-50 unique values
    if $cardinality < 2 {
      $score += 10000;  # Single value = useless
    } elsif $cardinality > 50 {
      $score += ($cardinality - 50) * 100;  # Penalize high cardinality
    } else {
      $score = $cardinality;  # Sweet spot
    }

    # Strong preference for _id columns (but not pure IDs)
    if $info<name-is-id> && !$info<looks-like-id> {
      $score -= 1000;  # thing_id, product_id → highly preferred
    }

    # Avoid pure IDs and datetime columns
    $score += 5000 if $info<looks-like-id>;
    $score += 3000 if $info<is-datetime>;

    # Slightly prefer integers
    $score -= 50 if $info<is-integer>;

    %dimension-scores{ $col } = $score;
  }

  # Get list of datetime columns
  my @datetime-columns = @valid-columns.grep({ %col-info{ $_ }<is-datetime> });

  # Debug output
  self.debug: "=== Column Detection Debug ===";
  self.debug: "Numeric columns only: " ~ @numeric-columns.join(', ');
  self.debug: "Datetime columns only: " ~ @datetime-columns.join(', ');
  for @valid-columns -> $col {
    my $info = %col-info{ $col };
    self.debug: "Column: $col";
    self.debug: "  DuckDB Type: {$info<type> // 'N/A'}";
    self.debug: "  Cardinality: {$info<cardinality> // 'N/A'}";
    self.debug: "  Is Numeric: {$info<is-numeric> // False}";
    self.debug: "  Is Integer: {$info<is-integer> // False}";
    self.debug: "  Is Float: {$info<is-float> // False}";
    self.debug: "  Is Datetime: {$info<is-datetime> // False}";
    self.debug: "  Looks Like ID: {$info<looks-like-id> // False}";
    self.debug: "  Name ends _id: {$info<name-is-id> // False}";
    self.debug: "  Label Score: {%label-scores{ $col } // 'N/A'}";
    self.debug: "  Value Score: {%value-scores{ $col } // 'N/A'}";
    self.debug: "  Dimension Score: {%dimension-scores{ $col } // 'N/A'}";
  }

  # Select best label and value columns
  my $label-col = @valid-columns.sort({ %label-scores{ $_ } })[0];

  # Select multiple high-cardinality value columns (top 3-4 with good scores)
  # Value columns must be numeric and different from label
  my @sorted-values = @numeric-columns.grep({ $_ ne $label-col }).sort({ %value-scores{ $_ } });

  # Take top columns with negative scores (high cardinality) or at least the best one
  my @default-values = @sorted-values.grep({ %value-scores{ $_ } < 0 }).head(4);
  @default-values = @sorted-values.head(1) unless @default-values;  # Fallback: take best one

  # Legacy single value for backwards compatibility
  my $value-col = @default-values[0] // @numeric-columns[0] // $label-col;

  # Select top 1-2 dimension candidates (exclude label and value columns)
  my @sorted-dimensions = @valid-columns
    .grep({ $_ ne $label-col && $_ ∉ @default-values })
    .sort({ %dimension-scores{ $_ } });

  my @default-dimensions = @sorted-dimensions
    .grep({ %dimension-scores{ $_ } < 100 })
    .head(2);

  self.debug: "Selected Label: $label-col";
  self.debug: "Selected Values (default): " ~ @default-values.join(', ');
  self.debug: "Selected Value (legacy): $value-col";
  self.debug: "Selected Dimensions (default): " ~ @default-dimensions.join(', ');
  self.debug: "=== End Debug ===";

  return {
    label => $label-col,
    value => $value-col,
    values => @default-values,  # Multiple default values
    numeric => @numeric-columns,
    datetime => @datetime-columns,
    dimensions => @default-dimensions,
  };
}

