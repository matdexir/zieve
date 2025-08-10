// This example shows how to use hooks to provide more control over a benchmark.
// The bubble_sort.zig example is enhanced with randomly generated numbers.
// Global strategy:
// * At the start of the benchmark, i.e., before the first iteration, we allocate an ArrayList and setup a random number generator.
// * Before each iteration, we fill the ArrayList with random numbers.
// * After each iteration, we reset the ArrayList while keeping the allocated memory.
// * At the end of the benchmark, we deinit the ArrayList.
const std = @import("std");
const inc = @import("include");
const zbench = @import("zbench");
const zieve = @import("zieve");

// Global variables modified/accessed by the hooks.
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const array_size: usize = 100;
// BenchmarkData contains the data generation logic.
var benchmark_data: BenchmarkData = undefined;
var sieve_cache: zieve.SieveCache(u32, u32) = undefined;

// Hooks do not accept any parameters and cannot return anything.
fn beforeAll() void {
    const allocator = gpa.allocator();
    benchmark_data.init(allocator, array_size) catch unreachable;
    sieve_cache = zieve.SieveCache(u32, u32).init(allocator, array_size);
}

fn beforeEach() void {
    benchmark_data.fill();
}

fn myBenchmark(_: std.mem.Allocator) void {}

fn afterEach() void {
    benchmark_data.reset();
}

fn afterAll() void {
    benchmark_data.deinit();
    sieve_cache.deinit();
}

pub fn main() !void {
    var stdout = std.fs.File.stdout().writerStreaming(&.{});
    var writer = &stdout.interface;

    var bench = zbench.Benchmark.init(gpa.allocator(), .{});
    defer {
        bench.deinit();
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.panic("Memory leak detected", .{});
    }

    try bench.add("Bubble Sort Benchmark", myBenchmark, .{
        .track_allocations = true, // Option used to show that hooks are not included in the tracking.
        .hooks = .{ // Fields are optional and can be omitted.
            .before_all = beforeAll,
            .after_all = afterAll,
            .before_each = beforeEach,
            .after_each = afterEach,
        },
    });

    try writer.writeAll("\n");
    try bench.run(writer);
}

const KVPair = struct {
    key: i32,
    value: i32,
};

const BenchmarkData = struct {
    rand: std.Random,
    numbers: std.ArrayList(KVPair),
    prng: std.Random.DefaultPrng,

    pub fn init(self: *BenchmarkData, allocator: std.mem.Allocator, num: usize) !void {
        self.prng = std.Random.DefaultPrng.init(blk: {
            var seed: u64 = undefined;
            std.posix.getrandom(std.mem.asBytes(&seed)) catch unreachable;
            break :blk seed;
        });
        self.rand = self.prng.random();
        self.numbers = try std.ArrayList(KVPair).initCapacity(allocator, num);
    }

    pub fn deinit(self: BenchmarkData) void {
        self.numbers.deinit();
    }

    pub fn fill(self: *BenchmarkData) void {
        for (0..self.numbers.capacity) |_| {
            const key = self.rand.intRangeAtMost(i32, 0, 100);
            const value = self.rand.intRangeAtMost(i32, 0, 100);
            self.numbers.appendAssumeCapacity(.{ .key = key, .value = value });
        }
    }

    pub fn reset(self: *BenchmarkData) void {
        self.numbers.clearRetainingCapacity();
    }
};
