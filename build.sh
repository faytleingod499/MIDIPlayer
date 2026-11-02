#!/bin/bash
# Makes the zips from package/ (rebuild package/MIDIPlayer/MIDIPlayer.pck first with pack.gd, see the README):
#   out/MIDIPlayer-<version>.zip   the Thunderstore upload
set -e
cd "$(dirname "$0")"
mkdir -p out
V=$(python3 -c "import json;print(json.load(open('thunderstore/manifest.json'))['version_number'])")
rm -f out/MIDIPlayer-$V.zip
T=$(mktemp -d)
cp thunderstore/manifest.json thunderstore/README.md thunderstore/CHANGELOG.md thunderstore/icon.png $T/
cp LICENSE $T/
mkdir -p $T/GDWeave/mods/MIDIPlayer
cp package/MIDIPlayer/manifest.json package/MIDIPlayer/MIDIPlayer.pck $T/GDWeave/mods/MIDIPlayer/
(cd $T && zip -qr - .) > out/MIDIPlayer-$V.zip
rm -rf $T
echo "out/MIDIPlayer-$V.zip"
