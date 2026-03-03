#!/bin/bash

echo "============================================================"
echo "DOCKER CONTAINER TEST REPORT"
echo "============================================================"

# Container info
echo ""
echo "[1] Container Info:"
docker ps --filter "name=platform-docs-test" --format "Name: {{.Names}} | Status: {{.Status}} | Ports: {{.Ports}}"

# Image size
echo ""
echo "[2] Image Size:"
docker images intabiafusion/platform-docs:test --format "{{.Repository}}:{{.Tag}} - {{.Size}}"

# Test page load times
echo ""
echo "[3] Page Load Performance Tests:"
echo "--------------------------------"

pages=(
  "/docs/"
  "/docs/ru/getting-started/introduction-platform/"
  "/docs/en/getting-started/introduction-platform/"
  "/docs/ru/task-tracking/creating-issues/"
  "/docs/en/task-tracking/creating-issues/"
  "/docs/ru/knowledge-management/documents/"
)

total_time=0
for page in "${pages[@]}"; do
  result=$(curl -s -o /dev/null -w "%{http_code}|%{time_total}|%{size_download}" "http://localhost:8080$page")
  IFS='|' read -r code time size <<< "$result"
  status="✓"
  [[ "$code" != "200" ]] && status="✗"
  size_kb=$(echo "scale=1; $size / 1024" | bc)
  printf "%s %s | Status: %s | Time: %.3fs | Size: %.1fKB\n" "$status" "$page" "$code" "$time" "$size_kb"
  total_time=$(echo "$total_time + $time" | bc)
done

avg_time=$(echo "scale=4; $total_time / ${#pages[@]}" | bc)
echo ""
echo "Average load time: ${avg_time}s"

# Test static assets
echo ""
echo "[4] Static Assets Performance Tests:"
echo "-------------------------------------"

assets=(
  "/docs/_astro/ec.p1z7b.js"
  "/docs/_astro/ec.v4551.css"
  "/docs/_astro/ui-core.I_3Ytv7a.js"
)

for asset in "${assets[@]}"; do
  result=$(curl -s -o /dev/null -w "%{http_code}|%{time_total}|%{size_download}" "http://localhost:8080$asset")
  IFS='|' read -r code time size <<< "$result"
  status="✓"
  [[ "$code" != "200" ]] && status="✗"
  size_kb=$(echo "scale=1; $size / 1024" | bc)
  printf "%s %s | Status: %s | Time: %.3fs | Size: %.1fKB\n" "$status" "$asset" "$code" "$time" "$size_kb"
done

# Check redirects
echo ""
echo "[5] Redirect Tests:"
echo "------------------"
root_response=$(curl -s -o /dev/null -w "%{http_code}|%{redirect_url}" "http://localhost:8080/")
echo "Root / redirects to: $root_response"

# Test nginx gzip compression
echo ""
echo "[6] Compression Test:"
echo "--------------------"
compressed=$(curl -s -o /dev/null -w "%{size_download}" -H "Accept-Encoding: gzip" "http://localhost:8080/docs/")
uncompressed=$(curl -s -o /dev/null -w "%{size_download}" "http://localhost:8080/docs/")
if [ "$compressed" -lt "$uncompressed" ]; then
  ratio=$(echo "scale=1; ($uncompressed - $compressed) * 100 / $uncompressed" | bc)
  echo "✓ Gzip compression working - ${ratio}% reduction"
  echo "  Uncompressed: ${uncompressed} bytes"
  echo "  Compressed: ${compressed} bytes"
else
  echo "✗ Gzip compression not working"
fi

echo ""
echo "============================================================"
echo "TEST SUMMARY ✓"
echo "============================================================"
