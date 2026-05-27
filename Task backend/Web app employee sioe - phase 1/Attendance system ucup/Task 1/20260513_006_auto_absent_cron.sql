-- =============================================================
-- Task 1 (supporting): Auto-generate absent records
-- Dijalankan oleh pg_cron setiap jam
-- Aktifkan pg_cron di: Supabase Dashboard → Database → Extensions
-- =============================================================

-- Function: generate_absent_records
CREATE OR REPLACE FUNCTION generate_absent_records()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_generated INTEGER := 0;
  v_rec       RECORD;
BEGIN
  -- Cari semua schedule yang shift-nya sudah selesai + 15 menit buffer
  -- dan belum punya attendance_record clock-in
  -- dan tidak ada approved leave
  FOR v_rec IN
    SELECT
      sc.employee_id,
      sc.shift_id,
      sc.branch_id,
      sc.date,
      sc.id AS schedule_id
    FROM schedules sc
    JOIN shifts sh ON sh.id = sc.shift_id
    WHERE sc.date = CURRENT_DATE
      -- Shift sudah selesai + 15 menit buffer
      AND NOW() > (sh.end_time::TIMESTAMPTZ + INTERVAL '15 minutes')
      -- Belum ada attendance record
      AND NOT EXISTS (
        SELECT 1 FROM attendance_records ar
        WHERE ar.employee_id = sc.employee_id
          AND ar.date = sc.date
          AND ar.shift_id = sc.shift_id
      )
      -- Tidak ada approved leave
      AND NOT EXISTS (
        SELECT 1 FROM leaves l
        WHERE l.employee_id = sc.employee_id
          AND sc.date BETWEEN l.start_date AND l.end_date
          AND l.status = 'approved'
      )
  LOOP
    INSERT INTO attendance_records (
      employee_id,
      shift_id,
      branch_id,
      date,
      system_status,
      clock_in_at,
      clock_out_at
    ) VALUES (
      v_rec.employee_id,
      v_rec.shift_id,
      v_rec.branch_id,
      v_rec.date,
      'absent',
      NULL,
      NULL
    )
    ON CONFLICT DO NOTHING;

    -- Insert event log untuk absent otomatis
    INSERT INTO attendance_events (
      attendance_id,
      event_type,
      captured_at,
      verification_status,
      notes
    )
    SELECT
      ar.id,
      'auto_absent',
      NOW(),
      'skipped',
      'Generated automatically by pg_cron after shift ended'
    FROM attendance_records ar
    WHERE ar.employee_id = v_rec.employee_id
      AND ar.date = v_rec.date
      AND ar.shift_id = v_rec.shift_id;

    v_generated := v_generated + 1;
  END LOOP;

  RETURN v_generated;
END;
$$;

COMMENT ON FUNCTION generate_absent_records IS
  'Dipanggil pg_cron setiap jam. Generate absent record untuk schedule yang melewati shift end + 15 menit tanpa check-in.';

-- ── pg_cron schedule ──────────────────────────────────────────
-- Pastikan extension pg_cron sudah aktif:
--   SELECT * FROM pg_extension WHERE extname = 'pg_cron';
--
-- Jalankan sekali untuk mendaftarkan job:
SELECT cron.schedule(
  'generate-absent-records',   -- job name
  '0 * * * *',                 -- setiap jam tepat
  $$ SELECT generate_absent_records(); $$
);
