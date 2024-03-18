const std = @import("std");
const repl = @import("zrepl");

pub fn main() !void {
    var hist = repl.History{};
    _ = hist;
    var term = repl.Terminal{};
    _ = term;

    try repl.Terminal.do_repl();
}
