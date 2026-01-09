//! Raw mode terminal wrapper for crossterm
//!
//! Ensures terminal is restored to normal mode on drop (even on panic).

use crossterm::terminal;
use anyhow::Result;

/// Guard that enables raw mode and restores normal mode on drop.
///
/// # Example
/// ```no_run
/// let _guard = RawModeGuard::enable()?;
/// // Terminal is now in raw mode
/// // ... do work ...
/// // Raw mode automatically disabled when guard is dropped
/// # Ok::<(), anyhow::Error>(())
/// ```
pub struct RawModeGuard;

impl RawModeGuard {
    /// Enable raw mode for the terminal.
    ///
    /// Raw mode disables:
    /// - Line buffering (input available immediately)
    /// - Local echo (characters not echoed locally)
    /// - Signal generation (Ctrl+C passed as 0x03 byte)
    ///
    /// The terminal is automatically restored when the guard is dropped.
    pub fn enable() -> Result<Self> {
        terminal::enable_raw_mode()?;
        Ok(Self)
    }
}

impl Drop for RawModeGuard {
    fn drop(&mut self) {
        // Best-effort restore - ignore errors during cleanup
        let _ = terminal::disable_raw_mode();
    }
}
