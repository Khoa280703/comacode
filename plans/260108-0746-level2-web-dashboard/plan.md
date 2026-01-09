---
title: "Level 2: Localhost Web Dashboard"
description: "Implement user-friendly web UI for QR pairing with browser auto-open"
status: pending
priority: P1
effort: 8h
branch: main
tags: [web-ui, ux-improvement, cross-platform]
created: 2026-01-08
---

# Level 2: Localhost Web Dashboard

> **Phase**: UX Enhancement (Post-MVP)
> **Goal**: Replace terminal QR display with beautiful web dashboard
> **Impact**: Non-tech users can now use Comacode without terminal knowledge

---

## Problem Statement

**Current Flow** (Level 1 - Terminal):
- User runs `comacode-server` in terminal
- QR code displayed in terminal (ASCII art)
- User must keep terminal window open
- Not user-friendly for non-technical users

**Pain Points**:
- ASCII QR is hard to scan on some terminals
- Requires keeping terminal window visible
- No connection status feedback
- Intimidating for non-technical users
- No way to retry if connection fails

---

## Solution Overview

**Level 2 Flow** (Web Dashboard):
1. User double-clicks `comacode-server` binary
2. Browser auto-opens to `http://127.0.0.1:3721`
3. Beautiful QR code pairing page (Catppuccin Mocha theme)
4. Real-time connection status updates
5. Mobile app scans QR → connects
6. Connection status updates live in browser

**Benefits**:
- One-click user experience (double-click binary)
- High-quality QR (SVG, scalable)
- Real-time status feedback
- Beautiful, professional UI
- Cross-platform (macOS, Windows, Linux)

---

## Technical Architecture

### Technology Stack

```toml
[dependencies]
# Web server
axum = "0.7"
tokio = { workspace = true }
tower = "0.5"
tower-http = { version = "0.5", features = ["cors", "trace"] }

# QR generation
qrcode-generator = "4.1"

# Browser automation
open = "5.0"

# Async runtime
tokio = { workspace = true, features = ["full"] }
```

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     User Double-Clicks                       │
│                         Binary                                │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  1. Axum Web Server Starts (127.0.0.1:3721)                 │
│  2. Browser Auto-Opens                                      │
│  3. QUIC Server Continues Running (0.0.0.0:8443)            │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      Web Browser                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Pairing Page (Catppuccin Mocha Theme)               │  │
│  │  - SVG QR Code (large, clear)                        │  │
│  │  - Connection Status: Waiting...                     │  │
│  │  - Fingerprint: AA:BB:CC... (click to copy)         │  │
│  │  - Port: 8443                                        │  │
│  │  - Auth Token: DEADBEEF...                           │  │
│  └──────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                   Mobile App Scans QR                        │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              SSE Real-time Status Update                     │
│  Connection Status: Connected ✓                             │
│  Client: 192.168.1.100:54321                                │
│  Session ID: 42                                              │
└─────────────────────────────────────────────────────────────┘
```

### Module Structure

```
crates/hostagent/src/
├── main.rs           # Modified: Launch web server + browser
├── quic_server.rs    # Unchanged
├── web_ui.rs         # NEW: Web UI server
│   ├── WebServer         # Axum server struct
│   ├── QrGenerator       # QR code SVG generation
│   ├── HtmlTemplate      # HTML/CSS rendering
│   └── StatusBroadcaster # SSE status updates
└── ... (other modules unchanged)
```

---

## Implementation Plan

### Phase 1: Foundation (2h)

**Task 1.1: Add Dependencies**
- [ ] Update `crates/hostagent/Cargo.toml`
- [ ] Add `axum`, `tower`, `tower-http`
- [ ] Add `qrcode-generator`, `open`
- [ ] Verify workspace compatibility

**Task 1.2: Create Web UI Module**
- [ ] Create `crates/hostagent/src/web_ui.rs`
- [ ] Implement `QrGenerator` struct (SVG format)
- [ ] Implement `HtmlTemplate` (inline HTML/CSS)
- [ ] Implement `WebServer` struct (Axum routes)

**Success Criteria**:
- Module compiles without errors
- QR generator produces valid SVG
- HTML template renders with Catppuccin Mocha theme

---

### Phase 2: Web Server Implementation (2h)

**Task 2.1: Implement Routes**
```rust
// GET / - Main pairing page
async fn pairing_page() -> Html<String>

// GET /api/status - Connection status (SSE)
async fn status_stream() -> Sse<...>

// GET /api/qr - QR code SVG
async fn qr_code() -> Svg<String>
```

**Task 2.2: Implement QR Generation**
```rust
impl QrGenerator {
    fn generate_svg(&self, payload: &QrPayload) -> String {
        // Use qrcode-generator crate
        // Return SVG string with styling
    }
}
```

**Task 2.3: Implement HTML Template**
```rust
impl HtmlTemplate {
    fn render(&self, qr_svg: &str, status: &ConnectionStatus) -> String {
        // Inline HTML + CSS
        // Catppuccin Mocha colors
        // Responsive layout
        // SSE JavaScript for status updates
    }
}
```

**Success Criteria**:
- Server starts on `127.0.0.1:3721`
- `/` route renders HTML page
- `/api/qr` returns SVG QR code
- SSE endpoint connects successfully

---

### Phase 3: Browser Auto-Open (1h)

**Task 3.1: Implement Browser Launch**
```rust
// In main.rs
#[cfg(target_os = "macos")]
fn open_browser(url: &str) -> Result<()> {
    open::that(url)?;
    Ok(())
}

#[cfg(target_os = "windows")]
fn open_browser(url: &str) -> Result<()> {
    open::that(url)?;
    Ok(())
}

#[cfg(target_os = "linux")]
fn open_browser(url: &str) -> Result<()> {
    open::that(url)?;
    Ok(())
}
```

**Task 3.2: Integration with main.rs**
```rust
// After web server starts
tokio::spawn(async move {
    // Wait 100ms for server to bind
    tokio::time::sleep(Duration::from_millis(100)).await;
    open_browser("http://127.0.0.1:3721")?;
});
```

**Success Criteria**:
- Browser opens automatically on macOS
- Browser opens automatically on Windows
- Browser opens automatically on Linux
- Opens to correct URL with QR displayed

---

### Phase 4: Real-time Status Updates (2h)

**Task 4.1: Implement SSE Broadcasting**
```rust
// In quic_server.rs, modify connection handler
async fn handle_connection(...) -> Result<()> {
    // Broadcast connection event
    status_broadcaster.broadcast(ConnectionEvent::Connected {
        peer_addr: remote_addr,
        session_id: id,
    }).await;
}

// In web_ui.rs
struct StatusBroadcaster {
    clients: Arc<Mutex<Vec<SseSender>>>,
}

impl StatusBroadcaster {
    async fn broadcast(&self, event: ConnectionEvent) {
        // Send to all connected SSE clients
    }
}
```

**Task 4.2: Frontend SSE Client**
```javascript
// In HTML template
const eventSource = new EventSource('/api/status');
eventSource.onmessage = (event) => {
    const status = JSON.parse(event.data);
    updateStatus(status);
};
```

**Task 4.3: Status Display States**
```rust
enum ConnectionStatus {
    Waiting,        // "Waiting for connection..."
    Connected,      // "Connected to 192.168.1.100"
    Disconnected,   // "Client disconnected"
}
```

**Success Criteria**:
- SSE connection established on page load
- Status updates when client connects
- Status updates when client disconnects
- Status displays peer address and session ID

---

### Phase 5: Polish & Error Handling (1h)

**Task 5.1: Port Conflict Handling**
```rust
// Try port 3721, fallback to 3722, 3723, etc.
fn bind_web_server() -> Result<SocketAddr> {
    for port in 3721..=3730 {
        match try_bind(port) {
            Ok(addr) => return Ok(addr),
            Err(_) => continue,
        }
    }
    Err("No available ports".into())
}
```

**Task 5.2: Browser Close Handling**
- Server continues running if browser closes
- Re-opening browser reconnects SSE
- Display "Re-open browser to view status" in terminal

**Task 5.3: Error Display in UI**
- Network errors: "Network unavailable"
- QR errors: "Failed to generate QR code"
- Connection errors: "Connection failed - retry"

**Success Criteria**:
- Port conflicts handled gracefully
- Browser close doesn't crash server
- Error messages displayed in UI (not console)

---

## HTML Template Specification

### Design System: Catppuccin Mocha

```css
:root {
  --ctp-base: #1E1E2E;
  --ctp-surface: #313244;
  --ctp-primary: #CBA6F7;
  --ctp-text: #CDD6F4;
  --ctp-green: #A6E3A1;
  --ctp-red: #F38BA8;
  --ctp-yellow: #F9E2AF;
  --ctp-blue: #89B4FA;
  --ctp-mauve: #CBA6F7;
}

body {
  background-color: var(--ctp-base);
  color: var(--ctp-text);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
}
```

### Layout Structure

```
┌─────────────────────────────────────────┐
│  Header: Comacode Pairing               │
├─────────────────────────────────────────┤
│  ┌───────────────────────────────────┐  │
│  │         [ QR Code SVG ]           │  │
│  │         (400x400px)               │  │
│  └───────────────────────────────────┘  │
│  Scan with mobile app                   │
├─────────────────────────────────────────┤
│  Status: Waiting for connection...      │
│  Fingerprint: AA:BB:CC... [Copy]        │
│  Port: 8443                             │
│  Auth Token: DEADBEEF...                │
└─────────────────────────────────────────┘
```

### Responsive Design

- Mobile: Single column, QR 300x300px
- Desktop: Centered card, QR 400x400px
- Tablet: Adjusted spacing

---

## API Specification

### GET `/`

Returns HTML pairing page

**Response**: `text/html`

### GET `/api/qr`

Returns QR code SVG

**Response**: `image/svg+xml`

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400">
  <!-- QR code modules -->
</svg>
```

### GET `/api/status`

Server-Sent Events stream for connection status

**Response**: `text/event-stream`

```
data: {"status":"waiting"}

data: {"status":"connected","peer":"192.168.1.100:54321","session_id":42}

data: {"status":"disconnected"}
```

---

## Testing Strategy

### Unit Tests

```rust
#[cfg(test)]
mod tests {
    #[test]
    fn test_qr_generator_svg() {
        let qr = QrGenerator::new();
        let svg = qr.generate_svg(&payload);
        assert!(svg.contains("<svg"));
        assert!(svg.contains("</svg>"));
    }

    #[test]
    fn test_html_template_render() {
        let template = HtmlTemplate::new();
        let html = template.render(&qr_svg, &ConnectionStatus::Waiting);
        assert!(html.contains("Comacode"));
        assert!(html.contains("--ctp-base"));
    }
}
```

### Integration Tests

1. **Manual Test - macOS**:
   - Build binary: `cargo build --release --bin hostagent`
   - Double-click `target/release/hostagent`
   - Verify browser opens to `http://127.0.0.1:3721`
   - Verify QR displays correctly
   - Scan QR with mobile app
   - Verify status updates to "Connected"

2. **Manual Test - Windows**:
   - Copy binary to Windows machine
   - Double-click `hostagent.exe`
   - Verify browser opens
   - Verify QR displays correctly

3. **Manual Test - Linux**:
   - Run `./hostagent`
   - Verify browser opens
   - Verify QR displays correctly

### Browser Compatibility

- [ ] Chrome/Edge (Chromium)
- [ ] Firefox
- [ ] Safari (macOS/iOS)

---

## Rollout Plan

### Version Strategy

**v0.2.0** (This release):
- Level 2: Web Dashboard enabled by default
- Backward compatibility: `--qr-terminal` flag for terminal QR
- Migration guide for existing users

**v0.1.x** (Current):
- Terminal QR only (current state)
- Remains stable branch

### Flags

```bash
# Level 2: Web dashboard (default)
comacode-server

# Level 1: Terminal QR (legacy)
comacode-server --qr-terminal

# Disable browser auto-open
comacode-server --no-browser
```

### Documentation Updates

1. **README.md**:
   - Update "Quick Start" section
   - Add screenshots of web dashboard
   - Update "What It Does" section

2. **docs/project-roadmap.md**:
   - Mark "Level 2: Web Dashboard" as complete
   - Update current phase

3. **docs/code-standards.md**:
   - Add web UI patterns (if new patterns emerge)

---

## Risk Mitigation

### Risk 0: Security - Localhost Only (CRITICAL)

**Risk**: Binding to 0.0.0.0 exposes dashboard to LAN → Auth token theft

**Mitigation**:
```rust
// SECURITY: MUST bind loopback only
const WEB_BIND_ADDR: &str = "127.0.0.1:3721";

let addr: SocketAddr = WEB_BIND_ADDR.parse()
    .expect("Invalid bind address");

// Runtime assertion (defense in depth)
assert!(addr.ip().is_loopback(),
    "SECURITY: Web UI MUST bind to loopback only!");
```

**Testing**:
- [ ] Verify `netstat -an | grep 3721` shows `127.0.0.1` only (NOT `0.0.0.0` or `192.168.x.x`)
- [ ] Try accessing from another device on LAN → should FAIL

---

### Risk 1: Browser Fails to Open

**Mitigation**:
- Fallback: Display terminal QR if browser fails
- Log error: "Failed to open browser - open http://127.0.0.1:3721 manually"
- Return code: Continue running server even if browser fails

### Risk 2: Port Already in Use

**Mitigation**:
- Auto-increment port: Try 3721, 3722, 3723...
- Log actual port: "Web server running on http://127.0.0.1:3722"
- Terminal QR fallback if all ports fail

### Risk 3: SSE Not Supported

**Mitigation**:
- Fallback: Polling endpoint `/api/status?poll=true`
- Browser detection: Use SSE if supported, polling if not
- Graceful degradation: Static status if both fail

### Risk 4: Binary Size Increase

**Mitigation**:
- Profile before/after: `cargo bloat --release --bin hostagent`
- Target: Keep binary < 3MB (current ~2MB)
- Use `lto = true` in Cargo.toml
- Strip symbols in release build

---

## Success Criteria

### Functional Requirements

- [ ] Double-click binary → Browser opens automatically
- [ ] QR code displays clearly in browser (SVG, 400x400px)
- [ ] Mobile app can scan and connect
- [ ] Connection status updates in real-time (SSE)
- [ ] Binary size < 3MB
- [ ] Cross-platform compatibility (macOS, Windows, Linux)

### Non-Functional Requirements

- [ ] Page load time < 100ms (localhost)
- [ ] SSE latency < 50ms
- [ ] Browser compatibility: Chrome, Firefox, Safari
- [ ] Error handling: Port conflicts, browser failures
- [ ] Accessibility: ARIA labels, keyboard navigation
- [ ] Code follows project standards (see `docs/code-standards.md`)

### User Experience

- [ ] One-click launch (double-click binary)
- [ ] Beautiful, professional UI (Catppuccin Mocha)
- [ ] Clear status feedback
- [ ] Mobile-responsive design
- [ ] Helpful error messages

---

## Open Questions

### Q1: Should we add WebSocket instead of SSE?

**Options**:
- **SSE (Server-Sent Events)**: Simpler, unidirectional (server → client)
- **WebSocket**: Bidirectional, more complex

**Recommendation**:
- Use SSE for this phase (simpler, fits use case)
- Consider WebSocket in Phase 3 if bidirectional comms needed

### Q2: How to handle browser close (keep server running)?

**Options**:
- **Keep running**: Server continues, browser close doesn't affect
- **Shutdown on close**: Server exits when browser closes

**Recommendation**:
- Keep server running (allows re-opening browser)
- Display message in terminal: "Press Ctrl+C to exit"

### Q3: Should we add "minimize to tray" option?

**Options**:
- **Yes**: Native tray icon on macOS/Windows
- **No**: Keep terminal window visible

**Recommendation**:
- Defer to Phase 3 (Level 3: System Tray Integration)
- Focus on web dashboard for now

### Q4: Port conflict handling strategy?

**Options**:
- **Auto-increment**: Try 3721, 3722, 3723...
- **User prompt**: Ask user to choose port
- **Fail fast**: Exit with error

**Recommendation**:
- Auto-increment with logging
- Terminal QR fallback if all ports fail

---

## Future Enhancements (Out of Scope)

### Level 3: System Tray Integration
- Native tray icon on macOS/Windows/Linux
- Right-click menu: "Show QR", "Exit", "Settings"
- Background service mode

### Level 4: Configuration UI
- Web-based settings page
- Port configuration
- Theme selection
- QR code customization

### Level 5: Advanced Features
- Multiple concurrent sessions
- Session management UI
- Connection history
- Analytics dashboard

---

## References

- [Axum Documentation](https://docs.rs/axum/)
- [qrcode-generator Crate](https://docs.rs/qrcode-generator/)
- [open Crate](https://docs.rs/open/)
- [Catppuccin Color Palette](https://catppuccin.com/)
- [MDN: Server-Sent Events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events)

---

## Appendix: Code Snippets

### A. QR Generation (SVG - Responsive)

```rust
use qrcode_generator::QrCodeEcc;

pub fn generate_qr_svg(payload: &str) -> String {
    let qr = QrCodeEcc::Medium
        .encode(payload.as_bytes())
        .to_svg()
        .build();

    // Use viewBox for responsive scaling, not fixed width/height
    format!(
        r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" style="width: 100%; height: auto;">
            {}
        </svg>"#,
        qr
    )
}

// CSS in HTML template handles max-width:
// .qr-container { max-width: 400px; width: 100%; }
```

**Why viewBox instead of fixed size:**
- Scales on mobile screens without overflow
- Maintains aspect ratio automatically
- Responsive by design (no JS needed)

### B. SSE Implementation

```rust
use axum::{
    response::{sse::{Event, Sse},
    Json,
};
use std::convert::Infallible;
use std::time::Duration;

pub async fn status_stream() -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let stream = async_stream::stream! {
        loop {
            let status = get_connection_status().await;
            let event = Event::default()
                .json_data(&status)
                .unwrap();
            yield Ok(event);
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
    };

    Sse::new(stream).keep_alive(
        axum::response::sse::KeepAlive::new()
            .interval(Duration::from_secs(30))
            .text("keepalive"),
    )
}
```

### C. HTML Template (Inline + SSE Reconnection)

```rust
pub fn render_html(qr_svg: &str, status: &ConnectionStatus) -> String {
    format!(
        r#"<!DOCTYPE html>
        <html>
        <head>
            <title>Comacode Pairing</title>
            <style>
                :root {{
                    --ctp-base: #1E1E2E;
                    --ctp-surface: #313244;
                    --ctp-primary: #CBA6F7;
                    --ctp-text: #CDD6F4;
                    --ctp-green: #A6E3A1;
                    --ctp-red: #F38BA8;
                    --ctp-yellow: #F9E2AF;
                }}
                body {{
                    background-color: var(--ctp-base);
                    color: var(--ctp-text);
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    min-height: 100vh;
                    margin: 0;
                }}
                .container {{
                    background-color: var(--ctp-surface);
                    padding: 2rem;
                    border-radius: 12px;
                    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3);
                    text-align: center;
                    max-width: 500px;
                    width: 90%;
                }}
                h1 {{
                    color: var(--ctp-primary);
                    margin-bottom: 1.5rem;
                }}
                .qr-container {{
                    background-color: white;
                    padding: 1rem;
                    border-radius: 8px;
                    display: block;
                    margin-bottom: 1.5rem;
                    width: 100%;
                    max-width: 400px;
                }}
                .status {{
                    font-size: 1.1rem;
                    margin-bottom: 1rem;
                }}
                .status.connected {{ color: var(--ctp-green); }}
                .status.waiting {{ color: var(--ctp-yellow); }}
                .status.error {{ color: var(--ctp-red); }}
                .status.reconnect {{
                    animation: pulse 1.5s infinite;
                }}
                @keyframes pulse {{
                    0%, 100% {{ opacity: 1; }}
                    50% {{ opacity: 0.5; }}
                }}
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Comacode Pairing</h1>
                <div class="qr-container">{}</div>
                <div id="status" class="status {}">{}</div>
            </div>
            <script>
                const MAX_RECONNECT_DELAY = 10000; // 10 seconds
                let reconnectAttempts = 0;
                let evtSource = null;

                function connectSSE() {{
                    evtSource = new EventSource('/api/status');

                    evtSource.onopen = () => {{
                        reconnectAttempts = 0;
                        const statusEl = document.getElementById('status');
                        statusEl.classList.remove('error', 'reconnect');
                    }};

                    evtSource.onmessage = (event) => {{
                        const status = JSON.parse(event.data);
                        const statusEl = document.getElementById('status');
                        statusEl.textContent = status.message;
                        statusEl.className = 'status ' + status.status;
                    }};

                    evtSource.onerror = () => {{
                        reconnectAttempts++;
                        const statusEl = document.getElementById('status');

                        // If disconnected too long, show reconnect animation
                        if (reconnectAttempts > 3) {{
                            statusEl.textContent = 'Connection lost. Reconnecting...';
                            statusEl.classList.add('error', 'reconnect');
                        }}

                        // If server restarts (port changes), reload page after 10s
                        setTimeout(() => {{
                            if (reconnectAttempts > 5) {{
                                location.reload();
                            }}
                        }}, MAX_RECONNECT_DELAY);
                    }};
                }}

                connectSSE();
            </script>
        </body>
        </html>"#,
        qr_svg,
        status.class(),
        status.message()
    )
}
```

**SSE Reconnection Logic:**
- Auto-reconnect (built into EventSource)
- Counter for reconnect attempts
- Show "Connection lost..." after 3 failures
- Auto-reload page after 10s if server restarts (port change)

---

**Last Updated**: 2026-01-08 (Updated with security + responsive QR + SSE reconnection feedback)
**Maintainer**: Comacode Development Team
**Review Date**: Phase Completion

---

## Changelog (Plan Updates)

### 2026-01-08 - User Feedback Incorporated
1. **Security**: Added Risk 0 with 127.0.0.1 runtime assertion
2. **Responsive QR**: Changed from fixed 400px to viewBox-based scaling
3. **SSE Reconnection**: Added auto-reload logic for server restart scenarios

---

## Checklist

### Pre-Implementation
- [ ] Read `docs/code-standards.md`
- [ ] Read `docs/system-architecture.md`
- [ ] Review existing `quic_server.rs` architecture
- [ ] Set up development environment

### Implementation
- [ ] Phase 1: Foundation (2h)
- [ ] Phase 2: Web Server (2h)
- [ ] Phase 3: Browser Auto-Open (1h)
- [ ] Phase 4: Real-time Status (2h)
- [ ] Phase 5: Polish (1h)

### Testing
- [ ] Unit tests pass
- [ ] Manual test on macOS
- [ ] Manual test on Windows (if possible)
- [ ] Manual test on Linux (if possible)
- [ ] Browser compatibility verified

### Documentation
- [ ] Update `README.md`
- [ ] Update `docs/project-roadmap.md`
- [ ] Add screenshots to `docs/`
- [ ] Update `CHANGELOG.md`

### Release
- [ ] Tag version `v0.2.0`
- [ ] Create GitHub release
- [ ] Upload binaries for macOS/Windows/Linux
- [ ] Announce in project README
