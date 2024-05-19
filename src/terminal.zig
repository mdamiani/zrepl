const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const fs = std.fs;
const time = std.time;
const ascii = std.ascii;
const Allocator = std.mem.Allocator;

const ConsoleImpl =
    switch (builtin.os.tag) {
    .windows => @import("terminal_win.zig"),
    .linux, .macos => @import("terminal_posix.zig"),
    else => @compileError("TTY is not supported for this platform"),
};

const Self = @This();

allocator: std.mem.Allocator,
stdin: fs.File = undefined,
stdout: fs.File = undefined,
ctrlc: bool,

impl: ConsoleImpl = undefined,

pub fn init(allocator: Allocator, stdin: fs.File, stdout: fs.File, ctrlc: bool) !Self {
    var self = Self{
        .allocator = allocator,
        .stdin = stdin,
        .stdout = stdout,
        .ctrlc = ctrlc,
        .impl = ConsoleImpl{},
    };

    if (stdin.isTty()) {
        try self.impl.consoleStdinInit(stdin);
    }
    errdefer if (stdin.isTty()) {
        self.impl.consoleStdinDeinit(stdin) catch |err| {
            std.log.warn("could not restore console stdin: {!}\n", .{err});
        };
    };

    if (stdout.isTty()) {
        try self.impl.consoleStdoutInit(stdout);
    }
    errdefer if (stdout.isTty()) {
        self.impl.consoleStdoutDeinit(stdout) catch |err| {
            std.log.warn("could not restore console stdout: {!}\n", .{err});
        };
    };

    if (ctrlc) {
        try self.impl.consoleCtrlcInit();
    }

    return self;
}

pub fn deinit(self: *Self) void {
    if (self.stdin.isTty()) {
        self.impl.consoleStdinDeinit(self.stdin) catch |err| {
            std.log.warn("could not restore console stdin: {!}\n", .{err});
        };
    }
    if (self.stdout.isTty()) {
        self.impl.consoleStdoutDeinit(self.stdout) catch |err| {
            std.log.warn("could not restore console stdout: {!}\n", .{err});
        };
    }
    if (self.ctrlc) {
        self.impl.consoleCtrlcDeinit() catch |err| {
            std.log.warn("could not restore ctrl-c handler: {!}\n", .{err});
        };
    }
}

pub fn do_repl(self: *Self) !void {
    if (self.stdin.isTty()) {
        const ctrlcFileR = std.fs.File{ .handle = self.impl.ctrlcFdR };
        var line = std.ArrayList(u8).init(self.allocator);
        defer line.deinit();

        std.debug.print("> ", .{});
        while (true) {
            const c = try ConsoleImpl.readChar(self.allocator, self.stdin, ctrlcFileR);
            switch (c) {
                '\n' => {
                    std.debug.print("\n: {s}\n", .{line.items});
                    std.debug.print("> ", .{});
                    line.clearAndFree();
                },
                ascii.control_code.bs, ascii.control_code.del => {
                    if (line.popOrNull()) |_| {
                        std.debug.print("{c} {c}", .{
                            ascii.control_code.bs,
                            ascii.control_code.bs,
                        });
                    }
                },
                else => {
                    try line.append(c);
                    std.debug.print("{c}", .{c});
                },
            }
        }
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
