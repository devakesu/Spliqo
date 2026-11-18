# Spliqo Engineering Standards

**Status:** Normative reference for all design, build, audit and correction work on Spliqo. **Applies to:** Flutter client, FastAPI (Python) backend, Supabase (PostgreSQL, Auth, Realtime), Gemini Vision receipt parsing. **Scope rule:** These standards govern code that is **built or being built**. Features listed in Section 23 as out of scope are not designed or implemented under this document. Sections marked _(when built)_ are binding only once that feature exists.

**Product in one paragraph.** One person (the **host**) pays the restaurant and becomes the expense coordinator. They photograph the receipt, verify the parsed items, and invite others. Each participant claims what they consumed and sees a live **estimated** share. When the host finalises, exact amounts are computed once on the server. Each participant then pays the host (UPI hand-off) or asks the host to cover their share. **Spliqo never holds or moves money.**

Keywords **MUST**, **MUST NOT**, **SHOULD**, **MAY** are used in the RFC 2119 sense. A MUST violation is a defect. A SHOULD deviation needs a written justification in the PR.

---

## 1. Core Principles

1. **Money is integers.** Every amount is stored, transmitted and computed as an integer number of paise. No floats, no `double`, no `num`, no JSON numbers with decimals, anywhere in the money path.
2. **Server authoritative.** The client displays estimates. The server decides final amounts, state transitions and payment outcomes. Every rule the client enforces for UX MUST be enforced again on the server.
3. **Estimates are never obligations.** Anything computed on the client, or before finalisation, is labelled _Estimated_ and can never be the source of a payable amount.
4. **Zero trust.** The Flutter client, FastAPI, Supabase API, database functions, Realtime payloads, and Gemini output are each verified at their own boundary.
5. **Deny by default / fail closed.** No policy, no grant, no membership, no match means no access. Errors in authorization code deny the request.
6. **Least privilege.** Each role, key, function and connection has the minimum permission needed.
7. **Defense in depth.** Every sensitive operation is protected by at least two independent layers (for example RLS plus a guard trigger, or FastAPI authorization plus a database constraint).
8. **Nobody pays for food they did not claim.** Unclaimed items are never auto-distributed. Only an explicit, audited host action allocates them.
9. **Minimize data.** Collect, return, store, cache and log the least data necessary. Receipt images and UPI IDs are the highest-risk data Spliqo holds.
10. **Simplicity.** Prefer boring, idiomatic solutions. Do not add layers, patterns or dependencies without a concrete problem they solve.
11. **Honest verification.** Nothing is "verified" unless the check was actually run. Spliqo cannot verify that a UPI payment happened, and the UI MUST NOT imply that it can.

---

## 2. Architecture and Trust Boundaries

### 2.1 Two access paths

Every table, column, function and feature MUST be classified into exactly one path.

| Path        | Route                                                          | Enforcement point                                                         | Use for                                                                                                                                                                     |
| ----------- | -------------------------------------------------------------- | ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Direct**  | Flutter → Supabase (PostgREST/RPC/Realtime) as `authenticated` | RLS, column grants, guard triggers, definer functions, constraints        | Reads of session data by members; claiming and un-claiming items; the "Done Selecting" RPC                                                                                  |
| **Backend** | Flutter → FastAPI → Postgres                                   | FastAPI service layer, plus DB constraints and triggers as a second layer | Receipt parsing, session lifecycle, joining, host resolution, finalisation, every payment/settlement write, payment intent (UPI) generation, anything calling a third party |

**Decision rule.** A resource MUST use the Backend path if any of these is true: it touches `participant_settlements` or any payment state; it changes session status other than the auto-advance described in 3.3; it adds or removes participants; it writes `host_assigned` claims; it calls Gemini or any third party; it needs a secret; it needs multi-step atomic logic across tables. Otherwise Direct is allowed **only if** RLS plus guard triggers fully protect it.

**A table MUST NOT be reachable by both paths for writes.** Backend-write tables have no `INSERT/UPDATE/DELETE` grants for `anon` or `authenticated`.

### 2.2 Dependency direction

- Flutter: `presentation → state/providers → repositories/domain → data sources (FastAPI client, Supabase client)`. Widgets MUST NOT call HTTP, Supabase or storage directly. The allocation engine lives in `domain/allocation/` and imports no Flutter UI and no transport.
- FastAPI: `routers (transport) → services (business rules, authorization) → repositories (SQL) → database`. Routers MUST NOT contain SQL. Repositories MUST NOT make authorization decisions; they accept an already-authorized scope.
- Database: tables, then constraints, then RLS, then functions and triggers. No rule exists only in the UI.

### 2.3 Session isolation (the tenancy model)

Spliqo has no organisation tenant. **The session is the isolation boundary.**

- Every session-owned row (`bill_items`, `session_participants`, `item_claims`, `participant_settlements`, receipt objects) carries `session_id`, `NOT NULL`, indexed, and covered by a foreign key.
- Composite foreign keys MUST include `session_id` so a child cannot reference a parent in another session (for example a claim whose item and participant belong to different sessions).
- Access is by **membership**: a user can read a session only if they have a `session_participants` row in it. Membership is never inferred from a client-supplied parameter.
- Hosting is **per session**, not a global role. A user can host one session and participate in another.

---

## 3. Product Flow (Normative)

This section is the reference flow. The client, backend and database MUST implement it identically. Deviations require a change to this section first.

### 3.1 Flow summary (Model C: hybrid)

1. **Draft.** Host uploads a receipt. FastAPI parses it, stores a draft session and items. Host verifies and corrects items and adjustments, and invites participants.
2. **Active.** Participants claim items. Each sees a live **Estimated** share. Host sees everyone's progress.
3. **Individual completion.** A participant taps _Done Selecting_. Their claims freeze. Their amount stays provisional.
4. **Reviewing.** Once everyone is complete (or the host locks the room), the host sees a consolidated allocation preview, including unclaimed items. The host resolves every unclaimed item.
5. **Finalised.** FastAPI computes exact liabilities in one transaction. Amounts are immutable.
6. **Settlement.** Each participant chooses _Pay my share_ or _Let the host cover my share_. Payment state is tracked independently.

### 3.2 Independent per-participant states

Item selection, payment preference and payment status are **three independent dimensions**. They MUST NOT be merged into one status column or one enum.

| Dimension          | Values                                   | Stored as                                                   | Who writes                                                |
| ------------------ | ---------------------------------------- | ----------------------------------------------------------- | --------------------------------------------------------- |
| Item selection     | Not started / In progress / Completed    | `selection_completed_at` (null or time) and claim existence | `complete_my_selection` RPC (Direct); host lock (Backend) |
| Payment preference | `undecided` / `self_pay` / `host_pays`   | `participant_settlements.pay_preference`                    | Backend only                                              |
| Payment status     | `unpaid` / `pending` / `paid` / `waived` | `participant_settlements.pay_status`                        | Backend only                                              |

**In progress is derived, not stored.** A participant is _In progress_ when `selection_completed_at IS NULL` and they hold at least one claim. Storing it would force a write on first claim, and concurrent claim inserts would then contend on one participant row.

### 3.3 Session state machine

Statuses: `draft`, `active`, `reviewing`, `finalized`, `cancelled`. Transitions not listed are illegal and MUST be rejected by a database guard trigger as well as by the service layer.

| From                           | To          | Trigger                                                          | Path                                                  |
| ------------------------------ | ----------- | ---------------------------------------------------------------- | ----------------------------------------------------- |
| `draft`                        | `active`    | Host activates after reconciliation checks pass (4.2)            | Backend                                               |
| `active`                       | `reviewing` | Last participant completes (auto), or host locks the room        | Auto: inside `complete_my_selection`. Manual: Backend |
| `reviewing`                    | `active`    | Host reopens (only before finalisation)                          | Backend                                               |
| `reviewing`                    | `finalized` | Host finalises; zero unclaimed items; all participants completed | Backend                                               |
| `finalized`                    | `reviewing` | Host reopens, **only if** no settlement row has left `unpaid`    | Backend                                               |
| `draft`, `active`, `reviewing` | `cancelled` | Host cancels, or `expires_at` passes                             | Backend / scheduled job                               |

- `finalized` and `cancelled` sessions are immutable except for settlement progress on `finalized`.
- **Forced completion on host lock.** When the host locks the room, any participant not yet complete is marked complete with the claims they currently hold. The action is audited with `forced = true`.
- **Late joiners** may join only while the session is `active`. After `reviewing`, joining is rejected.
- **Auto-advance** runs inside the `complete_my_selection` function, under the lock order in 8.7, so two simultaneous completions cannot both miss the "everyone is done" condition.

### 3.4 Visibility rules

Each participant sees:

- Their own selections and their current **Estimated** share (before finalisation) or **Final** amount (after).
- For every other participant: display name and completed / not completed.
- For every item: who claimed it. This is required, because shared splits and the client estimate depend on the claimant count. It is a deliberate product decision, and the privacy notice MUST state it.
- Whether the host has finalised.

Only the participant and the host can see a participant's payment preference, payment status and final amount. The host sees all of them.

### 3.5 Host resolution of unclaimed items

In `reviewing`, the host MUST resolve every unclaimed item through one of three explicit bulk actions, each creating `host_assigned` claims through the Backend:

1. **Assign to a specific participant.**
2. **Split equally among all participants.**
3. **Host absorbs** (assign to the host's own participant row).

Participants cannot delete `host_assigned` claims. Finalisation fails with `409 unresolved_items` if any item has zero claims.

### 3.6 Settlement rules

- The host's own row is set to `paid` at finalisation. The host already paid the restaurant, and the row is excluded from "outstanding" totals.
- `pay_status` transitions:

| From      | To        | Actor                                                              |
| --------- | --------- | ------------------------------------------------------------------ |
| `unpaid`  | `pending` | Participant ("I have paid"), only with `pay_preference = self_pay` |
| `pending` | `paid`    | Host confirms                                                      |
| `pending` | `unpaid`  | Host rejects                                                       |
| `unpaid`  | `waived`  | Host confirms a `host_pays` request                                |

- A participant MUST NOT be able to set `paid` or `waived`. Only the host can.
- A participant who chooses `host_pays` stays `unpaid` until the host confirms. Until then the UI says "Waiting for host to confirm."
- "Settled" for a session is **computed** (every row is `paid` or `waived`), never stored.

---

## 4. Money and the Allocation Engine

### 4.1 Money rules

1. All amounts are `bigint` paise in Postgres, `int` paise in Dart, `int` paise in Python, and integer JSON numbers on the wire. Field names end in `_paise`.
2. Currency is INR only. `sessions.currency` exists and is constrained to `'INR'` so a later change is a deliberate migration.
3. Cap: `MAX_RECEIPT_TOTAL_PAISE = 10_000_000` (₹1,00,000). The cap guarantees that every intermediate product in the engine stays below 2^53, so the engine is exact on every Dart target including web. Raising the cap requires re-proving this bound.
4. A single formatter converts paise to display text (`en_IN` grouping, exactly two decimals). A single parser converts user text to paise by integer arithmetic on the digit string. No `double.parse`, `num.parse`, `toDouble`, or `float()` in the money path.
5. Engine operands are non-negative. Signed adjustments are handled by sign separation (4.3). Python `//` and Dart `~/` agree for non-negative operands, and that is the only domain they are used on.

### 4.2 Receipt reconciliation (checked at activation)

The session stores `subtotal_paise`, `tax_paise`, `service_charge_paise`, `discount_paise`, `round_off_paise` (signed) and `total_paise`. A database `CHECK` and the Backend both enforce:

```text
total_paise = subtotal_paise + tax_paise + service_charge_paise - discount_paise + round_off_paise
sum(bill_items.price_paise) = subtotal_paise
subtotal_paise >= 1  and  total_paise BETWEEN 1 AND MAX_RECEIPT_TOTAL_PAISE
```

A draft that fails any equation cannot be activated. The host fixes items or adjustments. The parser's own claimed totals are never trusted.

**Quantity lines.** A receipt line with quantity _n_ > 1 is expanded at parse time into _n_ unit rows. The line total is divided with `split_exact` (4.3) so unit prices sum exactly. This keeps "I had one of the two naans" expressible without a quantity model.

### 4.3 The allocation algorithm

Let **A** = `total_paise − subtotal_paise` (signed). A is the net of tax, service charge, discount and round-off. This is the brief's tax formula generalised to every adjustment.

1. **Item shares.** For each item with claimants _k_ ≥ 1, split `price_paise` among the claimants with `split_exact` using equal weights. Sum per participant to get `items_i`. After resolution, `Σ items_i = subtotal_paise`.
2. **Adjustment shares.** Split `|A|` across participants with `split_exact`, using weights `items_i`. Apply the sign of A.
3. **Final.** `final_i = items_i + adj_i`. Invariants, enforced by assertion on the server and by property tests on both sides:
   - `Σ final_i = total_paise` exactly.
   - `final_i ≥ 0` for every participant.
   - A participant with `items_i = 0` receives `adj_i = 0`.

**`split_exact` (Largest Remainder Method).** Given a non-negative integer `amount` and non-negative integer weights with `Σ w > 0`:

- For each key: `quota = amount × w`, `base = quota ÷ Σw` (floor), `rem = quota mod Σw`.
- `leftover = amount − Σ base`. Give one extra paisa to the `leftover` keys with the largest `rem`.
- **Tie-break is deterministic:** equal `rem` is resolved by ascending key, where keys are lowercase canonical UUID strings compared as plain strings. Dart and Python agree on this ordering for that alphabet.
- A weight-zero key never receives a paisa (its `rem` is zero, and at least `leftover` keys have `rem > 0`).

The reference implementation is in Appendix B.

### 4.4 Live estimate vs final

During `active`, the client shows an estimate, computed against the **receipt subtotal**, never against the sum of currently claimed items:

```text
adj_i_estimate = sign(A) × round_half_up( |A| × items_i / subtotal_paise )
estimate_i     = items_i + adj_i_estimate
```

Dividing by claimed items instead would make the first claimer carry 100% of the restaurant's tax until others join, producing jarring price drops. The estimate is allowed to differ from the final by a few paise and does not need to sum to the total. The UI labels it **Estimated** and shows "Subject to change as others finish."

Rules:

1. The estimate MUST NOT be sent to the server as an amount, MUST NOT build a payment intent, and MUST NOT be persisted.
2. After finalisation the client displays `final_amount_paise` from the server and does not recompute.
3. Unclaimed value is shown to the host as **Unallocated**, never folded into anyone's estimate.

### 4.5 One algorithm, two languages

The engine is a deliberate duplication: Dart for instant client estimates, Python for authoritative finalisation. It is the **only** sanctioned duplicate of business logic. To keep them identical:

1. Both implementations are pure functions with no I/O, clock, randomness or locale.
2. A shared fixture file `shared/allocation_vectors.json` holds input/expected-output vectors. **Both test suites load the same file.** CI fails if either diverges. Adding or changing a vector requires both suites to pass.
3. Property tests (Python with `hypothesis`, Dart with a randomised loop and fixed seeds) assert the invariants in 4.3 across random inputs, including: 1 to 30 participants, 1 to 200 items, shared items with up to 30 claimants, negative and positive A, and totals up to the cap.
4. Any change to rounding, tie-break or ordering is a **breaking change to money behaviour** and needs explicit approval and a vector update.

---

## 5. Authentication and Session Management

1. Identity is established only by a verified Supabase-issued JWT. FastAPI MUST verify signature (via the issuer's JWKS, cached with rotation), `iss`, `aud`, `exp` and `nbf`, and MUST pin accepted algorithms. `alg: none` and algorithm confusion MUST be rejected.
2. Authorization never reads `user_metadata`. It is user-editable. The user id (`sub`) is the only identity input, and everything else is looked up server-side.
3. Access tokens are short-lived and refresh tokens rotate. Sign-out invalidates the server session.
4. **Step-up authentication** is required for: changing the payout UPI ID, confirming `paid` or `waived` in bulk, deleting an account, exporting data.
5. Login, OTP, join and parse endpoints are rate limited per account and per IP, and return uniform responses to prevent enumeration.
6. **Invitations.** Invite tokens are random with at least 128 bits of entropy, stored only as a hash, expire, are revocable by the host, and are bound to one session. Joining is a Backend call that verifies the token, the session status (`active`), and the participant cap, then creates the participant row. A token is never usable after the session leaves `active`.
7. Deep links and redirects are exact-match allowlisted. A deep link never performs a privileged action by itself. Joining from a link still requires an authenticated user and a server check.
8. Guest participants (no account) are an open decision (Section 25). Until it is resolved, every participant MUST be an authenticated user.

---

## 6. Authorization

### 6.1 Model

Authorization is **per-session membership + object-level ownership**. There is no global role beyond "authenticated user".

| Per-session role | How it is granted                              | Powers                                                                                                                                                          |
| ---------------- | ---------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `host`           | Creating the session (exactly one per session) | Edit draft, activate, invite, lock, resolve unclaimed items, finalise, reopen, cancel, confirm or reject payments. Also claims own items as a participant.      |
| `participant`    | Joining via a valid invite                     | Read the session, claim and un-claim own items while active and not completed, complete own selection, choose own payment preference, mark own payment as sent. |

### 6.2 Authorization matrix (minimum)

| Action                            | Non-member | Participant                      | Host                |
| --------------------------------- | ---------- | -------------------------------- | ------------------- |
| Read session, items, claims       | No         | Own sessions only                | Yes                 |
| Read others' settlement rows      | No         | No                               | Yes                 |
| Insert/delete own `self` claim    | No         | While `active` and not completed | Same                |
| Complete own selection            | No         | Yes, once                        | Yes, once           |
| Write `host_assigned` claims      | No         | No                               | Yes, in `reviewing` |
| Finalise / reopen / lock / cancel | No         | No                               | Yes                 |
| Set `paid` / `waived`             | No         | **Never**                        | Yes                 |

### 6.3 Rules

1. Every service function authorizes the actor against the **specific object** (session id, participant id, item id). Checking "is logged in" is never sufficient. IDOR on any identifier is a defect.
2. The acting participant is derived from `(session_id, auth.uid())`, never from a client-supplied `participant_id` alone. If a client supplies `participant_id`, the server verifies it belongs to the caller.
3. Host actions verify `sessions.host_id = caller`. Host status is read from the database, never from a token claim or request field.
4. DTOs are allowlisted. Unknown fields are rejected. Privileged fields (`status`, `final_amount_paise`, `pay_status`, `source`, `host_id`) are never accepted from clients on routes that are not specifically their writer.

---

## 7. Input Validation and Server-Side Parity

### 7.1 The parity rule (non-negotiable)

**Every validation that exists on the client MUST exist on the server, and the server version is the authority.**

| Request path                | Authoritative validation location                                                 |
| --------------------------- | --------------------------------------------------------------------------------- |
| Backend (Flutter → FastAPI) | Pydantic strict models and service layer, **plus** DB constraints                 |
| Direct (Flutter → Supabase) | `CHECK`, `NOT NULL`, `UNIQUE`, FKs, enum types, guard triggers, definer functions |

Each client rule gets a row in the parity table (Appendix C). A client rule without a server counterpart is **High** by default. Limits come from one documented source (`shared/limits.json`, consumed by Dart, Python and migrations) so they cannot drift.

### 7.2 Limits (initial values, in `shared/limits.json`)

| Limit                               | Value                          |
| ----------------------------------- | ------------------------------ |
| Participants per session            | 30                             |
| Items per session (after expansion) | 200                            |
| Item name length                    | 1 to 80 characters             |
| Display name length                 | 1 to 40 characters             |
| Session title length                | 1 to 80 characters             |
| Item price                          | 1 to `MAX_RECEIPT_TOTAL_PAISE` |
| Receipt total                       | 1 to 10,000,000 paise          |
| Receipt image                       | 8 MB, JPEG/PNG/WEBP/HEIC       |
| Session lifetime                    | 30 days from creation          |

### 7.3 Validation rules

1. **Allowlist, not blocklist.** Validate type, length, range, format, charset.
2. **Canonicalize, then validate.** Normalize Unicode (NFC), trim, and reject control characters before checks.
3. **Bound everything.** Strings, arrays, request bodies, upload sizes, page sizes.
4. **Typed parsing.** UUID, enum, `datetime`, integer. Amounts arrive as integers only. A decimal point in a money field is a `422`.
5. **Parameterized queries only.** No string-built SQL in Python or PL/pgSQL.
6. **User text is data.** Item names and display names come from users or OCR. They are never rendered as markup and never concatenated into prompts, SQL or URLs without encoding.
7. **UPI identifiers** (VPA) are validated against an allowlist pattern server-side before storage.
8. **Idempotency.** `finalize`, `create session`, `parse`, `payment mark`, and `confirm` accept an `Idempotency-Key`, stored with a unique constraint and a response replay.
9. **Time** is `timestamptz` in UTC. Display converts to the device time zone.

### 7.4 File uploads (receipt images)

Verify size, extension **and** content type by magic bytes. Generate server-side object names (`receipts/<session_id>/<uuid>.<ext>`), never client filenames. Store in a **private** bucket with storage RLS limited to the host of that session. Serve only via short-lived signed URLs. **Strip EXIF/GPS** before storage. Apply per-user upload quotas. Re-encode the image server-side so a polyglot or malformed file cannot reach the parser.

---

## 8. Database Standards (Supabase / PostgreSQL)

### 8.1 Ownership and baseline

- All application objects are owned by `postgres` and created only through migrations.
- `anon` has **no** grants on application tables or functions.
- Start from `REVOKE ALL ON ALL TABLES/FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated`, then grant narrowly. `REVOKE CREATE ON SCHEMA public FROM PUBLIC`. Set default privileges so new objects do not inherit open grants.
- FastAPI connects with its **own least-privilege database role** (`spliqo_api`) that has only the table and function grants it needs. The Supabase `service_role` key is not used by default. If it is needed, it lives only in the backend secret store.
- Because the backend role may bypass RLS, **FastAPI MUST do its own authorization** (6.3). It MUST NOT assume RLS protects it.

### 8.2 Core schema (summary)

```sql
CREATE TYPE public.session_status AS ENUM ('draft','active','reviewing','finalized','cancelled');
CREATE TYPE public.participant_role AS ENUM ('host','participant');
CREATE TYPE public.claim_source AS ENUM ('self','host_assigned');
CREATE TYPE public.pay_preference AS ENUM ('undecided','self_pay','host_pays');
CREATE TYPE public.pay_status AS ENUM ('unpaid','pending','paid','waived');

CREATE TABLE public.sessions (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id              uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  title                text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 80),
  currency             char(3) NOT NULL DEFAULT 'INR' CHECK (currency = 'INR'),
  subtotal_paise       bigint NOT NULL CHECK (subtotal_paise >= 1),
  tax_paise            bigint NOT NULL DEFAULT 0 CHECK (tax_paise >= 0),
  service_charge_paise bigint NOT NULL DEFAULT 0 CHECK (service_charge_paise >= 0),
  discount_paise       bigint NOT NULL DEFAULT 0 CHECK (discount_paise >= 0),
  round_off_paise      bigint NOT NULL DEFAULT 0,
  total_paise          bigint NOT NULL CHECK (total_paise BETWEEN 1 AND 10000000),
  status               public.session_status NOT NULL DEFAULT 'draft',
  revision             integer NOT NULL DEFAULT 0,
  expires_at           timestamptz NOT NULL,
  finalized_at         timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT sessions_total_reconciles_chk CHECK (
    total_paise = subtotal_paise + tax_paise + service_charge_paise
                  - discount_paise + round_off_paise)
);

CREATE TABLE public.bill_items (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  position    integer NOT NULL CHECK (position >= 0),
  name        text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
  price_paise bigint NOT NULL CHECK (price_paise BETWEEN 1 AND 10000000),
  UNIQUE (session_id, id),
  UNIQUE (session_id, position)
);

CREATE TABLE public.session_participants (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id              uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  user_id                 uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  role                    public.participant_role NOT NULL DEFAULT 'participant',
  display_name            text NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 40),
  selection_completed_at  timestamptz,
  joined_at               timestamptz NOT NULL DEFAULT now(),
  UNIQUE (session_id, user_id),
  UNIQUE (session_id, id)
);
CREATE UNIQUE INDEX session_participants_one_host_key
  ON public.session_participants (session_id) WHERE role = 'host';

CREATE TABLE public.item_claims (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id     uuid NOT NULL,
  item_id        uuid NOT NULL,
  participant_id uuid NOT NULL,
  source         public.claim_source NOT NULL DEFAULT 'self',
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (item_id, participant_id),
  FOREIGN KEY (session_id, item_id)        REFERENCES public.bill_items (session_id, id) ON DELETE CASCADE,
  FOREIGN KEY (session_id, participant_id) REFERENCES public.session_participants (session_id, id) ON DELETE CASCADE
);

-- Backend-write only. Direct SELECT is limited to the owner and the host (8.3).
CREATE TABLE public.participant_settlements (
  participant_id     uuid PRIMARY KEY,
  session_id         uuid NOT NULL,
  final_amount_paise bigint CHECK (final_amount_paise >= 0),
  pay_preference     public.pay_preference NOT NULL DEFAULT 'undecided',
  pay_status         public.pay_status NOT NULL DEFAULT 'unpaid',
  updated_at         timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (session_id, participant_id) REFERENCES public.session_participants (session_id, id) ON DELETE CASCADE
);
```

Rules (in addition to the baseline table rules below): the host's payout UPI ID is stored in a separate **Backend-only** table, never in a client-readable table.

### 8.3 Table baseline and Row Level Security

Every table follows this baseline:

1. **RLS is `ENABLE`d and `FORCE`d on every table** in an exposed schema. A table without RLS is **Critical**.
2. Explicit `OWNER TO postgres`, explicit `REVOKE ALL ... FROM PUBLIC, anon, authenticated`, then minimal column-level grants.
3. UUID primary keys (`gen_random_uuid()`). Enumerations are enum types, not free text.
4. Constraints do the integrity work: `NOT NULL`, `CHECK`, `UNIQUE`, composite FKs, explicit `ON DELETE`.
5. `created_at` is immutable. `updated_at` is maintained by a trigger. Both are excluded from client write grants.

Policy rules:

1. **One policy per command per role. No `FOR ALL`.** Policies are `TO authenticated`. Never `TO public`.
2. `UPDATE` policies have **both** `USING` and `WITH CHECK`.
3. Wrap auth calls as `(select auth.uid())` so Postgres evaluates them once per statement.
4. Membership and ownership lookups go through **stable `SECURITY DEFINER` helpers** (`public.is_session_member(p_session_id)`, `public.is_open_participant(p_session_id, p_participant_id)`) to avoid recursive RLS.
5. Never use `user_metadata` in policies.
6. Client-exposed views MUST use `security_invoker = true`.
7. Every policy has a pgTAP test proving **allow** for the right actor and **deny** for: another user, a non-member, the wrong role, a completed participant, a non-active session, and `anon`.

**The claiming policies** (the one place the brief's draft needs care: the policy MUST bind the row to the caller, not just to a participant id, or any authenticated user could edit anyone's claims):

```sql
-- Members can read all claims in their session (required for shared splits).
CREATE POLICY item_claims_select_member ON public.item_claims
  FOR SELECT TO authenticated
  USING ( public.is_session_member(session_id) );

-- A participant may add only their own self-claims, only while active and not completed.
CREATE POLICY item_claims_insert_self ON public.item_claims
  FOR INSERT TO authenticated
  WITH CHECK ( source = 'self'
               AND public.is_open_participant(session_id, participant_id) );

-- ...and remove only their own self-claims under the same conditions.
CREATE POLICY item_claims_delete_self ON public.item_claims
  FOR DELETE TO authenticated
  USING ( source = 'self'
          AND public.is_open_participant(session_id, participant_id) );
-- No UPDATE policy and no UPDATE grant: claims are immutable.
```

`is_open_participant` returns true only when a `session_participants` row exists with `id = p_participant_id`, `session_id = p_session_id`, **`user_id = auth.uid()`**, `selection_completed_at IS NULL`, and the parent session has `status = 'active'`.

**Settlement read policy:** `participant_settlements` SELECT is allowed when the row's participant is the caller, or the caller is the session host. No write grants exist for `authenticated`.

**Participants table:** `authenticated` gets `SELECT` on non-payment columns for sessions they belong to, and **no** write grants. All writes go through the Backend or the `complete_my_selection` RPC.

### 8.4 Function standard (mandatory template)

Every function in an exposed or application schema follows this form:

```sql
CREATE OR REPLACE FUNCTION public.fn_name(p_arg uuid) RETURNS ...
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- 1. authenticate:  auth.uid() IS NOT NULL
  -- 2. authorize:     membership/ownership predicate for THIS row
  -- 3. validate:      every argument
  -- 4. lock:          in the order defined in 8.7
  -- 5. act:           schema-qualified, parameterized statements
END;
$$;
ALTER FUNCTION public.fn_name(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_name(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_name(uuid) TO authenticated;  -- only if client-callable
```

1. `SECURITY DEFINER` with a pinned `search_path` (`pg_temp` last) is **required**. A function without a pinned `search_path` is **Critical**.
2. Every object reference is schema-qualified.
3. Execute privileges are explicit. Trigger functions and helpers are not granted to client roles.
4. A definer function bypasses RLS, so it MUST perform its own authentication and authorization.
5. Validate every argument. Raise with explicit `ERRCODE` and non-revealing messages. Never echo table names, other users' ids or SQL.
6. No dynamic SQL built from input.
7. Accurate `STABLE`/`IMMUTABLE`/`VOLATILE` marking. Policy helpers are `STABLE`. Functions that lock rows are `VOLATILE`.
8. `COMMENT ON` states purpose, caller, and authorization contract.

### 8.5 The two Direct-path write mechanisms

1. **Claims** use RLS (8.3) plus a **guard trigger** `trg_guard_item_claim` (BEFORE INSERT/DELETE on `item_claims`, definer). For `source = 'self'` rows, it takes `FOR SHARE` locks on the session row and then the participant row (in that order) and re-checks `status = 'active'` and `selection_completed_at IS NULL`. RLS alone is not enough, because a policy sees only committed data and cannot take locks. The trigger closes the race between a claim insert and a simultaneous "Done Selecting".
2. **Completing a selection** is the RPC `public.complete_my_selection(p_session_id uuid)`. It authenticates, locks the session `FOR UPDATE`, then the caller's participant row `FOR UPDATE`, rejects if the session is not `active` or the row is already complete, sets `selection_completed_at = now()`, then counts incomplete participants **after taking the session lock**. If none remain, it sets `sessions.status = 'reviewing'`. Because the session lock serialises all completions, the last two simultaneous completers cannot both see the other as incomplete.

### 8.6 Migrations

1. Schema changes ship only as versioned, reviewed migration files. No manual dashboard edits.
2. Migrations are forward-only, idempotent where feasible, with a documented compensating plan.
3. Destructive changes need explicit approval and a verified backup.
4. A new table ships with RLS, FORCE RLS, grants, indexes, guard triggers and policy tests **in the same migration**.
5. Large-table changes use `CREATE INDEX CONCURRENTLY` and `NOT VALID` then `VALIDATE`.
6. A CI check fails the build if any table in an exposed schema lacks RLS/FORCE RLS, any function lacks `SECURITY DEFINER` plus a pinned `search_path`, or any policy uses `FOR ALL` (catalog queries on `pg_class`, `pg_proc`, `pg_policies`).

### 8.7 Transactions, locking and concurrency

- **Global lock order: `sessions` → `session_participants` → `item_claims`.** Every code path that locks more than one of these MUST acquire in this order. This applies to `complete_my_selection`, `trg_guard_item_claim`, finalisation, lock, reopen and cancel. Violating the order creates deadlocks.
- Finalisation runs in one transaction: `SELECT ... FOR UPDATE` on the session, verify `status = 'reviewing'`, verify all participants complete, verify zero unclaimed items, load items and claims in one set-based read, run `calculate_split`, write all `participant_settlements` rows, set `status = 'finalized'`, write the audit row. Any failure rolls back everything.
- Finalisation is **idempotent**: a repeat call on a finalised session returns the stored result and changes nothing.
- Uniqueness races are resolved by `UNIQUE` constraints, never check-then-insert. A claim toggled twice rapidly relies on `UNIQUE (item_id, participant_id)`.
- State changes use compare-and-set: `UPDATE ... WHERE id = $1 AND status = $2`, and the affected row count is checked.
- `sessions.revision` increments on every status or adjustment change. Draft edits use optimistic concurrency against it.
- Set `statement_timeout`, `lock_timeout` and `idle_in_transaction_session_timeout` per role.

### 8.8 Audit trail

Settlement and lifecycle actions write to an **append-only** audit table. Mandatory events: session activated, locked (with `forced`), reopened, cancelled, unclaimed item resolved (with method), finalised (with totals and participant count), payment marked pending, payment confirmed, payment rejected, payment waived, payout UPI ID changed, invite created and revoked, receipt parsed (with model id and validation outcome). Every row carries `actor_id`, `action`, `resource_type`, `resource_id`, `before_state`, `after_state`, `ip_address` (trusted proxy header), `trace_id`, `created_at` (server clock). Writers have `INSERT` only. Audit rows are written by FastAPI, not by the client. UPI IDs are hashed or masked in state diffs.

---

## 9. Realtime and Sync Standards

1. **Realtime is a hint, not the source of truth.** The client treats every `postgres_changes` event as an **invalidation signal** and re-reads through RLS. It does not patch local state from the event payload.
2. **Do not depend on DELETE payloads.** DELETE events carry little data and cannot be filtered by `session_id`, so un-claims can reach other subscribers as bare keys. The client handles a delete event by refetching the session's claims. Re-verify this behaviour against current Supabase documentation when upgrading the client library.
3. Subscribe per session: `item_claims` and `session_participants` filtered by `session_id` for INSERT/UPDATE, plus `sessions` (status) and `participant_settlements` (RLS limits rows to self and host). One channel per session screen. Unsubscribe on dispose. Do not leave channels open for sessions not on screen.
4. **Debounce** refetches (about 150 ms) so a burst of claims produces one re-read.
5. **Resync** on channel reconnect, app resume, and network recovery. After any gap, re-read the full session.
6. **Optimistic UI** for claim taps is allowed. On an RLS or trigger rejection, roll back and show a clear message ("Your selection is locked").
7. Because Realtime applies RLS per subscriber, session size is capped (7.2) and any new subscribed table is load-tested at the participant cap.
8. Clients MUST NOT receive or subscribe to rows outside their sessions. Test it.

---

## 10. Receipt Parsing (Gemini Vision) Standards

1. The model API key lives only in the backend secret store. It never reaches Flutter.
2. **Model output is untrusted input.** Parse with strict Pydantic models. Reject unknown fields, enforce the limits in 7.2, require integer paise (convert from decimal strings with integer arithmetic, never floats), and run the reconciliation in 4.2. Output that fails validation is a parse failure, not a draft.
3. **Receipt text is data, never instructions.** The prompt states that text in the image must not be followed as instructions. The response schema is enforced through structured output. Nothing from the receipt is concatenated into a later prompt, query or URL.
4. The parser never receives user PII. It receives only the image and a fixed prompt.
5. Every parse sets `needs_review = true`. The host MUST confirm items and adjustments before activation. Low-confidence or mismatched fields are flagged in the draft.
6. **Failure fallback.** On timeout, circuit-open, validation failure or quota exhaustion, the host can enter items manually. Parsing outages MUST NOT block the product.
7. Resilience: connect/read timeouts (initial target 30 s overall), bounded retries with backoff and jitter on idempotent calls only, a circuit breaker, a per-user and global rate limit, and a daily cost cap with alerting.
8. The stored raw model response is kept only for debugging, with a short retention (initial: 7 days) and no PII.
9. Receipt images are deleted on session `finalized` or `cancelled` plus a short grace period (initial: 30 days), or earlier on host request.
10. Model id and prompt version are recorded on the session for auditability. Changing the model or prompt requires a regression run over a fixed receipt test set with an accuracy threshold.

---

## 11. Payments and Settlement Standards

1. **Spliqo never holds, receives or moves funds.** Payment is a hand-off to the participant's own UPI app. No card data, no bank account numbers, no payment gateway. _(When built)_: adding a gateway requires server-authoritative amounts, signed webhook verification, idempotency, reconciliation, and a threat-model review before launch.
2. **Server builds the payment intent.** `GET /v1/sessions/{id}/payment-intent` returns the `upi://pay` URI. The client launches it and never assembles it.
   - Allowed only when the session is `finalized`, the caller is a non-host participant, `pay_preference = self_pay`, and `pay_status = unpaid`.
   - The amount is the stored `final_amount_paise`, formatted from integer paise (`f"{p // 100}.{p % 100:02d}"`).
   - `pa` is the host's validated VPA, `pn` is percent-encoded, `cu=INR`, and `tn` is a short fixed note. Every parameter is encoded. Nothing client-supplied is interpolated.
3. The host's VPA is returned **only** inside a payment intent to eligible participants of that finalised session. It is never exposed in a readable table, a list endpoint, a log or a notification.
4. **Spliqo cannot confirm a UPI payment happened.** `pending` means "participant says they paid." Only the host's confirmation produces `paid`. The UI wording MUST reflect this ("Mark as paid", "Waiting for host to confirm"), never "Payment successful."
5. If no UPI app can handle the intent, the UI shows the amount and the host's identity with a copy action. No silent failure.
6. `host_pays` requests and all confirmations are audited (8.8). Reversing a confirmed `paid` or `waived` is a separate, audited host action with step-up auth. It is not an ordinary state edit.
7. Payment reminders and notifications contain no amounts or item names. They carry a pointer, and the app fetches details after authentication.

---

## 12. Data Classification, Retention and Privacy

### 12.1 Classification

| Class            | Examples                                                                              | Handling                                                                               |
| ---------------- | ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| **Restricted**   | Auth tokens, signing keys, API keys, DB credentials                                   | Secure storage or secret manager only. Never logged. Never in the repo.                |
| **Confidential** | Host UPI ID, phone number/email, receipt images, per-person amounts, payment statuses | Backend-only or RLS-limited. Encrypted at rest. Never logged in full. Short retention. |
| **Internal**     | Session titles, item names, claim state, display names                                | Visible to session members only.                                                       |
| **Public**       | App marketing content                                                                 | No restriction.                                                                        |

The host UPI ID is Confidential and SHOULD be encrypted at the application level in the backend-only table, with the key outside the database.

### 12.2 Retention and deletion

1. Receipt images: see 10.9. Raw parse output: 7 days.
2. Finalised session data is retained for a documented period (initial proposal: 2 years, or until all members delete their accounts), then deleted or anonymised.
3. Account deletion removes or anonymises the user's participant rows, display names and payout details across the database, storage, logs and backups per policy. Settlement history needed by other members is retained with the deleted user shown as "Former member".
4. Provide data export and deletion workflows consistent with applicable Indian data-protection law (for example the DPDP Act, 2023).
5. Collect only what a feature needs, with a documented purpose. A privacy notice states that claims are visible to session members (3.4).

### 12.3 Incident response

Documented severity levels, an owner, containment steps (revoke sessions, rotate keys, disable an endpoint or feature flag, revoke invite tokens), evidence preservation, user notification requirements, and a post-incident review.

---

## 13. FastAPI Backend Standards

### 13.1 Structure

```text
backend/
  app/
    main.py            # app factory, middleware, router registration
    config.py          # typed settings from environment, validated at startup
    api/v1/            # routers: sessions.py, items.py, participants.py, payments.py ...
    services/          # business rules and authorization
    repositories/      # SQL only
    domain/allocation.py   # pure engine (Appendix B)
    schemas/           # Pydantic request/response DTOs
    integrations/      # gemini.py, storage.py (wrapped in circuit breakers)
    core/              # security (JWT), errors, logging, idempotency, rate limit
  tests/
```

### 13.2 Middleware order (outermost first)

1. Request id and trace id. 2. Panic/exception handler mapping to the error envelope. 3. Security headers. 4. Request body size limit. 5. Timeout. 6. Rate limiting. 7. Authentication (JWT). 8. Idempotency (mutations). Authorization is **not** middleware. It happens in services, against the specific object.

CORS is disabled by default. Enable it only for explicitly allowlisted origins if a browser client is ever added.

### 13.3 Handler and service rules

1. Routers validate input through Pydantic strict models, call exactly one service function, and map results to response DTOs. They contain no SQL and no business rules.
2. Identity comes from the verified token only. Session membership and host status are looked up in the database for the specific session.
3. Response DTOs are explicit. Never serialize ORM or database rows directly.
4. Endpoints that can be retried accept `Idempotency-Key`.
5. Async all the way: no blocking calls on the event loop. Database access uses an async driver with a bounded pool. CPU-heavy work (image re-encoding) runs in a worker thread or process pool with a size cap.

### 13.4 Database access

1. Parameterized queries only. No f-strings in SQL.
2. Explicit transactions for multi-statement operations, with the lock order in 8.7.
3. Pool size, `statement_timeout` and `lock_timeout` are configured. Every query is bounded (`LIMIT`) and keyset-paginated where lists can grow.
4. Repositories take an already-authorized scope and make no authorization decisions.

### 13.5 Errors, logging and responses

Errors map to the envelope in Section 14. Logs are structured JSON with `request_id`, `trace_id`, route, status, latency and actor id. Logs never contain tokens, UPI IDs, phone numbers, image URLs, receipt text, or full request bodies.

### 13.6 Outbound calls

Every outbound call (Gemini, storage) has connect and read timeouts, bounded retries with jitter (idempotent calls only), a circuit breaker, and response size limits. No outbound call accepts a URL from user input (SSRF).

### 13.7 Lifecycle

Graceful shutdown drains in-flight requests. Startup fails fast on invalid configuration. A scheduled job expires sessions past `expires_at`, deletes stale receipts, and purges expired idempotency keys and invite tokens.

---

## 14. API Contract and Error Model

1. APIs are versioned (`/v1/...`). Breaking changes require a new version.
2. FastAPI generates the OpenAPI spec. The exported `openapi.json` is **committed**. Dart models and clients are generated from it. A CI step regenerates the spec and fails on any diff from the committed file ("zero drift"). Hand-edited generated files are rejected.
3. **Standard error envelope:**

```json
{
  "error": {
    "code": "unresolved_items",
    "message": "Request could not be processed.",
    "fields": [{ "field": "items", "reason": "unclaimed" }],
    "request_id": "..."
  }
}
```

1. Codes are a closed, documented set. Mapping: `400` malformed, `401` unauthenticated, `403` forbidden, `404` not found (also used to hide existence), `409` conflict (illegal state transition, `unresolved_items`, stale `revision`), `422` validation, `429` rate limit (with `Retry-After`), `5xx` generic only.
2. Errors never include SQL, stack traces, table or column names, internal ids, or hints about whether a protected resource exists.
3. Responses return only the fields the caller needs. Amounts are integer `_paise` fields. Timestamps are RFC 3339 UTC. IDs are UUID strings. Enums are strict and unknown values are rejected.
4. Mutations return the resulting resource or a minimal acknowledgement and are idempotent where retried.
5. Pagination is keyset-based with opaque cursors.

---

## 15. Flutter Client Standards

### 15.1 Architecture

- Keep one state-management approach for the whole app. Do not switch frameworks without a written justification.
- Layers: presentation → state → repositories → data sources. Widgets contain no networking, no SQL-shaped logic, and no business rules beyond UX validation.
- Immutable, typed models (`freezed`/`json_serializable` or equivalent). No `dynamic` or `Map<String, dynamic>` past the data layer.
- Dependency injection at the composition root.
- Strict analysis: `strict-casts`, `strict-inference`, `strict-raw-types` and a maintained lint set enforced in CI. No `// ignore` without a comment.
- **Allocation engine** in `domain/allocation/` is pure Dart with no Flutter or I/O imports, mirrors Appendix B, and passes the shared vectors (4.5).

### 15.2 Client security (the client is untrusted and observable)

1. **No secrets in the app.** The Supabase `anon` key is public by design and is safe only because of RLS and grants. No service-role key, API secret, Gemini key, or signing key in code, assets, `--dart-define` or build config.
2. Tokens live in platform secure storage behind one `SecureStore` interface. Never `SharedPreferences` or plain files for tokens or Confidential data.
3. HTTPS only. Android `usesCleartextTraffic=false`, iOS ATS on. Never disable certificate validation, including in builds shipped to users. Evaluate certificate pinning for the FastAPI host with a rotation-safe backup pin.
4. Release hardening: `--obfuscate --split-debug-info`, strip logs, no debug banners or dev menus, no test endpoints. Android `allowBackup=false`, no debuggable flag. Obfuscation is friction, not protection.
5. Deep links: validate against an exact allowlist, treat parameters as untrusted, never perform privileged actions from a link alone.
6. Logging: no tokens, UPI IDs, phone numbers, or receipt contents in logs or crash reports.
7. Camera and photo permissions are requested at the point of use with a clear purpose string. Images are not retained on the device after upload unless the user saves them.
8. Local biometric gates are UX only and never replace server authentication.
9. Handle session expiry centrally: one interceptor performs one refresh attempt, then signs out cleanly.

### 15.3 Money UX rules

1. Every pre-finalisation amount is labelled **Estimated**. Every post-finalisation amount is labelled **Final**. The two are never shown with the same label or styling.
2. A single formatter produces all displayed amounts. No ad-hoc string interpolation of paise.
3. The payment button is enabled only when the server has returned a `final_amount_paise` and `pay_status = unpaid`. It launches the server-built intent and never builds a URI.
4. Estimates and unallocated amounts are shown with clear copy. The host's preview separates **Allocated**, **Unallocated** and **Adjustments** (tax, service, discount, round-off).
5. After "Done Selecting" the checkboxes freeze visibly, with copy explaining why. The share continues to update reactively as others finish.

### 15.4 Networking and resilience

- One configured HTTP client with timeouts, cancellation, bounded retries with backoff and jitter for **idempotent** requests only, and idempotency keys for retried mutations.
- Typed error mapping from the envelope to domain failures. Users see actionable messages, never raw exceptions.
- Prevent double-submit with a disabled button, an in-flight guard and server idempotency.
- Offline: reading cached session data is allowed and clearly marked stale. Claiming, completing, finalising and payments **require connectivity**. Queued writes are never replayed after a state change, and the server rejects them anyway.

### 15.5 Cross-platform, responsive, accessible

- Maintain a platform capability matrix for secure storage, camera/photo picking, deep links, URL launching (UPI intent), notifications, clipboard and permissions. The UPI intent depends on UPI apps being installed, so each platform has an explicit fallback (5 in Section 11).
- Adaptive layouts with breakpoints. Respect text scale and reduce-motion.
- `Semantics` labels on non-text controls, minimum 48×48 dp tap targets, WCAG AA contrast.
- Item and participant status MUST NOT rely on colour alone.
- Localization via `intl`/ARB. No hard-coded user-facing strings in widgets. Amounts use `en_IN` grouping.

---

## 16. Performance Standards

### 16.1 Rules

1. No N+1 queries and no unbounded results. Session load is a bounded number of set-based queries (target: session, items, participants, claims, settlement).
2. Policy predicates are index-friendly. Required indexes include `item_claims (session_id)`, `item_claims (participant_id)`, `session_participants (session_id, user_id)`, `bill_items (session_id)`.
3. The client engine runs on the UI thread only because inputs are bounded (≤ 200 items × ≤ 30 participants). Recomputation is memoised on a claims revision and not run per frame.
4. Never `SELECT *` in hot paths. Use explicit column lists.
5. Image upload is compressed on the client (size and dimension caps) before sending.

### 16.2 Initial budgets (to be revised after measurement)

| Operation                                   | Budget                        |
| ------------------------------------------- | ----------------------------- |
| Claim tap → local UI update                 | Same frame (no network wait)  |
| Claim insert round trip                     | p95 < 300 ms                  |
| Realtime propagation to another participant | p95 < 1 s                     |
| Session load (cold)                         | p95 < 500 ms server time      |
| `finalize` at 30 participants / 200 items   | p95 < 500 ms                  |
| Receipt parse (end to end)                  | p95 < 15 s, hard timeout 30 s |
| Flutter frame build in claiming screen      | Under 16 ms in profile mode   |

Budgets are enforced by query plan checks, `k6` load tests against the participant and item caps, and Flutter profile-mode metrics.

---

## 17. Reliability Standards

1. Every outbound dependency has a timeout, a circuit breaker and a defined degraded behaviour (parser down → manual entry).
2. Mutations that can be retried are idempotent. A retried `finalize` or confirmation never double-applies.
3. Health endpoints: `/healthz` (process up) and `/readyz` (database reachable, dependencies configured).
4. Backups and restore are tested. The recovery objective for settlement data is documented.
5. Feature flags allow disabling parsing, joining and payment-intent generation independently during an incident.
6. Clock-dependent behaviour (expiry) uses the database or server clock only, never the client clock.

---

## 18. Observability and Privacy-Safe Logging

1. Structured logs with `request_id`, `trace_id`, route, status and latency.
2. Metrics: parse success/failure rate and latency, finalise latency, claim rejection rate (by cause), Realtime reconnects, forced completions, unresolved-item finalise rejections, payment confirm latency.
3. Alerts: sustained parse failure, Gemini cost anomaly, spike in `403`/`409`, any finalise invariant failure (`Σ final ≠ total`), unusual join or invite volume.
4. **A finalise invariant failure is a page-worthy event.** The transaction aborts, nothing is written, and the failing inputs are captured in a redacted form for reproduction.
5. Never log tokens, UPI IDs, phone numbers, receipt images or text, or full request and response bodies.

---

## 19. Secrets and Configuration

1. Secrets live in a secret manager or CI secret store. Never in the repo, images, logs, or client builds.
2. Configuration is typed and validated at startup. Missing or invalid values stop the process.
3. Separate credentials for dev, staging and production. Rotate on a schedule and immediately on suspicion.
4. A secret scanner runs in CI and pre-commit. A secret in a diff blocks the merge, and the secret is rotated even if the commit is reverted.
5. The Gemini key, database credentials, JWT verification config and encryption keys each have an owner and a rotation procedure.

---

## 20. Supply Chain and CI

1. Dependencies are pinned and locked (`pubspec.lock`, `uv.lock`/`poetry.lock`/`requirements` with hashes). New dependencies need a stated reason, a maintenance check and a licence check.
2. Scanners in CI: `pip-audit`, `bandit`, `ruff`, `mypy --strict` for Python; `dart analyze`, `dart pub outdated` for Dart; a secret scanner; container image scan.
3. Docker images for FastAPI are multi-stage, non-root, base image pinned by digest, with a `.dockerignore`, a minimal runtime image, and `/healthz` plus `/readyz`.
4. Build artifacts are reproducible where practical. Releases tag a commit, and the SBOM is generated and stored.
5. **Required checks to merge:** format, lint, type-check, unit and property tests (including shared allocation vectors), pgTAP, OpenAPI zero-drift, secret scan, dependency audit, migration lint (8.6.6), coverage thresholds, and platform builds for touched targets.
6. Branch policy: protected main, required review, no direct pushes, squash or rebase merges with meaningful messages.

---

## 21. Testing and Release Gates

### 21.1 Required test types

| Layer       | Tests                                                                                                                                                                                                                                                                                                  |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| SQL/RLS     | pgTAP: for every table and function, **allow** for the right actor and **deny** for another user, a non-member, a completed participant, a non-active session, and `anon`. Column-grant tests. Constraint tests, including the reconciliation `CHECK`. Guard-trigger tests. Illegal state transitions. |
| Concurrency | Two simultaneous `complete_my_selection` calls (exactly one auto-advance). Claim insert racing a completion (claim either lands before completion or is rejected, never after). Duplicate claim taps. Concurrent finalise calls (one wins, one replays). Lock-order deadlock test under load.          |
| Engine      | Shared vectors on both languages. Property tests for every invariant in 4.3. Edge cases: one participant, shared items with remainders, negative A, A = 0, cap-sized totals, a participant with zero items, ties.                                                                                      |
| Python      | Table-driven unit tests, authorization matrix per endpoint (role × membership × object), Pydantic boundary tests, idempotency replay, circuit-breaker states, integration tests against a real Postgres with RLS on.                                                                                   |
| Parser      | A fixed receipt test set with an accuracy threshold, prompt-injection receipts, malformed model output, timeout and quota paths, reconciliation failures.                                                                                                                                              |
| Flutter     | Unit tests for logic and parsing, widget tests for every state (loading, empty, error, locked, partial), golden tests for money screens, integration tests for join → claim → done → finalise → pay, accessibility checks.                                                                             |
| Contract    | OpenAPI zero-drift. Error-envelope mapping tests.                                                                                                                                                                                                                                                      |
| Security    | IDOR/BOLA on every id, mass assignment of privileged fields, forged `participant_id`, invite replay and expiry, JWT tampering, rate-limit tests, upload abuse, Realtime subscription to a foreign session, UPI parameter injection.                                                                    |

Tests assert **outcomes** (data was or was not exposed, row was or was not changed), not implementation details. A test that always passes is a defect.

### 21.2 Gates

1. Format, analysis, lint and security scanners clean (or each exception justified in writing).
2. All tests pass, including the shared allocation vectors on both sides.
3. No new table without RLS + FORCE RLS + explicit grants + policy tests. No new function without the 8.4 template.
4. Parity table updated for any new client validation.
5. No secrets in the diff and no unreviewed dependency.
6. Migration reviewed with a forward-fix plan.
7. Coverage: Python services and engine ≥ 85%, Flutter feature logic ≥ 70%, engine branches 100%.
8. **Critical/High** findings are fixed or have an owned, dated risk acceptance.

### 21.3 Release verification

Smoke test on every supported platform for sign-in, join via link, claiming, Done Selecting, host resolution, finalise, UPI hand-off with and without a UPI app, and error handling. A threat-model review precedes launch of any new money-affecting capability.

---

## 22. Code Hygiene and Conventions

1. **One concept, one name** across Dart, Python and SQL: `session`, `participant`, `claim`, `item`, `settlement`, `host`. Not `bill`/`group`/`split` interchangeably.
2. Naming: SQL `snake_case`, plural tables, `<entity>_id` foreign keys, `<event>_at` timestamps, `is_`/`has_` booleans, money columns `_paise`, policies `<table>_<command>_<actor>`, functions `verb_noun`, trigger functions `trg_` prefix, function arguments `p_` prefix. JSON is `snake_case`, and Dart models map explicitly. Dart money fields end in `Paise`.
3. No duplicated logic, except the sanctioned allocation engine pair (4.5). Search before adding a helper.
4. No dead code, unused dependencies, or commented-out code. `TODO(<owner or ticket>): <action>` format only.
5. Explicit return types on public Dart APIs, named parameters for more than two arguments, no positional booleans. Python is fully type-annotated and passes `mypy --strict`.
6. Comments explain **why**, constraints and invariants. Security- and money-critical code carries a short `SECURITY:` or `MONEY:` comment naming the invariant (for example "MONEY: integer paise only; Σ final must equal total").
7. Formatting is automatic and enforced in CI: `dart format`, `ruff format`, a SQL formatter. Style is not debated in review.
8. Significant decisions are recorded as short ADRs. Changes to allocation, rounding, tie-break or the state machine require one.

---

## 23. Handling Built vs. Unbuilt Features

1. Audit and correct only implemented code. Classify each feature as BUILT / PARTIAL / STUB / ABSENT.
2. Do not build, scaffold or design features listed below under this document. Do not add speculative abstractions "for later".
3. A stub may still be a risk today (exposed routes, permissive grants, placeholder secrets). Report and fix real risks.
4. When built code depends on an unbuilt feature's future shape, choose the simplest secure behaviour now and record the assumption.
5. **Out of scope until explicitly adopted:** payment gateway or in-app payments, multi-currency, recurring or group-wide running balances, post-finalisation adjustments, chat, itemised tip handling, push notification content, web client.
6. _(When built)_ Notifications: pointer-only content (11.7), per-user opt-out, rate limits. Post-finalisation corrections: an append-only adjustment record, never an edit of `final_amount_paise`.

---

## 24. Review Checklists

### 24.1 Pull request checklist

- [ ] Preserves intended behaviour and the flow in Section 3 (or the change is approved and Section 3 updated).
- [ ] Money path uses integer paise only. No floats, `double`, `num` or decimal parsing.
- [ ] Allocation, rounding or tie-break changes: shared vectors updated, both suites pass, ADR written.
- [ ] Every client validation has a server equivalent and a test (parity table updated).
- [ ] Identity comes from the verified token. Membership and host status come from the database.
- [ ] Object-level authorization on every identifier (no IDOR). A client-supplied `participant_id` is verified to belong to the caller.
- [ ] DTOs allowlisted, unknown fields rejected, privileged fields not writable.
- [ ] SQL is parameterized. No dynamic SQL from input.
- [ ] New or changed tables: RLS enabled and forced, owner set, minimal column grants, one policy per command, `USING` and `WITH CHECK` on updates, composite FKs include `session_id`, indexes added.
- [ ] New or changed functions: definer, pinned `search_path`, owner `postgres`, schema-qualified, explicit `REVOKE`/`GRANT`, internal authorization, input validation.
- [ ] Multi-table locking follows the order `sessions → session_participants → item_claims`.
- [ ] State transitions match 3.3 and are enforced in the service **and** a database guard.
- [ ] Payment state changes are Backend-only, audited, and idempotent. A participant cannot set `paid` or `waived`.
- [ ] Gemini output validated and reconciled. Receipt text never reaches a prompt, query or URL.
- [ ] Errors use the standard envelope with no internal detail.
- [ ] No N+1, no unbounded results, keyset pagination where lists grow.
- [ ] Timeouts, cancellation, circuit breakers and idempotency on I/O and retried mutations.
- [ ] Realtime handlers treat events as invalidation signals, resync on reconnect, and unsubscribe on dispose.
- [ ] Flutter: no secrets, secure storage, no networking in widgets, estimates labelled **Estimated**, payment intent comes from the server, resources disposed, accessible and responsive.
- [ ] OpenAPI export regenerated and committed. Zero-drift passes.
- [ ] Logs contain no tokens, UPI IDs, phone numbers or receipt data.
- [ ] Tests assert allow **and** deny paths. Gates pass and coverage thresholds are met.
- [ ] Assumptions about unbuilt features are recorded, and nothing was built for them.

### 24.2 Severity scale

| Severity          | Meaning (examples)                                                                                                                                                                                                                                                                                         |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Critical**      | Money computed with floats or amounts that do not sum to the total; missing RLS; definer function without a pinned `search_path`; exposed API or service key; participant able to set `paid`/`waived`; host UPI ID readable by non-eligible users; auth bypass                                             |
| **High**          | Claim policy not bound to the caller (edit another's claims); missing server-side validation for a client rule; IDOR on a session, participant or item; client-built payment intent; unclaimed items auto-distributed; missing guard on a state transition; client estimate persisted or sent as an amount |
| **Medium**        | Missing rate limit, missing idempotency on a retried mutation, lock-order violation, unbounded query, N+1 on a hot path, parse output not reconciled, missing audit event                                                                                                                                  |
| **Low**           | Hardening gap with limited impact, missing audit detail                                                                                                                                                                                                                                                    |
| **Informational** | Maintainability and style observations                                                                                                                                                                                                                                                                     |

---

## 25. Open Decisions

These are unresolved product or architecture questions. Until each is decided, the stated default applies.

| #   | Question                                                                         | Default until decided                                                                                |
| --- | -------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| 1   | Guest participants without an account (anonymous sign-in, or phone-only)?        | Every participant must be an authenticated user.                                                     |
| 2   | Rate-limit store shared across backend instances (Postgres counters or a cache)? | Run a single backend instance; do not rely on per-process limits for abuse control across instances. |
| 3   | How are corrections handled after finalisation and payment activity?             | Reopen only while no settlement row has left `unpaid`; otherwise out of scope (Section 23).          |
| 4   | Should others' item claims remain visible after finalisation?                    | Yes, to members, per 3.4.                                                                            |
| 5   | Retention period for finalised sessions                                          | 2 years proposed (12.2). Needs a policy owner.                                                       |
| 6   | Supported Flutter targets (mobile only, or desktop/web)?                         | Engine bound (4.1.3) is valid on all Dart targets, so no constraint yet.                             |

---

## Appendix A. Migration Template (guarded Direct-path table)

```sql
-- Helper: stable, definer. Used by RLS so policies stay non-recursive.
CREATE OR REPLACE FUNCTION public.is_open_participant(p_session_id uuid, p_participant_id uuid)
RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.session_participants sp
    JOIN public.sessions s ON s.id = sp.session_id
    WHERE sp.id = p_participant_id
      AND sp.session_id = p_session_id
      AND sp.user_id = (select auth.uid())          -- SECURITY: bind to the caller
      AND sp.selection_completed_at IS NULL
      AND s.status = 'active'
  );
$$;
ALTER FUNCTION public.is_open_participant(uuid, uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.is_open_participant(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_open_participant(uuid, uuid) TO authenticated;

-- Guard trigger: serialises claims against completion and locking.
CREATE OR REPLACE FUNCTION public.trg_guard_item_claim() RETURNS trigger
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_row     public.item_claims;
  v_status  public.session_status;
  v_done    timestamptz;
BEGIN
  v_row := CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  IF v_row.source <> 'self' THEN
    RETURN v_row;                       -- host_assigned rows are written by the Backend
  END IF;

  -- Lock order: sessions -> session_participants (Section 8.7)
  SELECT s.status INTO v_status
    FROM public.sessions s WHERE s.id = v_row.session_id FOR SHARE;
  SELECT sp.selection_completed_at INTO v_done
    FROM public.session_participants sp WHERE sp.id = v_row.participant_id FOR SHARE;

  IF v_status IS DISTINCT FROM 'active' OR v_done IS NOT NULL THEN
    RAISE EXCEPTION 'selection_locked' USING ERRCODE = 'P0001';
  END IF;
  RETURN v_row;
END;
$$;
ALTER FUNCTION public.trg_guard_item_claim() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.trg_guard_item_claim() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER item_claims_guard_trg
  BEFORE INSERT OR DELETE ON public.item_claims
  FOR EACH ROW EXECUTE FUNCTION public.trg_guard_item_claim();

ALTER TABLE public.item_claims OWNER TO postgres;
ALTER TABLE public.item_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE ONLY public.item_claims FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.item_claims FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.item_claims TO authenticated;
GRANT INSERT (session_id, item_id, participant_id, source) ON public.item_claims TO authenticated;
GRANT DELETE ON public.item_claims TO authenticated;
-- policies: Section 8.3 (select_member, insert_self, delete_self)

CREATE INDEX item_claims_session_idx     ON public.item_claims (session_id);
CREATE INDEX item_claims_participant_idx ON public.item_claims (participant_id);
-- pgTAP tests ship in the same migration: allow/deny matrix from 21.1.
```

---

## Appendix B. Allocation Engine Reference (Python) and Golden Vector

```python
MAX_RECEIPT_TOTAL_PAISE = 10_000_000


def split_exact(amount: int, weights: dict[str, int]) -> dict[str, int]:
    """Largest Remainder split of a non-negative integer. Keys are lowercase UUID strings."""
    total_w = sum(weights.values())
    if amount < 0 or total_w <= 0 or any(w < 0 for w in weights.values()):
        raise ValueError("invalid_split_input")
    base: dict[str, int] = {}
    rem: dict[str, int] = {}
    for key, w in weights.items():
        base[key], rem[key] = divmod(amount * w, total_w)
    leftover = amount - sum(base.values())
    for key in sorted(weights, key=lambda k: (-rem[k], k))[:leftover]:
        base[key] += 1
    return base


def calculate_split(
    items: dict[str, int],              # item_id -> price_paise
    claims: dict[str, list[str]],       # item_id -> participant_ids (unique)
    participants: list[str],
    subtotal_paise: int,
    total_paise: int,
) -> dict[str, int]:
    """Authoritative final amounts. Raises if any invariant fails."""
    if sum(items.values()) != subtotal_paise or subtotal_paise < 1:
        raise ValueError("items_do_not_match_subtotal")
    if not 1 <= total_paise <= MAX_RECEIPT_TOTAL_PAISE:
        raise ValueError("total_out_of_range")

    items_total = {p: 0 for p in participants}
    for item_id, price in items.items():
        claimants = claims.get(item_id, [])
        if not claimants:
            raise ValueError("unclaimed_item")          # host must resolve first
        for p, share in split_exact(price, {p: 1 for p in claimants}).items():
            items_total[p] += share

    adjustment = total_paise - subtotal_paise           # signed: tax + service - discount + round-off
    adj = split_exact(abs(adjustment), items_total)
    sign = -1 if adjustment < 0 else 1
    final = {p: items_total[p] + sign * adj[p] for p in participants}

    assert sum(final.values()) == total_paise, "sum_invariant_failed"
    assert all(v >= 0 for v in final.values()), "negative_share"
    return final


def estimate_share(items_paise: int, subtotal_paise: int, total_paise: int) -> int:
    """Live estimate for one participant. Mirrors the Dart implementation."""
    adjustment = total_paise - subtotal_paise
    a = abs(adjustment)
    adj = (a * items_paise + subtotal_paise // 2) // subtotal_paise
    return items_paise + (adj if adjustment >= 0 else -adj)
```

Dart signatures (same algorithm, same tie-break, no I/O):

```dart
/// Mirrors backend/app/domain/allocation.py. Validated by shared/allocation_vectors.json.
Map<String, int> splitExact(int amount, Map<String, int> weights);
int estimateSharePaise({required int itemsPaise, required int subtotalPaise, required int totalPaise});
```

**Golden vector #1.** One ₹100.00 item shared by three people, ₹5.00 net tax.

```json
{
  "name": "shared_item_three_way_with_tax",
  "items": { "i1": 10000 },
  "claims": { "i1": ["a", "b", "c"] },
  "participants": ["a", "b", "c"],
  "subtotal_paise": 10000,
  "total_paise": 10500,
  "expected_final": { "a": 3501, "b": 3500, "c": 3499 }
}
```

Derivation: item split `10000 / 3` leaves 1 paisa, tie broken to `a` (3334, 3333, 3333). Adjustment 500 split by those weights leaves 2 paise, which go to `a` (largest remainder) then `b` (tie-break), giving 167, 167, 166. Final amounts sum to 10500. (Test keys here are shortened for readability. Real vectors use full lowercase UUIDs.)

---

## Appendix C. Server-Side Validation Parity Table (template)

| Client rule                    | Server enforcement (file/migration)                                    | Test              |
| ------------------------------ | ---------------------------------------------------------------------- | ----------------- |
| Item name 1 to 80 characters   | `CHECK (char_length(name) BETWEEN 1 AND 80)`; Pydantic `max_length=80` | pgTAP + pytest    |
| Price is a positive integer    | `CHECK (price_paise BETWEEN 1 AND 10000000)`; Pydantic `StrictInt`     | pgTAP + pytest    |
| Cannot claim after Done        | `trg_guard_item_claim`; `is_open_participant` in policy                | pgTAP + race test |
| Cannot finalise with unclaimed | `finalize` service check; `409 unresolved_items`                       | pytest            |
| Participant cap 30             | Join service check under session lock                                  | pytest            |
| Total equals the sum of parts  | `sessions_total_reconciles_chk`; activation check                      | pgTAP + pytest    |

---

## Appendix D. Data Inventory Table (template)

| Data                    | Table / location          | Class        | Path                        | Who can read                          | Retention                        | Encrypted at rest         |
| ----------------------- | ------------------------- | ------------ | --------------------------- | ------------------------------------- | -------------------------------- | ------------------------- |
| Receipt image           | Private storage bucket    | Confidential | Backend                     | Host (signed URL)                     | Per 10.9                         | Storage-level             |
| Host UPI ID             | Backend-only table        | Confidential | Backend                     | Eligible participants via intent only | Until changed or account deleted | App-level, key outside DB |
| Claims                  | `item_claims`             | Internal     | Direct                      | Session members                       | With the session                 | Database-level            |
| Final amount, pay state | `participant_settlements` | Confidential | Backend writes, Direct read | Owner and host                        | Per 12.2                         | Database-level            |
| Parse raw output        | Backend-only table        | Internal     | Backend                     | Backend role only                     | 7 days                           | Database-level            |
