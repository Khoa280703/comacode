//! Terminal abstraction trait

use crate::error::{CoreError, Result};
use crate::types::TerminalEvent;
use async_trait::async_trait;

/// Terminal abstraction for PTY operations
#[async_trait]
pub trait Terminal: Send + Sync {
    /// Write data to terminal input
    async fn write(&mut self, data: &[u8]) -> Result<()>;

    /// Read output events from terminal
    async fn read(&mut self) -> Result<TerminalEvent>;

    /// Resize terminal
    fn resize(&mut self, rows: u16, cols: u16) -> Result<()>;

    /// Close/kill terminal process
    async fn kill(&mut self) -> Result<()>;

    /// Get current size
    fn size(&self) -> Result<(u16, u16)>;

    /// Get current terminal state for snapshot
    /// Returns (raw bytes, rows, cols) for maximum compatibility
    fn get_snapshot(&self) -> Result<(Vec<u8>, u16, u16)>;
}

/// Terminal configuration
#[derive(Debug, Clone)]
pub struct TerminalConfig {
    /// Initial rows
    pub rows: u16,

    /// Initial columns
    pub cols: u16,

    /// Shell command to run
    pub shell: String,

    /// Environment variables
    pub env: Vec<(String, String)>,
}

impl Default for TerminalConfig {
    fn default() -> Self {
        Self {
            rows: 24,
            cols: 80,
            shell: Self::default_shell(),
            env: vec![("TERM".to_string(), "xterm-256color".to_string())],
        }
    }
}

impl TerminalConfig {
    #[cfg(unix)]
    fn default_shell() -> String {
        std::env::var("SHELL").unwrap_or_else(|_| "/bin/bash".to_string())
    }

    #[cfg(windows)]
    fn default_shell() -> String {
        std::env::var("COMSPEC").unwrap_or_else(|_| "cmd.exe".to_string())
    }

    /// Create with custom size
    pub fn with_size(rows: u16, cols: u16) -> Self {
        Self {
            rows,
            cols,
            ..Default::default()
        }
    }

    /// Set custom shell
    pub fn with_shell(mut self, shell: String) -> Self {
        self.shell = shell;
        self
    }

    /// Add configuration variable
    pub fn with_env(mut self, key: String, value: String) -> Self {
        self.env.push((key, value));
        self
    }
}

/// Mock terminal for testing
pub struct MockTerminal {
    config: TerminalConfig,
    alive: bool,
    snapshot_data: Vec<u8>,
}

impl MockTerminal {
    /// Create new mock terminal
    pub fn new(config: TerminalConfig) -> Self {
        Self {
            config,
            alive: true,
            snapshot_data: Vec::new(),
        }
    }

    /// Set snapshot data for testing
    pub fn set_snapshot_data(&mut self, data: Vec<u8>) {
        self.snapshot_data = data;
    }
}

#[async_trait]
impl Terminal for MockTerminal {
    async fn write(&mut self, _data: &[u8]) -> Result<()> {
        if !self.alive {
            return Err(CoreError::Terminal("Terminal is dead".into()));
        }
        Ok(())
    }

    async fn read(&mut self) -> Result<TerminalEvent> {
        if !self.alive {
            return Err(CoreError::Terminal("Terminal is dead".into()));
        }
        Ok(TerminalEvent::output(b"".to_vec()))
    }

    fn resize(&mut self, rows: u16, cols: u16) -> Result<()> {
        if !self.alive {
            return Err(CoreError::Terminal("Terminal is dead".into()));
        }
        self.config.rows = rows;
        self.config.cols = cols;
        Ok(())
    }

    async fn kill(&mut self) -> Result<()> {
        self.alive = false;
        Ok(())
    }

    fn size(&self) -> Result<(u16, u16)> {
        Ok((self.config.rows, self.config.cols))
    }

    fn get_snapshot(&self) -> Result<(Vec<u8>, u16, u16)> {
        if !self.alive {
            return Err(CoreError::Terminal("Terminal is dead".into()));
        }
        Ok((
            self.snapshot_data.clone(),
            self.config.rows,
            self.config.cols,
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_mock_terminal() {
        let mut term = MockTerminal::new(TerminalConfig::default());
        assert_eq!(term.size().unwrap(), (24, 80));
        term.resize(40, 120).unwrap();
        assert_eq!(term.size().unwrap(), (40, 120));
        term.write(b"test").await.unwrap();
        term.kill().await.unwrap();
    }

    #[tokio::test]
    async fn test_dead_terminal() {
        let mut term = MockTerminal::new(TerminalConfig::default());
        term.kill().await.unwrap();
        let result = term.write(b"test").await;
        assert!(result.is_err());
    }

    #[test]
    fn test_terminal_config() {
        let config = TerminalConfig::with_size(40, 120)
            .with_shell("/bin/zsh".to_string())
            .with_env("TEST".to_string(), "value".to_string());
        assert_eq!(config.rows, 40);
        assert_eq!(config.cols, 120);
        assert_eq!(config.shell, "/bin/zsh");
        assert_eq!(config.env.len(), 2);
    }

    #[tokio::test]
    async fn test_get_snapshot() {
        let mut term = MockTerminal::new(TerminalConfig::default());
        let test_data = b"Terminal snapshot data".to_vec();
        term.set_snapshot_data(test_data.clone());
        let (data, rows, cols) = term.get_snapshot().unwrap();
        assert_eq!(data, test_data);
        assert_eq!(rows, 24);
        assert_eq!(cols, 80);
    }

    #[tokio::test]
    async fn test_get_snapshot_dead_terminal() {
        let mut term = MockTerminal::new(TerminalConfig::default());
        term.kill().await.unwrap();
        let result = term.get_snapshot();
        assert!(result.is_err());
    }
}
