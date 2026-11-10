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
    const c_module = c.createModule();
    const test_step = b.step("test", "Test utilities using private pasteboards");
    const unit_step = b.step("test-unit", "Run tests without pasteboard access");
    const e2e_module = b.createModule(.{
        .root_source_file = b.path("src/e2e.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "c", .module = c_module }},
    });
    e2e_module.linkFramework("CoreFoundation", .{});
    e2e_module.linkFramework("ApplicationServices", .{});
    const e2e = b.addRunArtifact(b.addExecutable(.{ .name = "test-e2e", .root_module = e2e_module }));
    e2e.has_side_effects = true;
    e2e.addFileArg2(b.path("tests/e2e.sh"), .{ .make_absolute = true });
    b.step("test-e2e", "Run the three CLIs against an isolated pasteboard").dependOn(&e2e.step);
    test_step.dependOn(&e2e.step);
    for ([_]struct { name: []const u8, source: []const u8 }{
        .{ .name = "pbimgcopy", .source = "src/main.zig" },
        .{ .name = "pbimgpaste", .source = "src/paste.zig" },
        .{ .name = "pblist", .source = "src/list.zig" },
    }) |tool| {
        const module = b.createModule(.{
            .root_source_file = b.path(tool.source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{.{ .name = "c", .module = c_module }},
        });
        module.linkFramework("CoreFoundation", .{});
        module.linkFramework("ImageIO", .{});
        module.linkFramework("ApplicationServices", .{});
        module.linkFramework("CoreServices", .{});
        if (std.mem.eql(u8, tool.name, "pblist")) module.linkFramework("AppKit", .{});
        const exe = b.addExecutable(.{ .name = tool.name, .root_module = module });
        b.installArtifact(exe);
        e2e.addArtifactArg2(exe, .{ .make_absolute = true });
        if (std.mem.eql(u8, tool.name, "pbimgcopy")) {
            const run = b.addRunArtifact(exe);
            run.addPassthruArgs();
            b.step("run", "Copy an image to the clipboard").dependOn(&run.step);
        }
        const tests = b.addTest(.{ .root_module = module });
        test_step.dependOn(&b.addRunArtifact(tests).step);
        const unit_tests = b.addTest(.{ .root_module = module, .filters = &.{"unit:"} });
        unit_step.dependOn(&b.addRunArtifact(unit_tests).step);
    }
    e2e.addDirectoryArg2(b.path("src/testdata"), .{ .make_absolute = true });
}
