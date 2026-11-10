// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

const std = @import("std");
const a = @import("apple.zig");
const c = @import("c");
const clipboard = @import("clipboard.zig");

fn list(allocator: std.mem.Allocator, stream: ?*c.FILE, label: [:0]const u8, board: a.Ref) !void {
    const n = try clipboard.count(board);
    if (n == 0) {
        if (c.fprintf(stream, "%s\t-\t-\t0\n", label.ptr) < 0) return error.WriteFailed;
    }
    var index: usize = 0;
    while (index < n) : (index += 1) {
        const id = try clipboard.item(board, index + 1);
        const types = try clipboard.flavors(board, id);
        defer a.CFRelease(types);
        var i: isize = 0;
        while (i < a.CFArrayGetCount(types)) : (i += 1) {
            const flavor = a.CFArrayGetValueAtIndex(types, i);
            if (try clipboard.isSynthetic(board, id, flavor)) continue;
            const capacity = a.CFStringGetMaximumSizeForEncoding(a.CFStringGetLength(flavor), a.utf8);
            if (capacity < 0) return error.InvalidTypeName;
            const name = try allocator.alloc(u8, @as(usize, @intCast(capacity)) + 1);
            defer allocator.free(name);
            if (a.CFStringGetCString(flavor, name.ptr, @intCast(name.len), a.utf8) == 0) return error.InvalidTypeName;
            // Keep each row on one line even for unusual application-defined types.
            for (name[0..std.mem.indexOfScalar(u8, name, 0).?]) |*ch| {
                if (ch.* == '\t' or ch.* == '\n' or ch.* == '\r') ch.* = '?';
            }
            const value = clipboard.data(board, id, flavor) catch {
                if (c.fprintf(stream, "%s\t%zu\t%s\t?\n", label.ptr, index + 1, name.ptr) < 0) return error.WriteFailed;
                continue;
            };
            defer a.CFRelease(value);
            if (c.fprintf(stream, "%s\t%zu\t%s\t%ld\n", label.ptr, index + 1, name.ptr, a.CFDataGetLength(value)) < 0) return error.WriteFailed;
        }
    }
    if (c.fflush(stream) != 0) return error.WriteFailed;
}

fn formats(allocator: std.mem.Allocator, stream: ?*c.FILE) !void {
    const types = a.CGImageSourceCopyTypeIdentifiers() orelse return error.OutOfMemory;
    defer a.CFRelease(types);
    if (c.fputs("TYPE\tEXTENSION\tMIME\n", stream) < 0) return error.WriteFailed;
    var i: isize = 0;
    while (i < a.CFArrayGetCount(types)) : (i += 1) {
        const image_type = a.CFArrayGetValueAtIndex(types, i);
        const name = try clipboard.utf8(allocator, image_type);
        defer allocator.free(name);
        const extension = a.UTTypeCopyPreferredTagWithClass(image_type, a.kUTTagClassFilenameExtension);
        defer if (extension) |value| a.CFRelease(value);
        const mime = a.UTTypeCopyPreferredTagWithClass(image_type, a.kUTTagClassMIMEType);
        defer if (mime) |value| a.CFRelease(value);
        const extension_text = if (extension) |value| try clipboard.utf8(allocator, value) else try allocator.dupeSentinel(u8, "-", 0);
        defer allocator.free(extension_text);
        const mime_text = if (mime) |value| try clipboard.utf8(allocator, value) else try allocator.dupeSentinel(u8, "-", 0);
        defer allocator.free(mime_text);
        if (c.fprintf(stream, "%s\t%s\t%s\n", name.ptr, extension_text.ptr, mime_text.ptr) < 0) return error.WriteFailed;
    }
    if (c.fflush(stream) != 0) return error.WriteFailed;
}

fn run(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    const selection = try clipboard.select(args[1..]);
    if (selection.args.len == 1 and std.mem.eql(u8, selection.args[0], "--formats")) {
        if (selection.name != null) return error.UnexpectedArgument;
        try formats(allocator, c.stdout());
        return;
    }
    if (try clipboard.help(selection.args)) {
        _ = c.fputs("Usage: pblist [--pasteboard name]\n       pblist --formats\nList supported image formats or standard macOS pasteboards, item types, and byte counts.\n", c.stdout());
        return;
    }
    if (c.fputs("PASTEBOARD\tITEM\tTYPE\tBYTES\n", c.stdout()) < 0) return error.WriteFailed;
    if (selection.name) |name| {
        const board = try clipboard.named(name);
        defer a.CFRelease(board);
        try list(allocator, c.stdout(), name, board);
        return;
    }
    const names = [_]a.Ref{ a.NSPasteboardNameGeneral, a.NSPasteboardNameFind, a.NSPasteboardNameFont, a.NSPasteboardNameRuler };
    const labels = [_][:0]const u8{ "general", "find", "font", "ruler" };
    var failed = false;
    for (names, labels) |name, label| {
        const board = clipboard.open(name) catch {
            _ = c.fprintf(c.stderr(), "pblist: %s: ClipboardUnavailable\n", label.ptr);
            failed = true;
            continue;
        };
        defer a.CFRelease(board);
        try list(allocator, c.stdout(), label, board);
    }
    if (failed) return error.ClipboardUnavailable;
}

pub fn main(init: std.process.Init) void {
    run(init) catch |err| {
        _ = c.fprintf(c.stderr(), "pblist: %s\n", @errorName(err).ptr);
        std.process.exit(1);
    };
}

test "clipboard: list empty and multiple representations with exact sizes" {
    const board = try clipboard.open(null);
    defer a.CFRelease(board);
    try std.testing.expectEqual(@as(i32, 0), a.PasteboardClear(board));
    const file = c.tmpfile() orelse return error.CannotOpenFile;
    defer _ = c.fclose(file);
    try list(std.testing.allocator, file, "test", board);
    const types = [_][:0]const u8{ "public.utf8-plain-text", "public.png" };
    const bytes = [_][]const u8{ "hello", @embedFile("testdata/transparent.png") };
    for (types, bytes) |name, value| {
        const flavor = try clipboard.string(name);
        defer a.CFRelease(flavor);
        const data = a.CFDataCreate(null, value.ptr, @intCast(value.len)) orelse return error.OutOfMemory;
        defer a.CFRelease(data);
        try std.testing.expectEqual(@as(i32, 0), a.PasteboardPutItemFlavor(board, 1, flavor, data, 0));
    }
    try list(std.testing.allocator, file, "test", board);
    c.rewind(file);
    var buffer: [1024]u8 = undefined;
    const n = c.fread(&buffer, 1, buffer.len, file);
    const expected = try std.testing.allocator.print("test\t-\t-\t0\ntest\t1\tpublic.utf8-plain-text\t5\ntest\t1\tpublic.png\t{d}\n", .{bytes[1].len});
    defer std.testing.allocator.free(expected);
    // macOS may also publish unflagged text-encoding aliases. Verify our
    // supplied representations without assuming these aliases are absent.
    try std.testing.expect(std.mem.startsWith(u8, buffer[0..n], expected));
    try std.testing.expect(std.mem.indexOf(u8, buffer[0..n], "public.jpeg") == null);
    try std.testing.expect(std.mem.indexOf(u8, buffer[0..n], "public.tiff") == null);
}

test "unit: format catalog includes native image readers and tags" {
    const file = c.tmpfile() orelse return error.CannotOpenFile;
    defer _ = c.fclose(file);
    try formats(std.testing.allocator, file);
    c.rewind(file);
    var buffer: [32768]u8 = undefined;
    const n = c.fread(&buffer, 1, buffer.len, file);
    try std.testing.expect(n < buffer.len);
    try std.testing.expect(std.mem.startsWith(u8, buffer[0..n], "TYPE\tEXTENSION\tMIME\n"));
    try std.testing.expect(std.mem.indexOf(u8, buffer[0..n], "public.png\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer[0..n], "public.rtf\t") == null);
}

test "clipboard: report EPS RTF and arbitrary application types" {
    const board = try clipboard.open(null);
    defer a.CFRelease(board);
    try std.testing.expectEqual(@as(i32, 0), a.PasteboardClear(board));
    const types = [_][:0]const u8{ "com.adobe.encapsulated-postscript", "public.rtf", "org.pbimgcopy.test-data" };
    const bytes = [_][]const u8{ "%!PS-Adobe-3.0 EPSF-3.0\n%%BoundingBox: 0 0 1 1\n", "{\\rtf1 test}", "opaque" };
    for (types, bytes, 1..) |name, value, id| {
        const flavor = try clipboard.string(name);
        defer a.CFRelease(flavor);
        const data = a.CFDataCreate(null, value.ptr, @intCast(value.len)) orelse return error.OutOfMemory;
        defer a.CFRelease(data);
        try std.testing.expectEqual(@as(i32, 0), a.PasteboardPutItemFlavor(board, id, flavor, data, 0));
    }
    const file = c.tmpfile() orelse return error.CannotOpenFile;
    defer _ = c.fclose(file);
    try list(std.testing.allocator, file, "test", board);
    c.rewind(file);
    var buffer: [8192]u8 = undefined;
    const n = c.fread(&buffer, 1, buffer.len, file);
    for (types, bytes, 1..) |name, value, id| {
        const row = try std.testing.allocator.print("test\t{d}\t{s}\t{d}\n", .{ id, name, value.len });
        defer std.testing.allocator.free(row);
        try std.testing.expect(std.mem.indexOf(u8, buffer[0..n], row) != null);
    }
}
