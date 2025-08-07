//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub fn Node(comptime T: type) type {
    return struct {
        value: T,
        next: ?*Node(T),
        prev: ?*Node(T),
        visited: u1,
        const Self = @This();

        fn init(value: T) Self {
            return Self{ .value = value, .next = null, .prev = null, .visited = 0 };
        }
    };
}

pub fn SieveCache(comptime T: type) type {
    return struct {
        head: ?*Node(T),
        tail: ?*Node(T),
        hand: ?*Node(T),
        cache: std.AutoHashMap(T, *Node(T)),
        allocator: std.mem.Allocator,
        capacity: u32,
        size: u32,
        const Self = @This();

        fn init(allocator: std.mem.Allocator, capacity: u32) Self {
            return Self{
                .allocator = allocator,
                .head = null,
                .tail = null,
                .hand = null,
                .capacity = capacity,
                .size = 0,
                .cache = std.AutoHashMap(T, *Node(T)).init(allocator),
            };
        }

        fn deinit(self: *Self) void {
            var current = self.head;
            while (current) |node| {
                const next_node = node.next;
                self.allocator.destroy(node);
                current = next_node;
            }
            self.cache.deinit();
        }

        fn remove_node(self: *Self, node: *Node(T)) void {
            if (node.prev) |prev_node| {
                prev_node.next = node.next;
            } else {
                self.head = node.next;
            }

            if (node.next) |next_node| {
                next_node.prev = node.prev;
            } else {
                self.tail = node.prev;
            }
        }

        fn insert_at_head(self: *Self, node: *Node(T)) void {
            node.next = self.head;
            node.prev = null;

            if (self.head) |h| {
                h.prev = node;
            } else {
                self.tail = node;
            }

            self.head = node;
        }

        fn evict(self: *Self) void {
            var evicted_node: ?*Node(T) = null;
            var current_hand = self.hand orelse self.tail;

            var did_circle = false;
            while (true) {
                if (current_hand == null) {
                    return;
                }

                if (current_hand.?.visited == 0) {
                    evicted_node = current_hand;
                    break;
                } else {
                    current_hand.?.visited = 0;
                    current_hand = current_hand.?.prev;
                    if (current_hand == null) {
                        current_hand = self.tail;
                        if (did_circle) {
                            evicted_node = self.tail;
                            break;
                        }
                        did_circle = true;
                    }
                }
            }

            self.hand = evicted_node.?.prev orelse null;

            const to_be_removed_value = evicted_node.?.value;
            _ = self.cache.remove(to_be_removed_value);
            self.remove_node(evicted_node.?);
            self.allocator.destroy(evicted_node.?);
            self.size -= 1;
        }

        fn access(self: *Self, x: T) !void {
            if (self.cache.get(x)) |c| {
                c.visited = 1;
            } else {
                if (self.size == self.capacity) {
                    self.evict();
                }

                const new_node = try self.allocator.create(Node(T));
                new_node.* = Node(T).init(x);

                self.insert_at_head(new_node);

                try self.cache.put(x, new_node);
                self.size += 1;
            }
        }
    };
}

test "create node" {
    const node = Node(u32).init(10);
    try std.testing.expectEqual(node.value, 10);
    try std.testing.expectEqual(node.visited, 0);
}

test "create sieve cache" {
    const testing_allocator = std.testing.allocator;
    var sieve = SieveCache(u32).init(testing_allocator, 3);
    try std.testing.expectEqual(sieve.capacity, 3);
    sieve.deinit();
}

test "create sieve one access" {
    const testing_allocator = std.testing.allocator;
    var sieve = SieveCache(u32).init(testing_allocator, 3);
    defer sieve.deinit(); // Use defer to ensure deinit is always called
    try std.testing.expectEqual(sieve.capacity, 3);

    // `access` is now fallible and returns an error, so we need to handle it
    try sieve.access(2);
    try std.testing.expectEqual(sieve.size, 1);
    try std.testing.expect(sieve.head != null);
    try std.testing.expectEqual(sieve.head.?.value, 2);
}

test "sieve access and eviction" {
    const testing_allocator = std.testing.allocator;
    var sieve = SieveCache(u32).init(testing_allocator, 3);
    defer sieve.deinit();

    try sieve.access(10); // size: 1, head: 10
    try sieve.access(20); // size: 2, head: 20 -> 10
    try sieve.access(30); // size: 3, head: 30 -> 20 -> 10

    try std.testing.expectEqual(sieve.size, 3);
    try std.testing.expectEqual(sieve.head.?.value, 30);
    try std.testing.expectEqual(sieve.tail.?.value, 10);

    try sieve.access(40); // size: 3, evicts 10 (unvisited)
    try std.testing.expectEqual(sieve.size, 3);
    try std.testing.expectEqual(sieve.head.?.value, 40);
    try std.testing.expectEqual(sieve.tail.?.value, 20); // Tail is now 20
    try std.testing.expect(sieve.cache.get(10) == null);

    try sieve.access(30); // Hit, 30 is visited=1
    try std.testing.expectEqual(sieve.size, 3);

    // Access 50, evicts 20 (unvisited)
    try sieve.access(50);
    try std.testing.expectEqual(sieve.size, 3);
    try std.testing.expectEqual(sieve.head.?.value, 50);
    try std.testing.expectEqual(sieve.tail.?.value, 30); // Tail is now 30, which was unvisited
    try std.testing.expect(sieve.cache.get(20) == null);
}
