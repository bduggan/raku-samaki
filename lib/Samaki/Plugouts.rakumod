unit class Samaki::Plugouts;
use Samaki::Conf;
use Log::Async;
use Terminal::ANSI::OO 't';

has @.rules;

method configure(Samaki::Conf $conf) {
  @.rules = $conf.plugouts;
}

method dispatch(
     IO::Path $path!,
    :$pane,
    :$data-dir = $path.dirname.IO,
    :$name!, #= cell name
    Str :$plugout_name,
    Str :$cell-content,
    :@cell-conf,
  ) {
  my @handlers;
  for @.rules -> %entry {
    next if $plugout_name && %entry<handler>.name ne $plugout_name;
    my $regex := %entry<regex>;
    if $path.Str ~~ /$regex/ {
      my $handler = %entry<handler>;
      @handlers.push: $handler;
      
    }
  }
  unless @handlers {
    $pane.put: "No plugout handler matched for $path";
    $pane.put: "Available plugout handlers:";
    for @.rules -> %entry {
      $pane.put: " - {%entry<regex>.raku} --> {%entry<handler-class>}";
    }
  }
  unless @handlers {
    $pane.put: "No plugouts matched for $path";
    return;
  }
  my $handler = @handlers[0];
  $pane.clear if $handler.clear-before;
  $pane.put: "Matched plugout handler {$handler.name} for $path";
  for @handlers[1..*] {
    $pane.put: [ t.color(%COLORS<button>) => '[' ~ .name ~ ']' ], meta => %( action => 'do_output', plugout_name => .name, :$path );
  }
  try {
   $handler.pane = $pane;
   $handler.execute(:$path, :$pane, :$data-dir, :$name, :$cell-content, :@cell-conf);
   $pane.select(0) if $handler.clear-before;
   CATCH {
     default {
       $pane.put: "Error executing plugout handler: $_";
       error "Error executing plugout handler: $_";
       for Backtrace.new.Str.lines {
          error "--> $_";
        }
    }
   }
  }
}

method list-all {
  return @.rules.map: {
    %(
      regex => .<regex>,
      name => .<handler>.name,
      desc => .<handler>.description
    )
  }
}

