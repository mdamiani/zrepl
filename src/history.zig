const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

// The actual data structure for history items.
array: std.ArrayList([]const u8) = undefined,

// Number of elements in the history,
// no more than than the capacity.
count: usize = 0,

// Tail of the history as a circular buffer.
// That is, the index of the oldest element.
tail: usize = 0,

// Initializes the history data structure.
// The capacity parameter tells the maximum number of
// entries that the data structure shall keep.
pub fn init(allocator: Allocator, capacity: usize) Self {
    var self = Self{};

    self.array.init(allocator);
    self.array.resize(capacity);

    return self;
}

// Frees the memory of the history list.
// The contained entries are freed as well.
pub fn deinit(self: Self) void {
    for (self.array.items) |el| {
        self.array.allocator.free(el);
    }
    self.array.deinit();
}

// Adds a new entry into the history list.
// The passed string gets owned.
pub fn add(self: Self, item: []const u8) void {
    self.array.items[self.tail] = item;

    if (self.count < self.array.items.len) {
        self.count += 1;
    }

    if (self.tail + 1 < self.array.items.len) {
        self.tail += 1;
    } else {
        self.tail = 0;
    }
}
