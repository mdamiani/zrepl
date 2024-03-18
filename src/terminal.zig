const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const fs = std.fs;
const time = std.time;
const ascii = std.ascii;
const term =
    switch (builtin.os.tag) {
    .windows => @import("terminal_win.zig"),
    .linux, .macos => @import("terminal_posix.zig"),
    else => @compileError("TTY is not supported for this platform"),
};

pub fn do_repl() !void {
    try term.console();
}
