# Client Test Script Fixes - v0.0.18

**Date**: 2026-02-11
**File**: `client/scripts/test.sh`
**Bugs Fixed**: Same 2 critical bugs as server test script

---

## Overview

Client hardware test results revealed **identical bugs** to those found in the server test script. Both timing calculation and JSON parsing issues were present, suggesting a common origin (likely copy-paste).

---

## Bug 1: Timing Calculation Error ⏱️

### Problem
Test 15 showed absurd elapsed time:
- **46,220,000 seconds** = **535 days** 🚨

### Evidence from Hardware Test
```
[0;34m[INFO][0m Elapsed time: 46220000000ms
```

### Root Cause
**Identical to server bug** - Nanosecond detection logic inverted:
```bash
# BROKEN LOGIC:
if [[ "$START_TIME" =~ N ]]; then
    ELAPSED_MS=$(( (END_TIME - START_TIME) / 1000000 ))
else
    ELAPSED_MS=$(( (END_TIME - START_TIME) * 1000 ))
fi
```

- When `date +%s%N` succeeds → returns nanoseconds → no "N" → **multiplies by 1000** ❌
- When `date +%s%N` fails → returns "1234567890N" → contains "N" → **divides by 1000000** ❌

### Fix Applied
```bash
# CORRECT LOGIC:
if [[ ${#START_TIME} -gt 12 ]]; then
    # Nanoseconds (19 digits) - convert to milliseconds
    ELAPSED_MS=$(( (END_TIME - START_TIME) / 1000000 ))
else
    # Seconds (10 digits) - convert to milliseconds
    ELAPSED_MS=$(( (END_TIME - START_TIME) * 1000 ))
fi
```

### Tests Fixed
- 9 timing calculation fixes across all timed tests

---

## Bug 2: JSON Parsing Error (Verbose Mode) 🔍

### Problem
Test 15 **failed** despite:
- ✅ HTTP Status: **200 OK**
- ✅ Valid JSON response present

### Evidence from Hardware Test
Lines 41-46 show verbose curl output mixed with JSON:
```
Response Body:   % Total    % Received % Xferd  Average Speed...
* Host remote-ollama:11434 was resolved.
{ [108 bytes data]
100   108  100   108    0     0   5062...
{"object":"list","data":[{"id":"qwen2.5:0.5b",...}]}
```

### Root Cause
**Identical to server bug** - Verbose mode mixes curl debug with JSON:
```bash
# Complex filtering that doesn't work reliably:
MODELS_RESPONSE=$(... | grep -v '^[<>*]' | grep -v '^{' -A 9999 || ...)
```

The filtering logic was:
1. Remove lines starting with `<`, `>`, or `*` (curl debug markers)
2. Remove lines starting with `{` and show next 9999 lines (????)
3. This was backwards and unreliable

### Fix Applied
**Simplified approach** - Just extract the last line (the JSON):
```bash
# NEW (FIXED):
MODELS_RESPONSE=$(echo "$RESPONSE_WITH_CODE" | sed '$d')
JSON_ONLY=$(echo "$MODELS_RESPONSE" | tail -n 1)

# Then parse JSON_ONLY instead of MODELS_RESPONSE
echo "$JSON_ONLY" | jq -e '.object == "list"'
```

### Tests Fixed
- 5 JSON extraction fixes:
  - Test 15: GET /v1/models
  - Test 16: GET /v1/models/{model}
  - Test 17: POST /v1/chat/completions (non-streaming)
  - Test 21: POST /v1/chat/completions (JSON mode)
  - Any other verbose mode JSON parsing

---

## Test Results Summary

### Before Fixes
**30 passed, 1 failed, 11 skipped**
- Test 15: **FAIL** (timing bug + JSON parsing bug)
- Other skips: Legitimate (no models, quick mode, etc.)

### After Fixes (Expected)
**31 passed, 0 failed, 11 skipped**
- Test 15: **PASS** (timing: ~50ms, JSON parsed correctly)
- Skips remain legitimate

### Improvement
**+1 test fixed** (from failed to passed)
Success rate: 96.8% → **100%** of runnable tests ✅

---

## Key Insights

### 1. Identical Bugs in Both Scripts
Both `server/scripts/test.sh` and `client/scripts/test.sh` had:
- Same timing calculation bug
- Same JSON parsing bug

**Likely origin**: One script copied from the other, propagating bugs.

### 2. Pattern of False Failures
- **APIs worked perfectly** (HTTP 200 + valid JSON)
- **Test infrastructure was broken** (timing + parsing)
- Lesson: Always check raw responses before trusting test verdicts

### 3. Complex Code is Fragile
The original JSON filtering logic was overly complex:
```bash
grep -v '^[<>*]' | grep -v '^{' -A 9999
```

Simple solution works better:
```bash
tail -n 1
```

---

## Files Modified

**1 file, 14 bug fixes**:
- `client/scripts/test.sh`:
  - 9 timing calculation fixes (all timed tests)
  - 5 JSON extraction fixes (all verbose JSON parsing)

---

## Verification

✅ Bash syntax validation passed:
```bash
bash -n client/scripts/test.sh
```

⏳ Awaiting hardware test re-run for final confirmation

---

## Impact

### Before All Fixes (v0.0.17)
- **Server**: 20 passed, 2 failed, 4 skipped (77% success)
- **Client**: 30 passed, 1 failed, 11 skipped (97% success)

### After All Fixes (v0.0.18 - Expected)
- **Server**: 25 passed, 0 failed, 1 skipped (96% success)
- **Client**: 31 passed, 0 failed, 11 skipped (100% success)

### Total Impact
**3 scripts fixed, 31 bugs eliminated**:
1. `server/scripts/test.sh` - 16 fixes (H3-2a)
2. `client/scripts/install.sh` - 1 fix (H3-2b)
3. `client/scripts/test.sh` - 14 fixes (H3-2c)

---

**All fixes completed and documented. Ready for hardware test re-run.**
