// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

const std = @import("std");
const apple = @import("apple.zig");
const c = @import("c");
const clipboard = @import("clipboard.zig");

const usage =
    \\Usage: pbimgcopy [--pasteboard name] [--] <image>
    \\       pbimgcopy [--pasteboard name] [-] < image
    \\
    \\Copy original image bytes to the macOS clipboard without conversion.
    \\Use - or omit the filename to read stdin. Use -- before a filename
    \\that starts with a dash. --help prints this message.
    \\
;

const Input = union(enum) { help, stdin, file: [:0]const u8 };

fn parseArgs(args: []const [:0]const u8) !Input {
    if (args.len == 0) return .stdin;
    if (std.mem.eql(u8, args[0], "--")) {
        if (args.len != 2) return error.ExpectedOneFilename;
        return .{ .file = args[1] };
    }
    if (args.len != 1) return error.ExpectedOneFilename;
    if (std.mem.eql(u8, args[0], "--help") or std.mem.eql(u8, args[0], "-h")) return .help;
    if (std.mem.eql(u8, args[0], "-")) return .stdin;
    if (std.mem.startsWith(u8, args[0], "-")) return error.UnknownOption;
    return .{ .file = args[0] };
}

const Image = struct {
    data: apple.Ref,
    source: apple.Ref,
    image_type: apple.Ref,

    fn init(bytes: []const u8) !Image {
        if (bytes.len == 0) return error.EmptyInput;
        const data = apple.CFDataCreate(null, bytes.ptr, @intCast(bytes.len)) orelse return error.OutOfMemory;
        errdefer apple.CFRelease(data);
        const source = apple.CGImageSourceCreateWithData(data, null) orelse return error.UnsupportedImage;
        errdefer apple.CFRelease(source);
        const image_type = apple.CGImageSourceGetType(source) orelse return error.UnsupportedImage;
        if (apple.CGImageSourceGetCount(source) == 0 or apple.CGImageSourceGetStatus(source) != 0)
            return error.InvalidImage;
        return .{ .data = data, .source = source, .image_type = image_type };
    }

    fn deinit(self: Image) void {
        apple.CFRelease(self.source);
        apple.CFRelease(self.data);
    }

    fn copyTo(self: Image, pasteboard: apple.Ref) !void {
        if (apple.PasteboardClear(pasteboard) != 0) return error.ClipboardClearFailed;
        // Supply the original data directly, never a decoded/re-encoded image.
        if (apple.PasteboardPutItemFlavor(pasteboard, 1, self.image_type, self.data, 0) != 0)
            return error.ClipboardWriteFailed;
    }
};

fn run(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    const selection = try clipboard.select(args[1..]);
    const input = try parseArgs(selection.args);
    if (input == .help) {
        _ = c.fputs(usage, c.stdout());
        return;
    }
    const stream = switch (input) {
        .file => |path| c.fopen(path, "rb") orelse return error.CannotOpenFile,
        .stdin => blk: {
            if (c.isatty(c.fileno(c.stdin())) != 0) return error.NoInput;
            break :blk c.stdin();
        },
        .help => unreachable,
    };
    defer if (input == .file) {
        _ = c.fclose(stream);
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(allocator);
    var buffer: [64 * 1024]u8 = undefined;
    while (true) {
        const count = c.fread(&buffer, 1, buffer.len, stream);
        try bytes.appendSlice(allocator, buffer[0..count]);
        if (count < buffer.len) {
            if (c.ferror(stream) != 0) return error.ReadFailed;
            break;
        }
    }
    const img = try Image.init(bytes.items);
    defer img.deinit();
    const pasteboard = try clipboard.named(selection.name);
    defer apple.CFRelease(pasteboard);
    try img.copyTo(pasteboard);
    var type_buffer: [256]u8 = undefined;
    const type_name = if (apple.CFStringGetCString(img.image_type, &type_buffer, type_buffer.len, apple.utf8) != 0)
        std.mem.sliceTo(&type_buffer, 0)
    else
        "image";
    const label = switch (input) {
        .file => |path| std.fs.path.basename(path),
        else => "stdin",
    };
    const message = try allocator.printSentinel("Copied {s} to clipboard ({s}, {d} bytes, unchanged)\n", .{ label, type_name, bytes.items.len }, 0);
    _ = c.fputs(message, c.stdout());
}

pub fn main(init: std.process.Init) void {
    run(init) catch |err| {
        _ = c.fprintf(c.stderr(), "pbimgcopy: %s\n", @errorName(err).ptr);
        std.process.exit(1);
    };
}

test "unit: argument handling" {
    try std.testing.expect(try parseArgs(&.{}) == .stdin);
    try std.testing.expect(try parseArgs(&.{"-"}) == .stdin);
    try std.testing.expect(try parseArgs(&.{"--help"}) == .help);
    try std.testing.expectEqualStrings("-image", (try parseArgs(&.{ "--", "-image" })).file);
    try std.testing.expectError(error.UnknownOption, parseArgs(&.{"--bogus"}));
    try std.testing.expectError(error.ExpectedOneFilename, parseArgs(&.{ "a", "b" }));
    try std.testing.expectError(error.ExpectedOneFilename, parseArgs(&.{"--"}));
}

test "unit: reject empty and non-image input" {
    try std.testing.expectError(error.EmptyInput, Image.init(""));
    try std.testing.expectError(error.UnsupportedImage, Image.init("this is not an image"));
}

const samples = .{
    .{ @embedFile("testdata/transparent.png"), "public.png", @as(usize, 1) },
    .{ @embedFile("testdata/photo.jpg"), "public.jpeg", @as(usize, 1) },
    .{ @embedFile("testdata/animated.gif"), "com.compuserve.gif", @as(usize, 2) },
    .{ @embedFile("testdata/image.tiff"), "public.tiff", @as(usize, 1) },
};

test "clipboard: original formats and bytes survive a private pasteboard round trip" {
    // A null name creates a private pasteboard, never the user's clipboard.
    var board: ?apple.Ref = null;
    try std.testing.expectEqual(@as(i32, 0), apple.PasteboardCreate(null, &board));
    const pasteboard = board orelse return error.ClipboardUnavailable;
    defer apple.CFRelease(pasteboard);
    inline for (samples) |sample| {
        const img = try Image.init(sample[0]);
        defer img.deinit();
        var type_buffer: [256]u8 = undefined;
        try std.testing.expect(apple.CFStringGetCString(img.image_type, &type_buffer, type_buffer.len, apple.utf8) != 0);
        try std.testing.expectEqualStrings(sample[1], std.mem.sliceTo(&type_buffer, 0));
        try std.testing.expectEqual(sample[2], apple.CGImageSourceGetCount(img.source));
        try img.copyTo(pasteboard);
        const data = try @import("clipboard.zig").image(pasteboard);
        defer apple.CFRelease(data);
        const length: usize = @intCast(apple.CFDataGetLength(data));
        try std.testing.expectEqualSlices(u8, sample[0], apple.CFDataGetBytePtr(data)[0..length]);
        const file = c.tmpfile() orelse return error.CannotOpenFile;
        defer _ = c.fclose(file);
        try @import("clipboard.zig").writeData(file, data);
        c.rewind(file);
        const saved = try std.testing.allocator.alloc(u8, length + 1);
        defer std.testing.allocator.free(saved);
        const read = c.fread(saved.ptr, 1, saved.len, file);
        try std.testing.expectEqualSlices(u8, sample[0], saved[0..read]);
    }
}

test "unit: detect formats and preserve source data" {
    inline for (samples) |sample| {
        const img = try Image.init(sample[0]);
        defer img.deinit();
        var type_buffer: [256]u8 = undefined;
        try std.testing.expect(apple.CFStringGetCString(img.image_type, &type_buffer, type_buffer.len, apple.utf8) != 0);
        try std.testing.expectEqualStrings(sample[1], std.mem.sliceTo(&type_buffer, 0));
        try std.testing.expectEqual(sample[2], apple.CGImageSourceGetCount(img.source));
        const length: usize = @intCast(apple.CFDataGetLength(img.data));
        try std.testing.expectEqualSlices(u8, sample[0], apple.CFDataGetBytePtr(img.data)[0..length]);
    }
}
