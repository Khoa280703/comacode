//! Snapshot buffer for terminal output resync
//!
//! Provides ring buffer for storing raw PTY output bytes.
//! Preserves ANSI codes (colors, cursor movement) for accurate terminal replay.

use std::collections::VecDeque;

/// Ring buffer for terminal output snapshot
///
/// # Why Raw Bytes?
/// - Terminal output contains ANSI codes (colors, cursor movement, etc.)
/// - Parsing into String → .lines() would break ANSI structure
/// - Client receives raw bytes → xterm.dart handles ANSI rendering
/// - Reconnection displays correct vim/htop UI instead of garbled text
#[allow(dead_code)]
pub struct SnapshotBuffer {
    buffer: VecDeque<u8>,
    max_bytes: usize,
}

#[allow(dead_code)]
impl SnapshotBuffer {
    /// Create new snapshot buffer
    ///
    /// # Arguments
    /// * `max_bytes` - Maximum buffer size (e.g., 1MB for several screenfuls)
    pub fn new(max_bytes: usize) -> Self {
        Self {
            buffer: VecDeque::with_capacity(max_bytes),
            max_bytes,
        }
    }

    /// Push raw PTY output into buffer
    ///
    /// Automatically evicts oldest bytes when buffer is full.
    pub fn push(&mut self, data: &[u8]) {
        for &byte in data {
            if self.buffer.len() >= self.max_bytes {
                self.buffer.pop_front(); // Remove oldest byte
            }
            self.buffer.push_back(byte);
        }
    }

    /// Get full snapshot for resync (raw bytes)
    ///
    /// Returns all buffered bytes for sending to client on reconnection.
    pub fn get_snapshot(&self) -> Vec<u8> {
        self.buffer.iter().cloned().collect()
    }

    /// Get current buffer size in bytes
    pub fn len(&self) -> usize {
        self.buffer.len()
    }

    /// Check if buffer is empty
    pub fn is_empty(&self) -> bool {
        self.buffer.is_empty()
    }

    /// Clear buffer
    pub fn clear(&mut self) {
        self.buffer.clear();
    }

    /// Get buffer capacity
    pub fn capacity(&self) -> usize {
        self.max_bytes
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_push_and_get_snapshot() {
        let mut buf = SnapshotBuffer::new(100);
        assert!(buf.is_empty());

        buf.push(b"hello");
        assert_eq!(buf.len(), 5);
        assert_eq!(buf.get_snapshot(), b"hello");

        buf.push(b" world");
        assert_eq!(buf.len(), 11);
        assert_eq!(buf.get_snapshot(), b"hello world");
    }

    #[test]
    fn test_buffer_eviction_when_full() {
        let mut buf = SnapshotBuffer::new(10);

        // Fill buffer
        buf.push(b"0123456789"); // 10 bytes
        assert_eq!(buf.len(), 10);

        // Add more - should evict oldest
        buf.push(b"AB");
        assert_eq!(buf.len(), 10);

        // Oldest bytes (0, 1) should be evicted
        let snapshot = buf.get_snapshot();
        assert_eq!(snapshot, b"23456789AB");
    }

    #[test]
    fn test_clear() {
        let mut buf = SnapshotBuffer::new(100);
        buf.push(b"data");
        assert_eq!(buf.len(), 4);

        buf.clear();
        assert!(buf.is_empty());
        assert_eq!(buf.len(), 0);
    }

    #[test]
    fn test_preserve_ansi_codes() {
        let mut buf = SnapshotBuffer::new(100);

        // Simulate terminal output with ANSI color codes
        let output = b"\x1b[31mRed text\x1b[0mNormal text";
        buf.push(output);

        assert_eq!(buf.get_snapshot(), output);
    }

    #[test]
    fn test_large_output_eviction() {
        let mut buf = SnapshotBuffer::new(20);

        // Push multiple chunks
        buf.push(b"AAAABBBB"); // 8 bytes
        buf.push(b"CCCCDDDD"); // 8 bytes (total 16)
        buf.push(b"EEEEFFFF"); // 8 bytes (total 24, evicts first 4)

        // Should only keep last 20 bytes
        assert_eq!(buf.len(), 20);
        let snapshot = buf.get_snapshot();
        // After pushing "AAAABBBB" + "CCCCDDDD" + "EEEEFFFF" (24 bytes),
        // the first 4 bytes "AAAA" are evicted, leaving:
        // "BBBB" + "CCCCDDDD" + "EEEEFFFF" = "BBBBCCCCDDDDEEEEFFFF"
        assert_eq!(snapshot, b"BBBBCCCCDDDDEEEEFFFF");
    }
}
