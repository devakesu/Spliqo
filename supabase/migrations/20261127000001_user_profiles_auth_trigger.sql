-- ============================================================================
-- Migration: 20261127000001_user_profiles_auth_trigger.sql
-- Spliqo Engineering Standards: Section 5, Section 8.3 & Section 8.4
-- Auto-provisions public.user_profiles on auth.users creation (Email, Phone, OAuth).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.trg_handle_new_auth_user()
RETURNS trigger
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_raw_name     text;
  v_display_name text;
BEGIN
  -- Derive initial display_name from metadata (email signup or OAuth profile),
  -- falling back safely to 'Spliqo User'. Never used for authorization (Section 5.2).
  v_raw_name := COALESCE(
    NEW.raw_user_meta_data ->> 'display_name',
    NEW.raw_user_meta_data ->> 'full_name',
    NEW.raw_user_meta_data ->> 'name',
    ''
  );

  -- Strip ASCII control characters and surrounding whitespace
  v_display_name := btrim(regexp_replace(v_raw_name, E'[\\x00-\\x1F\\x7F]', '', 'g'));

  IF char_length(v_display_name) < 1 THEN
    v_display_name := 'Spliqo User';
  ELSIF char_length(v_display_name) > 40 THEN
    v_display_name := left(v_display_name, 40);
  END IF;

  INSERT INTO public.user_profiles (id, display_name)
  VALUES (NEW.id, v_display_name)
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

ALTER FUNCTION public.trg_handle_new_auth_user() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.trg_handle_new_auth_user() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.trg_handle_new_auth_user() IS
  'Trigger function owned by postgres that provisions a baseline public.user_profiles row whenever a new auth.users row is created.';

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.trg_handle_new_auth_user();
