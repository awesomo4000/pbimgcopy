// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

const std = @import("std");
const a = @import("apple.zig");
const c = @import("c");
const clipboard = @import("clipboard.zig");

fn run(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const selection = try clipboard.select(args[1..]);
    if (try clipboard.help(selection.args)) {
        _ = c.fputs("Usage: pbimgpaste [--pasteboard name] > file\nWrite the first clipboard image to stdout without conversion.\n", c.stdout());
        return;
    }
    if (c.isatty(c.fileno(c.stdout())) != 0) return error.RedirectStdout;
    const board = try clipboard.named(selection.name);
    defer a.CFRelease(board);
    const data = try clipboard.image(board);
    defer a.CFRelease(data);
    try clipboard.writeData(c.stdout(), data);
}

pub fn main(init: std.process.Init) void {
    run(init) catch |err| {
        _ = c.fprintf(c.stderr(), "pbimgpaste: %s\n", @errorName(err).ptr);
        std.process.exit(1);
    };
}

test "clipboard: skip text items and leave the pasteboard unchanged" {
    const board = try clipboard.open(null);
    defer a.CFRelease(board);
    try std.testing.expectEqual(@as(i32, 0), a.PasteboardClear(board));
    try std.testing.expectError(error.NoImage, clipboard.image(board));
    const text_type = try clipboard.string("public.utf8-plain-text");
    defer a.CFRelease(text_type);
    const text = a.CFDataCreate(null, "hello", 5) orelse return error.OutOfMemory;
    defer a.CFRelease(text);
    try std.testing.expectEqual(@as(i32, 0), a.PasteboardPutItemFlavor(board, 7, text_type, text, 0));
    try std.testing.expectError(error.NoImage, clipboard.image(board));
    const png_type = try clipboard.string("public.png");
    defer a.CFRelease(png_type);
    const bytes = @embedFile("testdata/transparent.png");
    const png = a.CFDataCreate(null, bytes, bytes.len) orelse return error.OutOfMemory;
    defer a.CFRelease(png);
    try std.testing.expectEqual(@as(i32, 0), a.PasteboardPutItemFlavor(board, 42, png_type, png, 0));
    const result = try clipboard.image(board);
    defer a.CFRelease(result);
    try std.testing.expectEqualSlices(u8, bytes, a.CFDataGetBytePtr(result)[0..@intCast(a.CFDataGetLength(result))]);
    try std.testing.expectEqual(@as(usize, 2), try clipboard.count(board));
    const original_text = try clipboard.data(board, 7, text_type);
    defer a.CFRelease(original_text);
    try std.testing.expectEqualStrings("hello", a.CFDataGetBytePtr(original_text)[0..5]);
}
