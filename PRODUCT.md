# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

- **Host**: The person who pays the restaurant bill and coordinates the split—photographs the receipt, verifies parsed line items and adjustments, invites the table, resolves any unclaimed items, finalises the bill, and confirms or waives participant settlements.
- **Participants (Guests)**: Diners at the table (up to 30 per session, authenticated users) who join via a 6-character room code or deep link, claim the items they consumed, monitor their live **Estimated** share, and either pay their **Final** share directly via UPI or ask the host to cover it.

## Product Purpose

Fair restaurant bill coordination without the math. Spliqo turns a receipt photo into an itemized collaborative session where participants claim only what they consumed, see live provisional estimates, and settle exact, server-finalised amounts directly with the host via UPI—without Spliqo ever holding or moving money.

## Positioning

- **Zero-custody, UPI-native settlement**: Spliqo never holds or moves funds; it generates server-assembled `upi://pay` intents (with a 1-tap clipboard fallback) so participants pay the host directly.
- **Nobody pays for food they did not claim**: Unclaimed items are never auto-distributed; only an explicit, audited host action allocates them before finalisation.
- **Strict Estimate vs. Final separation**: Client-side calculations before finalisation are always labelled **Estimated** and never create payment obligations; exact liabilities are computed once on the server in integer paise using Largest Remainder allocation.

## Operating Context

- **Setting**: Group dining and restaurant bill splitting in India (INR only, up to ₹1,00,000 / `10,000,000` paise per receipt).
- **Workflow**:
  1. **Draft**: Host uploads a receipt photo (parsed via Gemini Vision), reconciles line items and adjustments (tax, service charge, discount, round-off), and activates the room.
  2. **Active**: Participants join via 6-character room code or deep link, claim items, see live **Estimated** shares, and tap *Done Selecting*.
  3. **Reviewing**: Triggered automatically when all participants complete or manually when the host locks the room; host resolves any unclaimed items (assign to participant, split equally, or host absorbs).
  4. **Finalised**: Server computes immutable final shares in one transaction.
  5. **Settlement**: Participants choose *Pay my share* (`self_pay` via UPI intent / clipboard fallback) or *Let host cover* (`host_pays`); host confirms, rejects, or waives each share.
- **Tenancy**: Session-isolated—there is no organization tenant, and hosting is per-session.

## Capabilities and Constraints

- **Currency & Precision**: INR (`INR`) only; all amounts are integer paise (no floats anywhere in the money path), capped at ₹1,00,000 (`10,000,000` paise).
- **Capacity & Auth**: Maximum 30 participants per session. Every participant must currently be an authenticated user.
- **Security & Privacy**: Zero-trust boundaries across Flutter, FastAPI, and Supabase. Host payout UPI IDs are encrypted (Infisical KMS envelope encryption + hardware-backed secure storage) and exposed only to eligible participants via server-assembled payment intents. Receipt images and UPI IDs are never logged.
- **Out of Scope**: In-app payment gateway, multi-currency, recurring or group-wide running balances, post-finalisation amount edits (reopening is allowed only while no settlement row has left `unpaid`), chat, itemised tip handling, push notification content, and web client.
- **Open Decisions (Undecided)**:
  - Guest participants without an account (default: authenticated users only).
  - Shared rate-limit store across backend instances (default: single backend instance).
  - Post-finalisation corrections after payment activity has begun.
  - Retention period for finalised sessions (2 years proposed; needs policy owner).

## Brand Commitments

- **Name & Tagline**: `Spliqo` — *"Fair bill coordination without the math"* (`spliqo_client/lib/core/constants/app_strings.dart`).
- **Domain Terminology**: Use `session`, `participant`, `claim`, `item`, `settlement`, and `host` consistently across UI and code.
- **Honest UI**: Estimates must always be labelled **Estimated**; the UI must never imply Spliqo can verify that a UPI payment occurred; the privacy notice must disclose that item claims are visible to session members to enable shared splits.

## Evidence on Hand

- Normative product and engineering specification in `STANDARDS.md`.
- Existing Flutter client implementation in `spliqo_client/` (screens, Riverpod providers, GoRouter routes, `CurrencyFormatter`, `AppStrings`, `AppColors`, `AppTheme`, `AppTokens`).
- No user testimonials, press, or external marketing assets exist in the repository; future work must not fabricate them.

## Product Principles

1. **Estimates are never obligations**: Clearly distinguish live **Estimated** shares from immutable server-computed **Final** amounts.
2. **Nobody pays for unclaimed food**: Never auto-distribute unclaimed items; require explicit host resolution.
3. **Zero-custody, honest verification**: Facilitate direct UPI hand-off without holding funds or claiming payment verification Spliqo cannot perform.
4. **Session-scoped privacy & minimal data**: Isolate data per session, protect UPI IDs and receipt images, and clearly disclose shared claim visibility.
5. **Paisa-exact fairness**: Preserve exact integer-paise arithmetic across every split, tax/discount adjustment, and tie-break.

## Accessibility & Inclusion

- The Flutter client must be accessible and responsive across `adaptive` iOS and Android form factors (`STANDARDS.md` §24.1); no formal target standard (e.g., specific WCAG level) has been locked in yet.
