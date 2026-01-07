# Brainstorming: Phase E06 - Windows Build via CI

**Ngày**: 2026-01-07
**Repo**: https://github.com/Khoa280703/comacode.git
**Status**: Đã chốt phương án

---

## Problem Statement

Feedback về plan E06 gốc:
1. **Không có máy Windows vật lý** → Không thể test ngay
2. **Blind coding** → Viết Windows code mà không verify được
3. **Risk**: Code sai syntax phải fix loop nhiều lần

---

## Key Discovery

**`portable-pty` ĐÃ cross-platform sẵn!**

```rust
// crates/hostagent/src/pty.rs:39
let pty_system = native_pty_system();
```

`native_pty_system()` tự động:
- Unix/macOS → POSIX PTY
- Windows → ConPTY (Windows 10 1809+)

**Kết luận**: Không cần viết `windows.rs` riêng, không cần platform abstraction trait.

---

## Evaluated Approaches

### Approach A: Platform-Specific Code (Revised Plan gốc)
```
crates/hostagent/src/pty/
├── mod.rs          # trait abstraction
├── unix.rs         # #[cfg(unix)]
└── windows.rs      # #[cfg(windows)]
```

**Pros**:
- Full control
- Platform-specific optimizations

**Cons**:
- **VI PHẠM YAGNI** - portable-pty đã làm rồi
- Duplicate code
- More maintenance burden
- Blind coding risk cao

### Approach B: CI Build Only (Được chọn)
```
.github/workflows/build-windows.yml  # CI verifies build
```

**Pros**:
- **KISS** - Dùng abstraction có sẵn
- CI validate syntax ngay lập tức
- No platform-specific code needed
- portable-pty team test already

**Cons**:
- Rely on external crate (nhưng đã dùng từ Phase 03)

---

## Final Decision: Approach B

### Rationale

1. **YAGNI**: portable-pty đã giải quyết cross-platform problem
2. **KISS**: Không viết code không cần thiết
3. **DRY**: Không reimplement abstraction layer

---

## Simplified Plan E06

### 6.1 GitHub Actions CI (30min)

**File**: `.github/workflows/build-windows.yml`

```yaml
name: Build Windows

on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]

env:
  CARGO_TERM_COLOR: always

jobs:
  build-windows:
    runs-on: windows-latest

    steps:
    - uses: actions/checkout@v4

    - name: Setup Rust
      uses: dtolnay/rust-toolchain@stable
      with:
        targets: x86_64-pc-windows-msvc

    - name: Cache Cargo
      uses: actions/cache@v4
      with:
        path: |
          ~/.cargo/registry
          ~/.cargo/git
          target
        key: ${{ runner.os }}-cargo-${{ hashFiles('**/Cargo.lock') }}

    - name: Build Release
      run: |
        cargo build --release --target x86_64-pc-windows-msvc -p hostagent
        cargo build --release --target x86_64-pc-windows-msvc -p cli_client

    - name: Upload Artifacts
      uses: actions/upload-artifact@v4
      with:
        name: comacode-windows-x64-${{ github.sha }}
        path: |
          target/x86_64-pc-windows-msvc/release/hostagent.exe
          target/x86_64-pc-windows-msvc/cli_client.exe
        retention-days: 7
```

### 6.2 Verify Existing Code (15min)

Kiểm tra `portable-pty` dependencies:

```toml
# crates/hostagent/Cargo.toml
portable-pty = "0.8"  # Supports Windows 10 1809+
```

**Verify**:
```bash
cargo check --target x86_64-pc-windows-msvc -p hostagent  # trên macOS
```

### 6.3 Manual Testing (Cuối tuần)

1. Download artifact từ GitHub Actions
2. Test trên máy Windows:
   ```
   hostagent.exe
   cli_client.exe --connect 127.0.0.1:8443 --token <TOKEN> --insecure
   ```

---

## Acceptance Criteria

| Criterion | Validation |
|-----------|------------|
| ✅ Code compile trên macOS | `cargo build --release` vẫn works |
| ✅ CI build thành công | GitHub Actions green tick |
| ✅ Artifact .exe tạo ra | Download được từ Actions |
| ✅ portable-pty tự chọn PTY | Không cần code changes |

---

## Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Windows-specific bug | Low | Medium | CI sẽ catch compile errors |
| portable-pty Windows bug | Low | High | Crate đã mature, ~2M downloads |
| ConPTY not available | Very Low | High | Windows 10 1809+ (2018) |

---

## Files to Create

```
.github/workflows/
  └── build-windows.yml    # New
```

**No Rust code changes needed!**

---

## Next Steps

1. Tạo `.github/workflows/build-windows.yml`
2. Push để trigger CI
3. Verify build green
4. Download .exe artifact
5. Manual test vào cuối tuần

---

## Timeline Estimate

| Task | Time |
|------|------|
| Create CI workflow | 15min |
| Push & verify | 10min |
| Total | **25min** |

*(So với 4h trong revised plan gốc)*

---

## Unresolved Questions

1. **Code signing**: Windows SmartScreen sẽ block unsigned .exe → Cần giải quyết sau
2. **Installer**: MSI installer hay standalone .exe?
3. **Distribution**: GitHub Releases hay khác?

---

**Last updated**: 2026-01-07
**Status**: ✅ Ready to implement
