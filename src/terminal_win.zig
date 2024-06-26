const std = @import("std");
const os = std.os;
const fs = std.fs;
const win = os.windows;
const Allocator = std.mem.Allocator;

const kernel32 = struct {
    const KEY_EVENT = 0x1;
    const VK_BACK = 0x08;
    const VK_RETURN = 0x0D;
    const VK_SCROLL = 0x91;
    const VK_TAB = 0x09;
    const VK_CAPITAL = 0x14;

    const ENABLE_ECHO_INPUT = 0x4;
    const ENABLE_INSERT_MODE = 0x20;
    const ENABLE_LINE_INPUT = 0x2;
    const ENABLE_MOUSE_INPUT = 0x0010;
    const ENABLE_QUICK_EDIT_MODE = 0x0040;
    const ENABLE_WINDOW_INPUT = 0x0008;
    const ENABLE_VIRTUAL_TERMINAL_INPUT = 0x0200;
    const ENABLE_PROCESSED_INPUT = 0x0001;

    const ENABLE_PROCESSED_OUTPUT = 0x0001;
    const ENABLE_WRAP_AT_EOL_OUTPUT = 0x0002;
    const ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
    const DISABLE_NEWLINE_AUTO_RETURN = 0x0008;
    const ENABLE_LVB_GRID_WORLDWIDE = 0x0010;

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

    extern "kernel32" fn PeekConsoleInputA(
        in_hConsoleInput: win.HANDLE,
        out_lpBuffer: [*]INPUT_RECORD,
        in_nLength: win.DWORD,
        out_lpNumberOfEventsRead: *win.DWORD,
    ) callconv(win.WINAPI) win.BOOL;

    extern "kernel32" fn ReadConsoleInputA(
        in_hConsoleInput: win.HANDLE,
        out_lpBuffer: [*]INPUT_RECORD,
        in_nLength: win.DWORD,
        out_lpNumberOfEventsRead: *win.DWORD,
    ) callconv(win.WINAPI) win.BOOL;

    extern "kernel32" fn ReadConsoleA(
        in_hConsoleInput: win.HANDLE,
        out_lpBuffer: win.LPVOID,
        in_nNumberOfCharsToRead: win.DWORD,
        out_lpNumberOfCharsRead: *win.DWORD,
        in_pInputControl: ?win.LPVOID,
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

pub fn PeekConsoleInput(hConsoleInput: win.HANDLE, lpBuffer: []kernel32.INPUT_RECORD) !usize {
    const nLength: win.DWORD = @as(win.DWORD, @intCast(lpBuffer.len));
    var lpNumberOfEventsRead: win.DWORD = undefined;
    if (kernel32.PeekConsoleInputA(hConsoleInput, lpBuffer.ptr, nLength, &lpNumberOfEventsRead) == 0) {
        return win.unexpectedError(win.kernel32.GetLastError());
    }
    return @as(usize, @intCast(lpNumberOfEventsRead));
}

pub fn ReadConsoleInput(hConsoleInput: win.HANDLE, lpBuffer: []kernel32.INPUT_RECORD) !usize {
    const nLength: win.DWORD = @as(win.DWORD, @intCast(lpBuffer.len));
    var lpNumberOfEventsRead: win.DWORD = undefined;
    if (kernel32.ReadConsoleInputA(hConsoleInput, lpBuffer.ptr, nLength, &lpNumberOfEventsRead) == 0) {
        return win.unexpectedError(win.kernel32.GetLastError());
    }
    return @as(usize, @intCast(lpNumberOfEventsRead));
}

pub fn ReadConsole(hConsoleInput: win.HANDLE, lpBuffer: []u8) !usize {
    // TODO: may be WCHAR as well?
    const numChars: win.DWORD = @as(win.DWORD, @intCast(@divTrunc(lpBuffer.len, @sizeOf(win.CHAR))));
    var n: win.DWORD = undefined;
    if (numChars <= 0) {
        return error.ReadConsoleBufferTooShort;
    }
    if (kernel32.ReadConsoleA(hConsoleInput, lpBuffer.ptr, numChars, &n, null) == 0) {
        return win.unexpectedError(win.kernel32.GetLastError());
    }
    return n;
}

pub fn SetEvent(hEvent: win.HANDLE) !void {
    if (kernel32.SetEvent(hEvent) == 0) {
        return win.unexpectedError(win.kernel32.GetLastError());
    }
}

const Self = @This();

const OldMode = struct {
    termStdin: win.DWORD,
    termStdout: win.DWORD,
};

var ctrlcEvent: win.HANDLE = undefined;
oldMode: OldMode = undefined,

fn ctrlHandler(fdwCtrlType: win.DWORD) callconv(win.WINAPI) win.BOOL {
    switch (fdwCtrlType) {
        win.CTRL_C_EVENT => {
            SetEvent(ctrlcEvent) catch {
                @panic("SetEvent failed!");
            };
            return win.TRUE;
        },
        else => {
            return win.FALSE;
        },
    }
}

pub fn consoleCtrlcInit(self: *Self) !void {
    _ = self;

    ctrlcEvent = try win.CreateEventEx(null, "CTRLCEvent", 0, win.EVENT_ALL_ACCESS);
    try os.windows.SetConsoleCtrlHandler(ctrlHandler, true);
}

pub fn consoleCtrlcDeinit(self: *Self) !void {
    _ = self;

    try os.windows.SetConsoleCtrlHandler(ctrlHandler, false);
    win.CloseHandle(ctrlcEvent);
}

pub fn consoleStdinInit(self: *Self, stdin: fs.File) !void {
    if (win.kernel32.GetConsoleMode(stdin.handle, &self.oldMode.termStdin) == 0) {
        return win.unexpectedError(win.kernel32.GetLastError());
    }

    const mode = (self.oldMode.termStdin &
        ~(@as(win.DWORD, 0) |
        kernel32.ENABLE_ECHO_INPUT |
        kernel32.ENABLE_INSERT_MODE |
        kernel32.ENABLE_LINE_INPUT |
        kernel32.ENABLE_MOUSE_INPUT |
        kernel32.ENABLE_QUICK_EDIT_MODE |
        kernel32.ENABLE_WINDOW_INPUT)) |
        kernel32.ENABLE_PROCESSED_INPUT |
        kernel32.ENABLE_VIRTUAL_TERMINAL_INPUT;

    try SetConsoleMode(stdin.handle, mode);
    try FlushConsoleInputBuffer(stdin.handle);
}

pub fn consoleStdinDeinit(self: *Self, stdin: fs.File) !void {
    try SetConsoleMode(stdin.handle, self.oldMode.termStdin);
}

pub fn consoleStdoutInit(self: *Self, stdout: fs.File) !void {
    if (win.kernel32.GetConsoleMode(stdout.handle, &self.oldMode.termStdout) == 0) {
        return win.unexpectedError(win.kernel32.GetLastError());
    }

    const mode = (self.oldMode.termStdout &
        ~(@as(win.DWORD, 0) |
        kernel32.ENABLE_PROCESSED_OUTPUT |
        kernel32.ENABLE_WRAP_AT_EOL_OUTPUT |
        kernel32.ENABLE_VIRTUAL_TERMINAL_PROCESSING |
        kernel32.DISABLE_NEWLINE_AUTO_RETURN |
        kernel32.ENABLE_LVB_GRID_WORLDWIDE));

    try SetConsoleMode(stdout.handle, mode);
}

pub fn consoleStdoutDeinit(self: *Self, stdout: fs.File) !void {
    try SetConsoleMode(stdout.handle, self.oldMode.termStdout);
}

fn dropConsoleInput(stdin: fs.File) !void {
    var drop: [1]kernel32.INPUT_RECORD = undefined;
    _ = try ReadConsoleInput(stdin.handle, drop[0..1]);
}

pub fn readChar(allocator: Allocator, stdin: fs.File, isCtrlc: bool) !u8 {
    _ = allocator;
    const hLen = x: {
        var len: usize = 1;
        if (isCtrlc) len = len + 1;
        break :x len;
    };

    while (true) {
        // wait for input or until event is signaled
        const h = [2]win.HANDLE{ stdin.handle, ctrlcEvent };
        const evt = try win.WaitForMultipleObjectsEx(h[0..hLen], false, win.INFINITE, false);

        // if not stdin, then exit
        if (evt != 0) {
            return error.SigInt;
        }

        var irArr: [16]kernel32.INPUT_RECORD = undefined;
        const recCnt = try PeekConsoleInput(stdin.handle, irArr[0..]);
        if (recCnt == 0) {
            continue;
        }

        var keyDownFound = false;

        for (0..recCnt) |i| {
            const ir = &irArr[i];

            if (ir.EventType != kernel32.KEY_EVENT) {
                try dropConsoleInput(stdin);
                continue;
            }

            const pKey: *kernel32.KEY_EVENT_RECORD = @ptrCast(&ir.Event);

            if (pKey.bKeyDown == 0) {
                try dropConsoleInput(stdin);
                continue;
            }

            switch (pKey.uChar.AsciiChar) {
                0x03,
                0x04,
                0x07...0x0D,
                0x1B,
                0x20...0x7F,
                => {
                    keyDownFound = true;
                    break;
                },
                else => {
                    try dropConsoleInput(stdin);
                    continue;
                },
            }
        }

        if (keyDownFound) {
            var mybuf: [1]u8 = undefined;
            const n = try ReadConsole(stdin.handle, mybuf[0..1]);
            if (n > 0) {
                return mybuf[0];
            }
        }
    }
}
