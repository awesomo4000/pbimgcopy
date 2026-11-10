#!/bin/sh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
set -eu
copy=$1
paste=$2
list=$3
fixtures=$4
board=$5
work=$(mktemp -d /tmp/pbimgcopy-e2e.XXXXXX)
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

# Every invocation names the isolated board, including failure cases.
if "$paste" --pasteboard "$board" > "$work/empty" 2> "$work/error"; then
    echo 'empty pasteboard unexpectedly produced an image' >&2
    exit 1
fi
test ! -s "$work/empty"
grep -q 'NoImage' "$work/error"
"$list" --pasteboard "$board" > "$work/list"
printf 'PASTEBOARD\tITEM\tTYPE\tBYTES\n%s\t-\t-\t0\n' "$board" > "$work/expected"
cmp "$work/expected" "$work/list"

"$list" --formats > "$work/formats"
for entry in transparent.png:public.png photo.jpg:public.jpeg animated.gif:com.compuserve.gif image.tiff:public.tiff image.webp:org.webmproject.webp image.bmp:com.microsoft.bmp image.ico:com.microsoft.ico image.jp2:public.jpeg-2000 image.psd:com.adobe.photoshop-image image.tga:com.truevision.tga-image image.exr:com.ilm.openexr-image image.heic:public.heic image.avif:public.avif image.jxl:public.jpeg-xl; do
    file=${entry%%:*}
    type=${entry#*:}
    if ! awk -F '\t' -v type="$type" '$1 == type { found = 1 } END { exit !found }' "$work/formats"; then
        case "$type" in
            public.png|public.jpeg|com.compuserve.gif|public.tiff)
                printf 'Missing required image reader: %s\n' "$type" >&2
                exit 1
                ;;
        esac
        printf 'SKIP %s (not supported by this macOS)\n' "$file"
        continue
    fi
    bytes=$(wc -c < "$fixtures/$file" | tr -d ' ')
    for mode in redirect pipe filename; do
        case "$mode" in
            redirect) "$copy" --pasteboard "$board" < "$fixtures/$file" > "$work/status" ;;
            pipe) cat "$fixtures/$file" | "$copy" --pasteboard "$board" - > "$work/status" ;;
            filename) "$copy" --pasteboard "$board" "$fixtures/$file" > "$work/status" ;;
        esac
        "$list" --pasteboard "$board" > "$work/list"
        printf 'PASTEBOARD\tITEM\tTYPE\tBYTES\n%s\t1\t%s\t%s\n' "$board" "$type" "$bytes" > "$work/expected"
        if ! cmp "$work/expected" "$work/list"; then
            printf 'Listing mismatch for %s (%s):\n' "$file" "$mode" >&2
            cat "$work/expected" "$work/list" >&2
            exit 1
        fi
        "$paste" --pasteboard "$board" > "$work/restored"
        cmp "$fixtures/$file" "$work/restored"
        # A failed copy must not clear the previous image.
        if printf 'not an image' | "$copy" --pasteboard "$board" > "$work/status" 2> "$work/error"; then
            echo 'invalid image unexpectedly accepted' >&2
            exit 1
        fi
        "$paste" --pasteboard "$board" > "$work/restored"
        cmp "$fixtures/$file" "$work/restored"
        printf 'PASS %s (%s)\n' "$file" "$mode"
    done
done
