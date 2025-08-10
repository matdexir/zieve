const std = @import("std");

const version = std.SemanticVersion{ .major = 0, .minor = 0, .patch = 0 };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Setup library
    _ = setupLibrary(b, target, optimize);

    // Setup examples
    setupExamples(b, target, optimize);
}

fn setupLibrary(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zieve",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .version = version,
    });

    b.installArtifact(lib);

    return lib;
}

fn setupExamples(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const example_step = b.step("bench", "Build benchmarks");
    const example_names = [_][]const u8{ "bench", "put" };

    for (example_names) |example_name| {
        const example = b.addExecutable(.{
            .name = example_name,
            .root_module = b.createModule(.{
                .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = b.fmt("bench/{s}.zig", .{example_name}) } },
                .target = target,
                .optimize = optimize,
            }),
        });
        const install_example = b.addInstallArtifact(example, .{});
        const zbench_mod = b.addModule("zbench", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "libs/zbench/zbench.zig" } },
        });
        const zieve_mod = b.addModule("zieve", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/root.zig" } },
        });
        example.root_module.addImport("zbench", zbench_mod);
        example.root_module.addImport("zieve", zieve_mod);
        example_step.dependOn(&example.step);
        example_step.dependOn(&install_example.step);
    }
}
