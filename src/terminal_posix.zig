const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const fs = std.fs;
const time = std.time;
const ascii = std.ascii;
const Allocator = std.mem.Allocator;

const Self = @This();

const OldMode = struct {
    termStdin: posix.termios,
    termStdout: posix.termios,
    sigState: posix.Sigaction,
};

var ctrlcFdW: posix.fd_t = undefined;
ctrlcFdR: posix.fd_t = undefined,
oldMode: OldMode = undefined,

fn handler_ctrlc(sig: i32, info: *const posix.siginfo_t, ctx_ptr: ?*const anyopaque) callconv(.C) void {
    _ = ctx_ptr;
    _ = info;
    _ = sig;
    const n = posix.write(ctrlcFdW, &[1]u8{'1'}) catch |err| {
        std.log.err("could not notify CTRL-C signal: {!}, aborting...\n", .{err});
        posix.abort();
    };
    if (n != 1) {
        std.log.err("could not notify CTRL-C signal: invalid write, aborting...\n", .{});
        posix.abort();
    }
}

pub fn consoleCtrlcInit(self: *Self) !void {
    self.ctrlcFdR, ctrlcFdW = try posix.pipe();

    var sa = posix.Sigaction{
        .handler = .{ .sigaction = &handler_ctrlc },
        .mask = posix.empty_sigset,
        .flags = posix.SA.SIGINFO,
    };
    try posix.sigaction(posix.SIG.INT, &sa, &self.oldMode.sigState);
}

pub fn consoleCtrlcDeinit(self: *Self) !void {
    try posix.sigaction(posix.SIG.INT, &self.oldMode.sigState, null);

    posix.close(ctrlcFdW);
    posix.close(self.ctrlcFdR);
}

pub fn consoleStdinInit(self: *Self, stdin: fs.File) !void {
    self.oldMode.termStdin = try posix.tcgetattr(stdin.handle);
    var termios = self.oldMode.termStdin;
    termios.lflag.ECHO = false;
    termios.lflag.ECHONL = false;
    termios.lflag.ICANON = false;
    termios.lflag.IEXTEN = false;
    termios.lflag.ISIG = true;
    try posix.tcsetattr(stdin.handle, posix.TCSA.NOW, termios);
}

pub fn consoleStdinDeinit(self: *Self, stdin: fs.File) !void {
    try posix.tcsetattr(stdin.handle, posix.TCSA.NOW, self.oldMode.termStdin);
}

pub fn consoleStdoutInit(self: *Self, stdout: fs.File) !void {
    _ = self;
    _ = stdout;
}

pub fn consoleStdoutDeinit(self: *Self, stdout: fs.File) !void {
    _ = self;
    _ = stdout;
}

pub fn readChar(allocator: Allocator, stdin: fs.File, ctrlc: fs.File) !u8 {
    var poller = std.io.poll(allocator, enum { stdin, ctrlc }, .{
        .stdin = stdin,
        .ctrlc = ctrlc,
    });
    defer poller.deinit();

    const pollStdin = poller.fifo(.stdin);
    const pollCtrlc = poller.fifo(.ctrlc);

    while (true) {
        if (!(try poller.poll())) {
            continue;
        }

        if (pollCtrlc.readableLength() > 0) {
            return error.SigInt;
        } else if (pollStdin.readableLength() > 0) {
            const c: u8 = pollStdin.readItem() orelse 0;
            return c;
        } else {
            unreachable;
        }
    }
}
