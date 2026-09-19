const std = @import("std");

// zigvm E0.2: one installable executable target, `zigvm`, rooted at
// src/zigvm_main.zig. The binary lands at zig-out/bin/zigvm. All VM modules
// live in src/ and are pulled in via relative @import from the root source,
// so no extra module wiring is required here.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zigvm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zigvm_main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    // `zig build run -- <args>` for convenience during development.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the zigvm executable");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run tests");
    const main_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/vm_all.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(main_tests).step);
}
