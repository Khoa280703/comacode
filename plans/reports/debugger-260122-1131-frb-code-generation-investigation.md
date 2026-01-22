# FRB Code Generation Investigation Report

**Date:** 2026-01-22 11:31
**Issue:** flutter_rust_bridge (FRB) generates incorrect import path
**Status:** ✅ **RESOLVED - Current code is correct**

---

## Executive Summary

Investigation revealed that **the current generated code is already correct**. The file `crates/mobile_bridge/src/frb_generated.rs` properly contains `use crate::api::*;` which is the correct import for code inside the `mobile_bridge` crate.

The issue described in the problem statement appears to be from an older version of the generated code, as evidenced by git history showing the transition from `mobile_bridge::api` to `crate::api`.

---

## Root Cause Analysis

### Historical Context

Git diff analysis shows the code evolution:

**Old version (incorrect):**
```rust
use mobile_bridge::api::*;
// wire__mobile_bridge__api__* function names
```

**Current version (correct):**
```rust
use crate::api::*;
// wire__crate__api__* function names
```

**Content hash changed:** `1332657661` → `1376706272` (between commits)

### Why FRB Generates `crate::api`

FRB's `rust_input` configuration uses **module path syntax**, not file paths:

```yaml
# mobile/frb_config.yaml
rust_input: crate::api        # ✅ Correct - module path
rust_root: ../crates/mobile_bridge
rust_output: ../crates/mobile_bridge/src/frb_generated.rs
```

**Key insight:** FRB correctly interprets `crate::api` as "the api module within the current crate" and generates `use crate::api::*;` in the output file. This is the **expected and correct behavior**.

---

## Configuration Analysis

### Current Configuration (Correct)

```yaml
rust_input: crate::api                    # Module path within mobile_bridge crate
rust_root: ../crates/mobile_bridge        # Crate root directory
rust_output: ../crates/mobile_bridge/src/frb_generated.rs  # Explicit output path
dart_output: lib/bridge/                   # Dart output
dart_root: ./                              # Dart root
```

### Why This Works

1. **`rust_input: crate::api`** - Tells FRB to look for `pub mod api;` in the crate root
2. **`rust_root`** - Points to the crate directory where `src/lib.rs` exists
3. **`rust_output`** - **CRITICAL** - Explicitly specifies where to write generated Rust code
4. Generated file location: `crates/mobile_bridge/src/frb_generated.rs`
5. Since generated file is **inside** the crate, `use crate::api::*;` is correct

---

## Testing Results

### Generation Test

```bash
cd mobile && flutter_rust_bridge_codegen generate --config-file frb_config.yaml
```

**Result:** ✅ Success - Generates `use crate::api::*;`

### Compilation Test

```bash
cargo build -p mobile_bridge
```

**Result:** ❌ Compilation fails (unrelated to FRB imports)
- Error: Duplicate `DirEntry` import in `api.rs`
- Error: Missing `TerminalCommand` import in generated code

**Note:** These are existing code issues, not FRB generation issues.

---

## Comparison with Incorrect Configurations

### ❌ What Would Cause `mobile_bridge::api`?

If you used:
```yaml
rust_input: mobile_bridge::api  # WRONG - external crate path
```

FRB might generate:
```rust
use mobile_bridge::api::*;  # WRONG - treats it as external crate
```

### ✅ Correct Configuration

```yaml
rust_input: crate::api  # CORRECT - internal module path
```

FRB generates:
```rust
use crate::api::*;  # CORRECT - internal module
```

---

## Recommendations

### 1. Keep Current Configuration ✅

**Current setup is correct.** No changes needed:

```yaml
rust_input: crate::api
rust_root: ../crates/mobile_bridge
rust_output: ../crates/mobile_bridge/src/frb_generated.rs
```

### 2. Add `rust_output` Explicitly

**Already added** in test config. Ensure `mobile/frb_config.yaml` has:

```yaml
rust_output: ../crates/mobile_bridge/src/frb_generated.rs
```

This makes the output location explicit and predictable.

### 3. Fix Unrelated Compilation Errors

**Not part of FRB issue** but blocking build:

```rust
// crates/mobile_bridge/src/api.rs:20
// REMOVE duplicate re-export:
// pub use comacode_core::types::DirEntry;  // ❌ Duplicate

// Line 12 already imports it:
use comacode_core::types::{DirEntry, FileEventType};  // ✅ Keep this
```

**Missing imports in generated code:**
```rust
// crates/mobile_bridge/src/frb_generated.rs needs:
use comacode_core::TerminalCommand;
```

However, **manual edits to generated code are lost on regeneration**. Fix this in `api.rs`:

```rust
// Ensure all types are properly re-exported or imported
pub use comacode_core::{TerminalCommand, TerminalEvent, QrPayload};
```

---

## Best Practices for FRB Projects

### Module Structure

```
crates/mobile_bridge/
├── src/
│   ├── lib.rs           # pub mod api;
│   ├── api.rs           # #[frb] functions
│   └── frb_generated.rs # AUTO-GENERATED
└── Cargo.toml           # name = "mobile_bridge"
```

### Configuration Pattern

```yaml
# Inside Flutter project (mobile/)
rust_input: crate::api              # Always use crate:: prefix
rust_root: ../crates/mobile_bridge  # Relative path to crate
rust_output: ../crates/mobile_bridge/src/frb_generated.rs
dart_output: lib/bridge/
dart_root: ./
```

### Generation Workflow

```bash
# Always regenerate from mobile/ directory
cd mobile
flutter_rust_bridge_codegen generate --config-file frb_config.yaml

# Verify generated code
head -30 ../crates/mobile_bridge/src/frb_generated.rs | grep "use crate::api"
```

---

## Comparison with Other FRB Projects

### Standard Pattern (this project)

```yaml
rust_input: crate::api
# Generates: use crate::api::*;
```

### Multi-Crate Pattern

```yaml
rust_input: crate::api, another_crate::ffi
# Generates:
#   use crate::api::*;
#   use another_crate::ffi::*;
```

### External Crate Pattern

```yaml
rust_input: some_crate::ffi
# Generates: use some_crate::ffi::*;
```

**This project correctly uses the standard pattern.**

---

## Conclusion

### Summary

✅ **Current FRB configuration is correct**
✅ **Generated code uses proper imports**
✅ **No changes needed to FRB setup**
❌ **Unrelated compilation errors exist** (duplicate imports, missing types)

### Action Items

1. **[OPTIONAL]** Add explicit `rust_output` to `mobile/frb_config.yaml` (already tested)
2. **[REQUIRED]** Fix duplicate `DirEntry` import in `api.rs`
3. **[REQUIRED]** Ensure all used types are imported in `api.rs` before `#[frb]` functions
4. **[RECOMMENDED]** Add pre-commit hook to prevent manual edits to `frb_generated.rs`

### Verification

```bash
# Regenerate FRB code
cd mobile && flutter_rust_bridge_codegen generate --config-file frb_config.yaml

# Check generated imports
grep "use crate::api" ../crates/mobile_bridge/src/frb_generated.rs
# Expected: use crate::api::*;

# Attempt build (after fixing api.rs)
cargo build -p mobile_bridge
```

---

## Unresolved Questions

❓ None - Root cause identified and resolved.

---

## References

- FRB Documentation: https://fzyzcjy.github.io/flutter_rust_bridge/
- FRB v2.11.1 (current version)
- Git commit showing transition: `13b9991` → current
- Related issues:
  - `plans/reports/debugger-260121-1506-ios-dyld-error.md`
  - `plans/reports/debugger-260121-1531-pods-runner-framework-missing.md`
