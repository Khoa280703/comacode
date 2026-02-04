#!/usr/bin/env python3
import sys
import re
import uuid

def generate_uuid():
    """Generate Xcode-style 24-char uppercase hex UUID"""
    return uuid.uuid4().hex.upper()[:24]

def add_build_script(pbxproj_path):
    """Add Build Rust Libraries build phase to Xcode project"""
    
    print("📖 Reading project.pbxproj...")
    with open(pbxproj_path, 'r') as f:
        content = f.read()
    
    # Check if already exists
    if 'Build Rust Libraries' in content:
        print("⚠️  'Build Rust Libraries' build phase already exists!")
        return False
    
    # Generate UUIDs
    build_phase_uuid = generate_uuid()
    print(f"🔑 Generated UUID: {build_phase_uuid}")
    
    # 1. Add PBXShellScriptBuildPhase object
    shell_script_obj = f'''\t\t{build_phase_uuid} /* Build Rust Libraries */ = {{
\t\t\tisa = PBXShellScriptBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\tinputFileListPaths = (
\t\t\t);
\t\t\tinputPaths = (
\t\t\t);
\t\t\tname = "Build Rust Libraries";
\t\t\toutputFileListPaths = (
\t\t\t);
\t\t\toutputPaths = (
\t\t\t\t"$(SRCROOT)/RustLibs/libmobile_bridge.a",
\t\t\t\t"$(SRCROOT)/RustLibs/libmobile_bridge_sim.a",
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t\tshellPath = /bin/sh;
\t\t\tshellScript = "\\"${{SRCROOT}}/build_rust_libs.sh\\"\\n";
\t\t}};
'''
    
    # Find or create PBXShellScriptBuildPhase section
    end_marker = '/* End PBXShellScriptBuildPhase section */'
    if end_marker in content:
        content = content.replace(end_marker, shell_script_obj + '\n' + end_marker)
        print("✅ Added to existing PBXShellScriptBuildPhase section")
    else:
        # Create new section
        insert_point = '/* Begin PBXSourcesBuildPhase section */'
        new_section = f'''/* Begin PBXShellScriptBuildPhase section */
{shell_script_obj}
/* End PBXShellScriptBuildPhase section */

'''
        content = content.replace(insert_point, new_section + insert_point)
        print("✅ Created new PBXShellScriptBuildPhase section")
    
    # 2. Add to buildPhases array in Runner target
    # Find PBXNativeTarget for Runner
    target_pattern = r'(/\* Runner \*/\s*=\s*\{[\s\S]*?buildPhases\s*=\s*\()([\s\S]*?)(\);)'
    match = re.search(target_pattern, content)
    
    if not match:
        print("❌ Could not find Runner target buildPhases!")
        return False
    
    before = match.group(1)
    phases_content = match.group(2)
    after = match.group(3)
    
    # Add our UUID to the beginning (before compile)
    new_phases = before + f'\n\t\t\t\t{build_phase_uuid} /* Build Rust Libraries */,' + phases_content + after
    
    content = re.sub(target_pattern, new_phases, content)
    print("✅ Added to Runner target buildPhases array")
    
    # Write back
    print("💾 Writing updated project.pbxproj...")
    with open(pbxproj_path, 'w') as f:
        f.write(content)
    
    print("🎉 Success! Build script added to Xcode project")
    return True

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 fix_xcode_project.py <path/to/project.pbxproj>")
        sys.exit(1)
    
    pbxproj_path = sys.argv[1]
    success = add_build_script(pbxproj_path)
    sys.exit(0 if success else 1)
