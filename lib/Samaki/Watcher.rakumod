unit class Samaki::Watcher;
use Log::Async;

has &.on-change;
has $.page is required;
has $.promise;

method start {
  IO::Notification.watch-path( $.page.wkdir ).tap(
    -> $change {
      if $change.path.IO.absolute eq $.page.path.IO.absolute {
        info $change.gist ~ ' event';
        &.on-change()( $.page ) 
      }
    }
  )
}
