-- =============================================================
-- Task 3: Attendance Event Model
-- Extend attendance_events sebagai immutable proof log
-- =============================================================

-- ── 1. Enum types ─────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE attendance_event_type AS ENUM (
    'check_in', 'check_out', 'auto_absent', 'admin_override'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE attendance_verification_status AS ENUM (
    'pending', 'passed', 'failed', 'skipped', 'error'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── 2. Extend attendance_events ───────────────────────────────
-- Pastikan tabel dasar sudah ada (buat jika belum)
CREATE TABLE IF NOT EXISTS attendance_events (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  attendance_id  UUID NOT NULL REFERENCES attendance_records(id) ON DELETE CASCADE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Core event fields
ALTER TABLE attendance_events
  ADD COLUMN IF NOT EXISTS event_type           attendance_event_type NOT NULL,
  ADD COLUMN IF NOT EXISTS captured_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Lokasi
  ADD COLUMN IF NOT EXISTS latitude             NUMERIC(10, 7),
  ADD COLUMN IF NOT EXISTS longitude            NUMERIC(10, 7),
  ADD COLUMN IF NOT EXISTS accuracy_meters      NUMERIC(8, 2),

  -- Foto & device
  ADD COLUMN IF NOT EXISTS photo_url            TEXT,
  ADD COLUMN IF NOT EXISTS device_id            TEXT,
  ADD COLUMN IF NOT EXISTS device_platform      TEXT,  -- 'ios' | 'android' | 'web'

  -- Verifikasi
  ADD COLUMN IF NOT EXISTS verification_status  attendance_verification_status NOT NULL DEFAULT 'pending',

  -- Biometric detail
  ADD COLUMN IF NOT EXISTS face_match_score     NUMERIC(5, 4),   -- 0.0000–1.0000
  ADD COLUMN IF NOT EXISTS liveness_score       NUMERIC(5, 4),
  ADD COLUMN IF NOT EXISTS biometric_provider   TEXT,
  ADD COLUMN IF NOT EXISTS biometric_message    TEXT,

  -- Admin override metadata (hanya untuk event_type = 'admin_override')
  ADD COLUMN IF NOT EXISTS actor_id             UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS actor_role           TEXT,
  ADD COLUMN IF NOT EXISTS notes                TEXT;

-- ── 3. Constraints ────────────────────────────────────────────
-- attendance_events bersifat IMMUTABLE — tidak boleh di-UPDATE setelah dibuat
CREATE OR REPLACE FUNCTION trg_prevent_event_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'attendance_events adalah immutable proof log — UPDATE tidak diizinkan. Buat event baru.';
END;
$$;

DROP TRIGGER IF EXISTS trg_no_update_attendance_events ON attendance_events;
CREATE TRIGGER trg_no_update_attendance_events
  BEFORE UPDATE ON attendance_events
  FOR EACH ROW EXECUTE FUNCTION trg_prevent_event_update();

-- Biometric field wajib ada jika event_type = check_in dan verification_status != 'skipped'
ALTER TABLE attendance_events
  DROP CONSTRAINT IF EXISTS chk_biometric_on_checkin,
  ADD CONSTRAINT chk_biometric_on_checkin CHECK (
    event_type <> 'check_in'
    OR verification_status = 'skipped'
    OR photo_url IS NOT NULL
  );

-- face_match_score range
ALTER TABLE attendance_events
  DROP CONSTRAINT IF EXISTS chk_face_score_range,
  ADD CONSTRAINT chk_face_score_range CHECK (
    face_match_score IS NULL OR (face_match_score >= 0 AND face_match_score <= 1)
  );

ALTER TABLE attendance_events
  DROP CONSTRAINT IF EXISTS chk_liveness_score_range,
  ADD CONSTRAINT chk_liveness_score_range CHECK (
    liveness_score IS NULL OR (liveness_score >= 0 AND liveness_score <= 1)
  );

-- ── 4. View: latest event per attendance ──────────────────────
CREATE OR REPLACE VIEW attendance_latest_events AS
SELECT DISTINCT ON (attendance_id, event_type)
  *
FROM attendance_events
ORDER BY attendance_id, event_type, captured_at DESC;

COMMENT ON VIEW attendance_latest_events IS
  'Event terbaru per attendance_id per event_type. Useful untuk dashboard status.';

-- ── 5. Indexes ────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_events_attendance_id  ON attendance_events(attendance_id);
CREATE INDEX IF NOT EXISTS idx_events_event_type     ON attendance_events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_captured_at    ON attendance_events(captured_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_verification   ON attendance_events(verification_status);

-- ── 6. RLS ────────────────────────────────────────────────────
ALTER TABLE attendance_events ENABLE ROW LEVEL SECURITY;

-- Karyawan hanya bisa lihat event milik sendiri
DROP POLICY IF EXISTS rls_events_employee_select ON attendance_events;
CREATE POLICY rls_events_employee_select ON attendance_events
  FOR SELECT USING (
    attendance_id IN (
      SELECT id FROM attendance_records
      WHERE employee_id = (
        SELECT id FROM employees WHERE auth_user_id = auth.uid()
      )
    )
  );

-- Admin / HR bisa lihat semua
DROP POLICY IF EXISTS rls_events_admin_select ON attendance_events;
CREATE POLICY rls_events_admin_select ON attendance_events
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM employees
      WHERE auth_user_id = auth.uid()
        AND role IN ('admin', 'hr', 'super_admin')
    )
  );

-- Insert hanya dari service_role atau fungsi SECURITY DEFINER
DROP POLICY IF EXISTS rls_events_service_insert ON attendance_events;
CREATE POLICY rls_events_service_insert ON attendance_events
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
