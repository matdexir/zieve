const std = @import("std");
const zbench = @import("zbench");
const zieve = @import("zieve");

var sieve_cache: zieve.SieveCache(u32, u32) = undefined;
const MAX_SIZE = 1000;

fn myBenchmark(allocator: std.mem.Allocator) void {
    sieve_cache = zieve.SieveCache(u32, u32).init(allocator, MAX_SIZE);
    defer sieve_cache.deinit();
    var i: u32 = 0;
    while (i < MAX_SIZE) : (i += 1) {
        _ = sieve_cache.put(i, i) catch unreachable;
    }
    i = 0;
    while (i < MAX_SIZE) : (i += 1) {
        _ = sieve_cache.get(i);
    }
}

pub fn main() !void {
    var stdout = std.fs.File.stdout().writerStreaming(&.{});
    var writer = &stdout.interface;

    var bench = zbench.Benchmark.init(std.heap.page_allocator, .{});
    defer bench.deinit();

    try bench.add("My Benchmark", myBenchmark, .{});

    try writer.writeAll("\n");
    try bench.run(writer);
}
