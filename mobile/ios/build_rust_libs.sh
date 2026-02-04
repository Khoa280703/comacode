#!/bin/bash
set -e

# Flutter Rust Bridge - Auto-build iOS libraries
# This script runs before Xcode "Compile Sources" phase
# to ensure latest Rust code is always used

echo "🦀 Building Rust libraries for iOS..."

# Add Rust toolchain, Go, and Homebrew to PATH (Xcode doesn't inherit full PATH)
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"

# Navigate to project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/../.."
IOS_LIBS="$SCRIPT_DIR/RustLibs"

cd "$PROJECT_ROOT"

# ===== ENV VARS FOR aws-lc-sys iOS CROSS-COMPILATION =====
# Force aws-lc-sys to build from source with proper iOS toolchain
export PKG_CONFIG_ALLOW_CROSS=1
export AWS_LC_SYS_FIPS_LINK_PRECOMPILED=0
export AWS_LC_SYS_STATIC=1

# Ensure Go is available for aws-lc-sys (needs go_tests.txt generation)
if ! command -v go &> /dev/null; then
    echo "❌ Error: go not found. Install with: brew install go"
    exit 1
fi
# =========================================================

# Check if cargo is available
if ! command -v cargo &> /dev/null; then
    echo "❌ Error: cargo not found. Install Rust from https://rustup.rs/"
    echo "Current PATH: $PATH"
    exit 1
fi

# Check if cmake is available (required for aws-lc-sys)
if ! command -v cmake &> /dev/null; then
    echo "❌ Error: cmake not found. Install with: brew install cmake"
    echo "Current PATH: $PATH"
    exit 1
fi

# Helper function to setup iOS SDK environment
setup_ios_env() {
    local sdk_name="$1"
    local target="$2"

    export SDKROOT=$(xcrun --sdk "$sdk_name" --show-sdk-path)
    export CC=$(xcrun --sdk "$sdk_name" -find clang)
    export CXX=$(xcrun --sdk "$sdk_name" -find clang++)
    export AR=$(xcrun --sdk "$sdk_name" -find ar)
    export RANLIB=$(xcrun --sdk "$sdk_name" -find ranlib)

    # Set linker for specific target
    local upper_target=$(echo "$target" | tr '[:lower:]-' '[:upper:]_')
    eval "export CARGO_TARGET_${upper_target}_LINKER='$CC'"
}

# Build for iOS device (ARM64)
echo "📱 Building for iOS device (aarch64-apple-ios)..."
setup_ios_env iphoneos aarch64-apple-ios
cargo build --release --target aarch64-apple-ios -p mobile_bridge

# Build for iOS simulator (ARM64)
echo "📲 Building for iOS simulator (aarch64-apple-ios-sim)..."
setup_ios_env iphonesimulator aarch64-apple-ios-sim
cargo build --release --target aarch64-apple-ios-sim -p mobile_bridge

# Create RustLibs directory if doesn't exist
mkdir -p "$IOS_LIBS"

# Copy libraries to iOS folder
echo "📦 Copying libraries to RustLibs/..."
cp target/aarch64-apple-ios/release/libmobile_bridge.a "$IOS_LIBS/libmobile_bridge.a"
cp target/aarch64-apple-ios-sim/release/libmobile_bridge.a "$IOS_LIBS/libmobile_bridge_sim.a"

# Verify libraries exist
if [ -f "$IOS_LIBS/libmobile_bridge.a" ] && [ -f "$IOS_LIBS/libmobile_bridge_sim.a" ]; then
    echo "✅ Rust libraries built successfully!"
    echo "   Device:    $(ls -lh $IOS_LIBS/libmobile_bridge.a | awk '{print $5}')"
    echo "   Simulator: $(ls -lh $IOS_LIBS/libmobile_bridge_sim.a | awk '{print $5}')"
else
    echo "❌ Error: Libraries not found after build"
    exit 1
fi
