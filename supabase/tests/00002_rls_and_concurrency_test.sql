-- ============================================================================
-- pgTAP Test: 00002_rls_and_concurrency_test.sql
-- Spliqo Engineering Standards: Section 8.3, 8.5 & 21.1
-- Tests RLS helpers, guard trigger (item_claims), and atomic completion RPC.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(10);

-- Mock Auth Users
INSERT INTO auth.users (id, email)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'host@test.com'),
  ('00000000-0000-0000-0000-000000000002', 'guest@test.com')
ON CONFLICT (id) DO NOTHING;

-- Create Active Session
INSERT INTO public.sessions (
  id, host_id, title, subtotal_paise, tax_paise, service_charge_paise,
  discount_paise, round_off_paise, total_paise, status, expires_at
) VALUES (
  '20000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000001',
  'Paragon Split',
  10000, 500, 0, 0, 0, 10500, 'active', now() + interval '1 day'
);

-- Create 2 Bill Items
INSERT INTO public.bill_items (id, session_id, position, name, price_paise)
VALUES
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 0, 'Biryani', 6000),
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 1, 'Lime Juice', 4000);

-- Add Participants
INSERT INTO public.session_participants (id, session_id, user_id, role, display_name)
VALUES
  ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'host', 'Host User'),
  ('40000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'participant', 'Guest User');

-- 1. Helper tests
-- Set context to Guest User
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000002';

SELECT is(
  public.is_session_member('20000000-0000-0000-0000-000000000001'),
  true,
  'Guest user is session member'
);

SELECT is(
  public.is_session_host('20000000-0000-0000-0000-000000000001'),
  false,
  'Guest user is NOT session host'
);

SELECT is(
  public.is_open_participant('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000002'),
  true,
  'Guest user is open participant while active and uncompleted'
);

-- 2. Guard trigger test: Inserting claim while open succeeds
SELECT lives_ok(
  $$
    INSERT INTO public.item_claims (session_id, item_id, participant_id, source)
    VALUES (
      '20000000-0000-0000-0000-000000000001',
      '30000000-0000-0000-0000-000000000001',
      '40000000-0000-0000-0000-000000000002',
      'self'
    );
  $$,
  'Open participant can claim item'
);

-- 3. Direct RPC: complete_my_selection
-- Guest completes selection
SELECT lives_ok(
  $$
    SELECT public.complete_my_selection('20000000-0000-0000-0000-000000000001');
  $$,
  'Guest successfully completes selection'
);

-- After completion, is_open_participant returns false
SELECT is(
  public.is_open_participant('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000002'),
  false,
  'Completed participant is no longer an open participant'
);

-- Guard trigger rejects new claim once completed
SELECT throws_ok(
  $$
    INSERT INTO public.item_claims (session_id, item_id, participant_id, source)
    VALUES (
      '20000000-0000-0000-0000-000000000001',
      '30000000-0000-0000-0000-000000000002',
      '40000000-0000-0000-0000-000000000002',
      'self'
    );
  $$,
  'P0001', -- selection_locked
  NULL,
  'Guard trigger blocks claim insert after completion'
);

-- Double complete throws already_completed
SELECT throws_ok(
  $$
    SELECT public.complete_my_selection('20000000-0000-0000-0000-000000000001');
  $$,
  'P0008', -- already_completed
  NULL,
  'Calling complete_my_selection twice throws already_completed'
);

-- Session is still active because Host has not completed
SELECT is(
  (SELECT status FROM public.sessions WHERE id = '20000000-0000-0000-0000-000000000001'),
  'active'::public.session_status,
  'Session remains active until last participant completes'
);

-- 4. Host completes -> triggers auto-advance to reviewing
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000001';

SELECT lives_ok(
  $$
    SELECT public.complete_my_selection('20000000-0000-0000-0000-000000000001');
  $$,
  'Host completes selection and session auto-advances to reviewing'
);

SELECT * FROM finish();
ROLLBACK;
