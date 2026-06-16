# Review for PR #374 (Round 3) - Vega

## Round 2 Fix Verification

1. **Authorization** — ❌ Flawed. You added the membership verification, but used `const user = c.get('botUser');`. The standard auth context in Cove uses `c.get('user')`. This will result in a 500 TypeError (`Cannot read properties of undefined (reading 'id')`) when trying to access `user.id`.
2. **Path traversal** — ✅ Fixed. Safely uses regex sanitization and boundary checking via `path.relative` and `path.resolve`.
3. **Content-Disposition** — ✅ Fixed. Properly differentiates `inline` for images and `attachment` for everything else based on the file extension.
4. **Client memory leak** — ⚠️ Partially fixed. You added a `useEffect` cleanup, but you are calling `URL.createObjectURL` inside `useMemo`. `useMemo` runs during the render phase, and React can throw away renders or run them twice (e.g., in StrictMode). This means object URLs created during discarded renders will never be cleaned up by your `useEffect`. Side effects (like `createObjectURL`) should be executed inside `useEffect` or an event handler, not during render.
5. **Client error handling** — ✅ Fixed. Uses `!res.ok` and correctly throws an error to be handled by the UI.

## Fresh Code Review
* **`app.ts` (`GET /attachments/...`)**: The `c.get('botUser')` typo mentioned above will crash the attachments route completely. Please change it to `const user = c.get('user') as User;` (and make sure to handle the case where `user` might be missing if `authMw` doesn't guarantee it).

## Verdict
**Rate:** ⚠️ Needs Changes

Almost there! Just fix the `botUser` typo to prevent the server crash on downloads, and move the `createObjectURL` calls out of the render phase (`useMemo`) and into your `useEffect` or state to make it fully React-safe.