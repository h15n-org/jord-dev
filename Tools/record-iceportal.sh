#!/bin/sh
# Part of Jord Dev. Copyright (C) 2026 Mikka Luster
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Records what the on-board portal of an ICE tells us about the train, to develop Jord's
# on-train features against real answers.
#
# Run it on the laptop while connected to the train's Wi-Fi (WIFIonICE):
#
#     Tools/record-iceportal.sh            # every 30 seconds until Ctrl-C
#     Tools/record-iceportal.sh 60         # every 60 seconds
#
# Each answer is saved as its own file under .secrets/samples/iceportal/ (never committed).
# Off the train the portal answers with an empty body; those are skipped.

interval="${1:-30}"
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/.secrets/samples/iceportal"
mkdir -p "$out"

echo "Recording to $out every ${interval}s. Stop with Ctrl-C."
while true; do
    stamp="$(date +%Y%m%d-%H%M%S)"
    saved=""
    for name in status tripInfo/trip; do
        file="$out/$stamp-$(echo "$name" | tr '/' '-').json"
        if curl -s -m 10 -o "$file" "https://iceportal.de/api1/rs/$name" && [ -s "$file" ]; then
            saved="$saved $(basename "$file")"
        else
            rm -f "$file"
        fi
    done
    if [ -n "$saved" ]; then
        echo "$stamp saved:$saved"
    else
        echo "$stamp no data (not on the train's Wi-Fi, or the portal is not answering)"
    fi
    sleep "$interval"
done
