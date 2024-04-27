const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const posix = std.posix;
const fs = std.fs;
const time = std.time;
const ascii = std.ascii;

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

pub fn consoleInitStdin(stdin: fs.File) !u32 {
    _ = stdin;
    return 0;
}

pub fn consoleInitStdout(stdout: fs.File) !u32 {
    _ = stdout;
    return 0;
}

pub fn consoleDeinit(stdfile: fs.File, oldmode: u32) void {
    _ = stdfile;
    _ = oldmode;
}

pub fn console(stdin: fs.File) !void {
    switch (builtin.target.os.tag) {
        .linux, .macos => {
            var sa = posix.Sigaction{
                .handler = .{ .sigaction = &handler_ctrlc },
                .mask = posix.empty_sigset,
                .flags = posix.SA.SIGINFO,
            };
            try posix.sigaction(posix.SIG.INT, &sa, null);
        },
        else => @compileError("CTRL-C is not supported for this platform"),
    }

    var stdin_stream = stdin.reader();
    var oldtermios: posix.termios = undefined;
    if (stdin.isTty()) {
        std.debug.print("stdin is TTY\n", .{});
        oldtermios = try configTty(&stdin);
    }
    defer if (stdin.isTty()) {
        posix.tcsetattr(stdin.handle, posix.TCSA.NOW, oldtermios) catch |err| {
            std.debug.print("TTY could not be restored: {!}\n", .{err});
        };
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var line = std.ArrayList(u8).init(allocator);
    defer line.deinit();

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
