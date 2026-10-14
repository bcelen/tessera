#!/usr/bin/env bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

./script/check-uncommitted-files.sh

rm -rf ~/Library/Developer/Xcode/DerivedData/Tessera-*
rm -rf ./.xcode-build

rm -rf xcode/Tessera.xcodeproj
./generate.sh
