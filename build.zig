// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    if (target.result.os.tag != .macos) @panic("pbimgcopy requires macOS");
    const optimize = b.standardOptimizeOption(.{});
    // Use the bundled translator to avoid adding a package dependency.
    const c = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
    });
    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "c", .module = c.createModule() }},
    });
    module.linkFramework("CoreFoundation", .{});
    module.linkFramework("ImageIO", .{});
    module.linkFramework("ApplicationServices", .{});
    const exe = b.addExecutable(.{ .name = "pbimgcopy", .root_module = module });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    b.step("run", "Copy an image to the clipboard").dependOn(&run.step);
    const tests = b.addTest(.{ .root_module = module });
    b.step("test", "Test image detection and byte-preserving clipboard writes").dependOn(&b.addRunArtifact(tests).step);
    const unit_tests = b.addTest(.{ .root_module = module, .filters = &.{"unit:"} });
    b.step("test-unit", "Run tests without access to the pasteboard service").dependOn(&b.addRunArtifact(unit_tests).step);
}
