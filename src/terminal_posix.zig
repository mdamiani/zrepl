const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const posix = std.posix;
const fs = std.fs;
const time = std.time;
const ascii = std.ascii;
const Allocator = std.mem.Allocator;

pub const SigState = posix.Sigaction;
pub const TermState = posix.termios;

fn handler_ctrlc(sig: i32, info: *const posix.siginfo_t, ctx_ptr: ?*const anyopaque) callconv(.C) void {
    _ = ctx_ptr;
    _ = info;
    _ = sig;
    std.debug.print("CTRL-C\n", .{});
    posix.abort();
}

fn configTty(stdin: *const fs.File) !posix.termios {
    const oldconf = try posix.tcgetattr(stdin.handle);
    var termios = oldconf;
    termios.lflag.ECHO = false;
    termios.lflag.ECHONL = false;
    termios.lflag.ICANON = false;
    termios.lflag.IEXTEN = false;
    termios.lflag.ISIG = true;
    try posix.tcsetattr(stdin.handle, posix.TCSA.NOW, termios);
    return oldconf;
}

pub fn consoleCtrlcInit() !posix.Sigaction {
    var oldstate: posix.Sigaction = undefined;
    var sa = posix.Sigaction{
        .handler = .{ .sigaction = &handler_ctrlc },
        .mask = posix.empty_sigset,
        .flags = posix.SA.SIGINFO,
    };
    try posix.sigaction(posix.SIG.INT, &sa, &oldstate);
    return oldstate;
}

pub fn consoleCtrlcDeinit(oldstate: posix.Sigaction) !void {
    try posix.sigaction(posix.SIG.INT, &oldstate, null);
}

pub fn consoleStdinInit(stdin: fs.File) !posix.termios {
    return try configTty(&stdin);
}

pub fn consoleStdinDeinit(stdfile: fs.File, oldmode: posix.termios) !void {
    _ = stdfile;
    _ = oldmode;
}

pub fn consoleStdoutInit(stdout: fs.File) !posix.termios {
    _ = stdout;
    const ret: posix.termios = undefined;
    return ret;
}

pub fn consoleStoudDeinit(stdfile: fs.File, oldmode: posix.termios) !void {
    _ = stdfile;
    _ = oldmode;
}

pub fn console(allocator: Allocator, stdin: fs.File) !void {
    var line = std.ArrayList(u8).init(allocator);
    defer line.deinit();

    var stdin_stream = stdin.reader();

    std.debug.print("> ", .{});
    while (true) {
        const c: u8 = stdin_stream.readByte() catch |err| {
            if (err == error.EndOfStream) {
                // EOF.
                std.debug.print("\nExiting.\n", .{});
                return;
            } else {
                std.debug.print("caught err: {!}\n", .{err});
                return err;
            }
        };
        switch (c) {
            '\n' => {
                std.debug.print("{s}\n", .{line.items});
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
}
