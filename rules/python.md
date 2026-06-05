# Python Review Rules

## Type Safety
- Type hints on public functions — at minimum params and return types
- `Optional[X]` vs `X | None`: are None checks present before use?
- `Any` usage justified? Can it be narrowed?

## Error Handling
- Bare `except:` or `except Exception:` — too broad? Catches KeyboardInterrupt/SystemExit?
- Exception chaining: `raise NewError() from original` preserves traceback
- Context managers (`with`) for resource cleanup — files, connections, locks
- Silent catches: `except: pass` is almost always wrong

## Async
- `await` on all coroutines — unawaited coroutines are silently dropped
- `asyncio.gather()` error handling: `return_exceptions=True` or individual try/catch?
- Sync blocking calls inside async functions (e.g., `time.sleep()` instead of `asyncio.sleep()`)
- Task cancellation: are tasks cancelled on shutdown?

## Security
- `eval()`, `exec()`, `pickle.loads()` on untrusted input
- SQL: parameterized queries, not f-strings/format
- `subprocess`: `shell=True` with user input → command injection
- Path traversal: `os.path.join()` doesn't prevent `../` — use `pathlib.resolve()` + check prefix
- YAML: `yaml.safe_load()` not `yaml.load()`

## Data Structures
- Mutable default arguments: `def f(x=[])` is a shared-state bug
- Dict `.get()` vs `[]`: which is appropriate for the access pattern?
- Dataclasses/Pydantic vs raw dicts for structured data
- Generator vs list: memory implications for large datasets

## Testing
- `pytest` fixtures: appropriate scope (function/module/session)?
- Mock targets: mock where imported, not where defined
- Assertions: specific (`assertEqual`) over generic (`assertTrue`)
- Test isolation: no shared mutable state between tests

## Performance
- List comprehension vs loop: comprehension preferred for simple transforms
- String concatenation in loops: `"".join()` not `+=`
- Unnecessary copies: `copy.deepcopy()` when shallow suffices
- Import-time side effects: heavy imports at module level slow startup
