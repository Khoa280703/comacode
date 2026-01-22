# Debug Report: iOS dyld Library Not Loaded Error

**Report ID:** debugger-260121-1506-ios-dyld-error
**Date:** 2026-01-21
**Status:** Analysis Complete

---

## Executive Summary

iOS app crash on debug build due to dyld attempting to load dylib from **absolute build path** on developer's machine instead of using the embedded framework.

**Root Cause:** Rust cdylib build contains hardcoded absolute path in its `LC_ID_DYLIB` load command, copied to framework without `install_name_tool` fix.

**Impact:** Critical - App crashes immediately on launch, unusable in debug configuration.

**Recommended Fix:** Use staticlib (`.a`) instead of cdylib (`.dylib`) for iOS - simpler, more reliable, no runtime loading issues.

---

## Technical Analysis

### Error Details

```
dyld: Library not loaded: /Users/khoa2807/development/2026/Comacode/target/aarch64-apple-ios/release/deps/libmobile_bridge.dylib
Referenced from: Runner.debug.dylib
Reason: image not found
```

### Root Cause Investigation

#### 1. **Rust Crate Configuration**

**File:** `/Users/khoa2807/development/2026/Comacode/crates/mobile_bridge/Cargo.toml`

```toml
[lib]
name = "mobile_bridge"
crate-type = ["staticlib", "cdylib"]  # ← Both types built
```

**Analysis:**
- Cargo builds **both** `libmobile_bridge.a` (staticlib) AND `libmobile_bridge.dylib` (cdylib)
- Staticlib: 11.6 MB, properly archived
- Dylib: 1.3 MB, **hardcoded absolute path** in LC_ID_DYLIB

#### 2. **Dylib Install Name Issue**

**Built dylib:**
```bash
$ otool -D target/aarch64-apple-ios/release/libmobile_bridge.dylib
/Users/khoa2807/development/2026/Comacode/target/aarch64-apple-ios/release/deps/libmobile_bridge.dylib
```

**Framework binary:**
```bash
$ otool -D mobile/ios/Frameworks/mobile_bridge.framework/mobile_bridge
/Users/khoa2807/development/2026/Comacode/target/aarch64-apple-ios/release/deps/libmobile_bridge.dylib
```

**Critical Finding:** The framework binary's install name was **NOT fixed** with `install_name_tool -id @rpath/mobile_bridge.framework/mobile_bridge`. The README instructions show the fix, but it wasn't applied to this copy.

**Evidence:**
```bash
$ md5 target/aarch64-apple-ios/release/libmobile_bridge.dylib \
        mobile/ios/Frameworks/mobile_bridge.framework/mobile_bridge
MD5 (original) = 62a3bde98281c9db2933b91a9e732aad
MD5 (framework) = 0b98a2016deef67e8bcac99cbe0a9eef  # Different! Not copied properly
```

#### 3. **Xcode Configuration**

**Framework Embedding:** ✅ Correct
- Framework is in "Embed Frameworks" build phase
- Set to `CodeSignOnCopy`, `RemoveHeadersOnCopy`
- RPATH includes `@executable_path/Frameworks` ✅

**Framework Search Paths:** ✅ Correct
- `$(PROJECT_DIR)/Frameworks/mobile_bridge.framework`

**Linking:** ⚠️ Links framework binary directly
- Links `mobile_bridge.framework/mobile_bridge` (the dylib)
- Not using static library approach

#### 4. **Dependency Chain**

```
Runner.debug.dylib (iOS app)
  └─> mobile_bridge.framework/mobile_bridge (dylib)
       └─> /Users/khoa2807/.../deps/libmobile_bridge.dylib (LC_ID_DYLIB)
            └─> ❌ NOT FOUND (absolute path from build machine)
```

When dyld loads the framework binary, it reads its `LC_ID_DYLIB` load command, which contains the **absolute build path**. It then tries to load that path, which doesn't exist on device.

---

## Why Staticlib Should Be Used for iOS

### Advantages of Staticlib (`.a`)

1. **No Runtime Loading** - Code is linked directly into app binary
2. **No dylib Signing** - Simpler code signing
3. **No Install Name Issues** - No LC_ID_DYLIB to fix
4. **Smaller Distribution** - Only symbols used are linked
5. **Apple Recommended** - Static libraries preferred for iOS

### Disadvantages of cdylib (`.dylib`)

1. **Must Fix Install Name** - `install_name_tool -id @rpath/...` required
2. **Must Code Sign Separately** - Framework needs signature
3. **Must Bundle Correctly** - Embed Frameworks + rpath setup
4. **More Moving Parts** - More failure points
5. **iOS App Store Warnings** - Dynamic frameworks need entitlements

---

## Recommended Solutions

### **Option 1: Use Staticlib Only** (RECOMMENDED)

**Change:** Use staticlib for iOS, remove cdylib

#### Steps:

1. **Update Cargo.toml**
   ```toml
   [lib]
   name = "mobile_bridge"
   crate-type = ["staticlib"]  # Remove cdylib
   ```

2. **Build Static Library**
   ```bash
   cargo build --release --target aarch64-apple-ios -p mobile_bridge
   ```

3. **Create Static Framework** (Manual Xcode setup)
   ```bash
   # Copy static lib to framework
   cp target/aarch64-apple-ios/release/libmobile_bridge.a \
      mobile/ios/Frameworks/mobile_bridge.framework/mobile_bridge

   # Update framework Info.plist to indicate static
   # No install_name_tool needed
   # No codesign needed for static lib
   ```

4. **Update Xcode Project**
   - Link `mobile_bridge.framework/mobile_bridge` (static archive)
   - Keep in "Link Binary With Libraries"
   - **Remove from** "Embed Frameworks" (static libs don't embed)

5. **Build Settings**
   - No changes needed - Xcode handles static linking

**Pros:**
- ✅ Simplest approach
- ✅ No runtime loading issues
- ✅ No dylib signing complexity
- ✅ Standard iOS practice

**Cons:**
- ❌ App binary larger (code linked in)
- ❌ Must rebuild for architecture changes

---

### **Option 2: Fix cdylib Install Name** (Current Approach)

**Change:** Apply `install_name_tool` fix properly

#### Steps:

1. **Build cdylib**
   ```bash
   cargo build --release --target aarch64-apple-ios -p mobile_bridge
   ```

2. **Copy to Framework + Fix Install Name**
   ```bash
   # Copy dylib
   cp target/aarch64-apple-ios/release/libmobile_bridge.dylib \
      mobile/ios/Frameworks/mobile_bridge.framework/mobile_bridge

   # CRITICAL: Fix install name BEFORE codesign
   install_name_tool -id @rpath/mobile_bridge.framework/mobile_bridge \
      mobile/ios/Frameworks/mobile_bridge.framework/mobile_bridge

   # Verify fix
   otool -D mobile/ios/Frameworks/mobile_bridge.framework/mobile_bridge
   # Should output: @rpath/mobile_bridge.framework/mobile_bridge

   # Code sign
   codesign --force --sign - \
      mobile/ios/Frameworks/mobile_bridge.framework
   ```

3. **Update README Instructions**
   - Add verification step after `install_name_tool`
   - Add warning about absolute path issue

4. **Keep Xcode Configuration**
   - Keep in "Embed Frameworks"
   - RPATH already correct

**Pros:**
- ✅ Dynamic framework (smaller app)
- ✅ Can update framework independently

**Cons:**
- ❌ More complex build process
- ❌ Easy to forget `install_name_tool`
- ❌ Code signing complexity
- ❌ Current setup already broken

---

### **Option 3: Use XCFramework** (Advanced)

**Change:** Build XCFramework with all architectures

#### Steps:

1. **Build for all targets**
   ```bash
   # Device
   cargo build --release --target aarch64-apple-ios -p mobile_bridge

   # Simulator
   cargo build --release --target aarch64-apple-ios-sim -p mobile_bridge
   ```

2. **Create XCFramework**
   ```bash
   xcodebuild -create-xcframework \
     -library target/aarch64-apple-ios/release/libmobile_bridge.a \
     -headers mobile/ios/Frameworks/mobile_bridge.framework/Headers \
     -library target/aarch64-apple-ios-sim/release/libmobile_bridge.a \
     -headers mobile/ios/Frameworks/mobile_bridge.framework/Headers \
     -output mobile/ios/Frameworks/mobile_bridge.xcframework
   ```

3. **Update Xcode**
   - Link XCFramework instead of framework

**Pros:**
- ✅ Multi-architecture in one package
- ✅ Apple's modern approach
- ✅ No simulator/device confusion

**Cons:**
- ❌ More complex build setup
- ❌ Requires Xcode 11+
- ❌ Static library complexity

---

## Why Current Setup Failed

### Analysis of Build Process

**Current README Instructions:**
```bash
cargo build --release --target aarch64-apple-ios --package mobile_bridge
cp target/aarch64-apple-ios/release/libmobile_bridge.dylib \
   mobile/ios/Frameworks/mobile_bridge.framework/mobile_bridge
install_name_tool -id @rpath/mobile_bridge.framework/mobile_bridge \
   mobile/ios/Frameworks/mobile_bridge.framework/mobile_bridge
codesign --force --sign - mobile/ios/Frameworks/mobile_bridge.framework
```

**Actual State (Evidence):**
1. ❌ MD5 mismatch - framework binary ≠ release dylib
2. ❌ Install name still shows absolute path
3. ❌ Either:
   - `install_name_tool` not run, OR
   - Wrong file copied after fix, OR
   - Build process automated incorrectly

**Most Likely Scenario:**
- Framework built with automated script
- Script forgot `install_name_tool` step
- Framework copied from old build with wrong ID
- Manual build from README not followed

---

## Unresolved Questions

1. **Build Automation:** Is there an automated build script that's skipping `install_name_tool`?
2. **CI/CD Pipeline:** Does CI build have same issue, or is it dev-only?
3. **Framework Version:** Why do MD5 hashes differ between source and framework?
4. **Podspec Usage:** Podspec exists but Podfile says "not via CocoaPods" - is it used?
5. **Flutter Integration:** Does Flutter's iOS build process interfere with framework?

---

## Recommended Action Plan

### Immediate Fix (Priority 1)

1. **Apply `install_name_tool` fix:**
   ```bash
   cd /Users/khoa2807/development/2026/Comacode
   cargo build --release --target aarch64-apple-ios -p mobile_bridge
   cp target/aarch64-apple-ios/release/libmobile_bridge.dylib \
      mobile/ios/Frameworks/mobile_bridge.framework/mobile_bridge
   install_name_tool -id @rpath/mobile_bridge.framework/mobile_bridge \
      mobile/ios/Frameworks/mobile_bridge.framework/mobile_bridge
   codesign --force --sign - mobile/ios/Frameworks/mobile_bridge.framework

   # Verify
   otool -D mobile/ios/Frameworks/mobile_bridge.framework/mobile_bridge
   ```

2. **Test on device/simulator**

### Long-term Fix (Priority 2)

1. **Switch to staticlib-only approach** (Option 1 above)
2. **Update build automation** to include `install_name_tool` verification
3. **Add pre-commit hook** to check install names
4. **Update CI/CD** to verify framework loading

---

## References

- **Apple dyld Documentation:** https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/DynamicLibraries/100-Articles/DynamicLibraryUsageGuidelines.html
- **install_name_tool Man Page:** https://ss64.com/osx/install_name_tool.html
- **FRB iOS Guide:** https://cjycode.com/flutter_rust_bridge/ios.html
- **iOS Framework Best Practices:** https://developer.apple.com/documentation/bundleresources/placing_content_in_a_bundle

---

## Appendix: Verification Commands

```bash
# Check dylib install name
otool -D mobile/ios/Frameworks/mobile_bridge.framework/mobile_bridge

# Check framework dependencies
otool -L mobile/ios/Frameworks/mobile_bridge.framework/mobile_bridge

# Check code signature
codesign -dv mobile/ios/Frameworks/mobile_bridge.framework 2>&1

# Check what's actually being linked in app
otool -L build/ios/iphoneos/Runner.app/Runner

# Check RPATH in app binary
otool -l build/ios/iphoneos/Runner.app/Runner | grep -A 3 LC_RPATH
```

---

**Next Steps:** Apply Option 1 (staticlib) for long-term stability, or Option 2 (fix install name) for immediate unblocking.
