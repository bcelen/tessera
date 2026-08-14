#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.0.0-SNAPSHOT"
codesign_identity="aerospace-codesign-certificate"
# --skip-docs builds just the app and the CLI. Man pages and shell completions need Ruby, Rust and
# fish, and the distributable zip and brew casks need those outputs, so all of it is skipped
# together. Enough for a personal install, not enough to cut a release.
build_docs=1
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        --skip-docs) build_docs=0; shift 1;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

#############
### BUILD ###
#############

if test $build_docs = 1; then
    ./build-docs.sh --release
    ./build-shell-completion.sh
fi

./generate.sh
./script/check-uncommitted-files.sh
./generate.sh --build-version "$build_version" --codesign-identity "$codesign_identity" --generate-git-hash

swift build -c release --arch arm64 --arch x86_64 --product aerospace-next -Xswiftc -warnings-as-errors # CLI

# todo: make xcodebuild use the same toolchain as swift
# toolchain="$(plutil -extract CFBundleIdentifier raw ~/Library/Developer/Toolchains/swift-6.1-RELEASE.xctoolchain/Info.plist)"
# xcodebuild -toolchain "$toolchain" \
# Unfortunately, Xcode 16 fails with:
#     2025-05-05 15:51:15.618 xcodebuild[4633:13690815] Writing error result bundle to /var/folders/s1/17k6s3xd7nb5mv42nx0sd0800000gn/T/ResultBundle_2025-05-05_15-51-0015.xcresult
#     xcodebuild: error: Could not resolve package dependencies:
#       <unknown>:0: warning: legacy driver is now deprecated; consider avoiding specifying '-disallow-use-new-driver'
#     <unknown>:0: error: unable to execute command: <unknown>

rm -rf .release && mkdir .release

cd ./xcode
    xcode_configuration="Release"
    xcodebuild -version
    xcodebuild-pretty ../.release/xcodebuild.log clean build \
        -scheme AeroSpaceNext \
        -destination "generic/platform=macOS" \
        -configuration "$xcode_configuration" \
        -derivedDataPath .xcode-build
cd -

git checkout .

cp -r "xcode/.xcode-build/Build/Products/$xcode_configuration/AeroSpace Next.app" .release
cp -r .build/apple/Products/Release/aerospace-next .release

################
### SIGN CLI ###
################

codesign -s "$codesign_identity" .release/aerospace-next

################
### VALIDATE ###
################

expected_layout=$(cat <<EOF
.release/AeroSpace Next.app
.release/AeroSpace Next.app/Contents
.release/AeroSpace Next.app/Contents/_CodeSignature
.release/AeroSpace Next.app/Contents/_CodeSignature/CodeResources
.release/AeroSpace Next.app/Contents/MacOS
.release/AeroSpace Next.app/Contents/MacOS/AeroSpace Next
.release/AeroSpace Next.app/Contents/Resources
.release/AeroSpace Next.app/Contents/Resources/default-config.toml
.release/AeroSpace Next.app/Contents/Resources/AppIcon.icns
.release/AeroSpace Next.app/Contents/Resources/Assets.car
.release/AeroSpace Next.app/Contents/Info.plist
.release/AeroSpace Next.app/Contents/PkgInfo
EOF
)

if test "$expected_layout" != "$(find ".release/AeroSpace Next.app")"; then
    echo "!!! Expect/Actual layout don't match !!!"
    find ".release/AeroSpace Next.app"
    exit 1
fi

check-universal-binary() {
    if ! file "$1" | grep --fixed-string -q "Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64"; then
        echo "$1 is not a universal binary"
        exit 1
    fi
}

check-contains-hash() {
    hash=$(git rev-parse HEAD)
    if ! strings "$1" | grep --fixed-string "$hash" > /dev/null; then
        echo "$1 doesn't contain $hash"
        exit 1
    fi
}

check-universal-binary ".release/AeroSpace Next.app/Contents/MacOS/AeroSpace Next"
check-universal-binary .release/aerospace-next

check-contains-hash ".release/AeroSpace Next.app/Contents/MacOS/AeroSpace Next"
check-contains-hash .release/aerospace-next

codesign -v ".release/AeroSpace Next.app"
codesign -v .release/aerospace-next

############
### PACK ###
############

if test $build_docs = 0; then
    echo
    echo "Built '.release/AeroSpace Next.app' and .release/aerospace-next"
    echo "Packaging skipped because of --skip-docs"
    exit 0
fi

mkdir -p ".release/AeroSpace-v$build_version/manpage" && cp .man/*.1 ".release/AeroSpace-v$build_version/manpage"
cp -r ./legal ".release/AeroSpace-v$build_version/legal"
cp -r .shell-completion ".release/AeroSpace-v$build_version/shell-completion"
cd .release
    mkdir -p "AeroSpace-v$build_version/bin" && cp -r aerospace-next "AeroSpace-v$build_version/bin"
    cp -r "AeroSpace Next.app" "AeroSpace-v$build_version"
    zip -r "AeroSpace-v$build_version.zip" "AeroSpace-v$build_version"
cd -

#################
### Brew Cask ###
#################
for cask_name in aerospace aerospace-dev; do
    ./script/build-brew-cask.sh \
        --cask-name "$cask_name" \
        --zip-uri ".release/AeroSpace-v$build_version.zip" \
        --build-version "$build_version"
done
