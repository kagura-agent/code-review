# TypeScript / JavaScript Review Rules

## Null Safety
- Strict null checks: are `undefined`/`null` handled at boundaries (API responses, user input, optional params)?
- Optional chaining (`?.`) used where appropriate — but not as a crutch hiding real null bugs
- Type narrowing: does a type guard actually narrow, or does the code rely on `as` casts?

## Async / Promises
- No floating promises — every `async` call is `await`ed, `.catch()`ed, or explicitly fire-and-forget with comment
- Error handling in async: `try/catch` around `await`, not wrapping the entire function
- No mixing `.then()` and `await` in the same flow
- Race conditions: concurrent state mutations without locks/queues?

## Type Safety
- No `any` without justification. `unknown` preferred for dynamic input.
- Generic constraints: are generics actually constraining, or just `<T>` with no bounds?
- Discriminated unions: switch/if-else on union types — is the exhaustiveness check present?
- Type assertions (`as`): each one is a trust-me — is the trust warranted?

## Error Handling
- Custom error classes: are they used, or just `throw new Error("...")`?
- Error boundaries in React: do component trees have them?
- HTTP error responses: consistent shape, correct status codes
- Does catch block swallow errors silently? Every catch should log or rethrow.

## Node.js Specifics
- `process.env` accessed with fallback/validation, not bare
- File paths: `path.join()` / `path.resolve()`, not string concatenation
- Stream handling: backpressure considered for large data
- Proper cleanup: event listeners removed, connections closed, intervals cleared

## React (if applicable)
- Hook dependency arrays: missing deps cause stale closures
- useEffect cleanup: subscriptions/timers cleaned up on unmount
- Key props in lists: stable keys, not array index (unless list is static)
- State updates from stale closures: using functional updater when needed
- Memoization: `useMemo`/`useCallback` only where measurably needed, not everywhere

## Security
- User input in `dangerouslySetInnerHTML`, `eval()`, `new Function()`
- RegExp DoS: unbounded quantifiers on user input
- Path traversal: user-controlled paths joined without sanitization
- Prototype pollution: `Object.assign` / spread from untrusted sources
