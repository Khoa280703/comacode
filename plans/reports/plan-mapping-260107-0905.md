# Plan Mapping - Original vs Enhancement

**Ngày**: 2026-01-07
**Strategy**: Enhancement First

---

## Overview

Có 2 plans song song:

1. **Original Plan** (`260106-2127-comacode-mvp`) - 7 phases, 60h
2. **Enhancement Plan** (`260107-0858-brainstorm-implementation`) - 6 phases, 28h

## Status Matrix

| Original Phase | Name | Status | Enhancement Phase |
|----------------|------|--------|-------------------|
| 01 | Project Setup | ⚠️ Partial | - |
| 02 | Rust Core | ✅ Complete | **E01** Core Enhancements |
| 03 | Host Agent | ✅ Complete | **E02** Output Streaming |
| 04 | Mobile App | ⏸️ Waiting | **E03** Security |
| 05 | Network Protocol | ⏸️ Waiting | **E04** Certificate + TOFU |
| 06 | Discovery + Auth | ⏸️ Waiting | **E05** macOS Build |
| 07 | Testing + Deploy | ⏸️ Waiting | **E06** Windows Cross |

## Execution Order

```
Step 1: Complete Enhancement Plan (6 phases, 28h)
  ├─ E01. Core Enhancements (3h)
  ├─ E02. Output Streaming Refactor (6h)
  ├─ E03. Security Hardening (6h)
  ├─ E04. Certificate Persistence + TOFU (5h)
  ├─ E05. macOS Build + Testing (4h)
  └─ E06. Windows Cross-Platform (4h)

Step 2: Resume Original Plan from Phase 04
  ├─ O04. Mobile App (16h)
  ├─ O05. Network Protocol (10h)
  ├─ O06. Discovery + Auth (6h)
  └─ O07. Testing + Deploy (4h)
```

## Why Enhancement First?

**Problem**: Phase 01-03 answers.md có nhiều unresolved questions:
- Output streaming architecture
- Certificate management
- Authentication method
- Session cleanup policy
- Security hardening

**Solution**: Enhancement plan giải quyết tất cả这些问题 trước khi build Mobile Client (Phase 04).

## Next Step

Start **E01. Core Enhancements**:
- Add version constants to `crates/core/src/lib.rs`
- Implement Strict Handshake
- Add Snapshot Resync message type
