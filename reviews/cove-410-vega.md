# Review: `fix(plugin): use sendDurableMessageBatch for long message chunking`

**PR:** `kagura-agent/cove#410`
**Reviewer:** 💫 Vega

**Verdict:** ✅ Ready

---

### Summary

This pull request correctly refactors the Cove plugin to handle long messages by delegating chunking logic to the `openclaw/plugin-sdk`. It replaces direct calls to `restClient.sendMessage` with the SDK's `sendDurableMessageBatch` for final message delivery. The changes also intelligently handle edge cases, such as falling back to a fresh, chunked send when a final edit exceeds the character limit, and truncating streaming previews to prevent API errors. The accompanying tests are thorough, covering the new logic paths, boundary conditions, and ensuring existing behavior is correctly adapted. This is a solid fix that improves reliability and aligns the Cove plugin with established SDK patterns.

### Critical Issues

None.

### Suggestions

None. The changes are clean, well-tested, and directly address the problem.

### Positive Notes

- **Correct Use of SDK:** The primary change to use `sendDurableMessageBatch` is the right approach. It avoids reimplementing chunking logic and leverages the shared, battle-tested functionality from the SDK.
- **Robust Edge Case Handling:** The fallback logic in `editFinal` for messages exceeding `COVE_TEXT_CHUNK_LIMIT` is excellent. It prevents a class of errors where a final, long message would fail to send. The truncation of streaming previews is also a smart, defensive measure.
- **Thorough Testing:** The new test suite (`I. Long Message Chunking`) is comprehensive. It specifically validates the new behavior for fresh sends, the `editFinal` fallback, preview truncation, and boundary conditions (text exactly at the limit). Updating existing tests to assert the new call signatures demonstrates a good understanding of the change's impact.
- **Clarity and Readability:** The code remains easy to follow, and the changes are localized and clear in their intent. The PR description is also very helpful in explaining the "why" behind the change.
