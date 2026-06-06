# PR Review: #248 (cove) - BFF Pattern

**Summary**
The PR successfully shifts Cove to a Backend-For-Frontend (BFF) authentication pattern, effectively neutralizing token leaks in URLs, Referer headers, and XSS by migrating session and pending tokens to HttpOnly cookies. The approach is sound, covering both HTTP endpoints and the WebSocket connection securely. However, there is a critical uncaught exception risk in the custom cookie parser that could lead to DoS.

**Critical Issues**
* **Uncaught `URIError` in WebSocket `verifyClient` (Security/Correctness)**: In `packages/server/src/ws/index.ts`, `parseCookies` uses `decodeURIComponent(rest.join("=").trim())`. If a user (or attacker) sends a malformed cookie header (e.g., `Cookie: foo=%`), `decodeURIComponent` will synchronously throw `URIError: URI malformed`. Because this is not wrapped in a try/catch, it crashes the WebSocket upgrade flow and can potentially crash the Node process (DoS). Wrap the decoding in a `try...catch` block.

**Product Impact**
* **Enhanced Security**: Token theft via XSS, browser history, or logs is strongly mitigated.
* **Seamless Transition**: Users with old bookmarks containing `?token=` will have their URLs cleaned up automatically without broken functionality.
* No negative functional behavior changes for end-users.

**Suggestions**
* **Strict BFF for `pendingToken`**: In `packages/server/src/routes/auth.ts`, `/api/auth/pending-status` sends `pendingToken` to the client, which echoes it back in `/api/register`. To adhere strictly to BFF, stop sending `pendingToken` to JS entirely. Let the server read it directly from `PENDING_COOKIE` during the registration POST.
* **Token leak in Registration Response**: `POST /api/register` still returns `{ token: result }` in the JSON body. If the client no longer uses it (and just reloads), change it to return `{ message: "registered" }` to guarantee the session token never touches the JS environment.
* **Legacy LocalStorage Cleanup**: Consider adding `localStorage.removeItem("cove-token")` in `App.tsx` during initialization to actively clean up legacy tokens from users' browsers.
* **Consistency in `/api/auth/me`**: The route manually checks `authHeader?.startsWith("Bearer ")`, ignoring the `Bot ` prefix that `resolveUser` supports. If bot clients ever need to call `/api/auth/me`, this will fail.

**Positive Notes**
* Excellent use of `verifyClient` to seamlessly upgrade authenticated WebSocket connections.
* Good backwards compatibility for bot clients (Authorization headers and explicit IDENTIFY payloads are preserved).
* Removing the token from the IDENTIFY payload (`token: null`) while relying on the upgrade auth is a very clean and secure design.

**Rating**: ⚠️ Needs Changes