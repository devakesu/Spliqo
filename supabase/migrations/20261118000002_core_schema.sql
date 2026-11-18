-- ============================================================================
-- Migration: 20261118000002_core_schema.sql
-- Spliqo Engineering Standards: Section 8 (Core schema & isolation model)
-- ============================================================================

-- Custom enum types
CREATE TYPE public.session_status AS ENUM ('draft', 'active', 'reviewing', 'finalized', 'cancelled');
CREATE TYPE public.participant_role AS ENUM ('host', 'participant');
CREATE TYPE public.claim_source AS ENUM ('self', 'host_assigned');
CREATE TYPE public.pay_preference AS ENUM ('undecided', 'self_pay', 'host_pays');
CREATE TYPE public.pay_status AS ENUM ('unpaid', 'pending', 'paid', 'waived');

-- ============================================================================
-- Table: public.sessions
-- Isolation boundary for all expense and split operations.
-- ============================================================================
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
                  - discount_paise + round_off_paise
  )
);

ALTER TABLE public.sessions OWNER TO postgres;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ONLY public.sessions FORCE ROW LEVEL SECURITY;

CREATE TRIGGER trg_sessions_updated_at
  BEFORE UPDATE ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();

CREATE INDEX sessions_host_idx ON public.sessions (host_id);
CREATE INDEX sessions_status_idx ON public.sessions (status);

-- ============================================================================
-- Table: public.bill_items
-- Granular line items belonging to a session.
-- ============================================================================
CREATE TABLE public.bill_items (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  position    integer NOT NULL CHECK (position >= 0),
  name        text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
  price_paise bigint NOT NULL CHECK (price_paise BETWEEN 1 AND 10000000),
  UNIQUE (session_id, id),
  UNIQUE (session_id, position)
);

ALTER TABLE public.bill_items OWNER TO postgres;
ALTER TABLE public.bill_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE ONLY public.bill_items FORCE ROW LEVEL SECURITY;

CREATE INDEX bill_items_session_idx ON public.bill_items (session_id);

-- ============================================================================
-- Table: public.session_participants
-- Users participating in a session (host or participant).
-- ============================================================================
CREATE TABLE public.session_participants (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id             uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  user_id                uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  role                   public.participant_role NOT NULL DEFAULT 'participant',
  display_name           text NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 40),
  selection_completed_at timestamptz,
  joined_at              timestamptz NOT NULL DEFAULT now(),
  UNIQUE (session_id, user_id),
  UNIQUE (session_id, id)
);

ALTER TABLE public.session_participants OWNER TO postgres;
ALTER TABLE public.session_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE ONLY public.session_participants FORCE ROW LEVEL SECURITY;

CREATE INDEX session_participants_session_idx ON public.session_participants (session_id);
CREATE INDEX session_participants_user_idx ON public.session_participants (user_id);
CREATE UNIQUE INDEX session_participants_one_host_key
  ON public.session_participants (session_id) WHERE role = 'host';

-- ============================================================================
-- Table: public.item_claims
-- Direct-path claiming table. Composite FKs strictly enforce session boundaries.
-- ============================================================================
CREATE TABLE public.item_claims (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id     uuid NOT NULL,
  item_id        uuid NOT NULL,
  participant_id uuid NOT NULL,
  source         public.claim_source NOT NULL DEFAULT 'self',
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (item_id, participant_id),
  FOREIGN KEY (session_id, item_id) REFERENCES public.bill_items (session_id, id) ON DELETE CASCADE,
  FOREIGN KEY (session_id, participant_id) REFERENCES public.session_participants (session_id, id) ON DELETE CASCADE
);

ALTER TABLE public.item_claims OWNER TO postgres;
ALTER TABLE public.item_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE ONLY public.item_claims FORCE ROW LEVEL SECURITY;

CREATE INDEX item_claims_session_idx ON public.item_claims (session_id);
CREATE INDEX item_claims_participant_idx ON public.item_claims (participant_id);
CREATE INDEX item_claims_item_idx ON public.item_claims (item_id);

-- ============================================================================
-- Table: public.participant_settlements (Backend-write only)
-- Tracks exact computed final shares and payment statuses.
-- ============================================================================
CREATE TABLE public.participant_settlements (
  participant_id     uuid PRIMARY KEY,
  session_id         uuid NOT NULL,
  final_amount_paise bigint CHECK (final_amount_paise >= 0),
  pay_preference     public.pay_preference NOT NULL DEFAULT 'undecided',
  pay_status         public.pay_status NOT NULL DEFAULT 'unpaid',
  updated_at         timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (session_id, participant_id) REFERENCES public.session_participants (session_id, id) ON DELETE CASCADE
);

ALTER TABLE public.participant_settlements OWNER TO postgres;
ALTER TABLE public.participant_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE ONLY public.participant_settlements FORCE ROW LEVEL SECURITY;

CREATE TRIGGER trg_participant_settlements_updated_at
  BEFORE UPDATE ON public.participant_settlements
  FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();

CREATE INDEX participant_settlements_session_idx ON public.participant_settlements (session_id);

-- ============================================================================
-- Table: public.session_invites (Backend-only)
-- Cryptographic invite tokens (stored only as hashes).
-- ============================================================================
CREATE TABLE public.session_invites (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  expires_at timestamptz NOT NULL,
  is_revoked boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.session_invites OWNER TO postgres;
ALTER TABLE public.session_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE ONLY public.session_invites FORCE ROW LEVEL SECURITY;

CREATE INDEX session_invites_session_idx ON public.session_invites (session_id);
CREATE INDEX session_invites_hash_idx ON public.session_invites (token_hash);
REVOKE ALL ON public.session_invites FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- Table: public.audit_log (Backend-only, append-only)
-- Mandatory audit log for all settlement and lifecycle mutations.
-- ============================================================================
CREATE TABLE public.audit_log (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id      uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action        text NOT NULL,
  resource_type text NOT NULL,
  resource_id   uuid NOT NULL,
  before_state  jsonb,
  after_state   jsonb,
  ip_address    inet,
  trace_id      text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.audit_log OWNER TO postgres;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE ONLY public.audit_log FORCE ROW LEVEL SECURITY;

CREATE INDEX audit_log_resource_idx ON public.audit_log (resource_type, resource_id);
CREATE INDEX audit_log_actor_idx ON public.audit_log (actor_id);
REVOKE ALL ON public.audit_log FROM PUBLIC, anon, authenticated;
