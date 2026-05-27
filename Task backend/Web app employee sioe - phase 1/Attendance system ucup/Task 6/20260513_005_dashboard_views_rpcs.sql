-- =============================================================
-- Task 6: Dashboard Data Contracts
-- RPCs + Views untuk admin dashboard
-- =============================================================

-- ─────────────────────────────────────────────────────────────
-- 6.1  get_admin_attendance_overview
-- Contract: ringkasan absensi harian untuk header dashboard
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_admin_attendance_overview(
  p_date        DATE    DEFAULT CURRENT_DATE,
  p_branch_id   UUID    DEFAULT NULL,
  p_department_id UUID  DEFAULT NULL
)
RETURNS TABLE (
  date                   DATE,
  total_employees_today  BIGINT,
  checked_in_count       BIGINT,
  not_checked_in_count   BIGINT,
  late_count             BIGINT,
  overtime_count         BIGINT,
  absent_count           BIGINT,
  leave_count            BIGINT,
  sick_count             BIGINT,
  flagged_count          BIGINT
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  WITH base AS (
    SELECT
      ar.id,
      CASE
        WHEN ar.is_overridden THEN ar.override_status::TEXT
        ELSE ar.system_status::TEXT
      END AS final_status,
      ar.clock_in_at,
      ar.overtime_minutes,
      ar.has_fraud_flag
    FROM attendance_records ar
    JOIN schedules sc ON sc.attendance_record_id = ar.id
    JOIN employees  e  ON e.id = ar.employee_id
    WHERE ar.date = p_date
      AND (p_branch_id     IS NULL OR e.branch_id     = p_branch_id)
      AND (p_department_id IS NULL OR e.department_id = p_department_id)
  )
  SELECT
    p_date,
    COUNT(*)                                    AS total_employees_today,
    COUNT(*) FILTER (WHERE clock_in_at IS NOT NULL)  AS checked_in_count,
    COUNT(*) FILTER (WHERE clock_in_at IS NULL AND final_status <> 'absent') AS not_checked_in_count,
    COUNT(*) FILTER (WHERE final_status = 'late')    AS late_count,
    COUNT(*) FILTER (WHERE overtime_minutes > 0)     AS overtime_count,
    COUNT(*) FILTER (WHERE final_status = 'absent')  AS absent_count,
    COUNT(*) FILTER (WHERE final_status = 'leave')   AS leave_count,
    COUNT(*) FILTER (WHERE final_status = 'sick')    AS sick_count,
    COUNT(*) FILTER (WHERE has_fraud_flag = TRUE)    AS flagged_count
  FROM base;
$$;

COMMENT ON FUNCTION get_admin_attendance_overview IS
  'Header summary card untuk admin dashboard. Filter: date, branch_id, department_id.';

-- ─────────────────────────────────────────────────────────────
-- 6.2  get_admin_attendance_logs
-- Contract: tabel list absensi harian dengan semua kolom yang dibutuhkan frontend
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_admin_attendance_logs(
  p_date           DATE    DEFAULT CURRENT_DATE,
  p_branch_id      UUID    DEFAULT NULL,
  p_department_id  UUID    DEFAULT NULL,
  p_status         TEXT    DEFAULT NULL,   -- filter by final_status
  p_flagged_only   BOOLEAN DEFAULT FALSE,
  p_search         TEXT    DEFAULT NULL,   -- cari nama/NIK employee
  p_limit          INTEGER DEFAULT 50,
  p_offset         INTEGER DEFAULT 0
)
RETURNS TABLE (
  attendance_id        UUID,
  employee_id          UUID,
  employee_name        TEXT,
  employee_nik         TEXT,
  department_name      TEXT,
  branch_name          TEXT,
  shift_name           TEXT,
  shift_start_time     TIME,
  shift_end_time       TIME,
  date                 DATE,
  clock_in_at          TIMESTAMPTZ,
  clock_out_at         TIMESTAMPTZ,
  final_status         TEXT,
  system_status        TEXT,
  is_overridden        BOOLEAN,
  late_minutes         INTEGER,
  overtime_minutes     INTEGER,
  work_duration_minutes INTEGER,
  has_fraud_flag       BOOLEAN,
  flag_count           INTEGER,
  total_rows           BIGINT
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT
    ar.id                   AS attendance_id,
    e.id                    AS employee_id,
    e.full_name             AS employee_name,
    e.nik                   AS employee_nik,
    d.name                  AS department_name,
    b.name                  AS branch_name,
    sh.name                 AS shift_name,
    sh.start_time           AS shift_start_time,
    sh.end_time             AS shift_end_time,
    ar.date,
    ar.clock_in_at,
    ar.clock_out_at,
    CASE WHEN ar.is_overridden THEN ar.override_status::TEXT ELSE ar.system_status::TEXT END AS final_status,
    ar.system_status::TEXT,
    ar.is_overridden,
    ar.late_minutes,
    ar.overtime_minutes,
    ar.work_duration_minutes,
    ar.has_fraud_flag,
    ar.flag_count,
    COUNT(*) OVER ()        AS total_rows
  FROM attendance_records ar
  JOIN employees    e  ON e.id  = ar.employee_id
  JOIN shifts       sh ON sh.id = ar.shift_id
  LEFT JOIN departments d  ON d.id  = e.department_id
  LEFT JOIN branches    b  ON b.id  = e.branch_id
  WHERE ar.date = p_date
    AND (p_branch_id     IS NULL OR e.branch_id     = p_branch_id)
    AND (p_department_id IS NULL OR e.department_id = p_department_id)
    AND (p_flagged_only  = FALSE  OR ar.has_fraud_flag = TRUE)
    AND (p_status        IS NULL  OR
         (CASE WHEN ar.is_overridden THEN ar.override_status::TEXT ELSE ar.system_status::TEXT END) = p_status)
    AND (p_search        IS NULL  OR
         e.full_name ILIKE '%' || p_search || '%' OR
         e.nik       ILIKE '%' || p_search || '%')
  ORDER BY ar.clock_in_at ASC NULLS LAST
  LIMIT  p_limit
  OFFSET p_offset;
$$;

COMMENT ON FUNCTION get_admin_attendance_logs IS
  'Tabel list absensi harian. Mendukung filter date/branch/dept/status/flagged/search. Includes total_rows untuk pagination.';

-- ─────────────────────────────────────────────────────────────
-- 6.3  get_admin_attendance_detail
-- Contract: detail lengkap satu attendance record (untuk modal/halaman detail)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_admin_attendance_detail(
  p_attendance_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'employee', jsonb_build_object(
      'id',          e.id,
      'full_name',   e.full_name,
      'nik',         e.nik,
      'department',  d.name,
      'branch',      b.name,
      'position',    e.position
    ),
    'schedule', jsonb_build_object(
      'shift_id',    sh.id,
      'shift_name',  sh.name,
      'start_time',  sh.start_time,
      'end_time',    sh.end_time,
      'grace_period_minutes', COALESCE(sh.grace_period_minutes, 15),
      'require_face',sh.require_face,
      'date',        ar.date
    ),
    'attendance', jsonb_build_object(
      'id',                    ar.id,
      'clock_in_at',           ar.clock_in_at,
      'clock_out_at',          ar.clock_out_at,
      'system_status',         ar.system_status,
      'override_status',       ar.override_status,
      'is_overridden',         ar.is_overridden,
      'override_reason',       ar.override_reason,
      'overridden_by',         ar.overridden_by,
      'overridden_at',         ar.overridden_at,
      'final_status',          CASE WHEN ar.is_overridden THEN ar.override_status::TEXT ELSE ar.system_status::TEXT END,
      'late_minutes',          ar.late_minutes,
      'overtime_minutes',      ar.overtime_minutes,
      'work_duration_minutes', ar.work_duration_minutes,
      'has_fraud_flag',        ar.has_fraud_flag,
      'flag_count',            ar.flag_count
    ),
    'events', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id',                  ae.id,
          'event_type',          ae.event_type,
          'captured_at',         ae.captured_at,
          'latitude',            ae.latitude,
          'longitude',           ae.longitude,
          'accuracy_meters',     ae.accuracy_meters,
          'photo_url',           ae.photo_url,
          'device_id',           ae.device_id,
          'device_platform',     ae.device_platform,
          'verification_status', ae.verification_status,
          'face_match_score',    ae.face_match_score,
          'liveness_score',      ae.liveness_score,
          'biometric_provider',  ae.biometric_provider,
          'biometric_message',   ae.biometric_message,
          'actor_id',            ae.actor_id,
          'actor_role',          ae.actor_role,
          'notes',               ae.notes
        ) ORDER BY ae.captured_at ASC
      )
      FROM attendance_events ae WHERE ae.attendance_id = ar.id
    ),
    'fraud_checks', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id',         fc.id,
          'check_type', fc.check_type,
          'result',     fc.result,
          'details',    fc.details,
          'checked_at', fc.checked_at
        ) ORDER BY fc.check_type
      )
      FROM attendance_fraud_checks fc WHERE fc.attendance_id = ar.id
    ),
    'override_history', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id',              oa.id,
          'action',          oa.action,
          'previous_status', oa.previous_status,
          'new_status',      oa.new_status,
          'reason',          oa.reason,
          'performed_by',    oa.performed_by,
          'performed_at',    oa.performed_at
        ) ORDER BY oa.performed_at DESC
      )
      FROM attendance_override_audit oa WHERE oa.attendance_id = ar.id
    )
  )
  INTO v_result
  FROM attendance_records ar
  JOIN employees    e  ON e.id  = ar.employee_id
  JOIN shifts       sh ON sh.id = ar.shift_id
  LEFT JOIN departments d  ON d.id  = e.department_id
  LEFT JOIN branches    b  ON b.id  = e.branch_id
  WHERE ar.id = p_attendance_id;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'Attendance record tidak ditemukan: %', p_attendance_id;
  END IF;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION get_admin_attendance_detail IS
  'Detail lengkap satu attendance: employee, schedule, attendance, events, fraud_checks, override_history.';

-- ─────────────────────────────────────────────────────────────
-- 6.4  get_monthly_attendance_summary
-- Contract: agregasi per employee per bulan untuk laporan bulanan / payroll
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_monthly_attendance_summary(
  p_year          INTEGER,
  p_month         INTEGER,
  p_branch_id     UUID    DEFAULT NULL,
  p_department_id UUID    DEFAULT NULL,
  p_employee_id   UUID    DEFAULT NULL
)
RETURNS TABLE (
  employee_id           UUID,
  employee_name         TEXT,
  employee_nik          TEXT,
  department_name       TEXT,
  branch_name           TEXT,
  year                  INTEGER,
  month                 INTEGER,
  total_scheduled_days  BIGINT,
  total_present         BIGINT,
  total_late            BIGINT,
  total_absent          BIGINT,
  total_leave           BIGINT,
  total_sick            BIGINT,
  total_overtime        BIGINT,
  total_late_minutes    BIGINT,
  total_overtime_minutes BIGINT,
  total_work_minutes    BIGINT
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT
    e.id                              AS employee_id,
    e.full_name                       AS employee_name,
    e.nik                             AS employee_nik,
    d.name                            AS department_name,
    b.name                            AS branch_name,
    p_year,
    p_month,
    COUNT(ar.id)                      AS total_scheduled_days,
    COUNT(ar.id) FILTER (WHERE
      (CASE WHEN ar.is_overridden THEN ar.override_status::TEXT ELSE ar.system_status::TEXT END)
      IN ('present', 'overtime'))     AS total_present,
    COUNT(ar.id) FILTER (WHERE
      (CASE WHEN ar.is_overridden THEN ar.override_status::TEXT ELSE ar.system_status::TEXT END) = 'late')
                                      AS total_late,
    COUNT(ar.id) FILTER (WHERE
      (CASE WHEN ar.is_overridden THEN ar.override_status::TEXT ELSE ar.system_status::TEXT END) = 'absent')
                                      AS total_absent,
    COUNT(ar.id) FILTER (WHERE
      (CASE WHEN ar.is_overridden THEN ar.override_status::TEXT ELSE ar.system_status::TEXT END) = 'leave')
                                      AS total_leave,
    COUNT(ar.id) FILTER (WHERE
      (CASE WHEN ar.is_overridden THEN ar.override_status::TEXT ELSE ar.system_status::TEXT END) = 'sick')
                                      AS total_sick,
    COUNT(ar.id) FILTER (WHERE ar.overtime_minutes > 0)
                                      AS total_overtime,
    COALESCE(SUM(ar.late_minutes), 0) AS total_late_minutes,
    COALESCE(SUM(ar.overtime_minutes), 0) AS total_overtime_minutes,
    COALESCE(SUM(ar.work_duration_minutes), 0) AS total_work_minutes
  FROM attendance_records ar
  JOIN employees    e  ON e.id  = ar.employee_id
  LEFT JOIN departments d  ON d.id  = e.department_id
  LEFT JOIN branches    b  ON b.id  = e.branch_id
  WHERE EXTRACT(YEAR  FROM ar.date) = p_year
    AND EXTRACT(MONTH FROM ar.date) = p_month
    AND (p_branch_id     IS NULL OR e.branch_id     = p_branch_id)
    AND (p_department_id IS NULL OR e.department_id = p_department_id)
    AND (p_employee_id   IS NULL OR e.id            = p_employee_id)
  GROUP BY e.id, e.full_name, e.nik, d.name, b.name
  ORDER BY e.full_name;
$$;

COMMENT ON FUNCTION get_monthly_attendance_summary IS
  'Agregasi bulanan per employee. Dipakai untuk laporan HR dan input payroll.';

-- ─────────────────────────────────────────────────────────────
-- 6.5  get_attendance_fraud_flags
-- Contract: list semua attendance yang punya fraud flag (untuk halaman monitoring)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_attendance_fraud_flags(
  p_date_from     DATE    DEFAULT CURRENT_DATE - 7,
  p_date_to       DATE    DEFAULT CURRENT_DATE,
  p_branch_id     UUID    DEFAULT NULL,
  p_department_id UUID    DEFAULT NULL,
  p_check_type    TEXT    DEFAULT NULL,  -- filter per fraud check type
  p_result        TEXT    DEFAULT 'failed', -- 'passed'|'warning'|'failed'
  p_limit         INTEGER DEFAULT 50,
  p_offset        INTEGER DEFAULT 0
)
RETURNS TABLE (
  attendance_id   UUID,
  employee_id     UUID,
  employee_name   TEXT,
  branch_name     TEXT,
  department_name TEXT,
  date            DATE,
  final_status    TEXT,
  clock_in_at     TIMESTAMPTZ,
  flag_count      INTEGER,
  checks          JSONB,
  total_rows      BIGINT
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT
    ar.id              AS attendance_id,
    e.id               AS employee_id,
    e.full_name        AS employee_name,
    b.name             AS branch_name,
    d.name             AS department_name,
    ar.date,
    CASE WHEN ar.is_overridden THEN ar.override_status::TEXT ELSE ar.system_status::TEXT END AS final_status,
    ar.clock_in_at,
    ar.flag_count,
    (
      SELECT jsonb_agg(jsonb_build_object(
        'check_type', fc2.check_type,
        'result',     fc2.result,
        'details',    fc2.details
      ))
      FROM attendance_fraud_checks fc2
      WHERE fc2.attendance_id = ar.id
        AND (p_check_type IS NULL OR fc2.check_type::TEXT = p_check_type)
        AND fc2.result::TEXT = p_result
    ) AS checks,
    COUNT(*) OVER () AS total_rows
  FROM attendance_records ar
  JOIN employees e ON e.id = ar.employee_id
  LEFT JOIN branches    b ON b.id = e.branch_id
  LEFT JOIN departments d ON d.id = e.department_id
  WHERE ar.has_fraud_flag = TRUE
    AND ar.date BETWEEN p_date_from AND p_date_to
    AND (p_branch_id     IS NULL OR e.branch_id     = p_branch_id)
    AND (p_department_id IS NULL OR e.department_id = p_department_id)
    AND EXISTS (
      SELECT 1 FROM attendance_fraud_checks fc
      WHERE fc.attendance_id = ar.id
        AND fc.result::TEXT = p_result
        AND (p_check_type IS NULL OR fc.check_type::TEXT = p_check_type)
    )
  ORDER BY ar.date DESC, ar.flag_count DESC
  LIMIT  p_limit
  OFFSET p_offset;
$$;

COMMENT ON FUNCTION get_attendance_fraud_flags IS
  'List attendance yang punya fraud flag. Filter: date range, branch, dept, check_type, result.';

-- ─────────────────────────────────────────────────────────────
-- Grant semua RPC ke authenticated role
-- ─────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION get_admin_attendance_overview    TO authenticated;
GRANT EXECUTE ON FUNCTION get_admin_attendance_logs        TO authenticated;
GRANT EXECUTE ON FUNCTION get_admin_attendance_detail      TO authenticated;
GRANT EXECUTE ON FUNCTION get_monthly_attendance_summary   TO authenticated;
GRANT EXECUTE ON FUNCTION get_attendance_fraud_flags       TO authenticated;
GRANT EXECUTE ON FUNCTION admin_override_attendance        TO authenticated;
GRANT EXECUTE ON FUNCTION revert_attendance_override       TO authenticated;
