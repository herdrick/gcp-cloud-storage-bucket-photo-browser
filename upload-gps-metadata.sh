#!/bin/bash
set -e

LOCAL_DIR="${1:-.}"
BUCKET="${2:-gs://jam-archive/2025}"

echo "Scanning $LOCAL_DIR for JPEGs with GPS data..."
echo "Will update objects in: $BUCKET"
echo

find "$LOCAL_DIR" -type f -iname '*.jpg' | while read -r local_file; do
  # Extract GPS (outputs lat on line 1, lon on line 2, or nothing)
  gps_data=$(exiftool -n -s -s -s -GPSLatitude -GPSLongitude "$local_file" 2>/dev/null || true)
  lat=$(echo "$gps_data" | head -1)
  lon=$(echo "$gps_data" | tail -1)

  if [[ -n "$lat" && -n "$lon" && "$lat" != "$lon" ]]; then
    # Get relative path and construct GCS object path
    rel_path="${local_file#$LOCAL_DIR/}"
    gcs_path="$BUCKET/$rel_path"

    echo "✓ $rel_path → GPS: $lat, $lon"
    gcloud storage objects update "$gcs_path" \
      --update-custom-metadata="gps-latitude=$lat,gps-longitude=$lon" \
      --quiet
  else
    echo "✗ $local_file (no GPS data)"
  fi
done

echo
echo "Done. Check a file with: gcloud storage objects describe gs://jam-archive/2025/path/to/file.jpg"
