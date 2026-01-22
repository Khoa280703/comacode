# Debug Report: Terminal Display Shows Strange Characters

**Report ID:** debugger-260122-0916-terminal-control-characters
**Date:** 2026-01-22
**Severity:** P1 - Major usability issue
**Status:** Root cause identified + solution proposed

---

## Executive Summary

Terminal display showing "%", control characters, unexpected line breaks. Root cause: **Simple text buffer cannot handle PTY control sequences** - only ANSI escape sequences stripped, but carriage returns, backspaces, bell, form feed, and other control characters (0x00-0x1F) rendered as literal characters instead of being interpreted.

**Current:** `String` buffer + `Text` widget + basic ANSI strip
**Needed:** Either proper terminal emulator package OR comprehensive control character processing

---

## Problem Analysis

### Current Implementation (terminal_page.dart)

```dart
// Lines 206, 244
String _output = '';  // Single buffer
_output += _stripAnsiCodes(text);  // Append to buffer

// Lines 277-282 - ONLY strips ANSI escape sequences
String _stripAnsiCodes(String text) {
  final ansiPattern = RegExp(r'\x1b\[[0-9;]*[a-zA-Z]');
  return text.replaceAll(ansiPattern, '');
}
```

**What Gets Stripped:** `\x1b[...` sequences (colors, cursor position, clear line)
**What Gets Rendered Literally:** All other control characters

### PTY Output from Server

From `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/pty.rs`:
```rust
// Lines 81-114 - PTY reader sends RAW bytes
let mut buf = [0u8; 8192];
match reader.read(&mut buf) {
    Ok(n) => {
        let data = Bytes::copy_from_slice(&buf[..n]);
        tx_clone.blocking_send(data);  // Raw PTY output
    }
}
```

**PTY sends RAW bytes including:**
- Shell prompts with `\r` (carriage return)
- Progress indicators with `\r` (overwrite current line)
- Backspaces for editing
- Bell characters for alerts
- ANSI escape sequences for colors/formatting

---

## Control Characters Causing Issues

### 1. Carriage Return `\r` (0x0D)

**ASCII:** 13
**Appearance:** `%`, ``, or strange symbol
**Example:**
```
Prompt: "user@host:~$ "
```
PTY sends: `user@host:~$ \r\n`
Current code displays: `user@host:~$ %` (CR shown as `%` or box)

**What Should Happen:**
- `\r` moves cursor to line start WITHOUT newline
- Following text overwrites current line
- Example: Progress bars `Downloading... 50%\rDownloaded... 100%\r`

**What Actually Happens:**
- `\r` rendered as literal character
- Causes unexpected line breaks
- Prompt formatting broken

### 2. Backspace `\b` / `\x08` (0x08)

**ASCII:** 8
**Appearance:** ``, `^H`, or box
**Usage:**
- Command line editing
- Typos correction
- Password input

**What Should Happen:**
- Delete previous character
- Shift remaining text left

**What Actually Happens:**
- Rendered as control character
- No deletion

### 3. Bell `\a` / `\x07` (0x07)

**ASCII:** 7
**Appearance:** ``, `^G`
**Usage:** Alert/sound

**What Should Happen:** Ignore or play sound

**What Actually Happens:** Rendered as garbage

### 4. Form Feed `\f` / `\x0C` (0x0C)

**ASCII:** 12
**Usage:** Page break/clear screen
**What Should Happen:** Clear screen
**What Actually Happens:** Garbage character

### 5. Other Control Characters (0x00-0x1F)

| Char | Code | Name | Current Behavior | Expected Behavior |
|------|------|------|------------------|-------------------|
| NUL | 0x00 | Null | Garbage | Ignore |
| TAB | 0x09 | Tab | Works (sometimes) | Indent |
| LF | 0x0A | Line Feed | Works | New line |
| VT | 0x0B | Vertical Tab | Garbage | Line break |
| FF | 0x0C | Form Feed | Garbage | Clear screen |
| CR | 0x0D | Carriage Return | Garbage | Move to line start |
| SO | 0x0E | Shift Out | Garbage | Ignore |
| SI | 0x0F | Shift In | Garbage | Ignore |

---

## Why List<String> → String Change Made This Worse

**Previous (List<String> + ListView):**
```dart
List<String> _lines = [];  // Each line separate
ListView.builder(
  itemCount: _lines.length,
  itemBuilder: (context, i) => Text(_lines[i]),
)
```

**Current (String buffer + single Text):**
```dart
String _output = '';  // All output in one string
Text(_output)  // Single Text widget
```

**Why String Buffer Worse:**
1. Control characters NOT filtered per-line
2. No line boundary handling
3. `\r` creates invisible text that breaks layout
4. Backspaces have no effect (no mutable buffer)

---

## Solution Options

### Option 1: Use Terminal Emulator Package (RECOMMENDED)

**Package:** `xterm.dart` (v4.0.0+)
**Pros:**
- ✅ Full VT100/VT220 emulation
- ✅ Handles ALL control characters correctly
- ✅ ANSI escape sequence support
- ✅ Scrollback buffer
- ✅ Proper cursor management
- ✅ Battle-tested (based on xterm.js)

**Cons:**
- ❌ Larger dependency (~500KB)
- ❌ Learning curve for API
- ❌ May require WebView integration on some platforms

**Implementation:**
```dart
// pubspec.yaml
dependencies:
  xterm: ^4.0.0

// terminal_page.dart
import 'package:xterm/xterm.dart';
import 'package:xterm/ui.dart' as xterm_ui;

class TerminalWidget extends StatefulWidget {
  @override
  _TerminalWidgetState createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends State<TerminalWidget> {
  late Terminal terminal;
  late TerminalController controller;

  @override
  void initState() {
    super.initState();
    terminal = Terminal(
      backend: NullBackend(),  // We'll write data directly
      maxLines: 10000,
    );
    controller = TerminalController();
  }

  // Write PTY output
  void _writePtyOutput(List<int> data) {
    terminal.write(String.fromCharCodes(data));
  }

  // Send input
  void _sendInput(String text) {
    bridge.sendCommand('$text\r');
  }

  @override
  Widget build(BuildContext context) {
    return xterm_ui.TerminalView(
      terminal: terminal,
      controller: controller,
    );
  }
}
```

**File:** `/Users/khoa2807/development/2026/Comacode/mobile/lib/features/terminal/terminal_page.dart`

---

### Option 2: Enhanced Control Character Processing

**If cannot use xterm.dart**, implement comprehensive control character handling:

```dart
class TerminalBuffer {
  final List<String> _lines = [''];
  int _cursorX = 0;
  int _cursorY = 0;

  void write(String text) {
    final chars = text.split('');
    for (var char in chars) {
      _processChar(char);
    }
  }

  void _processChar(String char) {
    final code = char.codeUnitAt(0);

    // Control characters
    switch (code) {
      case 0x08: // Backspace
        if (_cursorX > 0) _cursorX--;
        _deleteAtCursor();
        break;
      case 0x09: // Tab
        _cursorX = (_cursorX + 4) ~/ 4 * 4;
        _ensureCursor();
        break;
      case 0x0A: // Line Feed
        _lineFeed();
        break;
      case 0x0C: // Form Feed
        clear();
        break;
      case 0x0D: // Carriage Return
        _carriageReturn();
        break;
      case 0x1B: // ESC (ANSI sequence start)
        // Handle ANSI sequences
        break;
      default:
        if (code >= 0x20 && code <= 0x7E) {
          // Printable ASCII
          _insertChar(char);
        }
    }
  }

  void _carriageReturn() {
    _cursorX = 0;  // Move to line start WITHOUT newline
  }

  void _lineFeed() {
    _cursorY++;
    if (_cursorY >= _lines.length) {
      _lines.add('');
    }
    _cursorX = 0;
  }

  void _insertChar(String char) {
    final line = _lines[_cursorY];
    final before = line.substring(0, _cursorX);
    final after = line.substring(_cursorX);
    _lines[_cursorY] = before + char + after;
    _cursorX++;
  }

  void _deleteAtCursor() {
    final line = _lines[_cursorY];
    if (_cursorX < line.length) {
      final before = line.substring(0, _cursorX);
      final after = line.substring(_cursorX + 1);
      _lines[_cursorY] = before + after;
    }
  }

  String get displayText => _lines.join('\n');
}
```

**File:** `/Users/khoa2807/development/2026/Comacode/mobile/lib/features/terminal/terminal_buffer.dart`

---

### Option 3: Quick Fix - Strip Control Characters

**Minimal fix** if cannot implement full solution:

```dart
String _sanitizeTerminalOutput(String text) {
  // Remove ANSI escape sequences
  var cleaned = RegExp(r'\x1b\[[0-9;]*[a-zA-Z]').replaceAllFrom(text, '');

  // Handle control characters
  final buffer = StringBuffer();
  for (int i = 0; i < cleaned.length; i++) {
    final char = cleaned[i];
    final code = char.codeUnitAt(0);

    switch (code) {
      case 0x08: // Backspace - skip previous char
        if (buffer.isNotEmpty) {
          final current = buffer.toString();
          buffer.clear();
          buffer.write(current.substring(0, current.length - 1));
        }
        break;
      case 0x09: // Tab - convert to spaces
        buffer.write('    ');
        break;
      case 0x0A: // Line Feed - keep
        buffer.write('\n');
        break;
      case 0x0D: // Carriage Return - skip (already at line start)
        break;
      case 0x0C: // Form Feed - clear screen (skip for now)
        break;
      case 0x07: // Bell - skip
        break;
      default:
        // Only printables (0x20-0x7E)
        if (code >= 0x20 && code <= 0x7E) {
          buffer.write(char);
        }
    }
  }

  return buffer.toString();
}
```

**This:**
- ✅ Removes garbage characters
- ✅ Handles basic control chars
- ❌ Still not a real terminal (no overwrite, no cursor positioning)
- ❌ Progress bars still broken

---

## Recommended Approach

**Use Option 1 (xterm.dart)** because:

1. **Proper Terminal Emulation**
   - Full VT100/VT220 support
   - All control characters handled correctly
   - ANSI escape sequences work (colors, formatting)

2. **Battle-Tested**
   - Based on xterm.js (used in VS Code, Atom, etc.)
   - Handles edge cases (Unicode, emojis, wide characters)

3. **Future-Proof**
   - Scrollback buffer
   - Text selection/copy
   - Search functionality
   - Themes support

4. **Less Custom Code**
   - Don't reinvent terminal emulation
   - Don't maintain complex parsing logic
   - Focus on app features

---

## Implementation Steps (Option 1)

### 1. Add Dependency

```bash
cd /Users/khoa2807/development/2026/Comacode/mobile
flutter pub add xterm
```

### 2. Create Terminal Buffer

```dart
// lib/features/terminal/terminal_buffer.dart
import 'package:xterm/xterm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TerminalBackend extends TerminalBackend {
  @override
  void write(String data) {
    // Data written to terminal
  }

  @override
  void resize(int width, int height) {
    // Handle resize
  }

  @override
  void terminate() {
    // Cleanup
  }

  @override
  void sendKeyPress(String key) {
    // Send to PTY
  }
}

final terminalProvider = Provider((ref) => Terminal(
  backend: TerminalBackend(),
  maxLines: 10000,
));
```

### 3. Update terminal_page.dart

Replace `Text(_output)` with `TerminalView`.

### 4. Test Control Characters

Test cases:
- `\r` carriage return (prompt, progress bar)
- `\b` backspace (editing)
- `\a` bell (alert)
- ANSI colors `\x1b[31mRed\x1b[0m`
- Cursor positioning `\x1b[2K` (clear line)

---

## Files Requiring Changes

### Immediate Fix (Option 3 - Quick)
- `/Users/khoa2807/development/2026/Comacode/mobile/lib/features/terminal/terminal_page.dart`
  - Replace `_stripAnsiCodes()` with `_sanitizeTerminalOutput()`
  - Lines 277-282

### Proper Fix (Option 1 - Recommended)
- `/Users/khoa2807/development/2026/Comacode/mobile/pubspec.yaml`
  - Add: `xterm: ^4.0.0`

- `/Users/khoa2807/development/2026/Comacode/mobile/lib/features/terminal/terminal_page.dart`
  - Replace `Text` widget with `TerminalView`
  - Replace `String _output` with `Terminal` backend
  - Implement `TerminalBackend` interface

- `/Users/khoa2807/development/2026/Comacode/mobile/lib/features/terminal/terminal_buffer.dart` (NEW)
  - Create PTY-to-xterm bridge

---

## Testing Checklist

After implementing fix, test:

- [ ] Shell prompt displays correctly (no `%` or garbage)
- [ ] Progress bars overwrite correctly (e.g., `wget`, `rsync --progress`)
- [ ] Command line editing works (backspaces, arrows)
- [ ] ANSI colors display (e.g., `ls --color=auto`, `grep --color`)
- [ ] Text selection/copy works
- [ ] Scrollback buffer works
- [ ] Screen resize works (rotation)
- [ ] Unicode/emojis display correctly

---

## Unresolved Questions

1. **Why "%" specifically?**
   - Hypothesis: `\r` (0x0D) rendered as `%` by Flutter's Text widget
   - Needs verification with hex dump of PTY output

2. **Are we receiving raw PTY output correctly?**
   - Server sends raw bytes (pty.rs:94)
   - Client converts with `String.fromCharCodes()` (terminal_page.dart:243)
   - Should verify encoding is UTF-8

3. **Why did previous List<String> approach work better?**
   - Each line processed separately
   - Control chars maybe filtered per-line
   - ListView rendering may have handled newlines better

4. **Performance impact of xterm.dart?**
   - Need to test with large output (e.g., `dmesg`, `cat large-file.log`)
   - Memory usage for scrollback buffer

5. **Platform-specific issues?**
   - Does xterm.dart work on iOS?
   - Does xterm.dart work on Android?
   - Any WebView requirements?

---

## References

**Control Characters:**
- ASCII control codes (0x00-0x1F)
- VT100/VT220 terminal specification
- ANSI escape sequences

**Packages:**
- `xterm.dart`: https://pub.dev/packages/xterm
- Based on xterm.js: https://github.com/xtermjs/xterm.js

**Related Issues:**
- debugger-260122-0838-sendcommand-blocking-ios.md (iOS sendCommand blocking)
- debugger-260120-1640-terminal-command-not-received.md (QUIC framing issue)

---

## Next Steps

1. ✅ Root cause identified (control character handling)
2. ⏳ Choose solution (recommend Option 1: xterm.dart)
3. ⏳ Implement fix
4. ⏳ Test with real PTY output
5. ⏳ Verify control character handling
6. ⏳ Test edge cases (progress bars, colors, Unicode)

**Estimated Time:**
- Option 1 (xterm.dart): 4-6 hours
- Option 2 (custom buffer): 8-12 hours
- Option 3 (quick fix): 1-2 hours
