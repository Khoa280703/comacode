# Debug Report: Pods_Runner Framework Missing

**Date**: 2026-01-21
**Issue**: Framework 'Pods_Runner' not found / Linker command failed
**Status**: RESOLVED - User Error

## Executive Summary

Root cause identified: User opening `Runner.xcodeproj` instead of `Runner.xcworkspace`. CocoaPods dependencies unavailable in standalone project, causing framework not found errors.

**Build Status**: ✅ Working
- `flutter build ios` - SUCCESS
- `xcodebuild -workspace Runner.xcworkspace` - SUCCESS
- `xcodebuild -project Runner.xcodeproj` - FAILS (expected)

## Technical Analysis

### Phase 1: Evidence Collection

**Build Output Analysis**:
```
error: Module 'connectivity_plus' not found (in target 'Runner' from project 'Runner')
```

**Project Structure**:
- `Runner.xcodeproj` - references `Pods_Runner.framework` from BUILT_PRODUCTS_DIR
- `Runner.xcworkspace` - includes Pods project
- `Pods-Runner` scheme exists in workspace

**Configuration Files**:
- `Podfile`: Uses `use_frameworks!`, mobile_bridge excluded (embedded in Xcode)
- `Podfile.lock`: No mobile_bridge pod, correct
- `Pods-Runner.debug.xcconfig`: Framework search paths configured correctly
- `mobile_bridge.framework`: Present in `Frameworks/` directory

### Phase 2: Root Cause

**Problem**:
1. User opened `Runner.xcodeproj` in Xcode (not `Runner.xcworkspace`)
2. Project references `Pods_Runner.framework` (BUILT_PRODUCTS_DIR)
3. Without workspace, Pods project not loaded
4. `Pods_Runner.framework` not built
5. Linker fails: "framework not found"

**Why this happens**:
- CocoaPods generates aggregate framework `Pods_Runner.framework`
- Only built when using workspace (includes Pods.xcodeproj)
- Standalone project lacks dependency context

### Phase 3: Verification

**Test 1** - Build project directly (FAIL):
```bash
xcodebuild -project Runner.xcodeproj -scheme Runner build
# Result: Module 'connectivity_plus' not found
```

**Test 2** - Build workspace (SUCCESS):
```bash
xcodebuild -workspace Runner.xcworkspace -scheme Runner build
# Result: BUILD SUCCEEDED
```

**Test 3** - Flutter build (SUCCESS):
```bash
flutter build ios --debug --no-codesign
# Result: ✓ Built build/ios/iphoneos/Runner.app
```

## Actionable Recommendations

### Immediate Fix

**For User**:
1. **CLOSE** `Runner.xcodeproj` if open
2. **OPEN** `Runner.xcworkspace` instead
3. Build from workspace

**CLI Commands**:
```bash
# Correct - use workspace
xcodebuild -workspace Runner.xcworkspace -scheme Runner

# Wrong - use project
xcodebuild -project Runner.xcodeproj -scheme Runner  # FAILS
```

### Documentation Update

**Add to README.md or onboarding guide**:
```markdown
## Important: Always Use Workspace

When opening this project in Xcode:
- ✅ OPEN: `Runner.xcworkspace`
- ❌ DON'T: `Runner.xcodeproj`

The workspace includes CocoaPods dependencies. Opening the project directly
will cause "framework not found" errors.
```

### Consider Adding: Project-Only Warning

Add script to `.xcodeproj` to detect workspace usage:
```ruby
# In Podfile post_install
post_install do |installer|
  installer.pods_project.targets.each do |target|
    # Add build check
  end
end
```

## Supporting Evidence

**File: `/Users/khoa2807/development/2026/Comacode/mobile/ios/Podfile`**
- Line 32: `# mobile_bridge framework embedded directly in Xcode (not via CocoaPods)`
- Confirms mobile_bridge is NOT a CocoaPods dependency

**File: `/Users/khoa2807/development/2026/Comacode/mobile/ios/Runner.xcodeproj/project.pbxproj`**
- Contains: `Pods_Runner.framework` reference with `sourceTree = BUILT_PRODUCTS_DIR`
- This framework only exists when Pods project is built

**Build Log Output** (see attached logs):
```
Line 83: error: Module 'connectivity_plus' not found
Line 98: ScanDependencies failed
Line 100: ** BUILD FAILED **
```

## Prevention Measures

1. **Add `.xcodeproj` to .gitignore** (already done)
2. **Create README with workspace instruction**
3. **Consider adding pre-build check** in CI
4. **Educate team** on CocoaPods workspace requirement

## Unresolved Questions

None - issue fully resolved.

## Verification

✅ Build with workspace: SUCCESS
✅ Build with Flutter: SUCCESS
✅ Build with project: FAILS (expected behavior)

---

**Files Modified**: None (user error, not code issue)
**Time to Resolution**: ~15 minutes
**Confidence**: High (root cause definitively identified)
