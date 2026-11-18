-- ============================================================================
-- Migration: 20261118000003_functions_triggers_and_rls.sql
-- Spliqo Engineering Standards: Section 8 & Appendix A
-- Helper functions, concurrency guards, state machine triggers, and RLS policies.
-- ============================================================================

-- ============================================================================
-- 1. Helper Functions (STABLE, SECURITY DEFINER, search_path TO 'public', 'pg_temp')
-- Used by RLS policies to avoid recursive lookups.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_session_member(p_session_id uuid)
RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.session_participants sp
    WHERE sp.session_id = p_session_id
      AND sp.user_id = (select auth.uid())
  );
$$;

ALTER FUNCTION public.is_session_member(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.is_session_member(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_session_member(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.is_session_host(p_session_id uuid)
RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.sessions s
    WHERE s.id = p_session_id
      AND s.host_id = (select auth.uid())
  );
$$;

ALTER FUNCTION public.is_session_host(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.is_session_host(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_session_host(uuid) TO authenticated;

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

-- ============================================================================
-- 2. Concurrency Guard Trigger on item_claims
-- Serialises claims against completion and locking.
-- Locks sessions FOR SHARE, then session_participants FOR SHARE.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.trg_guard_item_claim()
RETURNS trigger
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
    RETURN v_row; -- host_assigned rows are written by the Backend
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

-- ============================================================================
-- 3. State Machine Transition Guard on sessions (Section 3.3)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.trg_guard_session_status_transition()
RETURNS trigger
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_unpaid_count integer;
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Legal transitions:
  -- draft -> active
  -- active -> reviewing
  -- reviewing -> active
  -- reviewing -> finalized
  -- finalized -> reviewing (only if no settlement has left unpaid)
  -- draft, active, reviewing -> cancelled
  IF OLD.status = 'draft' AND NEW.status IN ('active', 'cancelled') THEN
    RETURN NEW;
  ELSIF OLD.status = 'active' AND NEW.status IN ('reviewing', 'cancelled') THEN
    RETURN NEW;
  ELSIF OLD.status = 'reviewing' AND NEW.status IN ('active', 'finalized', 'cancelled') THEN
    RETURN NEW;
  ELSIF OLD.status = 'finalized' AND NEW.status = 'reviewing' THEN
    -- Verify no settlement row has left unpaid (Section 3.3)
    SELECT count(*) INTO v_unpaid_count
      FROM public.participant_settlements
      WHERE session_id = NEW.id AND pay_status <> 'unpaid';
    IF v_unpaid_count > 0 THEN
      RAISE EXCEPTION 'cannot_reopen_settlement_in_progress' USING ERRCODE = 'P0002';
    END IF;
    RETURN NEW;
  ELSE
    RAISE EXCEPTION 'illegal_status_transition: % to %', OLD.status, NEW.status
      USING ERRCODE = 'P0003';
  END IF;
END;
$$;

ALTER FUNCTION public.trg_guard_session_status_transition() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.trg_guard_session_status_transition() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER sessions_status_guard_trg
  BEFORE UPDATE OF status ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.trg_guard_session_status_transition();

-- ============================================================================
-- 4. Direct-path Stored RPC: complete_my_selection
-- Atomically completes participant selection and auto-advances to reviewing
-- if all participants have completed under the global lock order.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.complete_my_selection(p_session_id uuid)
RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user_id      uuid;
  v_session      public.sessions;
  v_participant  public.session_participants;
  v_incomplete   integer;
BEGIN
  v_user_id := (select auth.uid());
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = 'P0004';
  END IF;

  -- 1. Global lock order: sessions -> session_participants -> item_claims (Section 8.7)
  SELECT * INTO v_session FROM public.sessions
    WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'session_not_found' USING ERRCODE = 'P0005';
  END IF;

  IF v_session.status <> 'active' THEN
    RAISE EXCEPTION 'session_not_active' USING ERRCODE = 'P0006';
  END IF;

  -- 2. Lock participant row FOR UPDATE
  SELECT * INTO v_participant FROM public.session_participants
    WHERE session_id = p_session_id AND user_id = v_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_a_participant' USING ERRCODE = 'P0007';
  END IF;

  IF v_participant.selection_completed_at IS NOT NULL THEN
    RAISE EXCEPTION 'already_completed' USING ERRCODE = 'P0008';
  END IF;

  -- 3. Mark completed
  UPDATE public.session_participants
    SET selection_completed_at = now()
    WHERE id = v_participant.id;

  -- 4. Count incomplete participants under the session lock
  SELECT count(*) INTO v_incomplete
    FROM public.session_participants
    WHERE session_id = p_session_id AND selection_completed_at IS NULL;

  -- 5. Auto-advance if none remain
  IF v_incomplete = 0 THEN
    UPDATE public.sessions
      SET status = 'reviewing',
          updated_at = now()
      WHERE id = p_session_id;
    v_session.status := 'reviewing';
  END IF;

  RETURN jsonb_build_object(
    'participant_id', v_participant.id,
    'session_status', v_session.status,
    'all_completed', (v_incomplete = 0)
  );
END;
$$;

ALTER FUNCTION public.complete_my_selection(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.complete_my_selection(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_my_selection(uuid) TO authenticated;

-- ============================================================================
-- 5. Row Level Security Policies
-- ============================================================================

-- sessions
CREATE POLICY sessions_select_member ON public.sessions
  FOR SELECT TO authenticated
  USING ( public.is_session_member(id) );

-- bill_items
CREATE POLICY bill_items_select_member ON public.bill_items
  FOR SELECT TO authenticated
  USING ( public.is_session_member(session_id) );

-- session_participants
CREATE POLICY session_participants_select_member ON public.session_participants
  FOR SELECT TO authenticated
  USING ( public.is_session_member(session_id) );

-- item_claims (Direct Path)
CREATE POLICY item_claims_select_member ON public.item_claims
  FOR SELECT TO authenticated
  USING ( public.is_session_member(session_id) );

CREATE POLICY item_claims_insert_self ON public.item_claims
  FOR INSERT TO authenticated
  WITH CHECK (
    source = 'self'
    AND public.is_open_participant(session_id, participant_id)
  );

CREATE POLICY item_claims_delete_self ON public.item_claims
  FOR DELETE TO authenticated
  USING (
    source = 'self'
    AND public.is_open_participant(session_id, participant_id)
  );

-- participant_settlements (Direct Path SELECT: participant themselves or host)
CREATE POLICY participant_settlements_select ON public.participant_settlements
  FOR SELECT TO authenticated
  USING (
    participant_id IN (
      SELECT sp.id FROM public.session_participants sp
      WHERE sp.user_id = (select auth.uid())
    )
    OR public.is_session_host(session_id)
  );

-- ============================================================================
-- 6. Column-level Grants for authenticated role
-- ============================================================================

GRANT SELECT ON public.sessions TO authenticated;
GRANT SELECT ON public.bill_items TO authenticated;
GRANT SELECT (id, session_id, user_id, role, display_name, selection_completed_at, joined_at)
  ON public.session_participants TO authenticated;
GRANT SELECT, INSERT (session_id, item_id, participant_id, source), DELETE
  ON public.item_claims TO authenticated;
GRANT SELECT ON public.participant_settlements TO authenticated;
