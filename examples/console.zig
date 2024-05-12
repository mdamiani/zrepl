const std = @import("std");
const io = std.io;
const repl = @import("zrepl");

pub fn main() !void {
    const hist = repl.History{};
    _ = hist;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var term = try repl.Terminal.init(gpa.allocator(), io.getStdIn(), io.getStdOut(), true);
    defer term.deinit();

    try term.do_repl();
}
