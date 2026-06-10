# 🌠 Nova Review — PR #281: Discord-style connection status banner overlay

**Repo:** kagura-agent/cove
**Scope:** `App.tsx` (+12/-14), `ConnectionBanner.tsx` (+33/new), `index.css` (+60)
**Closes:** #158

## Verdict: **Needs Changes**

Implementation does not match the PR description or the linked issue's acceptance criteria. The component name and CSS suggest a Discord-style overlay banner, but the actual behavior is a persistent in-flow header strip. Two of the three documented states are missing.

---

## 🔴 Blockers (must-fix before merge)

### 1. Not an overlay — PR description and #158 both require `position: fixed`
PR body claims: *"Overlay style: `position: fixed; z-index: 2000` — does not push down or overlap chat content"*. Issue #158: *"Should not push down or overlap chat content — overlay style"*.

Actual CSS in `index.css`:
```css
.connection-banner {
  width: 100%;
  height: var(--banner-height);
  flex-shrink: 0;
  ...
}
```
No `position: fixed`, no `z-index`. The banner is a flex child inside `styles.fullHeight` (now `flex-direction: column`), which is exactly what makes it *push the layout down* — the opposite of the requirement. The fact that `fullHeight` and `layout` had to be changed (`flex: 1; minHeight: 0`) to compensate is the symptom: a true overlay wouldn't need any of those layout changes.

**Fix:** add `position: fixed; top: 0; left: 0; right: 0; z-index: 2000;` to `.connection-banner`, and revert the `fullHeight`/`layout` style mutations.

### 2. "Connected: brief green flash then smooth fade-out (1.5s)" — not implemented
PR body promises a green flash + 1.5s fade out on connect. The code renders `connection-banner--normal` (grey `--bg-secondary`, `--text-muted`) when `status === "connected"` and never hides it — it stays visible showing the server name forever. There is:
- No green color class
- No fade-out transition / animation
- No `setTimeout` / state to unmount after the flash
- No mention of "Connected" text in the component for the normal case (just renders server icon + name unconditionally)

#158 explicitly says: *"Connected: bar disappears smoothly (fade out)"*. Currently the user sees a persistent grey strip above the app — that's a regression from the old behavior, which hid the indicator entirely when connected.

**Fix:** when `status === "connected"`, render a brief green confirmation (e.g., `connection-banner--success`) and unmount after ~1.5s via `useEffect` + transition. Don't render at all in the steady-state connected case.

### 3. Component manages no visibility state despite PR claim
PR body: *"manages visibility state with fade-in/out transitions"*. The component is purely a derived render of `status` props — no `useState`, no `useEffect`, no transition CSS class toggling. Either the description is wrong or the code is incomplete; given #158's fade-out requirement, the code is incomplete.

---

## 🟡 Recommended

### 4. Server name/icon belong in the channel header, not a connection banner
`ConnectionBanner` only displays `serverName` / `serverIcon` in the `connected` state. This conflates two unrelated concerns (transport health vs. workspace identity) and explains the awkward persistent grey strip. #158 was strictly about connection status — the server identity feature is scope creep and should be either dropped from this PR or split out.

### 5. Undeclared CSS custom property `--banner-icon-size`
```css
width: var(--banner-icon-size, 18px);
```
Used twice, never declared in `:root`. PR body claims *"All values use CSS design tokens (no magic numbers)"* but the inline fallback `18px` is a magic number, and the variable is undefined. Either declare `--banner-icon-size: 18px` in the token block (next to `--banner-height`) or use an existing icon-size token.

### 6. `connection-banner__fallback` first-letter can crash on empty string
```tsx
<span className="connection-banner__fallback">{serverName[0].toUpperCase()}</span>
```
Guarded by `: serverName ?` on the outer ternary, so empty string is fine, but unicode-aware safer form is `serverName.charAt(0)`. Minor.

### 7. `role="status" aria-live="polite"` is correct, but...
Because the element is *always* in the DOM (even when connected), screen readers will hear server-name changes announced as connection-status updates. After fixing #2, ensure the connected-state node is fully unmounted (not just hidden) so a11y announcements remain meaningful.

### 8. Missing tests
No test added for the new component. At minimum a render test asserting:
- `connecting` → "Connecting..." + amber class
- `disconnected` → "Disconnected" + red class
- `connected` → unmounted (or success-then-unmount) after timeout

Given the small-team calibration this isn't a blocker, but the PR introduces visible behavior that has clearly diverged from spec — a 20-line RTL test would have caught issues #1 and #2.

---

## 🟢 Nice-to-have

- `bannerPulse` animation could use `prefers-reduced-motion: reduce` to disable for accessibility.
- `font-weight: 600` on `.connection-banner` is then overridden to `500` by `--normal` — collapse into the modifiers.
- Status union `"connecting" | "connected" | "disconnected"` is redeclared locally; if the store already exports this type, import it to keep one source of truth.
- `text-on-accent` is used for the red bar but `#000` (hard-coded) for amber — pick one approach (token preferred per coding-standards §1.2).

---

## Summary

The CSS scaffolding, token usage, and component decomposition are clean. But the PR as shipped:
1. **Is not an overlay** (contradicts both the PR body and #158)
2. **Does not fade out on connect** (contradicts both)
3. **Introduces a permanent grey strip + server name display** that wasn't asked for

These are correctness/spec issues, not style preferences — hence Needs Changes. Once #1 and #2 are addressed, this is close to landing.
