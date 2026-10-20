#!/bin/bash
# Сжимает скриншот или запись экрана на месте.
# PNG — без потерь (oxipng). Видео — H.265 с визуально неотличимым качеством;
# новое содержимое пишется в тот же файл (дата создания и теги Finder остаются),
# оригинал уходит в Корзину, только если новый файл получился меньше.
set -u
export PATH="/opt/homebrew/bin:$PATH"

f=$1
ext=${f##*.}
dir=$(dirname "$f")
tmp="$dir/.compressing-$$.$ext"   # результат ffmpeg
orig="$dir/.original-$$.$ext"     # клон оригинала, пока перезаписываем файл
writing=""

# Прервали посреди перезаписи — возвращаем оригинал; временные файлы не оставляем.
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

    cp -c "$f" "$orig" || exit 1   # клон APFS: мгновенно и без лишнего места
    writing=1
    if cat "$tmp" > "$f"; then
      writing=""
      touch -r "$orig" "$f"
      trash "$orig"
    fi
    ;;
esac
