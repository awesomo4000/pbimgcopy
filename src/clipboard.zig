// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

const std = @import("std");
const a = @import("apple.zig");
const c = @import("c");

pub fn open(name: ?a.Ref) !a.Ref {
    var result: ?a.Ref = null;
    if (a.PasteboardCreate(name, &result) != 0) return error.ClipboardUnavailable;
    return result orelse error.ClipboardUnavailable;
}

pub fn named(value: ?[:0]const u8) !a.Ref {
    const name = try string(value orelse "com.apple.pasteboard.clipboard");
    defer a.CFRelease(name);
    return open(name);
}

pub fn string(value: [:0]const u8) !a.Ref {
    return a.CFStringCreateWithCString(null, value, a.utf8) orelse error.OutOfMemory;
}

pub fn utf8(allocator: std.mem.Allocator, value: a.Ref) ![:0]u8 {
    const capacity = a.CFStringGetMaximumSizeForEncoding(a.CFStringGetLength(value), a.utf8);
    if (capacity < 0) return error.InvalidTypeName;
    const buffer = try allocator.allocSentinel(u8, @intCast(capacity), 0);
    errdefer allocator.free(buffer);
    if (a.CFStringGetCString(value, buffer.ptr, @intCast(buffer.len + 1), a.utf8) == 0) return error.InvalidTypeName;
    return buffer;
}

pub fn count(board: a.Ref) !usize {
    _ = a.PasteboardSynchronize(board);
    var result: c.ItemCount = 0;
    if (a.PasteboardGetItemCount(board, &result) != 0) return error.ClipboardReadFailed;
    return result;
}

pub fn item(board: a.Ref, index: usize) !usize {
    var result: usize = 0;
    if (a.PasteboardGetItemIdentifier(board, @intCast(index), &result) != 0) return error.ClipboardReadFailed;
    return result;
}

pub fn flavors(board: a.Ref, id: usize) !a.Ref {
    var result: ?a.Ref = null;
    if (a.PasteboardCopyItemFlavors(board, id, &result) != 0) return error.ClipboardReadFailed;
    return result orelse error.ClipboardReadFailed;
}

pub fn data(board: a.Ref, id: usize, flavor: a.Ref) !a.Ref {
    var result: ?a.Ref = null;
    if (a.PasteboardCopyItemFlavorData(board, id, flavor, &result) != 0) return error.ClipboardReadFailed;
    return result orelse error.ClipboardReadFailed;
}

// System-generated conversions are not representations supplied by the sender.
pub fn isSynthetic(board: a.Ref, id: usize, flavor: a.Ref) !bool {
    var flags: u32 = 0;
    if (a.PasteboardGetItemFlavorFlags(board, id, flavor, &flags) != 0) return error.ClipboardReadFailed;
    return flags & (1 << 8) != 0; // kPasteboardFlavorSystemTranslated
}

// The caller owns the returned CFData. Never clears or writes the pasteboard.
pub fn image(board: a.Ref) !a.Ref {
    const image_type = try string("public.image");
    defer a.CFRelease(image_type);
    const readers = a.CGImageSourceCopyTypeIdentifiers() orelse return error.OutOfMemory;
    defer a.CFRelease(readers);
    const n = try count(board);
    var index: usize = 0;
    var unreadable = false;
    while (index < n) : (index += 1) {
        const id = try item(board, index + 1);
        const types = try flavors(board, id);
        defer a.CFRelease(types);
        var i: isize = 0;
        while (i < a.CFArrayGetCount(types)) : (i += 1) {
            const flavor = a.CFArrayGetValueAtIndex(types, i);
            if (try isSynthetic(board, id, flavor)) continue;
            var recognized = a.UTTypeConformsTo(flavor, image_type) != 0;
            var reader_index: isize = 0;
            while (!recognized and reader_index < a.CFArrayGetCount(readers)) : (reader_index += 1) {
                recognized = a.CFEqual(flavor, a.CFArrayGetValueAtIndex(readers, reader_index)) != 0;
            }
            if (!recognized) continue;
            const result = data(board, id, flavor) catch {
                unreadable = true;
                continue;
            };
            if (a.CFDataGetLength(result) > 0) return result;
            a.CFRelease(result);
            unreadable = true;
        }
    }
    return if (unreadable) error.ClipboardReadFailed else error.NoImage;
}

pub fn writeData(stream: ?*c.FILE, value: a.Ref) !void {
    const length: usize = @intCast(a.CFDataGetLength(value));
    if (c.fwrite(a.CFDataGetBytePtr(value), 1, length, stream) != length or c.fflush(stream) != 0)
        return error.WriteFailed;
}

pub fn help(args: []const [:0]const u8) !bool {
    if (args.len == 0) return false;
    if (args.len == 1 and (std.mem.eql(u8, args[0], "-h") or std.mem.eql(u8, args[0], "--help"))) return true;
    return error.UnexpectedArgument;
}

test "unit: read-only command arguments" {
    try std.testing.expect(!try help(&.{}));
    try std.testing.expect(try help(&.{"--help"}));
    try std.testing.expect(try help(&.{"-h"}));
    try std.testing.expectError(error.UnexpectedArgument, help(&.{"file.png"}));
    try std.testing.expectError(error.UnexpectedArgument, help(&.{ "--help", "extra" }));
}

pub const Selection = struct {
    name: ?[:0]const u8 = null,
    args: []const [:0]const u8,
};

pub fn select(args: []const [:0]const u8) !Selection {
    if (args.len == 0 or !std.mem.eql(u8, args[0], "--pasteboard")) return .{ .args = args };
    if (args.len < 2 or args[1].len == 0) return error.ExpectedPasteboardName;
    for (args[1]) |ch| {
        if (ch < 32 or ch == 127) return error.InvalidPasteboardName;
    }
    return .{ .name = args[1], .args = args[2..] };
}

test "unit: named pasteboard selection" {
    try std.testing.expect((try select(&.{})).name == null);
    const selected = try select(&.{ "--pasteboard", "test.board", "-" });
    try std.testing.expectEqualStrings("test.board", selected.name.?);
    try std.testing.expectEqualStrings("-", selected.args[0]);
    try std.testing.expectError(error.ExpectedPasteboardName, select(&.{"--pasteboard"}));
    try std.testing.expectError(error.ExpectedPasteboardName, select(&.{ "--pasteboard", "" }));
    try std.testing.expectError(error.InvalidPasteboardName, select(&.{ "--pasteboard", "bad\nname" }));
    try std.testing.expect((try select(&.{ "--", "--pasteboard" })).name == null);
}
