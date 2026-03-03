#!/bin/bash

# Script to find unused images and videos

echo "=== Анализ использования медиафайлов ==="
echo ""

# Get all image files
echo "Поиск всех изображений..."
find ./src/assets ./public -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.gif" -o -name "*.webp" -o -name "*.svg" \) 2>/dev/null | grep -v node_modules | sed 's|^\./||' | sort > /tmp/all_images.txt

echo "Найдено изображений: $(wc -l < /tmp/all_images.txt)"

# Get all references from mdx files
echo ""
echo "Поиск ссылок на изображения..."
grep -rh "assets/" src/ --include="*.mdx" --include="*.astro" 2>/dev/null | \
  grep -oE "assets/[^\\\"\\'\\s\\)]+" | \
  sort -u > /tmp/all_refs.txt

echo "Найдено уникальных ссылок: $(wc -l < /tmp/all_refs.txt)"

# Check for unused images
echo ""
echo "=== Неиспользуемые изображения ==="
unused_count=0
unused_size=0

while read img; do
  img_name=$(basename "$img")
  if ! grep -q "$img_name" /tmp/all_refs.txt; then
    size=$(stat -f%z "$img" 2>/dev/null || stat -c%s "$img" 2>/dev/null || echo 0)
    unused_size=$((unused_size + size))
    unused_count=$((unused_count + 1))
    size_kb=$((size/1024))
    echo "${size_kb}KB - $img"
  fi
done < /tmp/all_images.txt

echo ""
echo "==========================================="
echo "Всего неиспользуемых изображений: $unused_count"
echo "Общий размер неиспользуемых: $((unused_size/1024/1024))MB"
echo "==========================================="

# Check videos
echo ""
echo "=== Проверка видео ==="
ls public/videos/*.mp4 2>/dev/null | xargs -n1 basename | sed 's/.mp4$//' | sort > /tmp/all_videos.txt
echo "Всего видео: $(wc -l < /tmp/all_videos.txt)"

grep -rh "LocalVideo" src/content/docs --include="*.mdx" | \
  grep -oE "id=[\\\"\\'][^\\\"\\']+" | \
  sed 's/id=[\\\"\\']//' | \
  sort -u > /tmp/used_videos.txt

echo "Используется видео: $(wc -l < /tmp/used_videos.txt)"

unused_videos=$(comm -23 /tmp/all_videos.txt /tmp/used_videos.txt)
if [ -n "$unused_videos" ]; then
  echo ""
  echo "=== Неиспользуемые видео ==="
  echo "$unused_videos"
else
  echo ""
  echo "✓ Все видео используются"
fi
