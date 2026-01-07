Phase 1:
1. Flutter Build Integration (CI/CD Workflow)

Để tích hợp flutter_rust_bridge (FRB) vào CI/CD (GitHub Actions/GitLab CI), bạn không nên commit file sinh ra (bridge_generated.dart, bridge_generated.rs) vào git để giữ repo sạch. Hãy sinh nó trong lúc build.

Workflow chuẩn (Pipeline Steps):

Environment Setup: Cài đặt Flutter SDK, Rust toolchain (cargo), và llvm (cho ffigen).

Install Codegen Tool:

Bash
cargo install flutter_rust_bridge_codegen
Dependencies Install:

Flutter: flutter pub get

Rust: cargo fetch (trong folder native)

Codegen Execution (Critical Step): Chạy lệnh này trước khi chạy lệnh flutter build.

Bash
flutter_rust_bridge_codegen generate --rust-input native/src/api.rs --dart-output lib/bridge_generated.dart
Build App:

Android: flutter build apk --release (Nó sẽ tự gọi cargo build qua script Gradle mà FRB đã hook sẵn).

iOS: flutter build ipa --release (Tự gọi cargo build qua script Build Phase trong Xcode).

2. Binary Distribution (Platform Priority)

Dựa trên đối tượng mục tiêu "Mass Market" nhưng là Developer, đây là thứ tự ưu tiên release cho PC Agent:

Priority 1: Windows (x64)

Lý do: Chiếm thị phần lớn nhất trong giới dev đại trà (đặc biệt là sinh viên, junior dev ở VN).

Format: .exe portable (Zip) hoặc Installer (.msi dùng WiX Toolset).

Priority 2: macOS (Apple Silicon + Intel)

Lý do: Nhóm người dùng "chịu chi" và high-profile developers thường dùng Mac.

Format: .dmg hoặc Homebrew cask.

Priority 3: Linux (Debian/Ubuntu)

Lý do: Dành cho nhóm Hardcore/Server users.

Format: .deb hoặc binary nén .tar.gz.

Lưu ý: Với Mobile App, bạn nên release Android (APK/Play Store) trước vì dễ deploy và test diện rộng hơn iOS (TestFlight review rất gắt với các app chạy code/terminal).

3. Testing Strategy (FFI Boundary)

Testing phần giao tiếp giữa Dart và Rust là khó nhất. Unit test riêng lẻ là không đủ.

Layer 1: Rust Unit Tests (Pure Logic)

Test logic giao thức QUIC, PTY parsing ngay trong Rust.

cargo test chạy trong CI.

Layer 2: Dart Widget Tests (UI Mock)

Mock lại lớp API Rust trả về dữ liệu giả để test UI Flutter.

Layer 3: Integration Tests (FFI Boundary - Quan trọng nhất)

Sử dụng gói integration_test của Flutter chạy trên máy ảo/thiết bị thật.

Chiến lược: Viết kịch bản Dart gọi xuống hàm Rust thực tế, Rust xử lý và trả về.

Ví dụ: Dart gọi connect_pc(), Rust thực hiện mock socket, trả về Stream. Dart expect stream đó nhận được gói tin HandshakeSuccess.

Lưu ý: Cần setup environment cho test này khá kỹ (load thư viện dynamic .so/.dylib trong môi trường test).

4. Code Signing (Nỗi đau cần thiết) ( phần này chúng ta sẽ giải quyết sau khi đã phát triển gần xong)

Để app không bị hệ điều hành chặn (SmartScreen/Gatekeeper), bạn bắt buộc phải ký code (Code Signing).

macOS (Bắt buộc):

Cần tài khoản Apple Developer ($99/năm).

Quy trình: Build Release -> Codesign (bằng certificate) -> Notarize (Gửi lên Apple server check malware) -> Staple (Gắn vé thông hành vào app).

Tool hỗ trợ: gon (của Hashicorp) để automate việc notarize trong CI/CD.

Windows (Nên làm):

Cần mua chứng chỉ EV Code Signing (khá đắt, ~$300-400/năm) để không hiện màn hình đỏ "Windows protected your PC".

Hack: Nếu chưa có kinh phí, có thể dùng Self-signed certificate, nhưng user phải bấm "Run anyway". Hoặc publish lên Microsoft Store, Microsoft sẽ ký thay bạn.

5. Version Management (Sync Rust & Flutter)

Dự án này là Monorepo, việc lệch version giữa Client (Flutter) và Agent (Rust) sẽ gây crash app (do sai lệch cấu trúc gói tin Binary Postcard).

Giải pháp: Single Source of Truth

Tạo một file VERSION ở thư mục gốc dự án (ví dụ: 0.1.0).

Viết một script scripts/sync_version.sh chạy pre-build:

Đọc file VERSION.

Ghi đè vào packages/agent/Cargo.toml (phần version).

Ghi đè vào packages/client_mobile/pubspec.yaml (phần version).

Sinh ra một file constant code:

Rust: pub const APP_VERSION: &str = "0.1.0";

Dart: const String appVersion = "0.1.0";

Runtime Check: Khi kết nối, PC Agent và Mobile App gửi version cho nhau. Nếu lệch Major/Minor version -> Hiện popup bắt buộc update.

Phase 2:
1. Protocol Versioning (Backward Compatibility)

Vấn đề: Khi bạn update App Mobile (v2.0), làm sao để nó vẫn nói chuyện được với PC Agent cũ (v1.0) mà không bị crash do lệch cấu trúc nhị phân (postcard)?

Giải pháp: Semantic Handshake & Enum Versioning

Strict Handshake (Cổng kiểm soát):

Gói tin đầu tiên khi kết nối luôn luôn là Handshake { protocol_version: u32, app_version: String }.

Quy tắc: Nếu protocol_version khác nhau -> Ngắt kết nối ngay lập tức và hiện thông báo: "PC Agent is outdated. Please update." (Đây là cách an toàn nhất cho giai đoạn đầu, tránh việc phải duy trì logic phức tạp cho nhiều phiên bản).

Enum Wrapper (Cho tương lai):

Thay vì gửi struct thô, hãy gói tất cả trong một Enum có version.

Rust
#[derive(Serialize, Deserialize)]
pub enum Packet {
    V1(PacketV1), // Cấu trúc cũ
    V2(PacketV2), // Cấu trúc mới có thêm field
}
Khi Mobile nhận được V1, nó sẽ map sang V2 (với các giá trị mặc định) để xử lý tiếp.

Lời khuyên: Với team nhỏ, hãy dùng Strict Handshake. Đừng cố hỗ trợ ngược (Backward Compatibility) quá sâu, nó sẽ làm code Rust của bạn thành "đống rác" logic rất nhanh.

2. Message Size Limits (16MB Limit)

Vấn đề: Bạn lo lắng giới hạn 16MB của quinn (hoặc cấu hình mặc định) không đủ khi chạy lệnh cat huge_file.log?

Giải pháp: Streaming, không phải Messaging.

Hiểu đúng về Terminal Output:

Terminal (PTY) không bao giờ trả về 16MB trong một lần đọc. Nó hoạt động theo cơ chế Stream. Hệ điều hành thường chỉ trả về buffer khoảng 4KB đến 64KB mỗi lần đọc (read syscall).

Vì vậy, bạn sẽ gửi hàng nghìn gói tin nhỏ (mỗi gói ~4KB), chứ không bao giờ gửi một cục 16MB. Gói tin nhỏ giúp độ trễ thấp hơn (người dùng thấy chữ chạy ra liên tục thay vì chờ load xong cục to).

Với tính năng File Transfer (Tải file):

Tuyệt đối không load toàn bộ file vào RAM rồi serialize thành một gói tin Packet::FileContent.

Cách làm đúng: Sử dụng QUIC Streams API.

Mở một SendStream.

Đọc file từ ổ cứng từng chunk 64KB -> Ghi thẳng vào Stream.

Bên nhận (Mobile) đọc từ Stream -> Ghi xuống file/cache.

Cách này cho phép bạn tải file 100GB cũng được, bộ nhớ RAM chỉ tốn vài chục KB.

3. Error Recovery (Connection Loss Scenarios)

Vấn đề: Xử lý thế nào khi mất mạng, và các loại lỗi cụ thể để UI phản hồi đúng?

Giải pháp: State Machine & Specific Error Types

Các loại lỗi cụ thể (Rust Enum): Định nghĩa rõ ràng trong Shared Core để cả Dart và Rust đều hiểu:

Rust
#[derive(Serialize, Deserialize, Debug)]
pub enum ConnectionError {
    AuthFailed,           // Sai mã PIN
    VersionMismatch,      // Cần update app
    HostUnreachable,      // PC tắt hoặc chặn firewall
    Timeout,              // Mất kết nối quá lâu (Heartbeat fail)
    StreamReset,          // Lỗi logic nội bộ
}
Cơ chế hồi phục (Recovery Strategy):

Transient Loss (Thoáng qua): QUIC tự xử lý (nhờ Connection Migration). UI không cần làm gì, hoặc chỉ hiện icon "Reconnecting..." nhỏ góc màn hình.

Hard Disconnect (Mất hẳn > 10s):

Client: Chuyển UI sang màn hình "Lost Connection".

Logic: Tự động thử reconnect (Exponential Backoff: thử lại sau 1s, 2s, 5s...).

Quan trọng - State Resync: Khi kết nối lại thành công, Mobile phải gửi lệnh RequestRedraw. PC Agent sẽ gửi lại toàn bộ nội dung màn hình hiện tại (Buffer 80x24) để đồng bộ lại, tránh việc màn hình bị rách hoặc thiếu chữ.

4. Testing Strategy (Integration Tests với Real Network)

Vấn đề: Unit test là không đủ. Bạn cần test xem QUIC có thực sự "ngon" khi mạng lag hay rớt gói không.

Giải pháp: Network Simulation (Giả lập môi trường mạng xấu)

Đừng test trên mạng thật (quá ngẫu nhiên). Hãy dùng công cụ để tạo ra môi trường mạng "tệ hại" một cách có kiểm soát trong CI/CD.

Tools: Sử dụng Toxiproxy (của Shopify) hoặc Docker + Pumba (Linux Traffic Control tc).

Kịch bản Test (Integration Test Suite): Dựng 2 container Docker: 1 Agent (Server), 1 Client (Test Runner).

Case 1: Happy Path: Kết nối, gửi lệnh echo hello, assert nhận về "hello".

Case 2: High Latency: Inject 500ms delay. Gửi lệnh, đo thời gian phản hồi. Kiểm tra xem app có crash không.

Case 3: Packet Loss: Inject 10% packet loss (QUIC phải tỏa sáng ở đây). Assert rằng dữ liệu cuối cùng vẫn nhận đủ (nhờ cơ chế retransmit của QUIC).

Case 4: Reconnection: Chặn port trong 5s rồi mở lại. Assert rằng Client tự kết nối lại được.

Workflow trong GitHub Actions:

YAML
steps:
  - name: Start Network Simulator
    run: docker-compose up -d toxiproxy
  - name: Run Integration Tests
    run: cargo test --test integration_network_resilience

Phase 3:
1. Output Streaming Architecture (High-Performance Design)

Đây là phần quan trọng nhất để đạt được "Zero Latency" mà không bị crash bộ nhớ.

Q: Use Arc<Mutex<SendStream>> for shared ownership?

A: TUYỆT ĐỐI KHÔNG.

Lý do: Trong lập trình Async (Tokio), Mutex là kẻ thù của hiệu năng cao. Khi bạn stream dữ liệu liên tục, việc lock/unlock Mutex hàng nghìn lần mỗi giây sẽ gây ra Lock Contention (tranh chấp khóa), làm nghẽn luồng thực thi.

Q: Or use channel-based forwarding with dedicated writer task?

A: CHÍNH XÁC. Đây là Best Practice (Actor Model).

Thiết kế:

Reader Task: Một vòng lặp đọc dữ liệu thô từ PTY (stdout).

Channel: Đẩy dữ liệu vào một mpsc::channel (Multi-producer, Single-consumer).

Writer Task: Một task riêng biệt chỉ làm nhiệm vụ lấy dữ liệu từ Channel và ghi vào QUIC SendStream.

Lợi ích: Tách biệt việc đọc và ghi. Nếu mạng chậm, nó không làm treo việc đọc PTY (đến một giới hạn).

Q: How to handle backpressure from slow clients?

A: Sử dụng Bounded Channel (Channel có giới hạn dung lượng).

Thay vì dùng channel vô tận (unbounded), hãy dùng mpsc::channel(1024) (chứa tối đa 1024 chunk).

Cơ chế:

Nếu mạng Mobile quá lag (Client nhận chậm), Writer Task sẽ lấy dữ liệu chậm.

Channel sẽ bị đầy.

Khi Channel đầy, hàm .send().await ở Reader Task sẽ bị block (tạm dừng) bởi Tokio.

Hệ quả: PTY ngừng đọc -> Process con (ví dụ cat huge_file) sẽ tự động bị OS dừng lại (block write stdout) -> Tự động cân bằng tốc độ (Natural Backpressure) mà không cần viết logic phức tạp.

2. Certificate Management (Security vs UX)

QUIC bắt buộc phải có TLS 1.3.

Q: Persist certificate/key to disk? Or regenerate on every startup?

A: Bắt buộc phải Persist (Lưu xuống đĩa).

Lý do UX: Nếu mỗi lần bật PC bạn lại sinh cert mới, Client Mobile sẽ thấy đây là một "Server lạ" và bắt người dùng xác nhận lại (Trust Warning) hoặc phải quét mã QR lại từ đầu. Điều này giết chết trải nghiệm "Vibe".

Vị trí lưu: Sử dụng thư viện dirs của Rust để lưu vào thư mục chuẩn của hệ thống (VD: %APPDATA%/comacode/cert.der trên Windows).

Q: How to distribute certificate to mobile clients?

A: Trust On First Use (TOFU) với Certificate Fingerprint.

Không gửi toàn bộ file cert qua mạng (rủi ro Man-in-the-Middle).

Quy trình:

PC: Sinh Cert -> Tính toán mã băm (SHA-256 Fingerprint) của Cert -> Hiển thị mã QR chứa: IP + Port + Cert_Fingerprint.

Mobile: Quét QR -> Lưu Fingerprint đó lại.

Handshake: Khi kết nối QUIC (TLS handshake), Mobile nhận Cert từ Server gửi về. Mobile so sánh mã băm của Cert nhận được với Fingerprint đã lưu trong QR.

Khớp: Kết nối an toàn. Không khớp: Cảnh báo bị tấn công.

3. Session Cleanup Policy (Resource Management)

Q: Should cleanup on connection close immediately?

A: KHÔNG. Cần có "Grace Period" (Thời gian ân hạn).

Thực tế: Mạng di động rất chập chờn. Người dùng chuyển từ Wifi sang 4G, hoặc lỡ tay tắt màn hình điện thoại, kết nối QUIC có thể bị rớt tạm thời.

Nếu kill PTY ngay lập tức: Người dùng mất toàn bộ công việc đang làm dở (VD: đang chạy server, đang edit vim).

Q: 30-second interval có hợp lý?

A: Interval check 30s là hợp lý, nhưng Timeout phải lâu hơn.

Cấu hình đề xuất:

Check Interval: 30 giây (Task dọn dẹp chạy 1 lần).

Session Timeout: 15 phút (hoặc cho user cấu hình).

Q: How to handle "zombie" sessions?

A: Cơ chế "Last Active Timestamp".

Cấu trúc dữ liệu (Rust):

Rust
struct Session {
    pty: PtyPair,
    last_active: Instant, // Cập nhật mỗi khi có input/output hoặc heartbeat
    is_connected: bool,
}
Logic dọn dẹp:

Khi Socket disconnect -> Set is_connected = false. (Vẫn giữ Session trong HashMap).

Background Task (chạy mỗi 30s) quét HashMap:

Nếu !is_connected VÀ now - last_active > 15 minutes => Kill PTY & Drop Session.

4. Platform-Specific Behavior (Xử lý đa nền tảng)

Dù thư viện portable-pty đã hỗ trợ abstraction rất tốt, nhưng "con quỷ nằm ở chi tiết" (devil is in the details). Bạn cần xử lý các khác biệt sau để trải nghiệm đồng nhất:

A. Windows PTY vs. Unix PTY

Unix (macOS/Linux): Sử dụng chuẩn POSIX PTY (/dev/ptmx). Hoạt động rất ổn định.

Windows:

Trước Windows 10 (1809): Dùng WinPTY (Hack cơ chế pipe). Rất nhiều lỗi, không hỗ trợ tốt mã màu ANSI.

Windows 10 (1809) trở lên: Microsoft đã ra mắt ConPTY (Pseudo Console API). Đây là chuẩn xịn, hỗ trợ ANSI 100%.

Quyết định: Trong code Rust, cấu hình portable-pty để Force use ConPTY. Nếu máy user là Windows 7/8, hãy hiện thông báo "Không hỗ trợ" thay vì cố dùng WinPTY đầy lỗi. Chúng ta hướng tới "Best Experience", không phải "All Support".

B. Shell Detection Fallback Logic (Tự động chọn Shell)

Agent không nên crash nếu user chưa cấu hình shell. Hãy dùng logic "thác nước" (Waterfall) để tìm shell khả dụng:

Windows:

Ưu tiên 1: pwsh.exe (PowerShell Core 7+ - Hiện đại, nhanh).

Ưu tiên 2: powershell.exe (PowerShell 5 cũ - Có sẵn mọi máy).

Ưu tiên 3: cmd.exe (Fallback cuối cùng).

macOS:

Ưu tiên 1: Biến môi trường $SHELL (User thường cài zsh/fish xịn).

Ưu tiên 2: /bin/zsh (Mặc định của macOS hiện đại).

Ưu tiên 3: /bin/bash.

Linux:

Ưu tiên 1: Biến môi trường $SHELL.

Ưu tiên 2: /bin/bash.

Ưu tiên 3: /bin/sh.

C. Environment Variables Inheritance (Thừa kế biến môi trường)

Nguyên tắc: PTY PHẢI thừa kế biến môi trường của hệ thống (đặc biệt là PATH) để user gõ npm, cargo, python máy đều hiểu.

Ghi đè (Override): Tuy nhiên, bạn bắt buộc phải ghi đè các biến sau để UI hiển thị đúng màu:

Rust
// Rust Agent Config
cmd_builder.env("TERM", "xterm-256color"); // Báo cho CLI biết terminal hỗ trợ màu
cmd_builder.env("COLORTERM", "truecolor"); // Hỗ trợ 16 triệu màu (RGB)
cmd_builder.env("LANG", "en_US.UTF-8");    // Fix lỗi hiển thị Unicode/Emoji
5. Security Hardening (Bảo mật tối đa)

Vì bạn mở cổng cho phép thực thi lệnh từ xa (Remote Code Execution), bảo mật phải đặt lên hàng đầu.

A. Client Certificate Authentication (mTLS)?

Phân tích: mTLS (Mutual TLS) yêu cầu cả Server và Client đều phải có chứng chỉ. Rất bảo mật nhưng UX cực tệ cho mô hình "Mass Market" (Làm sao chuyển Private Key an toàn từ PC sang điện thoại lúc setup?).

Giải pháp thay thế (Vibe & Secure): Sử dụng mô hình Shared Secret Token (API Key).

PC sinh ra một chuỗi ngẫu nhiên 32-byte (Token).

Token này được nhúng vào mã QR (cùng với IP/Port/Cert Fingerprint).

Mobile quét QR -> Lấy được Token.

Khi kết nối, Mobile gửi Token trong Header của QUIC handshake.

PC check Token: Đúng -> Cho phép. Sai -> Ngắt ngay lập tức.

Lợi ích: Vẫn được bảo vệ bởi lớp mã hóa TLS của QUIC, nhưng không cần quản lý file key phức tạp trên điện thoại.

B. IP Whitelisting/Blacklisting?

Whitelisting (Danh sách trắng): Không khả thi trong mạng LAN (IP thay đổi liên tục do DHCP) hoặc mạng 4G (IP động).

Blacklisting (Danh sách đen): Cần thiết để chặn các IP cố tình spam/tấn công.

Cơ chế: Lưu HashMap<IpAddr, BanUntilTime>. Nếu IP này bị ban, drop gói tin QUIC ngay từ tầng ngoài cùng, không tốn CPU xử lý handshake.

C. Rate Limiting (Giới hạn tần suất)

Bắt buộc phải có để chống Brute-force (dò mã PIN/Token).

Logic:

Cho phép tối đa: 5 lần thử kết nối sai trong 1 phút.

Nếu vượt quá: Ban IP đó trong 15 phút.

Thư viện Rust: Sử dụng crate governor (triển khai thuật toán GCRA - Generic Cell Rate Algorithm). Nó cực nhanh và thread-safe.

Rust
// Ví dụ logic Rate Limit trong Rust Agent
use governor::{Quota, RateLimiter};
use std::num::NonZeroU32;

// Cho phép 5 request mỗi phút
let quota = Quota::per_minute(NonZeroU32::new(5).unwrap());
let limiter = RateLimiter::direct(quota);

if limiter.check().is_err() {
    // Drop connection silently or send specific error
    return ConnectionError::RateLimitExceeded;
}

