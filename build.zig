const std = @import("std");
const set_version = @import("set_version");

pub fn build(b: *std.Build) void {
    set_version.VersionSetterStep.addStep(b);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "manipmv",
        .root_source_file = b.path("src/manipmv.zig"),
        .target = target,
        .optimize = optimize,
    });

    const vapoursynth_dep = b.dependency("vapoursynth", .{
        .target = target,
        .optimize = optimize,
    });

    // Pass the version in build.zig.zon to the code
    const options = b.addOptions();
    const current_version: []const u8 = set_version.currentVersion(b.allocator) catch unreachable;
    const version = b.option([]const u8, "version", "Semantic version string") orelse current_version;
    options.addOption([]const u8, "version", version);
    lib.root_module.addOptions("config", options);

    lib.root_module.addImport("vapoursynth", vapoursynth_dep.module("vapoursynth"));
    lib.linkLibC();

    if (lib.root_module.optimize == .ReleaseFast) {
        lib.root_module.strip = true;
    }

    b.installArtifact(lib);
}
