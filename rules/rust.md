# Rust Review Rules

## Ownership & Borrowing
- Unnecessary `.clone()`: is it avoiding a borrow checker fight, or actually needed?
- Lifetime annotations: are they minimal and correct? Over-constraining = fight with compiler
- Move vs borrow: does the function need ownership, or would `&` / `&mut` suffice?
- `Rc`/`Arc` usage: is shared ownership genuinely needed, or can ownership be restructured?

## Error Handling
- `unwrap()` / `expect()` in library code: should be `?` propagation
- Error types: `thiserror` for libraries, `anyhow` for applications
- `?` operator: is the error context preserved? Add `.context()` for meaningful errors
- Panic paths: are panics documented and intentional, or hidden in indexing/unwrap?

## Unsafe
- Every `unsafe` block: documented invariants, minimally scoped
- Raw pointer derefs: validity guaranteed by what?
- FFI boundaries: null checks, lifetime guarantees

## Concurrency
- `Send` / `Sync` bounds: are they correctly derived or manually implemented?
- Mutex poisoning: `.lock().unwrap()` — is poison recovery needed?
- Deadlock potential: lock ordering consistent?
- Channel usage: bounded vs unbounded — could unbounded grow forever?

## Performance
- Unnecessary allocations: `String` vs `&str`, `Vec` vs `&[T]`
- Iterator chains vs manual loops: iterators preferred (zero-cost abstractions)
- `collect()`: is the target type specified? Does it need to collect at all?
- Hot paths: unnecessary `format!()` or allocation in tight loops

## API Design
- Public API surface: is it minimal? Can any pub be made pub(crate)?
- Builder pattern: appropriate for complex construction?
- `From`/`Into` implementations: are conversions natural and non-lossy?
- Breaking changes to public types flagged

## Testing
- Property-based testing (`proptest`/`quickcheck`) for parsing/encoding
- `#[should_panic]` with expected message for panic tests
- Integration tests in `tests/` vs unit tests in modules
