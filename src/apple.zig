// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// C ABI declarations from the macOS SDK. No Objective-C runtime bridge needed.
pub const Ref = *const anyopaque;
pub extern "c" fn CFRelease(Ref) void;
pub extern "c" fn CFDataCreate(?Ref, [*]const u8, isize) ?Ref;
pub extern "c" fn CFDataGetLength(Ref) isize;
pub extern "c" fn CFDataGetBytePtr(Ref) [*]const u8;
pub extern "c" fn CFStringCreateWithCString(?Ref, [*:0]const u8, u32) ?Ref;
pub extern "c" fn CFStringGetCString(Ref, [*]u8, isize, u32) u8;
pub const utf8 = 0x08000100;

pub extern "c" fn CGImageSourceCreateWithData(Ref, ?Ref) ?Ref;
pub extern "c" fn CGImageSourceGetType(Ref) ?Ref;
pub extern "c" fn CGImageSourceGetCount(Ref) usize;
pub extern "c" fn CGImageSourceGetStatus(Ref) c_int;

pub extern "c" fn PasteboardCreate(?Ref, *?Ref) i32;
pub extern "c" fn PasteboardClear(Ref) i32;
pub extern "c" fn PasteboardPutItemFlavor(Ref, usize, Ref, Ref, u32) i32;
pub extern "c" fn PasteboardCopyItemFlavorData(Ref, usize, Ref, *?Ref) i32;

pub extern "c" fn PasteboardSynchronize(Ref) u32;
pub extern "c" fn PasteboardGetItemCount(Ref, *@import("c").ItemCount) i32;
pub extern "c" fn PasteboardGetItemIdentifier(Ref, isize, *usize) i32;
pub extern "c" fn PasteboardCopyItemFlavors(Ref, usize, *?Ref) i32;
pub extern "c" fn PasteboardGetItemFlavorFlags(Ref, usize, Ref, *u32) i32;
pub extern "c" fn CFArrayGetCount(Ref) isize;
pub extern "c" fn CFArrayGetValueAtIndex(Ref, isize) Ref;
pub extern "c" fn CFStringGetLength(Ref) isize;
pub extern "c" fn CFStringGetMaximumSizeForEncoding(isize, u32) isize;
pub extern "c" fn UTTypeConformsTo(Ref, Ref) u8;
pub extern "c" const NSPasteboardNameGeneral: Ref;
pub extern "c" const NSPasteboardNameFind: Ref;
pub extern "c" const NSPasteboardNameFont: Ref;
pub extern "c" const NSPasteboardNameRuler: Ref;
pub extern "c" fn PasteboardCopyName(Ref, *?Ref) i32;
pub extern "c" fn CGImageSourceCopyTypeIdentifiers() ?Ref;
pub extern "c" fn CFEqual(Ref, Ref) u8;
pub extern "c" fn UTTypeCopyPreferredTagWithClass(Ref, Ref) ?Ref;
pub extern "c" const kUTTagClassFilenameExtension: Ref;
pub extern "c" const kUTTagClassMIMEType: Ref;
