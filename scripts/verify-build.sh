#!/bin/bash

echo "Verifying macOS build..."

# Check if binary exists
if [ ! -f "target/hostagent-universal" ]; then
    echo "❌ Binary not found. Run build-macos.sh first."
    exit 1
fi

# Check binary architecture
echo "📦 Checking architecture..."
file target/hostagent-universal
# Expected: Mach-O universal binary with 2 architectures

# Check for stripped symbols (release mode)
echo "🔍 Checking symbols..."
SYMBOL_COUNT=$(nm target/hostagent-universal 2>/dev/null | wc -l | tr -d ' ')
echo "   Symbol count: $SYMBOL_COUNT (should be minimal)"

# Check binary size
echo "📏 Checking size..."
SIZE=$(du -h target/hostagent-universal | cut -f1)
echo "   Binary size: $SIZE (target: <10MB)"

# Run binary (help check)
echo "🧪 Testing --help flag..."
./target/hostagent-universal --help || echo "   ⚠️  Help command failed"

echo ""
echo "✅ Build verification complete"
