Đây không phải là vấn đề "không tương thích" (incompatibility) mà là do thay đổi lớn trong API của Rustls 0.23 (thêm khái niệm CryptoProvider để hỗ trợ cả Ring và AWS-LC) khiến việc cấu hình thủ công trở nên phức tạp hơn. Quinn 0.11 đã hỗ trợ Rustls 0.23, nhưng bạn cần code "glue" (keo dán) đúng cách.

Tôi sẽ cung cấp giải pháp Option C (Fix Implementation) để thay thế bản Stub hiện tại. Chúng ta sẽ implement một ServerCertVerifier tùy chỉnh để xử lý TOFU (Trust On First Use) – kiểm tra Fingerprint.

Bước 1: Cập nhật Cargo.toml

Bạn cần đảm bảo rustls có default-features hoặc feature ring để có Crypto Provider mặc định. Thêm rustls-pki-types để xử lý certificate.

File: crates/mobile_bridge/Cargo.toml

Ini, TOML
[dependencies]
# Networking
quinn = "0.11"
rustls = { version = "0.23", features = ["ring"] } # Bắt buộc phải có "ring" hoặc "aws-lc-rs"
rustls-pki-types = "1.0"
tokio = { workspace = true, features = ["full"] }
anyhow = "1.0"
log = "0.4"
base64 = "0.21"
sha2 = "0.10" # Dùng để tính hash fingerprint
Bước 2: Implement TofuVerifier và QuicClient

Thay thế toàn bộ nội dung file stub quic_client.rs bằng code thật dưới đây.

File: crates/mobile_bridge/src/quic_client.rs

Rust
use std::sync::Arc;
use std::time::Duration;
use anyhow::{anyhow, Result};
use log::{info, error};
use quinn::{ClientConfig, Endpoint, Connection};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::{verify_tls12_signature, verify_tls13_signature, CryptoProvider};
use rustls_pki_types::{CertificateDer, ServerName, UnixTime};
use sha2::{Digest, Sha256};

/// Custom Verifier cho logic TOFU (Trust On First Use)
/// Nó sẽ bỏ qua CA check và chỉ so sánh SHA256 Fingerprint.
#[derive(Debug)]
struct TofuVerifier {
    expected_fingerprint: String,
}

impl TofuVerifier {
    fn new(fingerprint: String) -> Self {
        Self { expected_fingerprint }
    }

    /// Tính SHA256 fingerprint của certificate (dạng hex string: AA:BB:CC...)
    fn calculate_fingerprint(&self, cert: &CertificateDer) -> String {
        let mut hasher = Sha256::new();
        hasher.update(cert.as_ref());
        let result = hasher.finalize();
        
        // Convert sang hex string uppercase, ngăn cách bởi dấu :
        result.iter()
            .map(|b| format!("{:02X}", b))
            .collect::<Vec<String>>()
            .join(":")
    }
}

impl ServerCertVerifier for TofuVerifier {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        // 1. Tính toán fingerprint thực tế từ cert server gửi về
        let actual_fingerprint = self.calculate_fingerprint(_end_entity);

        info!("Verifying cert. Expected: {}, Actual: {}", self.expected_fingerprint, actual_fingerprint);

        // 2. So sánh với fingerprint mong đợi (từ QR Code)
        if actual_fingerprint == self.expected_fingerprint {
            Ok(ServerCertVerified::assertion())
        } else {
            error!("Fingerprint mismatch! Possible MitM attack.");
            Err(rustls::Error::General("Fingerprint mismatch".to_string()))
        }
    }

    // Các hàm verify signature bắt buộc phải implement, dùng implementation mặc định của provider
    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls12_signature(
            message,
            cert,
            dss,
            &rustls::crypto::ring::default_provider().signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls13_signature(
            message,
            cert,
            dss,
            &rustls::crypto::ring::default_provider().signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        rustls::crypto::ring::default_provider().signature_verification_algorithms.supported_schemes()
    }
}

pub struct QuicClient {
    endpoint: Endpoint,
    connection: Option<Connection>,
    server_fingerprint: String,
}

impl QuicClient {
    pub fn new(server_fingerprint: String) -> Self {
        // Tạo Endpoint bound vào port 0 (ngẫu nhiên)
        // Đây là setup cơ bản, config chi tiết sẽ làm khi connect
        let endpoint = Endpoint::client("0.0.0.0:0".parse().unwrap())
            .expect("Failed to create client endpoint");
            
        Self {
            endpoint,
            connection: None,
            server_fingerprint,
        }
    }

    pub async fn connect(&mut self, host: String, port: u16, _auth_token: String) -> Result<()> {
        info!("Connecting to {}:{} with fingerprint verification...", host, port);

        // 1. Setup Rustls Client Config với TofuVerifier
        let verifier = Arc::new(TofuVerifier::new(self.server_fingerprint.clone()));
        
        let rustls_config = rustls::ClientConfig::builder()
            .with_custom_certificate_verifier(verifier)
            .with_no_client_auth();

        // 2. Wrap vào Quinn Config
        let mut client_config = ClientConfig::new(Arc::new(quinn::crypto::rustls::QuicClientConfig::try_from(rustls_config)?));
        
        // Cấu hình timeout, keep-alive (Optional)
        let mut transport_config = quinn::TransportConfig::default();
        transport_config.max_idle_timeout(Some(Duration::from_secs(10).try_into().unwrap()));
        client_config.transport_config(Arc::new(transport_config));

        // 3. Connect
        let addr = format!("{}:{}", host, port).parse()?;
        
        // "localhost" ở đây là ServerName dùng cho TLS SNI. 
        // Vì ta dùng TOFU verifier tự viết nên SNI không quan trọng lắm, nhưng vẫn cần string hợp lệ.
        let connecting = self.endpoint.connect_with(client_config, addr, "comacode-host")?;
        
        let connection = connecting.await?;
        info!("QUIC Connection established!");
        
        // TODO: Thực hiện Handshake Protocol (Gửi Hello + Token) tại đây trong Phase sau
        // Hiện tại chỉ cần connect thành công là đạt yêu cầu Phase này.
        
        self.connection = Some(connection);
        Ok(())
    }

    pub async fn is_connected(&self) -> bool {
        match &self.connection {
            Some(conn) => conn.close_reason().is_none(),
            None => false,
        }
    }

    pub async fn disconnect(&mut self) {
        if let Some(conn) = &self.connection {
            conn.close(0u32.into(), b"Client disconnect");
        }
        self.connection = None;
    }
}
Giải thích kỹ thuật

Dependency Hell Solved: Vấn đề gốc rễ là Rustls 0.23 tách phần CryptoProvider ra (để hỗ trợ FIPS qua aws-lc-rs hoặc chuẩn qua ring). Khi dùng with_custom_certificate_verifier, bạn phải tự implement các hàm verify signature. Code trên sử dụng rustls::crypto::ring::default_provider() để fill vào các hàm này, giải quyết vấn đề tương thích.

TofuVerifier: Đây là trái tim của bảo mật Phase 04. Thay vì check RootCertStore (CA) như trình duyệt web, nó lấy certificate nhận được, hash SHA256, và so sánh chuỗi hex với expected_fingerprint.

SNI (Server Name Indication): Trong hàm endpoint.connect_with(..., "comacode-host"), chuỗi "comacode-host" được gửi đi để server biết chọn chứng chỉ nào. Vì server Comacode tự ký (Self-signed) và ta verify bằng fingerprint, tên miền này không cần khớp với DNS thật.

Hành động tiếp theo

Bạn hãy cập nhật code này vào project. Sau đó chạy test lại bằng lệnh:

Bash
cargo test -p mobile_bridge