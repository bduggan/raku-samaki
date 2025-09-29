use Samaki::Plugout;
use Log::Async;
use Duck::CSV;
use Samaki::Utils;

unit class Samaki::Plugout::DataTable does Samaki::Plugout;

has $.name = 'data-table';
has $.description = 'Make an HTML table with the data and open a browser';
has $.clear-before = False;

method execute(IO::Path :$path!, IO::Path :$data-dir!, Str :$name!) {
  info "executing dataTable with $path";
  my $html-file = $data-dir.child("$name.html");
  my @rows = read-csv("$path");

  my $fh = open :w, $html-file;
  $fh.print: q:to/HTML/;
  <!DOCTYPE html>
  <html>
  <head>
      <title>Data Table</title>
      <link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/1.13.7/css/jquery.dataTables.css">
      <link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/1.13.7/css/dataTables.bootstrap5.min.css">
      <script type="text/javascript" src="https://code.jquery.com/jquery-3.7.0.min.js"></script>
      <script type="text/javascript" src="https://cdn.datatables.net/1.13.7/js/jquery.dataTables.min.js"></script>
      <style>
          body {
              font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
              margin: 20px;
              background-color: #f8f9fa;
              color: #2c3e50;
          }
          .container {
              max-width: 1200px;
              margin: 0 auto;
              padding: 20px;
              background: white;
              border-radius: 4px;
              box-shadow: 0 1px 2px rgba(0,0,0,0.05);
          }
          #dataTable {
              width: 100% !important;
              margin: 0 !important;
              border-collapse: collapse;
              font-size: 12px;
              letter-spacing: -0.2px;
          }
          #dataTable thead th {
              background-color: #f1f5f9;
              color: #2c3e50;
              font-weight: 500;
              padding: 8px 6px !important;
              border-bottom: 1px solid #e2e8f0;
          }
          #dataTable thead th:first-child,
          #dataTable tbody td:first-child {
              background-color: #f8fafc;
              color: #64748b;
              text-align: right;
              padding-right: 8px !important;
              border-right: 1px solid #f1f5f9;
              font-size: 11px;
          }
          #dataTable tbody td {
              padding: 4px 6px !important;
              border-bottom: 1px solid #f1f5f9;
              position: relative;
              line-height: 1.3;
              vertical-align: top;
          }
          #dataTable tbody td > div {
              position: relative;
              white-space: normal;
              word-wrap: break-word;
              word-break: normal;
          }
          #dataTable tbody td.collapsed > div {
              max-height: 45px;
              overflow: hidden;
              display: block;
          }
          #dataTable tbody tr:hover {
              background-color: #fafbfc;
          }
          .expand-btn {
              position: absolute;
              bottom: 2px;
              right: 2px;
              background: #e2e8f0;
              color: #475569;
              border: none;
              border-radius: 2px;
              width: 16px;
              height: 16px;
              line-height: 16px;
              text-align: center;
              cursor: pointer;
              font-size: 10px;
              opacity: 0.8;
              display: none;
          }
          .expand-btn:hover {
              opacity: 1;
              background: #cbd5e1;
          }
          td:hover .expand-btn {
              display: block;
          }
          .dataTables_wrapper {
              font-size: 12px;
          }
          .dataTables_wrapper .dataTables_length,
          .dataTables_wrapper .dataTables_filter {
              margin-bottom: 12px;
          }
          .dataTables_wrapper .dataTables_filter input {
              border: 1px solid #e2e8f0;
              border-radius: 3px;
              padding: 3px 6px;
              font-family: inherit;
              font-size: inherit;
          }
          .dataTables_wrapper .dataTables_paginate .paginate_button.current {
              background: #f1f5f9 !important;
              color: #2c3e50 !important;
              border: 1px solid #e2e8f0 !important;
              font-weight: 500;
          }
          .dataTables_wrapper .dataTables_paginate .paginate_button:hover {
              background: #f8fafc !important;
              color: #2c3e50 !important;
              border: 1px solid #e2e8f0 !important;
          }
      </style>
  </head>
  <body>
        <div class="container">
  HTML

  my $title = $data-dir.basename;
  $fh.print: "<h2>{html-escape($title)} : {$name}</h2>\n";

  $fh.print: q:to/HTML/;
          <table id="dataTable" class="display">
  HTML

  my @hdr = @rows[0].keys.sort;

  $fh.print: "<thead><tr><th style='width:30px'>#</th>";
  for @hdr -> $col {
    $fh.print: "<th>{html-escape($col)}</th>";
  }
  $fh.print: "</tr></thead>\n";
  
  $fh.print: "<tbody>\n";
  for @rows -> $row {
    $fh.put: "<tr><td></td>";
    for @hdr -> $col {
      my $val = $row{$col} // '';
      $fh.put: "<td>{html-escape($val)}</td>";
    }
    $fh.print: "</tr>\n";
  }
  $fh.print: "</tbody>\n";

  $fh.print: q:to/HTML/;
          </table>
      </div>
      <script>
          $(document).ready(function() {
              // Initialize DataTable
              $('#dataTable').DataTable({
                  "rowNumbers": true,
                  "columnDefs": [{
                      "targets": 0,
                      "data": null,
                      "render": function (data, type, row, meta) {
                          return meta.row + 1;
                      },
                      "width": "30px",
                      "orderable": false
                  }, {
                      "targets": [1, "_all"],
                      "width": "150px",
                      "render": function(data, type, row) {
                          if (type === 'display') {
                              return data.split(',').join(', ');
                          }
                          return data;
                      }
                  }],
                  "drawCallback": function() {
                      // After table is drawn/redrawn
                      $('td').each(function() {
                          const $td = $(this);
                          
                          // Wrap content in div if not already wrapped
                          if (!$td.find('> div').length) {
                              const content = $td.html();
                              $td.html(`<div>${content}</div>`);
                          }
                          
                          const $content = $td.find('> div');
                          const contentHeight = $content.height();
                          
                          // Only add expand button if content exceeds max height
                          if (contentHeight > 45) {
                              $td.addClass('collapsed');
                              if (!$td.find('.expand-btn').length) {
                                  const $btn = $('<button class="expand-btn">+</button>');
                                  $td.append($btn);
                                  
                                  $btn.on('click', function(e) {
                                      e.stopPropagation();
                                      const isCollapsed = $td.hasClass('collapsed');
                                      if (isCollapsed) {
                                          $td.removeClass('collapsed');
                                          $(this).text('-');
                                      } else {
                                          $td.addClass('collapsed');
                                          $(this).text('+');
                                      }
                                  });
                              }
                          }
                      });
                  }
              });
          });
      </script>
  </body>
  </html>
  HTML

  $fh.close;

  info "opening $html-file";
  shell-open $html-file;
}
