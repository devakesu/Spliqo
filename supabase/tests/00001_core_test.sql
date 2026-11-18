-- ============================================================================
-- pgTAP Test: 00001_core_test.sql
-- Spliqo Engineering Standards: Section 8 & Section 21.1
-- Tests schema structure, reconciliation constraints, RLS functions, and triggers.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(22);

-- 1. Schema existence tests
SELECT has_table('public', 'user_profiles', 'Table user_profiles exists');
SELECT has_table('public', 'user_payout_profiles', 'Table user_payout_profiles exists');
SELECT has_table('public', 'sessions', 'Table sessions exists');
SELECT has_table('public', 'bill_items', 'Table bill_items exists');
SELECT has_table('public', 'session_participants', 'Table session_participants exists');
SELECT has_table('public', 'item_claims', 'Table item_claims exists');
SELECT has_table('public', 'participant_settlements', 'Table participant_settlements exists');
SELECT has_table('public', 'session_invites', 'Table session_invites exists');
SELECT has_table('public', 'audit_log', 'Table audit_log exists');

-- 2. Enum type tests
SELECT has_type('public', 'session_status', 'Type session_status exists');
SELECT has_type('public', 'participant_role', 'Type participant_role exists');
SELECT has_type('public', 'claim_source', 'Type claim_source exists');
SELECT has_type('public', 'pay_preference', 'Type pay_preference exists');
SELECT has_type('public', 'pay_status', 'Type pay_status exists');

-- 3. Function existence tests
SELECT has_function('public', 'is_session_member', ARRAY['uuid'], 'Function is_session_member exists');
SELECT has_function('public', 'is_session_host', ARRAY['uuid'], 'Function is_session_host exists');
SELECT has_function('public', 'is_open_participant', ARRAY['uuid', 'uuid'], 'Function is_open_participant exists');
SELECT has_function('public', 'complete_my_selection', ARRAY['uuid'], 'Function complete_my_selection exists');

-- 4. Constraint tests: sessions_total_reconciles_chk
-- Setup mock auth user
INSERT INTO auth.users (id, email)
VALUES ('00000000-0000-0000-0000-000000000001', 'host@test.com')
ON CONFLICT (id) DO NOTHING;

-- Valid session reconciliation succeeds
SELECT lives_ok(
  $$
    INSERT INTO public.sessions (
      id, host_id, title, subtotal_paise, tax_paise, service_charge_paise,
      discount_paise, round_off_paise, total_paise, status, expires_at
    ) VALUES (
      '10000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000001',
      'Dinner at Paragon',
      10000, 500, 0, 0, 0, 10500, 'draft', now() + interval '1 day'
    );
  $$,
  'Valid session reconciliation passes check constraint'
);

-- Invalid session reconciliation fails check constraint
SELECT throws_ok(
  $$
    INSERT INTO public.sessions (
      id, host_id, title, subtotal_paise, tax_paise, service_charge_paise,
      discount_paise, round_off_paise, total_paise, status, expires_at
    ) VALUES (
      '10000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000001',
      'Bad Bill',
      10000, 500, 0, 0, 0, 99999, 'draft', now() + interval '1 day'
    );
  $$,
  '23514', -- check_violation
  NULL,
  'Invalid session reconciliation throws check violation'
);

-- 5. Trigger tests: Status transition guard
-- draft -> active succeeds
SELECT lives_ok(
  $$
    UPDATE public.sessions
    SET status = 'active'
    WHERE id = '10000000-0000-0000-0000-000000000001';
  $$,
  'Legal transition draft -> active succeeds'
);

-- active -> finalized directly (without reviewing) fails
SELECT throws_ok(
  $$
    UPDATE public.sessions
    SET status = 'finalized'
    WHERE id = '10000000-0000-0000-0000-000000000001';
  $$,
  'P0003', -- illegal_status_transition
  NULL,
  'Illegal transition active -> finalized throws exception'
);

SELECT * FROM finish();
ROLLBACK;
