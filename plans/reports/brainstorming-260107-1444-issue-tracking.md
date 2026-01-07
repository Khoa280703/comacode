# Brainstorming: Issue Tracking Strategy

**Date**: 2026-01-07
**Context**: Plan 260107-0858 completed, 3 issues remaining
**Decision**: How to track remaining issues

---

## Problem

Plan 260107-0858 (Phase 01-06) + Phase 07 (auth fix) completed. 3 issues unresolved:
- P1: Flutter Bridge Validation (4-6h)
- P2: IP Ban Persistence (2-3h)
- P2: Integration Tests (3-4h)

**Question**: Create new phases hay defer?

---

## Decision

### P1 (Flutter Bridge) → Defer to Mobile Project

**Rationale**:
- Flutter validation cần **app chạy thật** mới test được
- Làm integration test ngay = blind coding
- Khi build Flutter app, FFI testing là part của quá trình đó

**Action**: Track trong mobile plan (future project)

### P2 (IP Ban + Tests) → Create Tracking File

**Rationale**:
- P2 là "nice to have", không block MVP
- Need central place để track tech debt
- Plan gốc `260106-2127-comacode-mvp` là suitable location

**Action**: `plans/260106-2127-comacode-mvp/known-issues-technical-debt.md`

---

## Files Created

```
plans/
├── 260106-2127-comacode-mvp/
│   ├── known-issues-technical-debt.md  ← NEW
│   └── [existing phase files...]
│
└── 260107-0858-brainstorm-implementation/
    └── [Phase 01-06 files...]
```

---

## Next Steps

1. ✅ Issues tracked in `known-issues-technical-debt.md`
2. ✅ Plan 260107-0858 considered **complete**
3. ⏸️ P2 items implement khi cần (before public release)
4. ⏸️ P1 (Flutter) implement trong separate mobile project

---

## Unresolved Questions

1. **IP Ban Format**: JSON hay SQLite? (JSON recommended for MVP)
2. **Ban Duration**: 1h default hay configurable?
3. **Integration Test Priority**: Manual testing đủ tốt?

---

**Status**: ✅ Decision made, files created
**Last updated**: 2026-01-07
