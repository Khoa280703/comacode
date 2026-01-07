---
title: "Phase 06: Windows Cross-Platform"
description: "Windows build targets, ConPTY force enable, cross-platform testing"
status: pending
priority: P2
effort: 4h
phase: 06
created: 2026-01-07
---

## Objectives

Enable Windows cross-compilation cho hostagent, configure ConPTY (Windows pseudo-console), và ensure feature parity với macOS version.

## Tasks

### 6.1 Windows Cross-Compilation Setup (1h)

**Option A: Native Windows Build**
```bash
# On Windows machine with Rust installed
cargo build --release --target x86_64-pc-windows-msvc -p hostagent
```

**Option B: Cross-Compile from macOS**
```bash
# Install cross-compilation toolchain
rustup target add x86_64-pc-windows-msvc

# This is complex due to MSVC dependencies
# Recommend Option A for MVP
```

**File**: `scripts/build-windows.sh` (run on Windows)

```bash
#!/bin/bash
set -euo pipefail

echo "Building Comacode for Windows..."

# Build for x64
cargo build --release --target x86_64-pc-windows-msvc -p hostagent

# Expected output: target/x86_64-pc-windows-msvc/release/hostagent.exe

echo "✅ Windows binary created"
echo "Size:"
du -h target/x86_64-pc-windows-msvc/release/hostagent.exe
```

### 6.2 ConPTY Configuration (1h)

**File**: `crates/hostagent/src/pty/windows.rs` (new)

```rust
use portable_pty::{CommandBuilder, PtySize, MasterPty, SlavePty, native_pty_system};

pub struct WindowsPty {
    master: Box<dyn MasterPty + Send>,
    _slave: Box<dyn SlavePty + Send>,
    child: Box<dyn portable_pty::Child + Send>,
}

impl WindowsPty {
    /// Create new ConPTY session
    pub fn new(cmd: CommandBuilder, size: PtySize) -> Result<Self, CoreError> {
        let pty_system = native_pty_system();

        // Force enable ConPTY (Windows 10+)
        let pty_pair = pty_system.openpty(size)?;

        let child = pty_pair.slave.spawn_command(cmd)?;

        Ok(Self {
            master: pty_pair.master,
            _slave: pty_pair.slave,
            child,
        })
    }

    /// Get reader handle
    pub fn reader(&self) -> Box<dyn portable_pty::Reader + Send> {
        self.master.try_clone_reader()
    }

    /// Get writer handle
    pub fn writer(&self) -> Box<dyn portable_pty::Writer + Send> {
        self.master.take_writer()
    }

    /// Check if process is alive
    pub fn is_alive(&self) -> bool {
        self.child.try_wait().is_none()
    }
}
```

### 6.3 Conditional Compilation (30min)

**File**: `crates/hostagent/src/pty/mod.rs`

```rust
#[cfg(unix)]
use self::unix::UnixPty as PlatformPty;

#[cfg(windows)]
use self::windows::WindowsPty as PlatformPty;

pub fn create_pty(cmd: CommandBuilder, size: PtySize) -> Result<PlatformPty, CoreError> {
    PlatformPty::new(cmd, size)
}
```

**Update dependencies** in `crates/hostagent/Cargo.toml`:
```toml
[dependencies]
portable-pty = { workspace = true, features = ["conpty"] }  # Force ConPTY on Windows
```

### 6.4 Windows-Specific Handling (30min)

**Line Endings**:
```rust
// Windows uses CRLF (\r\n), Unix uses LF (\n)
// Ensure consistent output

fn normalize_line endings(input: &[u8]) -> Vec<u8> {
    #[cfg(windows)]
    {
        input.iter()
            .flat_map(|&b| if b == b'\r' { None } else { Some(b) })
            .collect()
    }
    #[cfg(not(windows))]
    {
        input.to_vec()
    }
}
```

**Path Handling**:
```rust
// Use std::path::Path for cross-platform paths
let log_dir = dirs::data_local_dir()?
    .join("comacode")
    .join("logs");
```

### 6.5 Windows Build Testing (1h)

**File**: `scripts/test-windows.ps1`

```powershell
# Test script for Windows

Write-Host "Building Comacode for Windows..."
cargo build --release --target x86_64-pc-windows-msvc -p hostagent

Write-Host "Running tests..."
cargo test --target x86_64-pc-windows-msvc

Write-Host "Running hostagent..."
.\target\x86_64-pc-windows-msvc\release\hostagent.exe
```

**Manual Test Checklist**:
1. ✅ Binary starts without errors
2. ✅ QR code displays
3. ✅ Can connect from mobile
4. ✅ Terminal commands work (dir, echo, etc.)
5. ✅ Output streaming works
6. ✅ ConPTY handles special characters

### 6.6 Platform Compatibility Matrix (30min)

**File**: `docs/platform-support.md`

```markdown
# Platform Support Matrix

## Hostagent

| Platform | Status | Notes |
|----------|--------|-------|
| macOS 11+ (M1) | ✅ Supported | Tested |
| macOS 11+ (Intel) | ✅ Supported | Tested |
| Windows 10+ | ✅ Supported | ConPTY enabled |
| Windows 8/7 | ❌ Not Supported | ConPTY unavailable |
| Linux (Ubuntu 20.04+) | ⚠️ Best Effort | Not tested |

## Mobile App

| Platform | Status | Notes |
|----------|--------|-------|
| iOS 12+ | ✅ Supported | Target |
| Android 5.0+ | ⚠️ Planned | Future phase |

## Known Limitations

### Windows
- **ConPTY only**: Windows 10+ required (build 18309+)
- **No fallback**: Older Windows versions not supported
- **Path handling**: Backslash vs forward slash
- **Line endings**: CRLF normalization needed

### macOS
- **Code signing**: Unidentified developer warning
- **Hardened runtime**: Not configured for MVP

### Linux
- **Untested**: No priority for MVP
- **Dependencies**: May require libpty dev files
```

## Testing Strategy

**Unit Tests**:
```rust
#[cfg(windows)]
#[test]
fn test_conpty_creation() {
    let cmd = CommandBuilder::new("cmd.exe");
    let size = PtySize {
        rows: 24,
        cols: 80,
        pixel_width: 0,
        pixel_height: 0,
    };

    let pty = WindowsPty::new(cmd, size).unwrap();
    assert!(pty.is_alive());
}
```

**Integration Tests**:
1. Start hostagent on Windows
2. Connect from mobile
3. Run Windows-specific commands:
   - `dir` (list directory)
   - `echo %USERNAME%` (environment variables)
   - `powershell` (PowerShell shell)

**Acceptance Criteria**:
- ✅ Windows binary builds successfully
- ✅ ConPTY session creates without errors
- ✅ Output streaming works
- ✅ Snapshot resync works
- ✅ All Phase 01-04 features work on Windows

## Dependencies

- Phase 01-04 (All features must work on Windows)

## Blocked By

- Phase 05 (macOS version must be stable first)

## Notes

**ConPTY Fallback**: Not implementing for MVP
- Older Windows (7/8) use legacy pseudo-consoles
- Complexity vs benefit trade-off
- Target audience: developers on modern OS

**Windows Defender**: May flag unsigned binary
- User must exclude from scans
- Document in troubleshooting guide

**Performance**: ConPTY has higher overhead than Unix PTY
- Expected: 2-3x slower than macOS
- Monitor in dogfooding

## Future Enhancements (Post-MVP)

1. **MSVC Code Signing**: Sign binary with trusted certificate
2. **Installer**: Create MSI/NSIS installer
3. **Windows Service**: Run as background service
4. **Named Pipes**: Alternative to TCP for localhost
5. **Cygwin/MSYS2 Support**: Alternative PTY implementations

## Unresolved Questions

1. **Windows 7/8 Support**: Should we add legacy PTY fallback? → No, ConPTY only for MVP
2. **PowerShell Default**: Should default shell be PowerShell or cmd? → cmd for MVP (simpler)
3. **Path Handling**: How to handle Windows paths in terminal? → Let PTY handle, normalize output only
4. **Cross-Compilation**: Should we enable macOS→Windows cross-compile? → No, use native Windows build
