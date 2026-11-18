-- ============================================================================
-- Migration: 20261118000001_auth_and_user_profiles.sql
-- Spliqo Engineering Standards: Section 8 & Section 12
-- Baseline security, user profiles, and encrypted payout storage (FLE).
-- ============================================================================

-- Pinned search path and extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Revoke default open privileges on public schema
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC, anon, authenticated;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- Utility trigger: Maintain updated_at timestamp
CREATE OR REPLACE FUNCTION public.trg_set_updated_at()
RETURNS trigger
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

ALTER FUNCTION public.trg_set_updated_at() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.trg_set_updated_at() FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- Table: public.user_profiles
-- Represents public metadata and encrypted personal data for an auth user.
-- Phone number is encrypted client-side or backend-side via FLE (bytea).
-- ============================================================================
CREATE TABLE public.user_profiles (
  id                     uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name           text NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 40),
  phone_number_encrypted bytea,
  phone_number_bidx      text,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_profiles OWNER TO postgres;
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE ONLY public.user_profiles FORCE ROW LEVEL SECURITY;

CREATE TRIGGER trg_user_profiles_updated_at
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();

CREATE INDEX user_profiles_phone_bidx ON public.user_profiles (phone_number_bidx)
  WHERE phone_number_bidx IS NOT NULL;

-- Policies: users can read their own profile
CREATE POLICY user_profiles_select_self ON public.user_profiles
  FOR SELECT TO authenticated
  USING ( id = (select auth.uid()) );

CREATE POLICY user_profiles_update_self ON public.user_profiles
  FOR UPDATE TO authenticated
  USING ( id = (select auth.uid()) )
  WITH CHECK ( id = (select auth.uid()) );

-- Minimal grants: authenticated can only read non-sensitive columns directly.
-- phone_number_encrypted and phone_number_bidx are accessed via Backend only.
REVOKE ALL ON public.user_profiles FROM PUBLIC, anon, authenticated;
GRANT SELECT (id, display_name, created_at, updated_at) ON public.user_profiles TO authenticated;
GRANT UPDATE (display_name) ON public.user_profiles TO authenticated;

-- ============================================================================
-- Table: public.user_payout_profiles (Backend-only)
-- Stores the host's payout UPI ID (Confidential, encrypted via FLE in bytea).
-- NEVER accessible to client Direct-path (no SELECT/INSERT/UPDATE/DELETE grants).
-- ============================================================================
CREATE TABLE public.user_payout_profiles (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  upi_id_encrypted bytea NOT NULL,
  upi_id_bidx      text NOT NULL,
  is_active        boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_payout_profiles OWNER TO postgres;
ALTER TABLE public.user_payout_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE ONLY public.user_payout_profiles FORCE ROW LEVEL SECURITY;

CREATE TRIGGER trg_user_payout_profiles_updated_at
  BEFORE UPDATE ON public.user_payout_profiles
  FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();

-- Enforce exactly one active payout profile per user
CREATE UNIQUE INDEX user_payout_profiles_user_active_idx
  ON public.user_payout_profiles (user_id) WHERE is_active = true;

CREATE INDEX user_payout_profiles_upi_bidx
  ON public.user_payout_profiles (upi_id_bidx);

-- Zero grants to authenticated or anon (Backend-write and Backend-read only)
REVOKE ALL ON public.user_payout_profiles FROM PUBLIC, anon, authenticated;
