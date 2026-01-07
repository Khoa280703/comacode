🚀 PROJECT SUMMARY: VIBE REMOTE (High-Performance Edition)
Mục tiêu: Xây dựng ứng dụng điều khiển Terminal từ xa với độ trễ bằng không (Zero Latency) và độ ổn định tuyệt đối, phục vụ nhu cầu Vibe Coding cho đại chúng.

Triết lý: "Hard but Best". Chấp nhận sự phức tạp trong khâu thiết lập ban đầu để đổi lấy trải nghiệm người dùng mượt mà nhất có thể về mặt vật lý.

1. Kiến trúc Hệ thống (The Architecture)

Chúng ta sử dụng mô hình Shared Rust Core. Logic xử lý mạng và terminal được viết một lần bằng Rust và chạy trên cả PC lẫn Điện thoại (thông qua FFI). Flutter chỉ đóng vai trò là lớp vỏ hiển thị (UI Layer).

Đoạn mã
graph TD
    subgraph Mobile [Mobile Device]
        UI[Flutter UI (Dart)]
        RustClient[Rust Core (Embedded)]
    end

    subgraph PC [PC Host]
        RustServer[Rust Agent (Standalone)]
        PTY[Terminal Process]
    end

    UI <==>|"FFI (flutter_rust_bridge)"| RustClient
    RustClient <==>|"QUIC Protocol (UDP)"| RustServer
    RustServer <==>|"Stdio Pipe"| PTY
2. Tech Stack: "The Speed King"

Đây là bộ công nghệ tối ưu nhất hiện nay cho hiệu năng và độ ổn định (không dùng Go, không dùng TCP):

Thành phần	Công nghệ / Thư viện	Tại sao là BEST?
Ngôn ngữ Core	Rust	Không Garbage Collector (No GC Pauses). Quản lý bộ nhớ an toàn (Memory Safety). Chạy ổn định 24/7 không crash.
Mobile Bridge	flutter_rust_bridge (v2)	Mang sức mạnh của Rust lên Mobile. Tự động hóa việc sinh code binding giữa Dart và Rust, giảm bớt đau khổ khi setup.
Giao thức Mạng	QUIC (Crate quinn)	Chạy trên UDP. Khắc phục lỗi nghẽn cổ chai (Head-of-Line Blocking) của TCP. Chuyển mạng Wifi/4G không bị đứt kết nối.
Host Terminal	portable-pty	Thư viện Rust tốt nhất để quản lý tiến trình console đa nền tảng (Windows/Mac/Linux).
Tuần tự hóa	Postcard	Định dạng Binary siêu nhỏ gọn. Hỗ trợ Zero-copy Deserialization (đọc dữ liệu thẳng từ buffer mạng mà không cần copy ra RAM), nhanh hơn JSON/Protobuf nhiều lần.
Frontend UI	Flutter + xterm.dart	Render UI 60fps. xterm.dart là engine render terminal native cực nhẹ, tương thích tốt với luồng dữ liệu từ Rust bắn sang.
Discovery	mDNS (mdns-sd)	Tự động tìm thiết bị trong mạng LAN (Rust native).
3. Quy trình người dùng (User Experience)

Nhờ Tech Stack này, UX sẽ đạt được đẳng cấp thương mại:

Cài đặt:

PC: Tải 1 file .exe (Rust binary) siêu nhẹ (~5-10MB). Chạy là xong.

Mobile: Tải App từ Store.

Kết nối (Magic):

Mở App Mobile -> Tự động hiện tên PC trong vòng tích tắc (nhờ mDNS Rust).

Bấm vào -> Kết nối thiết lập trong 0-RTT (nhờ QUIC).

Vibe Coding:

Bạn gõ phím trên điện thoại -> Tín hiệu bay qua UDP -> PC nhận và xử lý ngay lập tức.

Mạng lag? Gói tin hiển thị có thể mất, nhưng gói tin lệnh gõ phím vẫn đi tiếp (ưu điểm của QUIC), cảm giác gõ vẫn mượt.

Các giai đoạn sau sẽ tinh chỉnh cho việc vibe coding bao gồm việc view file, giao diện hiển thị khi vibe coding, giao diện khi có tuỳ chọn, ....