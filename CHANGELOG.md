# Changelog

## 11/10/2026

- Add pbimgpaste to write original clipboard image bytes to stdout.
- Add pblist to report pasteboard types and byte counts, including EPS and RTF.
- Add pblist --formats to list installed image readers, extensions, and MIME types.
- Add --pasteboard to select a named pasteboard in all three tools.
- Add isolated CLI round trips for 14 image formats through files, pipes, and stdin.
- Document all three commands in manual-page style.

## 11/05/2026

- Replace the shell script with a standalone Zig executable using macOS system frameworks.
- Preserve the original image format and bytes instead of converting to JPEG.
- Add mise setup pinned to Zig 0.17.0, build and test tasks, and installation instructions.
- Add argument validation and tests for exact image bytes on a private pasteboard.
- License under MPL 2.0 and document usage in manual-page style.
