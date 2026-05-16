#!/bin/bash

#

set -e

if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <zipfile> <gcs_path>"
    echo "Example: $0 archive.zip gs://jam-archive/photos/2024"
    echo "Will extract the zip, convert all .HEIC files to JPG and all .MOV files to .MP4, then rysnc to the provided Google Cloud Platform Cloud Storage bucket path."
    echo "Expects the zip to have no folders (i.e. what the standard Gooogle Photos download is) but you can easily adapt to the kind of the archive you get from Google Takeout. Note that Google Takeout gives you 'sidecar' JSON files. Those can be ignored."
    exit 1
fi

ZIPFILE=$1
GCS_TARGET=$2
LOGFILE="process-$(date +%Y%m%d-%H%M%S).log"

# Monitoring function
report() {
    local label=$1
    local dir=$2
    local count=$(find "$dir" -type f 2>/dev/null | wc -l)
    echo "[$label] $dir: $count files" | tee -a "$LOGFILE"
}

echo "Starting media processing at $(date)" | tee "$LOGFILE"

mkdir -p heic-discards mov-discards new-jpgs new-mp4s raw processed
cd raw/
unzip "$ZIPFILE" | tee -a "../$LOGFILE"
rm "$ZIPFILE"
cd ..

echo "=== HEIC Conversion ===" | tee -a "$LOGFILE"
START=$(date +%s)
find raw/ -iname "*.HEIC" | parallel "magick {} -quality 40 new-jpgs/{/.}.jpg && exiftool -TagsFromFile {} -all:all --Orientation --ThumbnailImage -overwrite_original new-jpgs/{/.}.jpg && mv {} heic-discards/" 2>&1 | tee -a "$LOGFILE"
ELAPSED=$(($(date +%s) - START))
report "HEIC→JPG" "new-jpgs"
report "Discarded HEIC" "heic-discards"
echo "HEIC conversion took ${ELAPSED}s" | tee -a "$LOGFILE"

echo "=== MOV Conversion ===" | tee -a "$LOGFILE"
START=$(date +%s)
find raw/ -iname "*.MOV" | parallel --line-buffer -j1 'ffmpeg -i "{}" -map 0:v -map 0:a -map 0:s? -map_metadata 0 -c:v libx265 -preset medium -crf 26 -tag:v hvc1 -c:a copy -movflags use_metadata_tags+write_colr+faststart "{.}.mp4" && touch -r "{}" "{.}.mp4" && mv "{}" mov-discards/ && mv "{.}.mp4" new-mp4s/' 2>&1 | tee -a "$LOGFILE"
ELAPSED=$(($(date +%s) - START))
report "MOV→MP4" "new-mp4s"
report "Discarded MOV" "mov-discards"
echo "MOV conversion took ${ELAPSED}s" | tee -a "$LOGFILE"

echo "=== Organizing into processed ===" | tee -a "$LOGFILE"
ls -la raw/ | tee -a "$LOGFILE"
mv new-jpgs/* processed/ 2>/dev/null || true
mv new-mp4s/* processed/ 2>/dev/null || true
mv raw/* processed/ 2>/dev/null || true

echo "=== Before Rsync ===" | tee -a "$LOGFILE"
BEFORE=$(gcloud storage ls -r "$GCS_TARGET" 2>/dev/null | wc -l)
echo "Files in GCS before rsync: $BEFORE" | tee -a "$LOGFILE"

echo "=== Rsyncing to GCS ===" | tee -a "$LOGFILE"
cd processed/
START=$(date +%s)
gcloud storage rsync --recursive . "$GCS_TARGET" 2>&1 | tee -a "../$LOGFILE"
ELAPSED=$(($(date +%s) - START))
AFTER=$(gcloud storage ls -r "$GCS_TARGET" 2>/dev/null | wc -l)
echo "Files in GCS after rsync: $AFTER (added $((AFTER - BEFORE)))" | tee -a "../$LOGFILE"
echo "Rsync took ${ELAPSED}s" | tee -a "../$LOGFILE"

echo "=== Adding GPS Metadata ===" | tee -a "../$LOGFILE"
GPS_TMPFILE=$(mktemp)
find . -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.mp4" \) -print0 | xargs -0 exiftool -n -p '${filename},${composite:gpslatitude},${composite:gpslongitude}' 2>/dev/null | grep -v '^[^,]*,,$' | while IFS=',' read filename lat lon; do
    gcloud storage objects update "$GCS_TARGET$(basename "$filename")" --update-custom-metadata="gps-latitude=$lat,gps-longitude=$lon" 2>&1 | tee -a "../$LOGFILE"
    echo "1" >> "$GPS_TMPFILE"
done
GPS_COUNT=$(wc -l < "$GPS_TMPFILE" 2>/dev/null || echo 0)
rm -f "$GPS_TMPFILE"
echo "GPS metadata added to $GPS_COUNT files" | tee -a "../$LOGFILE"

echo "Processing complete at $(date)" | tee -a "../$LOGFILE"
echo "Log saved to: $LOGFILE"
