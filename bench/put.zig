const std = @import("std");
const zbench = @import("zbench");
const zieve = @import("zieve");

// A global allocator is used to ensure memory is properly managed across hooks.
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// Global instances for the benchmark hooks to modify.
var sieve_cache: zieve.SieveCache(u32, u32) = undefined;
var benchmark_data: BenchmarkData = undefined;
const cache_capacity: u32 = 100;
const data_size: usize = 200;

const BenchmarkData = struct {
    prng: std.Random.DefaultPrng,
    rand: std.Random,
    keys: std.ArrayList(u32),
    values: std.ArrayList(u32),
    const Self = @This();

    pub fn init(self: *Self, allocator: std.mem.Allocator, size: usize) !void {
        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch unreachable;
        self.prng = std.Random.DefaultPrng.init(seed);
        self.rand = self.prng.random();
        self.keys = try std.ArrayList(u32).initCapacity(allocator, size);
        self.values = try std.ArrayList(u32).initCapacity(allocator, size);
    }

    pub fn deinit(self: *Self) void {
        self.keys.deinit();
        self.values.deinit();
    }

    pub fn fill(self: *Self) void {
        self.keys.clearAndFree();
        self.values.clearAndFree();
        for (0..data_size) |_| {
            self.keys.appendAssumeCapacity(self.rand.int(u32));
            self.values.appendAssumeCapacity(self.rand.int(u32));
        }
    }
};

/// A one-time setup hook that runs before all benchmark iterations.
/// Initializes the global allocator and the BenchmarkData struct.
fn beforeAllHook() void {
    const allocator = gpa.allocator();
    benchmark_data.init(allocator, data_size) catch unreachable;
    sieve_cache = zieve.SieveCache(u32, u32).init(allocator, cache_capacity);
}

/// A one-time teardown hook that runs after all benchmark iterations are complete.
/// Deinitializes the SieveCache, BenchmarkData, and checks for memory leaks.
fn afterAllHook() void {
    sieve_cache.deinit();
    benchmark_data.deinit();
    const deinit_status = gpa.deinit();
    if (deinit_status == .leak) std.debug.panic("Memory leak detected", .{});
}

/// A hook to clear and refill the cache with random data before each iteration.
/// This prepares the cache for hit, miss, and eviction benchmarks.
fn beforeEachFill() void {
    sieve_cache.deinit();
    sieve_cache = zieve.SieveCache(u32, u32).init(gpa.allocator(), cache_capacity);
    benchmark_data.fill();
    for (0..@as(u32, cache_capacity)) |i| {
        _ = sieve_cache.put(benchmark_data.keys.items[i], benchmark_data.values.items[i]) catch unreachable;
    }
}

/// A benchmark for putting a new item into a full cache, triggering an eviction.
fn BenchmarkPutWithEviction(_: std.mem.Allocator) void {
    const key = benchmark_data.keys.items[@as(usize, cache_capacity)];
    const value = benchmark_data.values.items[@as(usize, cache_capacity)];
    _ = sieve_cache.put(key, value) catch unreachable;
}

/// A benchmark for getting an item that is already in the cache (a cache hit).
fn BenchmarkGetHit(_: std.mem.Allocator) void {
    const key = benchmark_data.keys.items[0];
    _ = sieve_cache.get(key);
}

/// A benchmark for getting an item that is not in the cache (a cache miss).
fn BenchmarkGetMiss(_: std.mem.Allocator) void {
    const key = benchmark_data.keys.items[@as(usize, cache_capacity)];
    _ = sieve_cache.get(key);
}

pub fn main() !void {
    var stdout = std.fs.File.stdout().writerStreaming(&.{});
    var writer = &stdout.interface;

    var bench = zbench.Benchmark.init(gpa.allocator(), .{});

    // All benchmarks will use the before_all and after_all hooks
    // to manage the global state and memory.
    _ = zbench.Hooks{
        .before_all = beforeAllHook,
        .after_all = afterAllHook,
        .before_each = beforeEachFill,
    };

    try bench.add("get_hit", BenchmarkGetHit, .{ .track_allocations = true, .hooks = .{
        .before_all = beforeAllHook,
        .after_all = afterAllHook,
        .before_each = beforeEachFill,
    } });
    // try bench.add("get_miss", BenchmarkGetMiss, common_hooks);
    // try bench.add("get_hit", BenchmarkPutWithEviction, common_hooks);

    try writer.writeAll("\n");
    try bench.run(writer);
}

test "bench test" {
    // Note: The test runner does not support `before_all` and `after_all` hooks
    // in the same way the `main` function does. For a simple test, we will
    // run the benchmarks directly.
    var sieve = zieve.SieveCache(u32, u32).init(std.testing.allocator, 3);
    defer sieve.deinit();

    var bench = zbench.Benchmark.init(std.testing.allocator, .{});
    defer bench.deinit();

    // A simpler test that only checks if the benchmark functions can run without crashing.
    try bench.add("put_with_eviction", BenchmarkPutWithEviction, .{});
    try bench.run(std.io.getStdOut().writer());
}
