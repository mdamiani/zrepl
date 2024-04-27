const std = @import("std");
const io = std.io;
const repl = @import("zrepl");

pub fn main() !void {
    var hist = repl.History{};
    _ = hist;

    var term = try repl.Terminal.init(io.getStdIn(), io.getStdOut());
    try term.do_repl();
}
