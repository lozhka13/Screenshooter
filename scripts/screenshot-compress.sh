#!/bin/bash
# Compresses a screenshot or screen recording in place.
# PNG — lossless (oxipng). Video — H.265 at visually lossless quality;
# the new content is written into the same file (creation date and Finder tags are kept),
# and the original goes to the Trash only if the new file is smaller.
set -u
export PATH="/opt/homebrew/bin:$PATH"

f=$1
ext=${f##*.}
dir=$(dirname "$f")
tmp="$dir/.compressing-$$.$ext"   # ffmpeg output
orig="$dir/.original-$$.$ext"     # clone of the original while the file is rewritten
writing=""

# Interrupted mid-rewrite — restore the original; never leave temp files behind.
cleanup() {
  if [ -n "$writing" ] && [ -e "$orig" ]; then
    cat "$orig" > "$f" && touch -r "$orig" "$f"
  fi
  rm -f "$tmp" "$orig"
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP

case "$(echo "$ext" | tr '[:upper:]' '[:lower:]')" in
  png)
    oxipng -o 4 --strip safe -p -q "$f"
    ;;
  mov|mp4)
    ffmpeg -nostdin -loglevel error -y -i "$f" -map 0:v:0 -map '0:a?' \
      -c:v libx265 -crf 22 -preset medium -tag:v hvc1 -pix_fmt yuv420p \
      -x265-params log-level=error -fps_mode passthrough \
      -c:a copy -movflags +faststart "$tmp" || exit 1
    [ "$(stat -f %z "$tmp")" -lt "$(stat -f %z "$f")" ] || exit 0

    cp -c "$f" "$orig" || exit 1   # APFS clone: instant and takes no extra space
    writing=1
    if cat "$tmp" > "$f"; then
      writing=""
      touch -r "$orig" "$f"
      trash "$orig"
    fi
    ;;
esac
