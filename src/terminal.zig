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

const Self = @This();

stdin: fs.File = undefined,
stdout: fs.File = undefined,

oldModeStdin: u32 = undefined,
oldModeStdout: u32 = undefined,

pub fn init(stdin: fs.File, stdout: fs.File) !Self {
    var self = Self{
        .stdin = stdin,
        .stdout = stdout,
    };
    if (stdin.isTty()) {
        self.oldModeStdin = try term.consoleInitStdin(stdin);
    }
    if (stdout.isTty()) {
        self.oldModeStdout = try term.consoleInitStdout(stdout);
    }
    return self;
}

pub fn deinit(self: Self) void {
    if (self.stdin.isTty()) {
        term.consoleDeinit(self.stdin, self.oldModeStdin);
    }
    if (self.stdout.isTty()) {
        term.consoleDeinit(self.stdout, self.oldModeStdout);
    }
}

pub fn do_repl(self: Self) !void {
    try term.console(self.stdin);
}
