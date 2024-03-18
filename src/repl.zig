const std = @import("std");
pub const History = @import("history.zig");
pub const Terminal = @import("terminal.zig");

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit();
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
