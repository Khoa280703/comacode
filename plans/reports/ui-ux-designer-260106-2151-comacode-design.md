# Comacode UI/UX Design Report

**Project**: Comacode - Remote Terminal Control App
**Date**: 2026-01-06
**Designer**: UI/UX Subagent
**Status**: Complete

---

## Executive Summary

Complete design system & wireframes for Comacode - zero-latency remote terminal mobile app. Design follows **Developer Dark aesthetic** (Warp/VSCode vibes) with **mobile-first thumb-zone** principles.

**Key Decisions:**
- Color palette: Catppuccin Mocha (#1E1E2E base, #C678DD accent)
- Typography: JetBrains Mono (terminal) + System UI (controls)
- Layout: Bottom 30% screen = all interactive elements
- Motion: Subtle micro-interactions, respects `prefers-reduced-motion`

---

## 1. Design Research Findings

### Source Analysis

| Trend | Key Insight | Application |
|-------|-------------|-------------|
| **Warp Terminal** | Block-based output, customizable UI, minimal chrome | Terminal blocks for command grouping, hideable status bar |
| **Thumb Zone** | Bottom 1/3 screen = natural reach | All controls (keys bar, nav, CTAs) in bottom 30% |
| **Dark Mode 2025** | Soft grays over pure black, desaturated accents | #1E1E2E not #000000, muted purple/green accents |
| **Mobile Coding** | Need special keys row above keyboard | Modifier bar (Esc, Tab, Ctrl, Alt, arrows) |
| **VS Code Mobile** | No official app exists - opportunity gap | Focus on what's missing: good terminal input UX |

### Competitive Landscape

- **Termius**: Full-featured but complex UI
- **Blink Shell**: Powerful but dated design
- **Remotely**: Simple but limited
- **Gap**: No modern, Warp-inspired terminal app exists

**Comacode Positioning**: Modern, beautiful, zero-latency terminal for vibe coding.

---

## 2. Design Guidelines

### Color System

```css
/* Catppuccin Mocha-based palette */
--bg-base: #1E1E2E        /* Main background */
--bg-mantle: #181825      /* Elevated surfaces */
--text: #CDD6F4           /* Primary text */
--accent-purple: #C678DD  /* AI/Magic features */
--accent-green: #98C379   /* Success, Connected */
--accent-blue: #61AFEF    /* Info */
```

**Rationale**: Purple = creative/tech feel. Green = success/terminal tradition.

### Typography

| Context | Font | Size | Weight |
|---------|------|------|--------|
| Terminal output | JetBrains Mono | 13px | 400 |
| UI Headers | System UI | 17-20px | 600 |
| UI Body | System UI | 14-15px | 400 |
| Buttons | System UI | 15px | 600 |

**JetBrains Mono rationale**: Excellent ligatures, Vietnamese support, legible at small sizes.

### Spacing System

8px base grid - all spacing multiples of 8:
- `--space-2: 8px` (tight)
- `--space-4: 16px` (normal)
- `--space-6: 24px` (loose)
- `--page-padding: 16px`

### Component Specs

**Buttons**:
- Primary: 48px min height (touch target)
- Icon: 48x48px circular
- Radius: 8-10px

**Inputs**:
- Height: 52-56px
- Radius: 8px
- Focus: Purple border

**Cards**:
- Radius: 12px
- Subtle border: `rgba(255,255,255,0.05)`
- Active: Scale 0.98

### Animation

| Interaction | Duration | Easing |
|-------------|----------|--------|
| Button press | 150ms | cubic-bezier |
| Screen transition | 250ms | ease-out |
| Loading | 2s | linear (spin) |

---

## 3. Screen Designs

### 3.1 Splash Screen

**Purpose**: Brand impression, app initialization

**Elements**:
- Animated logo with glow pulse
- App name: "Comacode"
- Tagline: "Zero-latency remote terminal"
- Loading bar (gradient purple→green)
- Version tag

**Animation**:
- Logo: Fade in + scale (0.8s)
- Glow: 2s pulse infinite
- Loading: 2s progress loop

**File**: `docs/wireframes/01-splash.html`

---

### 3.2 Discovery Screen

**Purpose**: Auto-discover hosts via mDNS

**Elements**:
- Search bar (filter hosts)
- Scanning status (spinner + "Scanning local network...")
- Host cards (platform icon, hostname, IP, status dot)
- Bottom nav (Devices, Recent, Settings)

**Thumb Zone Usage**:
- Bottom nav: Always reachable
- Host cards: Tap anywhere (full-width targets)

**File**: `docs/wireframes/02-discovery.html`

---

### 3.3 Connection Screen

**Purpose**: Authenticate & connect to host

**Elements**:
- Host info card (avatar, platform, last seen)
- Status badge (green dot + "Ready to connect")
- Password input (56px height, toggle visibility)
- Options: Save password, Auto-reconnect
- Connect button (full width, purple)

**Security Considerations**:
- Password masking by default
- Secure credential storage mention
- LAN-only indicator

**File**: `docs/wireframes/03-connection.html`

---

### 3.4 Terminal Screen (Core)

**Purpose**: Main terminal interface

**Elements**:
- Header: Status dot, hostname, actions (copy, clear, disconnect)
- Terminal output: xterm.js-style rendering, syntax highlighting
- Keys bar: Esc, Tab, Ctrl, Alt, arrows (horizontal scroll)
- Keyboard toggle FAB
- Virtual keyboard (custom dev layout)

**Terminal Config** (xterm.dart):
```dart
fontSize: 13px
fontFamily: 'JetBrains Mono'
theme: Catppuccin Mocha
scrollback: 10000
cursorBlink: true
```

**Special Keys Bar**:
- Fixed above system keyboard
- Modifiers show active state (purple fill)
- Horizontal scroll for overflow

**File**: `docs/wireframes/04-terminal.html`

---

### 3.5 Settings Screen

**Purpose**: Customize terminal & connection

**Sections**:

**Terminal**:
- Font size slider (11-18px)
- Font family selector
- Color theme selector

**Connection**:
- Auto-reconnect toggle
- Keep-alive interval

**Interface**:
- Haptic feedback toggle
- Show status bar toggle

**About**:
- App card with logo
- Version, links

**File**: `docs/wireframes/05-settings.html`

---

## 4. Generated Assets

### Logo

**Location**: `docs/assets/logo.svg`

**Design**:
- Rounded square (512x512)
- Terminal window with `$ _` prompt
- Purple glow on cursor
- Dark gradient background
- Connection dots (signal remote nature)

**Usage**: App icon, splash screen, settings header

### Screenshots

All screens captured at 375x812 (iPhone 13/14 size):

| Screen | File |
|--------|------|
| Splash | `screenshots/01-splash.png` |
| Discovery | `screenshots/02-discovery.png` |
| Connection | `screenshots/03-connection.png` |
| Terminal | `screenshots/04-terminal.png` |
| Settings | `screenshots/05-settings.png` |

---

## 5. Accessibility Compliance

### WCAG 2.1 AA

| Requirement | Status | Notes |
|-------------|--------|-------|
| Color contrast (4.5:1) | Pass | All text verified |
| Touch targets (44x44px) | Pass | Buttons 48px minimum |
| Focus indicators | Pass | 2px purple outline |
| Reduced motion | Pass | `@media (prefers-reduced-motion)` |
| Screen reader | Pass | Semantic HTML, ARIA labels |

### Font Size Support

- Extra Small: 11px (320-375px)
- Small: 12px (default)
- Medium: 13px (375-428px)
- Large: 14px (428px+)
- Extra Large: 16px (accessibility)

---

## 6. Technical Implementation Notes

### Flutter Conversion

HTML wireframes use CSS that maps to Flutter:

| CSS | Flutter |
|-----|---------|
| `color: var(--bg-base)` | `Color(0xFF1E1E2E)` |
| `font-family: JetBrains Mono` | `GoogleFonts.jetbrainsMono()` |
| `border-radius: 12px` | `BorderRadius.circular(12)` |
| `ease-out` | `Curves.easeOut` |

### xterm.dart Config

See `docs/design-guidelines.md` → "Terminal Rendering Specs"

### Icon Library

**Lucide Icons** recommended:
- Flutter: `lucide_icons_flutter`
- 1000+ consistent icons
- Lightweight (tree-shakeable)

---

## 7. Next Steps

### Immediate
1. Review wireframes with stakeholder
2. Convert HTML to Flutter widgets
3. Set up xterm.dart with Catppuccin theme
4. Implement keys bar with modifier state

### Future Enhancements
1. AI command completion (Warp-style blocks)
2. Multi-terminal tabs
3. Gesture shortcuts (swipe = Ctrl+C)
4. Split view (tablet landscape)
5. Custom theme editor

---

## 8. File Structure

```
docs/
├── design-guidelines.md          # Complete design system
├── wireframes/
│   ├── 01-splash.html            # All 5 screen wireframes
│   ├── 02-discovery.html         # Interactive, annotated
│   ├── 03-connection.html
│   ├── 04-terminal.html
│   ├── 05-settings.html
│   └── screenshots/
│       ├── 01-splash.png
│       ├── 02-discovery.png
│       ├── 03-connection.png
│       ├── 04-terminal.png
│       └── 05-settings.png
└── assets/
    ├── logo.svg                  # App icon (vector)
    └── logo.error.txt            # AI gen failed (free tier)
```

---

## Unresolved Questions

1. **Password storage**: Use iOS Keychain / Android Keystore?
2. **mDNS fallback**: What if no hosts found? Manual IP entry flow?
3. **Terminal history**: Persist per-host or global?
4. **Font loading**: Bundle JetBrains Mono or download on-demand?
5. **Landscape mode**: Hide status bar? Show more terminal?

---

## Sources

- Warp Terminal Design: https://warp.dev/
- Catppuccin Theme: https://catppuccin.com/
- JetBrains Mono: https://jetbrainsmono.com/
- Thumb Zone Research: UXDesign.cc, Medium 2025
- Dark Mode Trends: Dribbble, Behance 2025 collections

---

**End of Report**
