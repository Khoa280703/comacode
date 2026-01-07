# portable-pty Research Report
**Date:** 2026-01-06
**Subject:** Cross-platform PTY crate for terminal process management

## 1. Current Status & Maintenance

**Version:** 0.9.0 (released 2025-02-11)
**Status:** ✅ Active development
**Repository:** Part of WezTerm project
**Indicators:**
- Recent releases (Feb 2025)
- Active issue management (issues closed Dec 2024, Mar 2024)
- 97+ contributors, 22k+ stars on WezTerm repo
- Production-proven in WezTerm terminal emulator

## 2. Platform Support

| Platform | Implementation | Status |
|----------|---------------|--------|
| **Linux** | POSIX ptmx/pts | ✅ Native |
| **macOS** | POSIX ptmx/pts | ✅ Native |
| **Windows** | ConPTY (Windows 1809+) | ⚠️ Limitations |
| **Windows (legacy)** | WinPTY fallback | ✅ Supported |
| **WSL** | Via Windows PTY | ✅ Works |

**Note:** Multiple Windows implementations selectable at runtime via trait system

## 3. PTY Creation Workflow

```rust
use portable_pty::{CommandBuilder, PtySize, native_pty_system, PtySystem};

// 1. Get native PTY system
let pty_system = native_pty_system();

// 2. Create PTY pair with initial size
let mut pair = pty_system.openpty(PtySize {
    rows: 24,
    cols: 80,
    pixel_width: 0,
    pixel_height: 0,
})?;

// 3. Build command
let cmd = CommandBuilder::new("bash");
cmd.arg("-i");  // interactive mode
cmd.set_controlling_tty(true);  // for signal propagation

// 4. Spawn into slave
let child = pair.slave.spawn_command(cmd)?;

// 5. I/O via master
let reader = pair.master.try_clone_reader()?;
let writer = pair.master.take_writer()?;
```

**Key Traits:**
- `PtySystem`: Runtime implementation selection
- `MasterPty`: Control end (reader/writer/resize)
- `SlavePty`: Process spawning endpoint
- `ChildKiller`: Process termination

## 4. Shell Integration

### Unix Shells (bash/zsh)
```rust
let cmd = CommandBuilder::new("bash");
cmd.arg("-i");  // Interactive shell
// Write: writeln!(writer, "ls -l\r\n")?
```

### Windows Shells
- **PowerShell:** `CommandBuilder::new("pwsh")` or `"powershell"`
- **CMD:** `CommandBuilder::new("cmd")`
- **WSL:** Via `wsl.exe` invocation

### Integration Features
- **OSC sequences:** OSC 7 (cwd), OSC 133 (prompt regions)
- **TTY detection:** Child processes detect interactive TTY correctly
- **Raw mode:** Automatic TTY configuration
- **Escape sequences:** VT100-256color compatible

## 5. Resize Handling

```rust
// Detect via SIGWINCH (Unix) or window events
let new_size = PtySize {
    rows: new_rows,
    cols: new_cols,
    pixel_width: 0,
    pixel_height: 0,
};
pair.master.resize(new_size)?;
```

**Detection:**
- Unix: Listen for `SIGWINCH` signal
- Query: Use `termsize` crate for current dimensions
- Apply: Call `MasterPty::resize()` method

## 6. Signal Handling

### SIGINT (Ctrl+C) Propagation

**Approach 1: Process Group**
```rust
// Get process group leader
let pgid = pair.master.process_group_leader()?;

// Send to entire group (Unix)
nix::sys::signal::killpg(nix::unistd::Pid::from_raw(pgid), nix::sys::signal::SIGINT)?;
```

**Approach 2: Ctrl+C Handler**
```rust
ctrlc::set_handler(|| {
    running.store(false, Ordering::SeqCst);
})?;
```

**Critical Setup:**
- Use `set_controlling_tty(true)` in `CommandBuilder`
- Enables proper signal propagation to child process group
- Windows: ConPTY translates Ctrl+C to input writes

## 7. Known Limitations

### Windows-Specific Issues

1. **Output Inconsistency**
   - Garbage output reported (v0.9.0)
   - Long-running processes may require child exit before readable output
   - Workaround: Buffer reads, handle partial data

2. **EOF Handling**
   - Reading to EOF may hang on Windows
   - Cause: Active writable handles prevent true EOF
   - Fix: Explicitly close all PTY handles

3. **No Non-Blocking I/O**
   - Windows PTYs lack non-blocking I/O support
   - Complicates async programming patterns
   - Use threads for async operations

4. **ConPTY Startup**
   - Initial escape sequences emitted at startup
   - Terminal emulator must handle VT sequences correctly
   - Compatible with vt100-256color

### General Limitations

1. **Platform Differences**
   - Signal handling varies (Unix vs Windows)
   - Windows: Signals translated to input writes
   - Performance: ConPTY slower than WinPTY/cmd.exe in some cases

2. **Architecture**
   - ConPTY is translation layer (Console API ↔ PTY interface)
   - conhost continues interpreting VT sequences
   - Fundamental differences between Unix PTYs and Windows console

## 8. Recommendations

### Use Cases
✅ Terminal emulators
✅ Build tools with real-time output
✅ Interactive shell integration
✅ Cross-platform process spawning

### Avoid
❌ High-frequency async I/O on Windows (no non-blocking)
❌ Applications requiring immediate EOF detection on Windows
❌ Simple pipe-based scenarios (overkill)

### Best Practices
1. Always set `controlling_tty(true)` for signals
2. Handle initial escape sequences from ConPTY
3. Use threads for async operations on Windows
4. Explicitly close all handles before EOF detection
5. Test shell-specific behaviors (PowerShell vs bash)

## 9. Dependencies

**Runtime:**
- `winapi`/`windows-sys` (Windows)
- `libc` (Unix)

**Recommended Complements:**
- `ctrlc`: Signal handling
- `termsize`: Terminal dimensions
- `anyhow`: Error management

## Unresolved Questions

1. What is the exact behavior difference between ConPTY and WinPTY implementations?
2. Are there known workarounds for Windows EOF hanging issue?
3. How does performance compare to native PTY on Unix for high-frequency output?
4. What is the recommended pattern for graceful shutdown on Windows?

## Sources

- [portable-pty docs.rs](https://docs.rs/portable-pty/latest/portable_pty/)
- [WezTerm GitHub](https://github.com/wez/wezterm)
- [lib.rs crate page](https://lib.rs/crates/portable-pty)
- [ConPTY documentation](https://docs.microsoft.com/en-us/windows/console/creating-a-pseudoconsole)
- GitHub issues: wez/wezterm (Dec 2024, Mar 2024)
