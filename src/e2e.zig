// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

const std = @import("std");
const a = @import("apple.zig");
const c = @import("c");
const clipboard = @import("clipboard.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 6) return error.ExpectedScriptBinariesAndFixtures;
    // Keep a unique board alive across the CLI processes, then empty and release it.
    const board = try clipboard.open(null);
    defer a.CFRelease(board);
    defer _ = a.PasteboardClear(board);
    var name_ref: ?a.Ref = null;
    if (a.PasteboardCopyName(board, &name_ref) != 0) return error.ClipboardUnavailable;
    const name = name_ref orelse return error.ClipboardUnavailable;
    defer a.CFRelease(name);
    var buffer: [1024]u8 = undefined;
    if (a.CFStringGetCString(name, &buffer, buffer.len, a.utf8) == 0) return error.InvalidPasteboardName;
    const result = try std.process.run(allocator, init.io, .{
        .argv = &.{ "/bin/sh", args[1], args[2], args[3], args[4], args[5], std.mem.sliceTo(&buffer, 0) },
    });
    _ = c.fwrite(result.stdout.ptr, 1, result.stdout.len, c.stdout());
    _ = c.fwrite(result.stderr.ptr, 1, result.stderr.len, c.stderr());
    if (!result.term.success()) return error.EndToEndTestFailed;
}
