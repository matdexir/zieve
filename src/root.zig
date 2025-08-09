const std = @import("std");

pub fn Node(comptime K: type, comptime V: type) type {
    return struct {
        key: K,
        value: V,
        next: ?*Node(K, V),
        prev: ?*Node(K, V),
        visited: u1,
        const Self = @This();

        pub fn init(key: K, value: V) Self {
            return Self{ .key = key, .value = value, .next = null, .prev = null, .visited = 0 };
        }
    };
}

pub fn SieveCache(comptime K: type, comptime V: type) type {
    const NodePtr = *Node(K, V);
    const HashMap = if (K == []const u8) std.StringHashMap(NodePtr) else std.AutoHashMap(K, NodePtr);

    return struct {
        head: ?NodePtr,
        tail: ?NodePtr,
        hand: ?NodePtr,
        cache: HashMap,
        allocator: std.mem.Allocator,
        capacity: u32,
        size: u32,
        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, capacity: u32) Self {
            return Self{
                .allocator = allocator,
                .head = null,
                .tail = null,
                .hand = null,
                .capacity = capacity,
                .size = 0,
                .cache = HashMap.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            var current = self.head;
            while (current) |node| {
                const next_node = node.next;
                self.allocator.destroy(node);
                current = next_node;
            }
            self.cache.deinit();
        }

        fn remove_node(self: *Self, node: NodePtr) void {
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

        fn insert_at_head(self: *Self, node: NodePtr) void {
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
            var evicted_node: ?NodePtr = null;
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

            const to_be_removed_key = evicted_node.?.key;
            self.hand = evicted_node.?.prev orelse null;

            _ = self.cache.remove(to_be_removed_key);
            self.remove_node(evicted_node.?);
            self.allocator.destroy(evicted_node.?);
            self.size -= 1;
        }

        pub fn put(self: *Self, key: K, value: V) !bool {
            if (self.cache.get(key)) |c| {
                c.visited = 1;
                return false;
            } else {
                if (self.size == self.capacity) {
                    self.evict();
                }

                const new_node = try self.allocator.create(Node(K, V));
                new_node.* = Node(K, V).init(key, value);
                self.insert_at_head(new_node);

                try self.cache.put(key, new_node);
                self.size += 1;
                return true;
            }
        }

        pub fn get(self: *Self, key: K) ?V {
            if (self.cache.get(key)) |node| {
                node.visited = 1;
                return node.value;
            } else {
                return null;
            }
        }
    };
}

test "create sieve cache" {
    const testing_allocator = std.testing.allocator;
    var sieve = SieveCache(u32, u32).init(testing_allocator, 3);
    defer sieve.deinit();
    try std.testing.expectEqual(sieve.capacity, 3);
}

test "sieve put and get" {
    const testing_allocator = std.testing.allocator;
    var sieve = SieveCache(u32, u32).init(testing_allocator, 3);
    defer sieve.deinit();

    const key1: u32 = 2;
    const value1: u32 = 20;

    // Put a new item
    const put_result = try sieve.put(key1, value1);
    try std.testing.expect(put_result); // Expect 'true' for a new item
    try std.testing.expectEqual(sieve.size, 1);
    try std.testing.expect(sieve.head != null);
    try std.testing.expectEqual(sieve.head.?.key, key1);

    // Get the item and check its value
    const retrieved_value = sieve.get(key1) orelse @panic("key not found");
    try std.testing.expectEqual(retrieved_value, value1);

    // Test a cache miss
    try std.testing.expect(sieve.get(99) == null);
}

test "sieve put, get, and eviction" {
    const testing_allocator = std.testing.allocator;
    var sieve = SieveCache(u32, u32).init(testing_allocator, 3);
    defer sieve.deinit();

    // Fill the cache
    _ = try sieve.put(10, 100); // size: 1, head: 10
    _ = try sieve.put(20, 200); // size: 2, head: 20 -> 10
    _ = try sieve.put(30, 300); // size: 3, head: 30 -> 20 -> 10

    try std.testing.expectEqual(sieve.size, 3);
    try std.testing.expectEqual(sieve.head.?.key, 30);
    try std.testing.expectEqual(sieve.tail.?.key, 10);

    // Trigger an eviction
    _ = try sieve.put(40, 400); // Evicts 10
    try std.testing.expectEqual(sieve.size, 3);
    try std.testing.expectEqual(sieve.head.?.key, 40);
    try std.testing.expectEqual(sieve.tail.?.key, 20); // Tail is now 20
    try std.testing.expect(sieve.get(10) == null); // Check that 10 was evicted

    // Get an item to set its visited bit
    _ = sieve.get(30) orelse @panic("key not found"); // 30 is now visited=1

    // Trigger another eviction
    _ = try sieve.put(50, 500); // Evicts 20 (unvisited)
    try std.testing.expectEqual(sieve.size, 3);
    try std.testing.expectEqual(sieve.head.?.key, 50);
    try std.testing.expectEqual(sieve.tail.?.key, 30); // Tail is now 30, which had its visited bit reset
    try std.testing.expect(sieve.get(20) == null); // Check that 20 was evicted
}
