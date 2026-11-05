# PBIMGCOPY(1)

## NAME

pbimgcopy - copy an image to the macOS clipboard

## SYNOPSIS

```text
pbimgcopy [--] file
pbimgcopy [-] < file
pbimgcopy -h | --help
```

## DESCRIPTION

Copies an image from a file or standard input to the clipboard.
Preserves the original bytes and format. Does not resize or convert.

Accepts formats recognized by macOS ImageIO. The receiving application
must support the image format. Input is held in memory.

## OPTIONS

```text
-           Read standard input. This is the default when no file is given.
--          Treat the next argument as a filename.
-h, --help  Print usage.
```

## EXIT STATUS

0 on success; 1 on error. Diagnostics go to standard error.

## EXAMPLES

```sh
pbimgcopy image.png
cat photo.jpg | pbimgcopy
pbimgcopy -- -image.png
```

## INSTALLATION

Requires macOS. Building requires Zig 0.17.0 and Apple Command Line Tools.

```sh
mise trust
mise install
mise run build
install -m 755 zig-out/bin/pbimgcopy /usr/local/bin/pbimgcopy
```

Without mise: `zig build -Doptimize=small`.

## TESTS

`mise run test` uses a private pasteboard; the clipboard is untouched.
Requires a desktop session. `mise run test-unit` omits pasteboard access.

## SEE ALSO

pbcopy(1), pbpaste(1), screencapture(1)

## LICENSE

Mozilla Public License 2.0. See [LICENSE](LICENSE).
