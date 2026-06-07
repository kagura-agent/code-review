# Cove PR #255 Review - Round 2

**Reviewer**: 💫 Vega
**Status**: ⚠️ Revisions Needed

## 1. R1 Issues Status
- ✅ **REST retry only 429**: Fixed. `rest-client.ts` now handles 429 delays, 5xx server errors, network errors, and implements exponential backoff.
- ✅ **Retry-After unbounded + NaN**: Fixed. Replaced with `Math.min(parseFloat(raw ?? "") || 1, 30)`, safely handling `NaN` and capping at 30 seconds.
- ✅ **RESUMED aborts dispatches**: Fixed. Split into `"reconnect"` (hard IDENTIFY reconnect) and `"resumed"` (soft resume). `pendingDispatches` are only aborted on hard reconnects.

## 2. New Issues (Regressions)
- 🔴 **`res.json()` on 204 No Content will throw and trigger a retry loop**
  In `rest-client.ts`, the new `request()` wrapper unconditionally calls `res.json()` on successful responses:
  ```typescript
  if (!res.ok) {
    // ...
  }
  return res.json() as Promise<T>;
  ```
  However, endpoints like `DELETE /messages/:id` and `POST /typing` (which now use `requestVoid` -> `request`) typically return a `204 No Content` with an empty body. `res.json()` on an empty body will throw a `SyntaxError: Unexpected end of JSON input`, which gets caught by your wrapper. This will cause the client to retry the request 3 times and eventually throw the parse error.
  
  **Fix**: Check `res.status === 204` or `res.headers.get("Content-Length")` before calling `.json()`:
  ```typescript
  if (res.status === 204) {
    return undefined as unknown as T;
  }
  return res.json() as Promise<T>;
  ```

## 3. Verdict
⚠️ **Action Required**: Please fix the 204 No Content JSON parsing regression in `rest-client.ts`. The rest of the refactor looks solid and addresses all R1 feedback!