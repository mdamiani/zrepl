const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const fs = std.fs;
const time = std.time;
const ascii = std.ascii;

fn handler_ctrlc(sig: i32, info: *const os.siginfo_t, ctx_ptr: ?*const anyopaque) callconv(.C) void {
    _ = ctx_ptr;
    _ = info;
    _ = sig;
    std.debug.print("CTRL-C\n", .{});
    os.abort();
}

fn configTty(stdin: *const fs.File) !os.termios {
    const oldconf = try os.tcgetattr(stdin.handle);
    var termios = oldconf;
    switch (builtin.target.os.tag) {
        .linux => {
            termios.lflag &= ~(os.linux.ECHO | os.linux.ECHONL | os.linux.ICANON);
            termios.lflag |= (os.linux.ISIG);
        },
        .macos => {
            termios.lflag &= ~(os.darwin.ECHO | os.darwin.ECHONL | os.darwin.ICANON | os.linux.IEXTEN);
            termios.lflag |= (os.darwin.ISIG);
        },
        else => @compileError("TTY is not supported for this platform"),
    }
    try os.tcsetattr(stdin.handle, os.TCSA.NOW, termios);
    return oldconf;
}

pub fn console() !void {
    switch (builtin.target.os.tag) {
        .linux, .macos => {
            var sa = os.Sigaction{
                .handler = .{ .sigaction = &handler_ctrlc },
                .mask = os.empty_sigset,
                .flags = os.SA.SIGINFO,
            };
            try os.sigaction(os.SIG.INT, &sa, null);
        },
        else => @compileError("CTRL-C is not supported for this platform"),
    }

    const stdin = std.io.getStdIn();
    var stdin_stream = stdin.reader();
    var oldtermios: os.termios = undefined;
    if (stdin.isTty()) {
        std.debug.print("stdin is TTY\n", .{});
        oldtermios = try configTty(&stdin);
    }
    defer if (stdin.isTty()) {
        os.tcsetattr(stdin.handle, os.TCSA.NOW, oldtermios) catch |err| {
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
