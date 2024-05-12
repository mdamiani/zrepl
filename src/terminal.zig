const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const fs = std.fs;
const time = std.time;
const ascii = std.ascii;
const Allocator = std.mem.Allocator;

const term =
    switch (builtin.os.tag) {
    .windows => @import("terminal_win.zig"),
    .linux, .macos => @import("terminal_posix.zig"),
    else => @compileError("TTY is not supported for this platform"),
};

const Self = @This();

const OldMode = struct {
    termStdin: term.TermState,
    termStdout: term.TermState,
    sigState: term.SigState,
};

allocator: std.mem.Allocator,
stdin: fs.File = undefined,
stdout: fs.File = undefined,
ctrlc: bool,

oldMode: OldMode = undefined,

pub fn init(allocator: Allocator, stdin: fs.File, stdout: fs.File, ctrlc: bool) !Self {
    var self = Self{
        .allocator = allocator,
        .stdin = stdin,
        .stdout = stdout,
        .ctrlc = ctrlc,
    };

    if (stdin.isTty()) {
        self.oldMode.termStdin = try term.consoleStdinInit(stdin);
    }
    errdefer if (stdin.isTty()) {
        term.consoleStdinDeinit(stdin, self.oldMode.termStdin) catch |err| {
            std.log.warn("could not restore console stdin: {!}\n", .{err});
        };
    };

    if (stdout.isTty()) {
        self.oldMode.termStdout = try term.consoleStdoutInit(stdout);
    }
    errdefer if (stdout.isTty()) {
        term.consoleStoudDeinit(stdout, self.oldMode.termStdout) catch |err| {
            std.log.warn("could not restore console stdout: {!}\n", .{err});
        };
    };

    if (ctrlc) {
        self.oldMode.sigState = try term.consoleCtrlcInit();
    }

    return self;
}

pub fn deinit(self: Self) void {
    if (self.stdin.isTty()) {
        term.consoleStdinDeinit(self.stdin, self.oldMode.termStdin) catch |err| {
            std.log.warn("could not restore console stdin: {!}\n", .{err});
        };
    }
    if (self.stdout.isTty()) {
        term.consoleStdinDeinit(self.stdout, self.oldMode.termStdout) catch |err| {
            std.log.warn("could not restore console stdout: {!}\n", .{err});
        };
    }
    if (self.ctrlc) {
        term.consoleCtrlcDeinit(self.oldMode.sigState) catch |err| {
            std.log.warn("could not restore ctrl-c handler: {!}\n", .{err});
        };
    }
}

pub fn do_repl(self: Self) !void {
    if (self.stdin.isTty()) {
        try term.console(self.allocator, self.stdin);
    } else {
        try self.consume_stdin();
    }
}

fn consume_stdin(self: Self) !void {
    var stdin_buffered_reader = std.io.bufferedReader(self.stdin.reader());
    var stdin_stream = stdin_buffered_reader.reader();

    const input = stdin_stream.readUntilDelimiterOrEofAlloc(
        self.allocator,
        ';',
        std.math.maxInt(usize),
    ) catch |err| {
        return err;
    } orelse {
        // EOF.
        return;
    };

    // parse input
    _ = input;
}
