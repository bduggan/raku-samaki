unit module helpers;

# Mock pane for testing REPL plugins
class MockPane is export {
  has @.output;
  method put(*@args) { @.output.push: @args.join }
  method clear() { @.output = () }
  method lines() { @.output }
  method height() { 24 }
  method width() { 80 }
  method stream($supply) {
    start react whenever $supply -> $chunk {
      @.output.push: $chunk.decode;
    }
  }
  method enable-selection() { }
}
