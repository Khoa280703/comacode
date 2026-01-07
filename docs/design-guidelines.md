# Comacode Design Guidelines

> Remote Terminal Control App - UI/UX Design System
> Version: 1.0 | Last Updated: 2026-01-06

---

## Design Philosophy

**"Zero-friction Vibe Coding"**

Comacode interface follows these principles:

1. **Instant Familiarity** - Devs already know terminals, don't reinvent
2. **Thumb-First** - All critical actions in bottom 30% screen
3. **Visual Quiet** - Reduce cognitive load, maximize code visibility
4. **Subtle Feedback** - Micro-interactions, not overwhelming animations

---

## Color System

### Base Palette (Catppuccin Mocha)

```css
--bg-base: #1E1E2E;        /* Main background */
--bg-mantle: #181825;      /* Elevated surfaces */
--bg-crust: #11111B;       /* Top bars, headers */

--text: #CDD6F4;           /* Primary text */
--text-subtle: #A6ADC8;    /* Secondary text */
--text-muted: #6C7086;     /* Disabled/placeholder */

/* Accents */
--accent-purple: #C678DD;  /* AI/Magic features, CTAs */
--accent-green: #98C379;   /* Success, Run, Connected */
--accent-blue: #61AFEF;    /* Info, Links */
--accent-yellow: #E5C07B;  /* Warnings */
--accent-red: #E06C75;     /* Errors, Disconnected */
--accent-orange: #D19A66;  /* Pending states */

/* Syntax highlighting (terminal output) */
--syn-keyword: #C678DD;
--syn-string: #98C379;
--syn-number: #D19A66;
--syn-comment: #5C6370;
--syn-func: #61AFEF;
--syn-var: #E06C75;
```

### Semantic Colors

| State | Color | Usage |
|-------|-------|-------|
| **Connected** | `#98C379` | Active session, successful operation |
| **Disconnected** | `#E06C75` | Lost connection, error states |
| **Connecting** | `#D19A66` | Pending connection, loading |
| **Scanning** | `#61AFEF` | mDNS discovery in progress |

### Surface Elevation

```
Level 0 (Base):  #1E1E2E
Level 1 (Cards): #1E1E2E + 1px border rgba(255,255,255,0.05)
Level 2 (Modals): #181825 + 8px blur
Level 3 (Tooltips): #11111B + 16px blur
```

---

## Typography

### Font Families

```css
/* Terminal - Monospace */
--font-terminal: 'JetBrains Mono', 'Fira Code', 'SF Mono', monospace;

/* UI - Sans */
--font-ui: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui;
```

**JetBrains Mono** (preferred):
- Download: https://jetbrainsmono.com
- Weights: 400 (Regular), 500 (Medium)
- Supports Vietnamese diacritics

### Type Scale

```css
/* Terminal Output */
--text-xs:   11px;   /* Compact density */
--text-sm:   12px;   /* Default terminal */
--text-md:   13px;   /* Large terminal */
--text-lg:   14px;   /* Extra large */
--text-xl:   16px;   /* Accessibility */

/* UI Text */
--ui-label:     12px;  /* Labels, captions */
--ui-body:      14px;  /* Body text */
--ui-subhead:   16px;  /* Section headers */
--ui-headline:  20px;  /* Page titles */
--ui-display:   24px;  /* Splash logo */
```

### Line Heights

```css
--lh-terminal: 1.4;    /* Compact for code */
--lh-ui:       1.5;    /* Standard UI */
--lh-tight:    1.2;    /* Headers */
```

---

## Spacing System

8px base grid (all spacing multiples of 8):

```css
--space-0:  0px;
--space-1:  4px;    /* Hair */
--space-2:  8px;    /* Tight */
--space-3:  12px;   /* Compact */
--space-4:  16px;   /* Normal */
--space-5:  20px;   /* Medium */
--space-6:  24px;   /* Loose */
--space-8:  32px;   /* XL */
--space-10: 40px;   /* XXL */
--space-12: 48px;   /* Huge */
```

### Layout Constants

```css
--safe-top:     env(safe-area-inset-top, 16px);
--safe-bottom:  env(safe-area-inset-bottom, 16px);
--page-padding: var(--space-4);    /* 16px edges */
--card-radius:  12px;
--btn-radius:   8px;
--input-radius: 8px;
```

---

## Component Specifications

### Buttons

#### Primary Button

```css
.btn-primary {
  background: var(--accent-purple);
  color: #fff;
  padding: 12px 24px;
  border-radius: var(--btn-radius);
  font: 600 15px var(--font-ui);
  min-height: 48px;  /* Touch target */
  min-width: 120px;
}
.btn-primary:active {
  opacity: 0.8;
  transform: scale(0.98);
}
```

#### Secondary Button

```css
.btn-secondary {
  background: rgba(198, 120, 221, 0.15);
  color: var(--accent-purple);
  border: 1px solid rgba(198, 120, 221, 0.3);
}
```

#### Icon Button (48px min)

```css
.btn-icon {
  width: 48px;
  height: 48px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: transparent;
}
.btn-icon:active {
  background: rgba(255,255,255,0.05);
}
```

### Terminal Keys Bar

Horizontal scrollable row above keyboard:

```css
.keys-bar {
  display: flex;
  gap: 8px;
  padding: 8px 16px;
  background: var(--bg-mantle);
  overflow-x: auto;
  min-height: 48px;
}
.terminal-key {
  min-width: 48px;
  height: 36px;
  padding: 0 12px;
  background: rgba(255,255,255,0.08);
  border-radius: 6px;
  font: 500 13px var(--font-terminal);
  color: var(--text);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.terminal-key.modifier {
  background: rgba(198, 120, 221, 0.2);
  color: var(--accent-purple);
}
.terminal-key.active {
  background: var(--accent-purple);
  color: #fff;
}
```

### Connection Card (Discovery Screen)

```css
.host-card {
  background: var(--bg-base);
  border: 1px solid rgba(255,255,255,0.05);
  border-radius: var(--card-radius);
  padding: 16px;
  margin-bottom: 12px;
}
.host-card__header {
  display: flex;
  align-items: center;
  gap: 12px;
}
.host-card__icon {
  width: 40px;
  height: 40px;
  background: rgba(152, 195, 121, 0.15);
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
}
.host-card__status {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--accent-green);
  margin-left: auto;
}
.host-card__hostname {
  font: 600 15px var(--font-ui);
  color: var(--text);
}
.host-card__ip {
  font: 400 13px var(--font-ui);
  color: var(--text-subtle);
}
```

### Input Fields

```css
.input {
  background: rgba(255,255,255,0.05);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: var(--input-radius);
  padding: 14px 16px;
  font: 400 16px var(--font-ui);
  color: var(--text);
  min-height: 52px;
}
.input:focus {
  border-color: var(--accent-purple);
  outline: none;
}
.input::placeholder {
  color: var(--text-muted);
}
```

### Toast Notifications

```css
.toast {
  position: fixed;
  bottom: calc(var(--safe-bottom) + 16px);
  left: 16px;
  right: 16px;
  background: var(--bg-mantle);
  border-radius: 10px;
  padding: 14px 16px;
  display: flex;
  align-items: center;
  gap: 12px;
  box-shadow: 0 8px 32px rgba(0,0,0,0.4);
}
.toast--success { border-left: 3px solid var(--accent-green); }
.toast--error { border-left: 3px solid var(--accent-red); }
.toast--info { border-left: 3px solid var(--accent-blue); }
```

---

## Terminal Rendering Specs

### xterm.dart Configuration

```dart
// Terminal configuration for xterm.dart
final terminalConfig = TerminalConfig(
  fontSize: 13.0,
  fontFamily: 'JetBrains Mono',
  cursorBlink: true,
  cursorStyle: CursorStyle.block,
  theme: TerminalTheme(
    background: '#1E1E2E',
    foreground: '#CDD6F4',
    cursor: '#C678DD',
    selection: 'rgba(198, 120, 221, 0.3)',
    black: '#45475A',
    red: '#E06C75',
    green: '#98C379',
    yellow: '#E5C07B',
    blue: '#61AFEF',
    magenta: '#C678DD',
    cyan: '#56B6C2',
    white: '#CDD6F4',
    brightBlack: '#6C7086',
    brightRed: '#E06C75',
    brightGreen: '#98C379',
    brightYellow: '#E5C07B',
    brightBlue: '#61AFEF',
    brightMagenta: '#C678DD',
    brightCyan: '#56B6C2',
    brightWhite: '#FFFFFF',
  ),
  scrollback: 10000,
  padding: 8,
);
```

### Font Size Options

```
Extra Small: 11px  (320-375px screens)
Small:       12px  (default)
Medium:      13px  (375-428px screens)
Large:       14px  (428px+ screens)
Extra Large: 16px  (accessibility)
```

---

## Iconography

### Icon Library

Use **Lucide Icons** (lightweight, consistent):

```dart
// Flutter: lucide_icons_flutter package
// Key icons:
Icon(Laptop, size: 20)
Icon(Terminal, size: 20)
Icon(Wifi, size: 20)
Icon(WifiOff, size: 20)
Icon(Settings, size: 20)
Icon(Keyboard, size: 20)
Icon(Scan, size: 20)
Icon(ChevronRight, size: 18)
Icon(ChevronDown, size: 18)
Icon(X, size: 20)
Icon(Eye, size: 20)
Icon(Copy, size: 20)
```

### Icon Sizes

```css
--icon-xs:  16px;
--icon-sm:  18px;
--icon-md:  20px;
--icon-lg:  24px;
--icon-xl:  32px;
```

---

## Motion & Animation

### Timing Functions

```css
--ease-out: cubic-bezier(0.0, 0.0, 0.2, 1);
--ease-in-out: cubic-bezier(0.4, 0.0, 0.2, 1);
```

### Durations

```css
--duration-fast: 150ms;   /* Micro-interactions */
--duration-normal: 250ms; /* Screen transitions */
--duration-slow: 350ms;   /* Complex animations */
```

### Animations

#### Fade In

```css
@keyframes fadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}
.fade-in {
  animation: fadeIn var(--duration-normal) var(--ease-out);
}
```

#### Slide Up (Keyboard, Modals)

```css
@keyframes slideUp {
  from { transform: translateY(100%); }
  to { transform: translateY(0); }
}
.slide-up {
  animation: slideUp var(--duration-normal) var(--ease-out);
}
```

#### Pulse (Connecting State)

```css
@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}
.pulse {
  animation: pulse 1.5s ease-in-out infinite;
}
```

#### Loading Spinner

```css
@keyframes spin {
  to { transform: rotate(360deg); }
}
.spinner {
  animation: spin 1s linear infinite;
}
```

### Reduced Motion

```css
@media (prefers-reduced-motion: reduce) {
  * {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```

---

## Thumb Zone Layout

### Screen Zones (Portrait 375x812)

```
┌─────────────────────┐
│   56px              │  ← Hard Zone (status, info)
├─────────────────────┤
│                     │
│                     │
│   Terminal Output   │  ← Reachable with stretch
│   (Scrollable)      │
│                     │
│                     │
├─────────────────────┤
│   48px              │  ← Natural Zone (keys bar)
├─────────────────────┤
│   216px (keyboard)  │  ← Natural Zone (system keyboard)
└─────────────────────┘
```

### Zone-Based Element Placement

| Zone | Placement | Elements |
|------|-----------|----------|
| **Hard (top)** | Status info only | Connection status, hostname |
| **Stretch (middle)** | Scrollable content | Terminal output |
| **Natural (bottom)** | All interactive | Keys bar, nav, buttons, FABs |

---

## Accessibility

### WCAG 2.1 AA Compliance

- **Text Contrast**: Minimum 4.5:1
- **Large Text**: Minimum 3:1
- **Touch Targets**: Minimum 48x48px
- **Focus Indicators**: 2px solid outline

### Screen Reader Support

```html
<!-- Semantic markup -->
<button aria-label="Connect to server">
<nav aria-label="Main navigation">
<main aria-label="Terminal output">
```

### Color Independence

Never rely on color alone to convey information:

- Connection state: icon + color + label
- Errors: icon + color + text message
- Active states: visual + haptic feedback

---

## Screen Layouts

### Common Header

```css
.header {
  height: calc(56px + var(--safe-top));
  padding-top: var(--safe-top);
  padding-left: 16px;
  padding-right: 16px;
  display: flex;
  align-items: center;
  gap: 12px;
  background: var(--bg-mantle);
  border-bottom: 1px solid rgba(255,255,255,0.05);
}
.header__title {
  font: 600 17px var(--font-ui);
  color: var(--text);
  flex: 1;
}
```

### Bottom Navigation (Discovery Screen)

```css
.bottom-nav {
  height: calc(56px + var(--safe-bottom));
  padding-bottom: var(--safe-bottom);
  background: var(--bg-mantle);
  border-top: 1px solid rgba(255,255,255,0.05);
  display: flex;
  align-items: center;
  justify-content: space-around;
}
.nav-item {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  padding: 8px 0;
  color: var(--text-muted);
}
.nav-item--active {
  color: var(--accent-purple);
}
.nav-item__icon {
  width: 24px;
  height: 24px;
}
.nav-item__label {
  font: 500 11px var(--font-ui);
}
```

---

## Responsive Breakpoints

```css
/* Small phones */
@media (max-width: 374px) {
  --text-md: 12px;
  --page-padding: 12px;
}

/* Standard phones */
@media (min-width: 375px) {
  --text-md: 13px;
  --page-padding: 16px;
}

/* Large phones / minis */
@media (min-width: 414px) {
  --text-md: 14px;
  --page-padding: 20px;
}

/* Tablets (landscape) */
@media (min-width: 768px) {
  /* Optional: split-view terminal */
}
```

---

## Gesture Guidelines

| Gesture | Action | Haptic |
|---------|--------|--------|
| **Tap** | Activate element | Light (if success) |
| **Long press** | Context menu, select text | Medium |
| **Swipe left** | Back, close terminal | None |
| **Swipe right** | Open drawer, next tab | None |
| **Pinch** | Adjust terminal font size | Light on change |
| **Pull down** | Refresh host list | Medium when complete |

---

## States & Feedback

### Connection States

| State | Visual | Haptic |
|-------|--------|--------|
| **Scanning** | Pulse animation + "Searching..." | None |
| **Found** | Card appears with slide-up | Light |
| **Connecting** | Spinner + "Connecting..." | None |
| **Connected** | Green dot + checkmark | Success |
| **Failed** | Red dot + error message | Error |

### Terminal Input Feedback

- **Key press**: Visual highlight + light haptic
- **Command sent**: Brief flash
- **Output received**: Smooth scroll to bottom

---

## File Structure

```
docs/
├── design-guidelines.md          # This file
├── wireframes/
│   ├── 01-splash.html
│   ├── 02-discovery.html
│   ├── 03-connection.html
│   ├── 04-terminal.html
│   └── 05-settings.html
├── assets/
│   ├── logo.png
│   └── screenshots/
│       ├── splash.png
│       ├── discovery.png
│       ├── connection.png
│       ├── terminal.png
│       └── settings.png
```

---

## References

- **Catppuccin Theme**: https://catppuccin.com/
- **JetBrains Mono**: https://jetbrainsmono.com/
- **Lucide Icons**: https://lucide.dev/
- **xterm.dart**: https://pub.dev/packages/xterm_flutter
- **Warp Terminal**: https://warp.dev/
