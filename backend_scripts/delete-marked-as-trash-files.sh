#!/usr/bin/env bash

BUCKET=$1

echo "looking for files like gs://$BUCKET/__marked_files/to-trash ..."
gcloud storage ls gs://$BUCKET/__marked_files/to-trash* | parallel --line-buffer --keep-order --jobs 1 "gcloud storage cat {} | grep 'gs://' | parallel --line-buffer --keep-order --jobs 1 --replace [] 'gcloud storage rm [] ; gcloud storage rm {}'"
