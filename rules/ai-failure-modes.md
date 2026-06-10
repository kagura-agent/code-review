# AI-Generated Code Failure Modes

Universal checklist for reviewing AI-generated code. These 14 systematic failure modes are research-backed and apply across all languages. Check each one explicitly.

## Error Handling
- **Catch-all error swallowing**: Empty `catch {}` or `catch { return null }` that silently hides failures. Every catch must log, rethrow, or handle meaningfully.
- **Hardcoded "success"**: Mock fixtures or stub returns left in production code. Tests that always pass because they assert against hardcoded values, not real behavior.

## Abstraction & Structure
- **Premature abstraction**: Generic wrappers, factories, or base classes created for a single use case. If there's only one implementation, it's not an abstraction — it's indirection.
- **Parameter explosion**: Functions taking 5+ parameters instead of using an options object or breaking into smaller units. Sign of scope creep in the generated solution.
- **Long functions**: Single functions doing too much. Watch for functions over ~50 lines — AI tends to generate monolithic blocks rather than composing smaller units.
- **YAGNI / speculative configurability**: Config options, plugin systems, or extension points nobody asked for. If the requirements don't mention it, the code shouldn't have it.

## Code Quality
- **Code duplication**: Near-identical blocks that should be extracted. AI models generate from examples and often repeat patterns verbatim instead of factoring out shared logic.
- **Comment pollution**: Obvious comments restating the code (`// increment counter` above `counter++`). Comments should explain *why*, not *what*.
- **Generic naming**: Variables like `data`, `result`, `temp`, `item`, `handler`. If a reviewer can't understand purpose from the name alone, it's too generic.
- **Dead code / half-implementations**: Unused imports, commented-out blocks, TODO stubs, functions that exist but are never called. Ship complete code or don't ship it.

## Correctness
- **Hallucinated APIs**: Calls to methods, classes, or libraries that don't exist or have wrong signatures. Cross-check any unfamiliar API call against actual docs/source.
- **Plausible-but-wrong logic**: Code that reads correctly and passes simple tests but has edge case bugs — off-by-one, boundary conditions, race conditions. The more "clean" the code looks, the more carefully you should test edge cases.
- **Inconsistency with surrounding code**: New code using different patterns, naming conventions, or error handling styles than the existing codebase. AI doesn't always read context — it generates from its training.

## Defensive Coding
- **Guards for impossible cases**: Null checks, type guards, or validation for values that are already guaranteed by the type system or call context. These aren't safety — they're noise that obscures real logic.

## Cross-Cutting Root Cause

8 of 14 failure modes trace to one bias: **the model prefers emitting more code** — more parameters, more guards, more abstractions, more comments. The cure is restraint, not knowledge. When reviewing AI output, the question is often "what should be removed?" not "what's missing?"
