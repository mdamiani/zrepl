const std = @import("std");
const os = std.os;
const win = os.windows;

const Allocator = std.mem.Allocator;

const kernel32 = struct {
    const KEY_EVENT = 0x1;
    const VK_BACK = 0x08;
    const VK_RETURN = 0x0D;

    const KEY_EVENT_RECORD = extern struct {
        bKeyDown: win.BOOL,
        wRepeatCount: win.WORD,
        wVirtualKeyCode: win.WORD,
        wVirtualScanCode: win.WORD,
        uChar: extern union {
            UnicodeChar: win.WCHAR,
            AsciiChar: win.CHAR,
        },
        dwControlKeyState: win.DWORD,
    };

    const COORD = extern struct {
        X: win.SHORT,
        Y: win.SHORT,
    };

    const MOUSE_EVENT_RECORD = extern struct {
        dwMousePosition: win.COORD,
        dwButtonState: win.DWORD,
        dwControlKeyState: win.DWORD,
        dwEventFlags: win.DWORD,
    };

    const WINDOW_BUFFER_SIZE_RECORD = extern struct {
        dwSize: COORD,
    };

    const MENU_EVENT_RECORD = extern struct {
        dwCommandId: win.UINT,
    };

    const FOCUS_EVENT_RECORD = extern struct {
        bSetFocus: win.BOOL,
    };

    const INPUT_RECORD = extern struct {
        EventType: win.WORD,
        Event: extern union {
            KeyEvent: KEY_EVENT_RECORD,
            MouseEvent: MOUSE_EVENT_RECORD,
            WindowBufferSizeEvent: WINDOW_BUFFER_SIZE_RECORD,
            MenuEvent: MENU_EVENT_RECORD,
            FocusEvent: FOCUS_EVENT_RECORD,
        },
    };

    extern "kernel32" fn SetConsoleMode(
        in_hConsoleHandle: win.HANDLE,
        in_dwMode: win.DWORD,
    ) callconv(win.WINAPI) win.BOOL;

    extern "kernel32" fn FlushConsoleInputBuffer(
        in_hConsoleInput: win.HANDLE,
    ) callconv(win.WINAPI) win.BOOL;

    extern "kernel32" fn ReadConsoleInputA(
        in_hConsoleInput: win.HANDLE,
        out_lpBuffer: [*]INPUT_RECORD,
        in_nLength: win.DWORD,
        out_lpNumberOfEventsRead: *win.DWORD,
    ) callconv(win.WINAPI) win.BOOL;

    extern "kernel32" fn ResetEvent(
        in_hEvent: win.HANDLE,
    ) callconv(win.WINAPI) win.BOOL;

    extern "kernel32" fn SetEvent(
        in_hEvent: win.HANDLE,
    ) callconv(win.WINAPI) win.BOOL;
};

pub fn SetConsoleMode(hConsoleHandle: win.HANDLE, dwMode: win.DWORD) !void {
    if (kernel32.SetConsoleMode(hConsoleHandle, dwMode) == 0) {
        return win.unexpectedError(win.kernel32.GetLastError());
    }
}

pub fn FlushConsoleInputBuffer(hConsoleInput: win.HANDLE) !void {
    if (kernel32.FlushConsoleInputBuffer(hConsoleInput) == 0) {
        return win.unexpectedError(win.kernel32.GetLastError());
    }
}

pub fn ReadConsoleInput(hConsoleInput: win.HANDLE, lpBuffer: []kernel32.INPUT_RECORD, lpNumberOfEventsRead: *win.DWORD) !void {
    const nLength: win.DWORD = @as(win.DWORD, @intCast(lpBuffer.len));
    if (kernel32.ReadConsoleInputA(hConsoleInput, lpBuffer.ptr, nLength, lpNumberOfEventsRead) == 0) {
        return win.unexpectedError(win.kernel32.GetLastError());
    }
}

pub fn SetEvent(hEvent: win.HANDLE) !void {
    if (kernel32.SetEvent(hEvent) == 0) {
        return win.unexpectedError(win.kernel32.GetLastError());
    }
}

var ctrlcEvent: win.HANDLE = undefined;
var ctrlcNum = 0;

fn ctrlHandler(fdwCtrlType: win.DWORD) callconv(win.WINAPI) win.BOOL {
    switch (fdwCtrlType) {
        win.CTRL_C_EVENT => {
            try SetEvent(ctrlcEvent) catch {
                os.abort();
            };
            return win.TRUE;
        },
        else => {
            return win.FALSE;
        },
    }
}

fn ReadStdIn(buf: []u8, hPipe: win.HANDLE) !win.DWORD {
    var irArr: [1]kernel32.INPUT_RECORD = undefined;
    var recCnt: win.DWORD = undefined;
    var dwLen: win.DWORD = undefined;
    var evt: win.DWORD = undefined;
    var h: [2]win.HANDLE = undefined;
    var hin = try win.GetStdHandle(win.STD_INPUT_HANDLE);

    h[0] = hin;
    h[1] = hPipe;

    // read characters until we reach buffer size
    dwLen = 0;
    lineLoop: while (dwLen < buf.len) {
        // wait for input or until mutex is released
        evt = try win.WaitForMultipleObjectsEx(h[0..], false, win.INFINITE, false);

        // if not STD_INPUT_HANDLE, exit
        if (evt != 0) {
            return error.PipeErr;
        }

        try ReadConsoleInput(hin, irArr[0..], &recCnt);

        for (0..recCnt) |i| {
            const ir = &irArr[i];

            if (ir.EventType == kernel32.KEY_EVENT) {
                var pKey: *kernel32.KEY_EVENT_RECORD = @ptrCast(&ir.Event);

                if (pKey.bKeyDown == 0) {
                    continue;
                }

                if (pKey.wVirtualKeyCode == kernel32.VK_BACK) {
                    dwLen = if (dwLen > 0) dwLen - 1 else dwLen;
                    continue;
                }

                if (pKey.uChar.AsciiChar != 0) {
                    buf[dwLen] = pKey.uChar.AsciiChar;
                    dwLen += 1;
                }

                if (pKey.wVirtualKeyCode == kernel32.VK_RETURN) {
                    break :lineLoop;
                }
            }
        }
    }

    buf[dwLen] = 0;
    return dwLen;
}

pub fn console() !void {
    var rp: win.HANDLE = undefined;
    var wp: win.HANDLE = undefined;
    var sattr = win.SECURITY_ATTRIBUTES{
        .nLength = @sizeOf(win.SECURITY_ATTRIBUTES),
        .bInheritHandle = win.FALSE,
        .lpSecurityDescriptor = null,
    };
    try win.CreatePipe(&rp, &wp, &sattr);

    ctrlcEvent = try win.CreateEventEx(null, "CTRLCEvent", 0, win.EVENT_ALL_ACCESS);
    defer win.CloseHandle(ctrlcEvent);

    try os.windows.SetConsoleCtrlHandler(ctrlHandler, true);

    const stdinFile = std.io.getStdIn();
    var oldmode: win.DWORD = undefined;
    _ = win.kernel32.GetConsoleMode(stdinFile.handle, &oldmode);
    const ENABLE_ECHO_INPUT: win.DWORD = 0x4;
    const ENABLE_INSERT_MODE = 0x20;
    const ENABLE_LINE_INPUT = 0x2;
    const mode = oldmode & ~(ENABLE_ECHO_INPUT | ENABLE_INSERT_MODE | ENABLE_LINE_INPUT);
    try SetConsoleMode(stdinFile.handle, mode);
    defer SetConsoleMode(stdinFile.handle, oldmode) catch {};

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var line = std.ArrayList(u8).init(allocator);
    defer line.deinit();

    try FlushConsoleInputBuffer(stdinFile.handle);

    std.debug.print("> ", .{});
    var buf = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
    while (true) {
        std.debug.print("stdin waiting...\n", .{});
        const n = ReadStdIn(buf[0..], ctrlcEvent) catch |err| {
            if (err == error.PipeErr) {
                std.debug.print("CTRL-C\n", .{});
            }
            return err;
        };
        std.debug.print("stdin got: {s}, #{d}\n", .{ buf[0..(n + 1)], n });
    }
    std.debug.print("Exiting\n", .{});
}
