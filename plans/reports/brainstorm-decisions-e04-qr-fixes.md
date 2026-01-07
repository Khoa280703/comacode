# Brainstorm Decisions: Phase E04 QR & TOFU Fixes

**Date**: 2026-01-07
**Topic**: Phase E04 Certificate Persistence + TOFU Plan Updates
**Status**: Applied

---

## Summary

Based on user feedback, applied 3 critical fixes to `phase-04-cert-persistence.md`:

1. **QR Code Rendering**: SVG → Unicode Dense1x2
2. **Local IP Detection**: Added Docker/loopback filter
3. **TOFU Persistence**: Documented Flutter delegation

---

## Fix 1: QR Code Rendering (Security Critical)

### Problem
Plan used `qrcode::render::svg::Color()` which outputs XML - cannot be scanned from terminal.

### Solution
Use `unicode::Dense1x2` renderer for terminal display:

```rust
pub fn to_qr_terminal(&self) -> Result<String, CoreError> {
    use qrcode::render::unicode;

    let qr_code = qrcode::QrCode::new(json)?;
    let image = qr_code.render::<unicode::Dense1x2>()
        .dark_color(unicode::Dense1x2::Light)
        .light_color(unicode::Dense1x2::Dark)
        .build();
    Ok(image)
}
```

**File**: `phase-04-cert-persistence.md` lines 190-210

---

## Fix 2: Local IP Detection (Network Discovery)

### Problem
First non-loopback interface often returns Docker bridge (172.17.0.1) - not reachable from mobile.

### Solution
Filter function with fallback:

```rust
fn is_docker_or_loopback(ip: Ipv4Addr) -> bool {
    let octets = ip.octets();
    octets[0] == 172 && octets[1] == 17  // Docker bridge
        || octets[0] == 127                // Loopback
}
```

**Added**: `get_local_ip()` with UDP socket trick + filter
**File**: `phase-04-cert-persistence.md` lines 274-308

**Trade-off**: Falls back to 192.168.1.1 if Docker detected.
**Future**: Add `--ip` CLI flag for manual override.

---

## Fix 3: TOFU Persistence (Architecture)

### Problem
TofuStore only in-memory → mobile app restart loses all trusted hosts.

### Solution
Document delegation to Flutter layer:

```rust
/// **IMPORTANT**: This is IN-MEMORY only for MVP.
/// Persistence delegated to Flutter layer (Phase E05) via FFI.
pub async fn load_from_flutter(&self, hosts: Vec<(String, String)>) {
    // Flutter loads from SharedPreferences and sends via FFI
}
```

**File**: `phase-04-cert-persistence.md` lines 320-402

**Rationale**: Rust FFI cannot directly access mobile file system.
Flutter has `SharedPreferences` with proper permissions.

---

## Dependencies Updated

**Removed**: `base64 = "0.21"` (not needed for Unicode renderer)
**Added**: `sha2 = "0.10"` (explicit for fingerprint)

---

## Unresolved Questions Updated

| Before | After |
|--------|-------|
| SVG vs PNG vs ASCII? | ~~RESOLVED~~: Unicode Dense1x2 |
| (none) | IP detection fallback? → Add --ip flag |

---

## Files Modified

1. `plans/260107-0858-brainstorm-implementation/phase-04-cert-persistence.md`
   - Section 4.1: Dependencies (sha2 added, base64 removed)
   - Section 4.4: `to_qr_terminal()` with Unicode renderer
   - Section 4.5: `get_local_ip()` with Docker filter
   - Section 4.6: TOFU persistence documentation
   - Unresolved Questions: Updated

---

## Next Steps

Plan E04 is ready for implementation.

**Pre-requisites met**:
- Phase E03 (Auth tokens) ✅
- QR rendering approach decided ✅
- IP detection strategy decided ✅
- TOFU architecture clarified ✅

**Risk Level**: LOW
- All technical decisions validated
- No new dependencies with compatibility issues
- Fallback strategies documented

---

*Report generated: 2026-01-07*
*Brainstorm session: Phase E04 plan fixes*
