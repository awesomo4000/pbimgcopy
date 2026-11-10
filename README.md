# PBIMGCOPY(1), PBIMGPASTE(1), PBLIST(1)

## NAME

pbimgcopy, pbimgpaste, pblist - image clipboard utilities for macOS

## SYNOPSIS

```text
pbimgcopy  [--pasteboard name] [--] file
pbimgcopy  [--pasteboard name] [-] < file
pbimgpaste [--pasteboard name] > file
pblist     [--pasteboard name]
pblist     --formats
```

## DESCRIPTION

`pbimgcopy` replaces the clipboard with an image read from a file or
standard input. Accepts formats recognized by macOS ImageIO, including
WebP, HEIC, AVIF, and camera RAW where supported.

`pbimgpaste` writes the first available image representation to standard
output, in pasteboard order. Refuses terminal output. Fails if no image
is present. Does not alter the clipboard.

`pblist` reports the general, find, font, and ruler pasteboards. Output is
tab-separated: PASTEBOARD, ITEM, TYPE, BYTES. Each representation occupies
one row. An item may have several representations. Empty boards show `-`
for item and type; unreadable data shows `?` for bytes. Lists all supplied
types, including text, RTF, EPS, and application-defined data.

Image bytes and format are preserved. No resizing or conversion.
Representations marked as system conversions are skipped. Check the type
with `pblist`; a filename extension does not select a format.

`pblist --formats` lists this Mac's ImageIO readers as TYPE, EXTENSION,
and MIME; `-` denotes unavailable type metadata. This is the image input
catalog, not a whitelist for clipboard inspection. Formats vary by macOS
version. EPS and RTF are listed when present, not accepted as image input.

## OPTIONS

```text
--pasteboard name  Use the named pasteboard. Must precede other arguments.
                   For pblist, list only this board.
-h, --help         Print usage.
```

For `pbimgcopy` only:

```text
-                  Read standard input. Default when no file is given.
--                 Treat the next argument as a filename.
```

## EXIT STATUS

0 on success; 1 on error. Diagnostics go to standard error.

## EXAMPLES

```sh
pbimgcopy < image.png
pblist
pbimgpaste > copy.png
cmp image.png copy.png

cat photo.jpg | pbimgcopy -
pbimgpaste > copy.jpg
pblist --formats
```

## INSTALLATION

macOS only. Build with Zig 0.17.0 and Apple Command Line Tools.
No third-party runtime dependencies.

```sh
mise trust
mise install
mise run build
install -m 755 zig-out/bin/pbimgcopy zig-out/bin/pbimgpaste zig-out/bin/pblist /usr/local/bin/
```

Without mise: `zig build -Doptimize=small`.

## TESTS

```sh
mise run test       # full suite
mise run test-e2e   # copy, list, paste, compare
mise run test-unit  # no pasteboard access
```

Pasteboard tests require a desktop session and use isolated boards.
End-to-end tests check types, byte counts, and exact file contents through
files, pipes, and redirected input: PNG, JPEG, GIF, TIFF, WebP, BMP, ICO,
JPEG 2000, PSD, TGA, OpenEXR, HEIC, AVIF, and JPEG XL. Unsupported formats
are reported as skipped. EPS and RTF listing is tested separately.
Fixtures are included; no image encoders are needed to run the tests.
The current clipboard is untouched.

## NOTES

Image data is held in memory. Reading byte counts may ask the owning
application to supply data. Private pasteboards cannot be enumerated;
a known name may be supplied explicitly.

## SEE ALSO

pbcopy(1), pbpaste(1), screencapture(1)

## LICENSE

Mozilla Public License 2.0. See [LICENSE](LICENSE).
