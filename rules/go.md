# Go Review Rules

## Error Handling
- Every error return checked — no `_ = someFunc()` unless explicitly justified
- Error wrapping: `fmt.Errorf("context: %w", err)` not `fmt.Errorf("failed: %s", err)` (loses unwrap chain)
- Sentinel errors: `errors.Is()` / `errors.As()`, not string comparison
- Don't log AND return error — pick one (usually return, let caller decide)

## Concurrency
- Goroutine leaks: every spawned goroutine has a shutdown path (context cancellation, done channel)
- Channel operations: could they block forever? Is there a `select` with `default` or timeout?
- Mutex scope: lock held as briefly as possible, no I/O under lock
- `sync.WaitGroup`: Add before goroutine launch, not inside
- Race conditions: shared state accessed from multiple goroutines without sync?

## Resource Management
- `defer` for cleanup: file handles, HTTP response bodies (`resp.Body.Close()`), mutexes
- Context propagation: are contexts passed through, or dropped/replaced with `context.Background()`?
- HTTP clients: reusing clients with connection pooling, not creating per-request
- `defer` in loops: defers stack until function return — use explicit close in loop body

## Nil Safety
- Nil pointer dereference: interface nil vs typed nil, nil map/slice write
- Nil channel: sending to nil channel blocks forever
- Nil function values: checked before call?

## API Design
- Exported names: clear, Go-idiomatic (no Get/Set prefix unless warranted)
- Error types: custom error types for callers who need to handle differently
- Package boundaries: does the change introduce circular imports?
- Interface compliance: `var _ Interface = (*Struct)(nil)` compile-time check

## Testing
- Table-driven tests: consistent structure, clear test names
- Test helpers: `t.Helper()` called for correct line reporting
- No test pollution: tests clean up temp files, env vars, global state
- Subtests: `t.Run()` for test cases, enabling selective execution

## Performance
- String building: `strings.Builder` not `+=` in loops
- Slice pre-allocation: `make([]T, 0, expectedLen)` when size is known
- Map pre-allocation: `make(map[K]V, expectedLen)`
- Unnecessary allocations: pointer vs value receiver, unnecessary copies
