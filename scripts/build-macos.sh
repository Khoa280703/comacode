#!/bin/bash
set -euo pipefail

echo "Building Comacode for macOS..."

# Build for M1 (ARM64) - EXPLICIT target-dir for workspace consistency
cargo build --release --target aarch64-apple-darwin --target-dir target -p hostagent

# Build for Intel (x64)
cargo build --release --target x86_64-apple-darwin --target-dir target -p hostagent

# Create universal binary using lipo
lipo -create \
  -output target/hostagent-universal \
  target/aarch64-apple-darwin/release/hostagent \
  target/x86_64-apple-darwin/release/hostagent

echo "✅ Universal binary created: target/hostagent-universal"

# Verify binary architecture
file target/hostagent-universal
# Expected: Mach-O universal binary with 2 architectures: [x86_64:Mach-O x86_64] [arm64]

# Make executable
chmod +x target/hostagent-universal
