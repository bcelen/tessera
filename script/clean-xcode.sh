#!/usr/bin/env bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

./script/check-uncommitted-files.sh

rm -rf ~/Library/Developer/Xcode/DerivedData/AeroSpaceNext-*
rm -rf ./.xcode-build

rm -rf xcode/AeroSpaceNext.xcodeproj
./generate.sh
