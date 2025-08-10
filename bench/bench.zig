const std = @import("std");
const zbench = @import("zbench");
const zieve = @import("zieve");

fn BenchmarkPut(allocator: std.mem.Allocator) void {
    var sieve = zieve.SieveCache(u32, u32).init(allocator, 3);
    _ = sieve.put(10, 100) catch return; // size: 1, head: 10
}

pub fn main() !void {
    var stdout = std.fs.File.stdout().writerStreaming(&.{});
    var writer = &stdout.interface;

    var bench = zbench.Benchmark.init(std.heap.page_allocator, .{});
    defer bench.deinit();

    try bench.add("Benchmark", BenchmarkPut, .{});

    try writer.writeAll("\n");
    try bench.run(writer);
}

test "bench test" {
    var bench = zbench.Benchmark.init(std.testing.allocator, .{});
    defer bench.deinit();
    try bench.add("My Benchmark", BenchmarkPut, .{});
    try bench.run(std.io.getStdOut().writer());
}
