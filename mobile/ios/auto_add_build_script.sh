#!/bin/bash
set -e

# Auto-add build script to Xcode project
# Chỉnh sửa Runner.xcodeproj để add "Build Rust Libraries" phase

echo "🔧 Tự động add build script vào Xcode project..."

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PBXPROJ="$SCRIPT_DIR/Runner.xcodeproj/project.pbxproj"

# Backup original
cp "$PBXPROJ" "$PBXPROJ.backup"
echo "💾 Backup: $PBXPROJ.backup"

# Check if script already exists
if grep -q "Build Rust Libraries" "$PBXPROJ"; then
    echo "⚠️  Build phase 'Build Rust Libraries' đã tồn tại!"
    echo "Nếu muốn add lại, xóa trong Xcode trước."
    exit 0
fi

echo "📝 Adding build phase to project.pbxproj..."

# Tạo UUID ngẫu nhiên cho build phase (format Xcode)
BUILD_PHASE_UUID=$(uuidgen | tr '[:lower:]' '[:upper:]' | tr -d '-' | cut -c1-24)
SHELL_SCRIPT_UUID=$(uuidgen | tr '[:lower:]' '[:upper:]' | tr -d '-' | cut -c1-24)

echo "Generated UUIDs:"
echo "  Build Phase: $BUILD_PHASE_UUID"
echo "  Shell Script: $SHELL_SCRIPT_UUID"

# Tìm PBXNativeTarget section
TARGET_SECTION=$(grep -n "PBXNativeTarget.*Runner" "$PBXPROJ" | head -1 | cut -d: -f1)

if [ -z "$TARGET_SECTION" ]; then
    echo "❌ Không tìm thấy PBXNativeTarget section!"
    exit 1
fi

echo "✅ Found target section at line $TARGET_SECTION"

# Script sẽ add:
# 1. PBXShellScriptBuildPhase object
# 2. Reference trong buildPhases array

# Tạo temporary file với modifications
python3 << 'PYTHON_SCRIPT'
import sys
import re

pbxproj_path = sys.argv[1]
build_phase_uuid = sys.argv[2]
shell_script_uuid = sys.argv[3]

with open(pbxproj_path, 'r') as f:
    content = f.read()

# 1. Add PBXShellScriptBuildPhase object BEFORE "/* End PBXShellScriptBuildPhase section */"
shell_script_obj = f'''		{build_phase_uuid} /* Build Rust Libraries */ = {{
			isa = PBXShellScriptBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			inputFileListPaths = (
			);
			inputPaths = (
			);
			name = "Build Rust Libraries";
			outputFileListPaths = (
			);
			outputPaths = (
				"$(SRCROOT)/RustLibs/libmobile_bridge.a",
				"$(SRCROOT)/RustLibs/libmobile_bridge_sim.a",
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "\\"${{SRCROOT}}/build_rust_libs.sh\\"\\n";
		}};
'''

# Find "/* End PBXShellScriptBuildPhase section */"
end_marker = "/* End PBXShellScriptBuildPhase section */"
if end_marker in content:
    content = content.replace(end_marker, shell_script_obj + '\n' + end_marker)
    print("✅ Added PBXShellScriptBuildPhase object")
else:
    print("⚠️  Creating new PBXShellScriptBuildPhase section")
    # Add new section before PBXSourcesBuildPhase
    insert_point = "/* Begin PBXSourcesBuildPhase section */"
    new_section = f'''
/* Begin PBXShellScriptBuildPhase section */
{shell_script_obj}
/* End PBXShellScriptBuildPhase section */

'''
    content = content.replace(insert_point, new_section + insert_point)

# 2. Add reference to buildPhases array in PBXNativeTarget
# Find Runner target's buildPhases array
runner_pattern = r'(/\* Runner \*/\s*=\s*\{[^}]*buildPhases\s*=\s*\([^)]*)'
match = re.search(runner_pattern, content, re.DOTALL)

if match:
    build_phases_section = match.group(1)
    # Add our phase UUID at the beginning (before compile)
    new_phases = build_phases_section + f'\n\t\t\t\t{build_phase_uuid} /* Build Rust Libraries */,'
    content = content.replace(build_phases_section, new_phases)
    print("✅ Added to buildPhases array")
else:
    print("❌ Could not find buildPhases array")
    sys.exit(1)

# Write modified content
with open(pbxproj_path, 'w') as f:
    f.write(content)

print("✅ project.pbxproj updated successfully!")
PYTHON_SCRIPT

python3 - "$PBXPROJ" "$BUILD_PHASE_UUID" "$SHELL_SCRIPT_UUID"

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 Build script đã được add vào Xcode project!"
    echo ""
    echo "Next steps:"
    echo "1. Mở Xcode (nếu đang mở thì close và reopen)"
    echo "2. Vào Build Phases → sẽ thấy 'Build Rust Libraries'"
    echo "3. Test: Product → Clean Build Folder → Build"
    echo ""
    echo "Nếu muốn restore: mv $PBXPROJ.backup $PBXPROJ"
else
    echo ""
    echo "❌ Failed to add build script!"
    echo "Restoring backup..."
    mv "$PBXPROJ.backup" "$PBXPROJ"
fi
