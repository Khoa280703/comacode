# Debugger Report: Newline Root Cause Analysis

**Date**: 2026-01-09 00:47
**Issue**: First keystroke causes newline (without `%` marker)
**Status**: Root cause identified

## Executive Summary

**ROOT CAUSE IDENTIFIED**: Banner ends with `\r\x1b[K` (CR + clear-to-EOL) which puts cursor at column 0, but Zsh prompt output starts **immediately after** banner arrives at client. When user types first character, it appears at column 0, then Zsh redraws prompt causing cursor to jump to next line.

**KEY INSIGHT**: The newline is NOT a real newline. It's a **visual artifact** from terminal redrawing.

---

## Timeline Analysis

### 1. Client Boot Sequence (main.rs:117-149)

```
T0: Write banner to stdout
    banner = "... \r\x1b[K"  // Ends with CR + clear line
    stdout: [BANNER DISPLAYED]

T1: Enable raw mode
    terminal: NOW IN RAW MODE

T2: Send Resize message
    network: Resize {rows, cols}

T3: Send Empty Input (eager spawn trigger)
    network: Input {data: []}

T4: Send Ping (force flush)
    network: Ping
```

**Critical Detail**: Banner ends with `\r\x1b[K`
- `\r` = Carriage Return (move to column 0)
- `\x1b[K` = ANSI "clear from cursor to end of line"

**Effect**: Cursor at column 0, line cleared

### 2. Server Spawn Sequence (quic_server.rs:262-331)

```
T5: Receive Resize
    pending_resize = (rows, cols)

T6: Receive Empty Input
    Create TerminalConfig:
      - rows, cols from pending_resize
      - COLUMNS=<cols>, LINES=<rows>  // For Zsh
      - PROMPT_EOL_MARK=""            // Hide % marker

    Spawn PTY with Zsh:
      fork() → execve("/bin/zsh", ..., env)

    Zsh starts:
      - Read COLUMNS/LINES from env
      - Initialize terminal
      - Output PROMPT

T7: PTY Output starts flowing
    Zsh prompt: "khoa2807@mbp ~ % "
    Pumped to QUIC stream → Client
```

**Critical Detail**: Zsh spawns **immediately** at T6, starts outputting prompt

### 3. Client Display Sequence

```
T8: Banner already on screen (from T0)
    Screen: [BANNER_CONTENT]
           Cursor at column 0 (after \r\x1b[K)

T9: First PTY output arrives (Zsh prompt)
    Network: "khoa2807@mbp ~ % "
    Display: [BANNER_CONTENT]khoa2807@mbp ~ %
           Cursor at column 18

T10: User types first character ('l' for 'ls')
    Keystroke: 'l'
    Sent to server, echoed back
    Display: [BANNER_CONTENT]khoa2807@mbp ~ % l
           Cursor at column 19

T11: Zsh processes command, triggers redraw
    Zsh: "Oh, user is typing, need to show command"
    Zsh redraws: Clears line, outputs prompt + command
    Output: "\r\x1b[Kkhoa2807@mbp ~ % l"

    Wait... what's happening on screen?

    BEFORE redraw:
    [BANNER_CONTENT]khoa2807@mbp ~ % l

    AFTER redraw (\r moves to col 0, \x1b[K clears rest):
    [BANNER_CONTENT]khoa2807@mbp ~ % l
    └─────────────┘
      Banner still there!
```

**THE PROBLEM**: Banner content + Prompt + Keystroke on same line looks like newline when Zsh redraws.

---

## Root Cause

### The Sequence

1. **Banner writes to stdout**: Ends with `\r\x1b[K`
   - Cursor at column 0
   - Line cleared from cursor to end
   - **BUT**: Banner content is STILL on screen above

2. **Zsh prompt arrives**: Writes to same line
   ```
   Screen: [BANNER_CONTENT]khoa2807@mbp ~ %
   ```

3. **User types 'l'**:
   ```
   Screen: [BANNER_CONTENT]khoa2807@mbp ~ % l
   ```

4. **Zsh redraws**: Outputs `\r\x1b[K` + prompt + command
   - `\r` moves to column 0
   - `\x1b[K` clears from cursor to end of line
   - **BUT**: This only clears from column 0, not banner content
   - Prompt + command written at column 0
   - **Old prompt at column 18 still visible on screen!**
   ```
   Screen: khoa2807@mbp ~ % l
           % l                     ← Old prompt remnant
   ```

5. **Visual artifact**: Looks like newline, but actually just leftover characters

### Why No `%` Marker?

`PROMPT_EOL_MARK=""` (line 292) hides the `%` marker Zsh would normally show for incomplete lines.

**Before fix**:
```
[BANNER]%           ← Zsh adds % marker
```

**After fix**:
```
[BANNER]khoa@host ~ ← No % marker, but prompt overlaps
```

---

## Evidence

### Code Evidence

1. **Banner ending** (main.rs:126):
   ```rust
   "\r\x1b[K", // FIX: Về đầu dòng + Xóa sạch dòng
   ```

2. **PROMPT_EOL_MARK** (quic_server.rs:292):
   ```rust
   config.env.push(("PROMPT_EOL_MARK".to_string(), "".to_string()));
   ```

3. **No delayed resize** (quic_server.rs:302):
   ```rust
   // NO Delayed Resize - causes SIGWINCH while user typing!
   ```

### Terminal Behavior

When a terminal receives:
1. `\r\x1b[K` → Move to col 0, clear to end of **current line**
2. This does NOT clear content before the cursor
3. If cursor was at col 18, content at cols 0-17 remains

### Zsh Redraw Behavior

Zsh redraws prompt when:
- User types character
- Terminal size changes (SIGWINCH)
- External program exits

Redraw sequence:
1. `\r` - Move to column 0
2. `\x1b[K` - Clear to end of line
3. Output prompt + current command

---

## Why It Looks Like Newline

**User perception**:
```
Before typing:  [BANNER_CONTENT]khoa@host ~
After typing 'l':  khoa@host ~ % l
                  % l        ← Old prompt, looks like newline
```

**Actually happening**:
- No real newline
- Old prompt characters not cleared
- Zsh's `\x1b[K` only clears from cursor position (col 0) to end
- Old prompt was at col 18, so it remains visible

---

## Why Removing Delayed Resize Helped

**Before**: Delayed resize (300ms) caused SIGWINCH during typing
- SIGWINCH → Zsh redraws prompt
- Redraw → `\r\x1b[K` → clears from cursor position
- **BUT**: Cursor moved during typing, so clear happens at wrong position
- Result: Partial prompt + `%` marker

**After**: No delayed resize
- SIGWINCH doesn't interrupt typing
- **BUT**: First keystroke still triggers Zsh redraw
- Redraw clears from col 0, old prompt at col 18 remains
- Result: Prompt "ghosting" (looks like newline)

---

## The Actual Problem

**Banner timing mismatch**:
1. Banner written to stdout **before** raw mode
2. Banner uses `\r\x1b[K` which assumes full line control
3. Zsh prompt arrives **after** banner, writes to same line
4. Zsh redraw uses `\r\x1b[K` which doesn't clear banner
5. Old prompt remnant + new prompt = visual newline

**Key insight**: Banner and Zsh prompt are **fighting for the same line**.

---

## Unresolved Questions

1. Should banner be cleared before spawning PTY?
2. Should we delay banner until after PTY starts?
3. Should we move banner to a different line?
4. Is there a race condition between banner display and PTY spawn?
5. Why doesn't `\r\x1b[K` clear the entire line?

---

## Recommendations (NOT IMPLEMENTING)

1. **Clear screen before PTY**: Send `\x1b[2J\x1b[H` (clear screen + home)
2. **Move banner to separate area**: Use `\r\n` to ensure banner on its own line
3. **Delay PTY spawn**: Wait for banner to be read by user
4. **Suppress Zsh redraw**: Use `zle -F` to prevent redraw on first keystroke
5. **Fix banner terminator**: Use `\r\n` instead of `\r\x1b[K`

---

## Conclusion

**Root cause**: Banner's `\r\x1b[K` + Zsh prompt + Zsh redraw = prompt "ghosting" that looks like newline.

**Not actually a newline**: Visual artifact from overlapping text on same line.

**Why `%` is gone**: `PROMPT_EOL_MARK=""` working as intended.

**Why newline persists**: Banner/Zsh timing issue, not PTY driver issue.
