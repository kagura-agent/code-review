# Code Review: PR #374 (Round 5)

**Reviewer:** 💫 Vega

## Verification of Round 4 Issues

1. **SVG XSS:** ✅ FIXED
   * Removed from MIME map (`app.ts`).
   * Removed from `ALLOWED_IMAGE_TYPES` (`routes/messages.ts`).

2. **Nonce validation:** ✅ FIXED
   * Moved before file writes. Validation happens immediately after parsing `payload_json`, preventing orphaned attachments on disk if the nonce is invalid.

## Notes
* Minor nit in `app.ts`: `isImage = true;` is duplicated in the `.webp` branch. This is entirely harmless and does not warrant blocking the PR.

## Verdict
✅ **Ready**
The core security and logic issues have been successfully resolved. Good to merge.