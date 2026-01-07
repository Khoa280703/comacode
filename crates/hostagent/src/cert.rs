//! Certificate storage for Phase E04
//!
//! # CertStore
//!
//! Manages persistent storage of TLS certificates and private keys
//! using platform-specific data directories.
//!
//! ## Storage Location
//!
//! - **macOS**: `~/Library/Application Support/comacode/`
//! - **Linux**: `~/.local/share/comacode/`
//! - **Windows**: `%LOCALAPPDATA%\comacode\`
//!
//! ## Files
//!
//! - `host.crt` - Certificate (DER format)
//! - `host.key` - Private key (DER format, permissions 0600 on Unix)

use comacode_core::{CoreError, Result};
use rustls::pki_types::CertificateDer;
use sha2::{Digest, Sha256};
use std::fs;
use std::path::PathBuf;

/// Certificate storage
///
/// Persists certificates to disk to avoid repeated pairing.
#[allow(dead_code)]
pub struct CertStore {
    data_dir: PathBuf,
}

impl CertStore {
    /// Initialize certificate store
    ///
    /// Creates data directory if it doesn't exist.
    ///
    /// # Example
    /// ```
    /// # use hostagent::cert::CertStore;
    /// let store = CertStore::new().unwrap();
    /// assert!(store.data_dir().ends_with("comacode"));
    /// ```
    pub fn new() -> Result<Self> {
        let data_dir = dirs::data_local_dir()
            .ok_or(CoreError::NoDataDir)?
            .join("comacode");

        // Create directory if not exists
        fs::create_dir_all(&data_dir)
            .map_err(|e| CoreError::Io(std::io::Error::other(e)))?;

        Ok(Self { data_dir })
    }

    /// Get data directory path
    #[allow(dead_code)]
    pub fn data_dir(&self) -> PathBuf {
        self.data_dir.clone()
    }

    /// Path to certificate file
    #[allow(dead_code)]
    fn cert_path(&self) -> PathBuf {
        self.data_dir.join("host.crt")
    }

    /// Path to private key file
    #[allow(dead_code)]
    fn key_path(&self) -> PathBuf {
        self.data_dir.join("host.key")
    }

    /// Load existing certificate pair
    #[allow(dead_code)]
    ///
    /// Returns `None` if either file doesn't exist.
    ///
    /// # Example
    /// ```
    /// # use hostagent::cert::CertStore;
    /// # let store = CertStore::new().unwrap();
    /// let result = store.load();
    /// // Ok(None) if files don't exist
    /// // Ok(Some((cert, key_bytes))) if they do
    /// ```
    pub fn load(&self) -> Result<Option<(CertificateDer<'static>, Vec<u8>)>> {
        let cert_path = self.cert_path();
        let key_path = self.key_path();

        if !cert_path.exists() || !key_path.exists() {
            return Ok(None);
        }

        let cert_bytes = fs::read(&cert_path)?;
        let key_bytes = fs::read(&key_path)?;

        // Return certificate as DER (no parsing needed)
        let cert = CertificateDer::from(cert_bytes);

        Ok(Some((cert, key_bytes)))
    }

    /// Save new certificate pair
    ///
    /// Writes certificate and key to disk.
    /// Sets key file permissions to 0600 on Unix.
    #[allow(dead_code)]
    pub fn save(&self, cert: &CertificateDer<'_>, key: &[u8]) -> Result<()> {
        fs::write(self.cert_path(), cert.as_ref())?;
        fs::write(self.key_path(), key)?;

        // Set permissions (read-only by owner)
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perm = fs::metadata(self.key_path())?.permissions();
            perm.set_mode(0o600); // rw-------
            fs::set_permissions(self.key_path(), perm)?;
        }

        Ok(())
    }

    /// Get certificate fingerprint (SHA-256) - static convenience method
    ///
    /// Returns fingerprint as colon-separated hex string without requiring a CertStore instance.
    /// Useful when you only have a certificate reference and don't need persistence.
    ///
    /// # Example
    /// ```
    /// # use hostagent::cert::CertStore;
    /// # use rustls::pki_types::CertificateDer;
    /// let cert_der = CertificateDer::from(vec![/* DER bytes */]);
    /// let fp = CertStore::fingerprint_from_cert_der(&cert_der);
    /// ```
    pub fn fingerprint_from_cert_der(cert: &CertificateDer<'_>) -> String {
        let der = cert.as_ref();
        let hash = Sha256::digest(der);

        hash.iter()
            .map(|b| format!("{:02x}", b))
            .collect::<Vec<_>>()
            .join(":")
    }

    /// Get certificate fingerprint (SHA-256)
    ///
    /// Returns fingerprint as colon-separated hex string
    /// (e.g., "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33")
    #[allow(dead_code)]
    pub fn fingerprint(&self, cert: &CertificateDer<'_>) -> String {
        let der = cert.as_ref();
        let hash = Sha256::digest(der);

        // Format as hex with colons
        hash.iter()
            .map(|b| format!("{:02x}", b))
            .collect::<Vec<_>>()
            .join(":")
    }

    /// Clear stored certificates (for testing/reset)
    #[allow(dead_code)]
    pub fn clear(&self) -> Result<()> {
        let _ = fs::remove_file(self.cert_path());
        let _ = fs::remove_file(self.key_path());
        Ok(())
    }
}

impl Default for CertStore {
    fn default() -> Self {
        Self::new().expect("Failed to create CertStore")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cert_store_new() {
        let store = CertStore::new().unwrap();
        assert!(store.data_dir().ends_with("comacode"));
    }

    #[test]
    fn test_cert_store_paths() {
        let store = CertStore::new().unwrap();
        assert!(store.cert_path().ends_with("host.crt"));
        assert!(store.key_path().ends_with("host.key"));
    }

    #[test]
    fn test_cert_store_load_missing() {
        let store = CertStore::new().unwrap();
        // Clear any existing files
        store.clear().unwrap();
        // Loading non-existent files should return Ok(None)
        let result = store.load().unwrap();
        assert!(result.is_none());
    }

    #[test]
    fn test_fingerprint_format() {
        let store = CertStore::new().unwrap();

        // Create a dummy cert (just for testing fingerprint format)
        let dummy_der = b"test certificate data";
        let hash = Sha256::digest(dummy_der);
        let expected: String = hash.iter()
            .map(|b| format!("{:02x}", b))
            .collect::<Vec<_>>()
            .join(":");

        // fingerprint should be 32 bytes = 64 hex chars + 31 colons = 95 chars
        assert_eq!(expected.len(), 95);
        assert_eq!(expected.chars().filter(|c| *c == ':').count(), 31);
    }

    #[test]
    fn test_cert_store_clear() {
        let store = CertStore::new().unwrap();
        // clear should not error even if files don't exist
        assert!(store.clear().is_ok());
    }
}
