#!/usr/bin/env sh

set -x

mode=release
release_flag=--release
package=leaf-ffi
name=leaf
lib=lib$name.a

# The script is assumed to run in the root of the workspace
base=$(dirname "$0")

# Debug or release build?
if [ "$1" = "debug" ]; then
	mode=debug
	release_flag=
fi

echo "x86_64-apple-ios-macabi and aarch64-apple-ios-macabi require the nightly toolchain"
rustup toolchain install nightly
rustup default nightly

# to allow for abi builds from the nightly toolchain for xargo...
rustup component add rust-src

echo "▸ Install xargo"
cargo install xargo

# Build for all desired targets
rustup target add aarch64-apple-ios
rustup target add aarch64-apple-ios-macabi
rustup target add x86_64-apple-ios-macabi

cargo build -p $package $release_flag --no-default-features --features "default-openssl" --target aarch64-apple-ios

echo "▸ x86_64-apple-ios-macabi"
xargo build -Zbuild-std -p $package $release_flag --no-default-features --features "default-openssl" --target x86_64-apple-ios-macabi

echo "▸ aarch64-apple-ios-macabi"
#xargo build --target aarch64-apple-ios-macabi --package automerge-c --release
xargo build -Zbuild-std -p $package $release_flag --no-default-features --features "default-openssl" --target aarch64-apple-ios-macabi

# Directories to put the libraries.
rm -rf target/apple/$mode
mkdir -p target/apple/$mode/include
mkdir -p target/apple/$mode/ios
mkdir -p target/apple/$mode/macCatalyst

# Put built libraries to folders where we can find them easier later
cp target/aarch64-apple-ios/$mode/$lib target/apple/$mode/ios/
# Create a single library for multiple archs	
lipo -create  \
    -arch arm64 target/aarch64-apple-ios-macabi/$mode/$lib \
    -arch x86_64 target/x86_64-apple-ios-macabi/$mode/$lib \
    -output target/apple/$mode/macCatalyst/$lib

# Generate the header file
cbindgen \
	--config $package/cbindgen.toml \
	$package/src/lib.rs > target/apple/$mode/include/$name.h

wd="$base/../target/apple/$mode"

# Remove existing artifact
rm -rf "$wd/$name.xcframework"

# A modulemap is required for the compiler to find the module when using Swift
cat << EOF > "$wd/include/module.modulemap"
module $name {
    header "$name.h"
    export *
}
EOF

# Create the XCFramework packaging both iOS and macOS static libraries, so we can
# use a single XCFramework for both platforms.
xcodebuild -create-xcframework \
	-library "$wd/ios/$lib" \
	-headers "$wd/include" \
	-library "$wd/macCatalyst/$lib" \
	-headers "$wd/include" \
	-output "$wd/$name.xcframework"

ls $wd/$name.xcframework
