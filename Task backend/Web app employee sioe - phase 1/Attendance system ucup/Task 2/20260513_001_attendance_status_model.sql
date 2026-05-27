-- =============================================================
-- Task 2: Attendance Status Model
-- Adds system_status, override_status, is_overridden + final_status VIEW
-- =============================================================

-- ── 1. Enum types ─────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE attendance_system_status AS ENUM (
    'scheduled', 'present', 'late', 'absent',
    'overtime', 'leave', 'sick', 'holiday'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE attendance_override_status AS ENUM (
    'present', 'late', 'absent', 'overtime',
    'leave', 'sick', 'manual_adjustment'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── 2. New columns on attendance_records ──────────────────────
ALTER TABLE attendance_records
  ADD COLUMN IF NOT EXISTS work_duration_minutes  INTEGER,
  ADD COLUMN IF NOT EXISTS late_minutes           INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS overtime_minutes       INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS system_status          attendance_system_status NOT NULL DEFAULT 'scheduled',
  ADD COLUMN IF NOT EXISTS override_status        attendance_override_status,
  ADD COLUMN IF NOT EXISTS is_overridden          BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS override_reason        TEXT,
  ADD COLUMN IF NOT EXISTS overridden_by          UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS overridden_at          TIMESTAMPTZ;

-- Constraint: jika is_overridden = true, override_status & reason wajib ada
ALTER TABLE attendance_records
  DROP CONSTRAINT IF EXISTS chk_override_fields,
  ADD CONSTRAINT chk_override_fields CHECK (
    (is_overridden = FALSE)
    OR (is_overridden = TRUE AND override_status IS NOT NULL AND override_reason IS NOT NULL)
  );

-- ── 3. VIEW: attendance_with_final_status ────────────────────
-- final_status tidak disimpan sebagai kolom agar tidak redundant
CREATE OR REPLACE VIEW attendance_with_final_status AS
SELECT
  ar.*,
  CASE
    WHEN ar.is_overridden THEN ar.override_status::TEXT
    ELSE ar.system_status::TEXT
  END AS final_status
FROM attendance_records ar;

COMMENT ON VIEW attendance_with_final_status IS
  'Final status = override_status jika admin override, else system_status. Read-only; tulis ke attendance_records.';

-- ── 4. Function: compute_and_set_system_status ───────────────
-- Dipanggil setelah check-in, check-out, atau generate absent
CREATE OR REPLACE FUNCTION compute_system_status(
  p_attendance_id UUID
) RETURNS attendance_system_status
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rec        attendance_records%ROWTYPE;
  v_shift      shifts%ROWTYPE;
  v_grace      INTEGER;
  v_threshold  TIMESTAMPTZ;
  v_status     attendance_system_status;
BEGIN
  SELECT * INTO v_rec  FROM attendance_records WHERE id = p_attendance_id;
  SELECT * INTO v_shift FROM shifts WHERE id = v_rec.shift_id;

  v_grace     := COALESCE(v_shift.grace_period_minutes, 15);
  v_threshold := (v_shift.start_time::TIMESTAMPTZ) + (v_grace || ' minutes')::INTERVAL;

  -- Leave/Sick check
  IF EXISTS (
    SELECT 1 FROM leaves l
    WHERE l.employee_id = v_rec.employee_id
      AND v_rec.date BETWEEN l.start_date AND l.end_date
      AND l.status = 'approved'
      AND l.leave_type = 'sick'
  ) THEN
    RETURN 'sick';
  END IF;

  IF EXISTS (
    SELECT 1 FROM leaves l
    WHERE l.employee_id = v_rec.employee_id
      AND v_rec.date BETWEEN l.start_date AND l.end_date
      AND l.status = 'approved'
      AND l.leave_type <> 'sick'
  ) THEN
    RETURN 'leave';
  END IF;

  -- Absent: tidak ada clock_in
  IF v_rec.clock_in_at IS NULL THEN
    RETURN 'absent';
  END IF;

  -- Present vs Late
  IF v_rec.clock_in_at <= v_threshold THEN
    v_status := 'present';
  ELSE
    v_status := 'late';
  END IF;

  RETURN v_status;
END;
$$;

-- ── 5. Function: refresh_attendance_computed_fields ──────────
-- Update semua kalkulasi numerik + system_status sekaligus
CREATE OR REPLACE FUNCTION refresh_attendance_computed_fields(
  p_attendance_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rec    attendance_records%ROWTYPE;
  v_shift  shifts%ROWTYPE;
  v_status attendance_system_status;
  v_late   INTEGER;
  v_ot     INTEGER;
  v_dur    INTEGER;
BEGIN
  SELECT * INTO v_rec   FROM attendance_records WHERE id = p_attendance_id;
  SELECT * INTO v_shift FROM shifts WHERE id = v_rec.shift_id;

  v_status := compute_system_status(p_attendance_id);

  -- late_minutes
  v_late := CASE
    WHEN v_rec.clock_in_at IS NULL THEN 0
    ELSE GREATEST(0, FLOOR(
      EXTRACT(EPOCH FROM (v_rec.clock_in_at - v_shift.start_time::TIMESTAMPTZ)) / 60
    ))::INTEGER
  END;

  -- overtime_minutes
  v_ot := CASE
    WHEN v_rec.clock_out_at IS NULL THEN 0
    ELSE GREATEST(0, FLOOR(
      EXTRACT(EPOCH FROM (v_rec.clock_out_at - v_shift.end_time::TIMESTAMPTZ)) / 60
    ))::INTEGER
  END;

  -- work_duration_minutes
  v_dur := CASE
    WHEN v_rec.clock_in_at IS NULL OR v_rec.clock_out_at IS NULL THEN NULL
    ELSE FLOOR(
      EXTRACT(EPOCH FROM (v_rec.clock_out_at - v_rec.clock_in_at)) / 60
    )::INTEGER
  END;

  UPDATE attendance_records
  SET
    system_status         = v_status,
    late_minutes          = v_late,
    overtime_minutes      = v_ot,
    work_duration_minutes = v_dur,
    updated_at            = NOW()
  WHERE id = p_attendance_id;
END;
$$;

-- ── 6. Trigger: auto-refresh setelah clock_in / clock_out berubah ──
CREATE OR REPLACE FUNCTION trg_refresh_attendance_on_clock_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.clock_in_at IS DISTINCT FROM OLD.clock_in_at
     OR NEW.clock_out_at IS DISTINCT FROM OLD.clock_out_at
  THEN
    PERFORM refresh_attendance_computed_fields(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_attendance_clock_change ON attendance_records;
CREATE TRIGGER trg_attendance_clock_change
  AFTER UPDATE OF clock_in_at, clock_out_at ON attendance_records
  FOR EACH ROW EXECUTE FUNCTION trg_refresh_attendance_on_clock_change();

-- ── 7. Indexes ────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_attendance_system_status   ON attendance_records(system_status);
CREATE INDEX IF NOT EXISTS idx_attendance_is_overridden   ON attendance_records(is_overridden);
CREATE INDEX IF NOT EXISTS idx_attendance_employee_date   ON attendance_records(employee_id, date);
