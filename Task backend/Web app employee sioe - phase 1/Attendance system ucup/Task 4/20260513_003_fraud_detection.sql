-- =============================================================
-- Task 4: Fraud Detection Rules
-- Tabel fraud_checks + function run_fraud_checks()
-- =============================================================

-- ── 1. Enum types ─────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE fraud_check_type AS ENUM (
    'location_mismatch',
    'face_not_match',
    'camera_failed',
    'abnormal_time',
    'device_untrusted',
    'missing_checkout',
    'duplicate_checkin',
    'outside_schedule_window'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE fraud_check_result AS ENUM ('passed', 'warning', 'failed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── 2. Tabel attendance_fraud_checks ─────────────────────────
CREATE TABLE IF NOT EXISTS attendance_fraud_checks (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  attendance_id  UUID NOT NULL REFERENCES attendance_records(id) ON DELETE CASCADE,
  event_id       UUID REFERENCES attendance_events(id) ON DELETE SET NULL,
  check_type     fraud_check_type NOT NULL,
  result         fraud_check_result NOT NULL,
  details        JSONB,               -- threshold, actual_value, message, dll
  checked_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Satu check type per attendance (latest menang — upsert by attendance_id+check_type)
  UNIQUE (attendance_id, check_type)
);

COMMENT ON TABLE attendance_fraud_checks IS
  'Hasil setiap fraud check per attendance record. Immutable per check_type — upsert untuk update.';
COMMENT ON COLUMN attendance_fraud_checks.details IS
  'JSON bebas: { threshold, actual_value, distance_meters, time_diff_seconds, ... }';

-- Kolom agregasi di attendance_records agar query dashboard tidak perlu join
ALTER TABLE attendance_records
  ADD COLUMN IF NOT EXISTS has_fraud_flag  BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS flag_count      INTEGER NOT NULL DEFAULT 0;

-- ── 3. Trigger: sync has_fraud_flag & flag_count ──────────────
CREATE OR REPLACE FUNCTION trg_sync_fraud_flags()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM attendance_fraud_checks
  WHERE attendance_id = COALESCE(NEW.attendance_id, OLD.attendance_id)
    AND result = 'failed';

  UPDATE attendance_records
  SET
    has_fraud_flag = v_count > 0,
    flag_count     = v_count,
    updated_at     = NOW()
  WHERE id = COALESCE(NEW.attendance_id, OLD.attendance_id);

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_fraud_flag_sync ON attendance_fraud_checks;
CREATE TRIGGER trg_fraud_flag_sync
  AFTER INSERT OR UPDATE OR DELETE ON attendance_fraud_checks
  FOR EACH ROW EXECUTE FUNCTION trg_sync_fraud_flags();

-- ── 4. Function: run_fraud_checks ────────────────────────────
-- Jalankan semua fraud check untuk satu attendance record
-- Panggil setelah check-in atau check-out berhasil
CREATE OR REPLACE FUNCTION run_fraud_checks(
  p_attendance_id UUID,
  p_event_id      UUID DEFAULT NULL
) RETURNS SETOF attendance_fraud_checks
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_ar      attendance_records%ROWTYPE;
  v_shift   shifts%ROWTYPE;
  v_branch  branches%ROWTYPE;
  v_ev      attendance_events%ROWTYPE;

  -- thresholds (bisa dipindah ke config table nanti)
  C_MAX_TIME_DIFF_SECONDS  CONSTANT INTEGER := 300;  -- 5 menit
  C_MAX_DUPLICATE_MINUTES  CONSTANT INTEGER := 1;

  v_distance     NUMERIC;
  v_time_diff    NUMERIC;
  v_check_result fraud_check_result;
  v_details      JSONB;
  v_inserted     attendance_fraud_checks;
BEGIN
  SELECT * INTO v_ar    FROM attendance_records  WHERE id = p_attendance_id;
  SELECT * INTO v_shift FROM shifts              WHERE id = v_ar.shift_id;
  SELECT * INTO v_branch FROM branches           WHERE id = v_ar.branch_id;
  SELECT * INTO v_ev    FROM attendance_events   WHERE id = p_event_id;

  -- ── CHECK 1: location_mismatch ──────────────────────────────
  IF v_ev.latitude IS NOT NULL AND v_branch.latitude IS NOT NULL THEN
    v_distance := (
      6371000 * ACOS(
        COS(RADIANS(v_branch.latitude)) * COS(RADIANS(v_ev.latitude)) *
        COS(RADIANS(v_ev.longitude) - RADIANS(v_branch.longitude)) +
        SIN(RADIANS(v_branch.latitude)) * SIN(RADIANS(v_ev.latitude))
      )
    );

    v_check_result := CASE
      WHEN v_distance <= v_branch.radius_meters THEN 'passed'
      ELSE 'failed'
    END;
    v_details := jsonb_build_object(
      'distance_meters',  ROUND(v_distance::NUMERIC, 2),
      'radius_meters',    v_branch.radius_meters,
      'employee_lat',     v_ev.latitude,
      'employee_lng',     v_ev.longitude,
      'branch_lat',       v_branch.latitude,
      'branch_lng',       v_branch.longitude
    );
  ELSE
    v_check_result := 'skipped';
    v_details := '{"reason": "koordinat tidak tersedia"}'::JSONB;
  END IF;

  INSERT INTO attendance_fraud_checks
    (attendance_id, event_id, check_type, result, details)
  VALUES
    (p_attendance_id, p_event_id, 'location_mismatch', v_check_result, v_details)
  ON CONFLICT (attendance_id, check_type) DO UPDATE
    SET result = EXCLUDED.result, details = EXCLUDED.details, checked_at = NOW()
  RETURNING * INTO v_inserted;
  RETURN NEXT v_inserted;

  -- ── CHECK 2: face_not_match ─────────────────────────────────
  IF v_ev.verification_status IS NOT NULL THEN
    v_check_result := CASE v_ev.verification_status
      WHEN 'passed'  THEN 'passed'
      WHEN 'failed'  THEN 'failed'
      WHEN 'error'   THEN 'warning'
      ELSE                'warning'
    END;
    v_details := jsonb_build_object(
      'verification_status', v_ev.verification_status,
      'face_match_score',    v_ev.face_match_score,
      'liveness_score',      v_ev.liveness_score,
      'biometric_provider',  v_ev.biometric_provider,
      'message',             v_ev.biometric_message
    );
  ELSE
    v_check_result := 'skipped';
    v_details := '{"reason": "tidak ada data biometric"}'::JSONB;
  END IF;

  INSERT INTO attendance_fraud_checks
    (attendance_id, event_id, check_type, result, details)
  VALUES
    (p_attendance_id, p_event_id, 'face_not_match', v_check_result, v_details)
  ON CONFLICT (attendance_id, check_type) DO UPDATE
    SET result = EXCLUDED.result, details = EXCLUDED.details, checked_at = NOW()
  RETURNING * INTO v_inserted;
  RETURN NEXT v_inserted;

  -- ── CHECK 3: camera_failed ──────────────────────────────────
  IF v_shift.require_face = TRUE THEN
    v_check_result := CASE WHEN v_ev.photo_url IS NULL THEN 'failed' ELSE 'passed' END;
    v_details := jsonb_build_object(
      'require_face', TRUE,
      'photo_url',    v_ev.photo_url
    );
  ELSE
    v_check_result := 'skipped';
    v_details := '{"reason": "shift tidak require face"}'::JSONB;
  END IF;

  INSERT INTO attendance_fraud_checks
    (attendance_id, event_id, check_type, result, details)
  VALUES
    (p_attendance_id, p_event_id, 'camera_failed', v_check_result, v_details)
  ON CONFLICT (attendance_id, check_type) DO UPDATE
    SET result = EXCLUDED.result, details = EXCLUDED.details, checked_at = NOW()
  RETURNING * INTO v_inserted;
  RETURN NEXT v_inserted;

  -- ── CHECK 4: abnormal_time ──────────────────────────────────
  IF v_ev.captured_at IS NOT NULL AND v_ev.created_at IS NOT NULL THEN
    v_time_diff := ABS(EXTRACT(EPOCH FROM (v_ev.created_at - v_ev.captured_at)));
    v_check_result := CASE
      WHEN v_time_diff <= C_MAX_TIME_DIFF_SECONDS THEN 'passed'
      ELSE 'warning'  -- warning saja, tidak block
    END;
    v_details := jsonb_build_object(
      'time_diff_seconds',     ROUND(v_time_diff::NUMERIC, 2),
      'threshold_seconds',     C_MAX_TIME_DIFF_SECONDS,
      'captured_at',           v_ev.captured_at,
      'server_received_at',    v_ev.created_at
    );
  ELSE
    v_check_result := 'skipped';
    v_details := '{"reason": "timestamp tidak tersedia"}'::JSONB;
  END IF;

  INSERT INTO attendance_fraud_checks
    (attendance_id, event_id, check_type, result, details)
  VALUES
    (p_attendance_id, p_event_id, 'abnormal_time', v_check_result, v_details)
  ON CONFLICT (attendance_id, check_type) DO UPDATE
    SET result = EXCLUDED.result, details = EXCLUDED.details, checked_at = NOW()
  RETURNING * INTO v_inserted;
  RETURN NEXT v_inserted;

  -- ── CHECK 5: device_untrusted ───────────────────────────────
  -- warning only — tidak block check-in
  IF v_ev.device_id IS NOT NULL THEN
    v_check_result := CASE
      WHEN EXISTS (
        SELECT 1 FROM trusted_devices
        WHERE device_id = v_ev.device_id AND employee_id = v_ar.employee_id
      ) THEN 'passed'
      ELSE 'warning'
    END;
    v_details := jsonb_build_object(
      'device_id',  v_ev.device_id,
      'platform',   v_ev.device_platform,
      'policy',     'warning_only'
    );
  ELSE
    v_check_result := 'skipped';
    v_details := '{"reason": "device_id tidak tersedia"}'::JSONB;
  END IF;

  INSERT INTO attendance_fraud_checks
    (attendance_id, event_id, check_type, result, details)
  VALUES
    (p_attendance_id, p_event_id, 'device_untrusted', v_check_result, v_details)
  ON CONFLICT (attendance_id, check_type) DO UPDATE
    SET result = EXCLUDED.result, details = EXCLUDED.details, checked_at = NOW()
  RETURNING * INTO v_inserted;
  RETURN NEXT v_inserted;

  -- ── CHECK 6: missing_checkout ───────────────────────────────
  -- Hanya relevan jika shift sudah selesai
  IF NOW() > v_shift.end_time::TIMESTAMPTZ AND v_ar.clock_out_at IS NULL THEN
    v_check_result := 'warning';
    v_details := jsonb_build_object(
      'shift_end_time', v_shift.end_time,
      'clock_out_at',   NULL
    );
  ELSE
    v_check_result := 'passed';
    v_details := jsonb_build_object('clock_out_at', v_ar.clock_out_at);
  END IF;

  INSERT INTO attendance_fraud_checks
    (attendance_id, event_id, check_type, result, details)
  VALUES
    (p_attendance_id, p_event_id, 'missing_checkout', v_check_result, v_details)
  ON CONFLICT (attendance_id, check_type) DO UPDATE
    SET result = EXCLUDED.result, details = EXCLUDED.details, checked_at = NOW()
  RETURNING * INTO v_inserted;
  RETURN NEXT v_inserted;

  -- ── CHECK 7: duplicate_checkin ──────────────────────────────
  IF EXISTS (
    SELECT 1 FROM attendance_events ae2
    WHERE ae2.attendance_id <> p_attendance_id
      AND ae2.event_type = 'check_in'
      AND ae2.attendance_id IN (
        SELECT id FROM attendance_records
        WHERE employee_id = v_ar.employee_id AND date = v_ar.date
      )
  ) THEN
    v_check_result := 'failed';
    v_details := '{"reason": "lebih dari 1 check-in ditemukan untuk employee+date yang sama"}'::JSONB;
  ELSE
    v_check_result := 'passed';
    v_details := '{}'::JSONB;
  END IF;

  INSERT INTO attendance_fraud_checks
    (attendance_id, event_id, check_type, result, details)
  VALUES
    (p_attendance_id, p_event_id, 'duplicate_checkin', v_check_result, v_details)
  ON CONFLICT (attendance_id, check_type) DO UPDATE
    SET result = EXCLUDED.result, details = EXCLUDED.details, checked_at = NOW()
  RETURNING * INTO v_inserted;
  RETURN NEXT v_inserted;

  -- ── CHECK 8: outside_schedule_window ───────────────────────
  IF v_ev.captured_at IS NOT NULL THEN
    -- Izinkan check-in 60 menit sebelum shift, check-out 60 menit setelah shift
    IF v_ev.captured_at < (v_shift.start_time::TIMESTAMPTZ - INTERVAL '60 minutes')
       OR v_ev.captured_at > (v_shift.end_time::TIMESTAMPTZ + INTERVAL '60 minutes')
    THEN
      v_check_result := 'warning';
    ELSE
      v_check_result := 'passed';
    END IF;
    v_details := jsonb_build_object(
      'captured_at',      v_ev.captured_at,
      'window_start',     v_shift.start_time::TIMESTAMPTZ - INTERVAL '60 minutes',
      'window_end',       v_shift.end_time::TIMESTAMPTZ   + INTERVAL '60 minutes'
    );
  ELSE
    v_check_result := 'skipped';
    v_details := '{"reason": "captured_at tidak tersedia"}'::JSONB;
  END IF;

  INSERT INTO attendance_fraud_checks
    (attendance_id, event_id, check_type, result, details)
  VALUES
    (p_attendance_id, p_event_id, 'outside_schedule_window', v_check_result, v_details)
  ON CONFLICT (attendance_id, check_type) DO UPDATE
    SET result = EXCLUDED.result, details = EXCLUDED.details, checked_at = NOW()
  RETURNING * INTO v_inserted;
  RETURN NEXT v_inserted;

  RETURN;
END;
$$;

-- ── 5. Indexes ────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_fraud_attendance_id  ON attendance_fraud_checks(attendance_id);
CREATE INDEX IF NOT EXISTS idx_fraud_result         ON attendance_fraud_checks(result);
CREATE INDEX IF NOT EXISTS idx_fraud_check_type     ON attendance_fraud_checks(check_type);

-- ── 6. RLS ────────────────────────────────────────────────────
ALTER TABLE attendance_fraud_checks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rls_fraud_admin_all ON attendance_fraud_checks;
CREATE POLICY rls_fraud_admin_all ON attendance_fraud_checks
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM employees
      WHERE auth_user_id = auth.uid()
        AND role IN ('admin', 'hr', 'super_admin')
    )
  );

-- trusted_devices reference table
CREATE TABLE IF NOT EXISTS trusted_devices (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id  UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  device_id    TEXT NOT NULL,
  platform     TEXT,
  label        TEXT,
  added_by     UUID REFERENCES auth.users(id),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (employee_id, device_id)
);
