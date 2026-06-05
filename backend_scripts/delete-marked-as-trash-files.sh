#!/usr/bin/env bash

BUCKET=$1
echo "cat this file for deleting 'marked as trash' files"
# gcloud storage ls gs://$BUCKET/__marked_files/to-trash* | parallel -k "gcloud storage cat {} | grep 'gs://' | parallel --replace [] -j1 'gcloud storage rm [] && gcloud storage rm {}'"
