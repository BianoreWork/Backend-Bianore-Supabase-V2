-- =============================================================================
-- MIGRATION 202: RPC employee_schedule_calendar
-- Module   : Schedule Backend
-- Project  : Absensi Bianore
-- Purpose  : Kalender bulanan karyawan — ringkasan + setiap hari dalam bulan.
-- =============================================================================

CREATE OR REPLACE FUNCTION employee_schedule_calendar(
    p_employee_id  UUID,
    p_month        INT,   -- 1–12
    p_year         INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_id     UUID;
    v_emp           RECORD;
    v_month_start   DATE;
    v_month_end     DATE;
    v_summary       RECORD;
    v_days          JSONB;
    v_result        JSONB;
BEGIN
    -- ----------------------------------------------------------------
    -- 1. Autentikasi & employee isolation
    -- ----------------------------------------------------------------
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0401';
    END IF;

    SELECT id INTO v_caller_id FROM employees WHERE user_id = auth.uid() LIMIT 1;

    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'EMPLOYEE_NOT_FOUND' USING ERRCODE = 'P0404';
    END IF;

    IF v_caller_id <> p_employee_id THEN
        RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'P0403';
    END IF;

    -- ----------------------------------------------------------------
    -- 2. Validasi parameter bulan/tahun
    -- ----------------------------------------------------------------
    IF p_month < 1 OR p_month > 12 THEN
        RAISE EXCEPTION 'INVALID_MONTH: Bulan harus antara 1–12' USING ERRCODE = 'P0422';
    END IF;

    IF p_year < 2020 OR p_year > 2100 THEN
        RAISE EXCEPTION 'INVALID_YEAR: Tahun tidak valid' USING ERRCODE = 'P0422';
    END IF;

    -- ----------------------------------------------------------------
    -- 3. Ambil data karyawan (tenant isolation)
    -- ----------------------------------------------------------------
    SELECT e.*, d.name AS department_name
    INTO v_emp
    FROM employees e
    LEFT JOIN departments d ON d.id = e.department_id
    WHERE e.id = p_employee_id;

    IF NOT v_emp.is_active THEN
        RAISE EXCEPTION 'EMPLOYEE_INACTIVE' USING ERRCODE = 'P0403';
    END IF;

    -- ----------------------------------------------------------------
    -- 4. Tentukan range bulan
    -- ----------------------------------------------------------------
    v_month_start := MAKE_DATE(p_year, p_month, 1);
    v_month_end   := (v_month_start + INTERVAL '1 month - 1 day')::DATE;

    -- ----------------------------------------------------------------
    -- 5. Monthly summary
    -- ----------------------------------------------------------------
    SELECT
        COUNT(ar.id) FILTER (
            WHERE ar.attendance_status IN ('checked_in', 'late', 'very_late', 'completed')
        ) AS present_count,

        COUNT(ar.id) FILTER (
            WHERE ar.attendance_status IN ('late', 'very_late')
        ) AS late_count,

        COUNT(ar.id) FILTER (
            WHERE ar.attendance_status = 'absent'
        ) AS absent_count,

        COUNT(lr.id) FILTER (
            WHERE lr.leave_type NOT IN ('sick_leave') AND lr.leave_status = 'approved'
        ) AS leave_count,

        COUNT(lr.id) FILTER (
            WHERE lr.leave_type = 'sick_leave' AND lr.leave_status = 'approved'
        ) AS sick_leave_count,

        ROUND(
            COALESCE(SUM(ar.overtime_minutes) FILTER (WHERE ar.attendance_status = 'completed'), 0) / 60.0,
            1
        ) AS overtime_hours

    INTO v_summary
    FROM employee_schedules es
    LEFT JOIN attendance_records ar
        ON ar.employee_id = es.employee_id
       AND ar.work_date   = es.work_date
       AND ar.tenant_id   = es.tenant_id
    LEFT JOIN leave_requests lr
        ON lr.employee_id = es.employee_id
       AND es.work_date BETWEEN lr.start_date AND lr.end_date
       AND lr.tenant_id   = es.tenant_id
       AND lr.leave_status = 'approved'
    WHERE es.employee_id = p_employee_id
      AND es.tenant_id   = v_emp.tenant_id
      AND es.work_date BETWEEN v_month_start AND v_month_end;

    -- ----------------------------------------------------------------
    -- 6. Generate calendar days — setiap tanggal dalam bulan
    -- ----------------------------------------------------------------
    SELECT jsonb_agg(
        jsonb_build_object(
            'date',         day_date,
            'day_name',     TO_CHAR(day_date, 'Day'),
            'day_number',   EXTRACT(DAY FROM day_date),
            'is_today',     day_date = CURRENT_DATE,
            'is_weekend',   EXTRACT(DOW FROM day_date) IN (0, 6),

            -- Jadwal
            'has_schedule',  es.id IS NOT NULL AND es.schedule_status = 'active',
            'schedule_id',   es.id,
            'shift_name',    es.shift_name,
            'start_time',    TO_CHAR(es.start_time, 'HH24:MI'),
            'end_time',      TO_CHAR(es.end_time, 'HH24:MI'),

            -- Status absensi
            'attendance_status', CASE
                -- Ada cuti disetujui
                WHEN lr.id IS NOT NULL AND lr.leave_status = 'approved' THEN
                    CASE lr.leave_type
                        WHEN 'sick_leave' THEN 'sick_leave'
                        ELSE 'leave'
                    END
                -- Tidak ada jadwal
                WHEN es.id IS NULL OR es.schedule_status <> 'active' THEN 'no_schedule'
                -- Ada jadwal, cek attendance
                WHEN ar.id IS NOT NULL THEN ar.attendance_status::TEXT
                -- Tanggal sudah lewat → absent
                WHEN day_date < CURRENT_DATE THEN 'absent'
                -- Tanggal mendatang → belum ada
                ELSE 'no_attendance'
            END,

            -- Waktu absensi
            'checkin_time',  TO_CHAR(ar.checkin_time  AT TIME ZONE 'Asia/Jakarta', 'HH24:MI'),
            'checkout_time', TO_CHAR(ar.checkout_time AT TIME ZONE 'Asia/Jakarta', 'HH24:MI'),

            -- Menit telat dan durasi
            'late_minutes',          COALESCE(ar.late_minutes, 0),
            'work_duration_minutes', COALESCE(ar.work_duration_minutes, 0),

            -- Marker warna untuk kalender
            'marker', CASE
                WHEN lr.id IS NOT NULL AND lr.leave_status = 'approved' THEN
                    CASE lr.leave_type WHEN 'sick_leave' THEN 'sick' ELSE 'leave' END
                WHEN es.id IS NULL OR es.schedule_status <> 'active' THEN 'none'
                WHEN ar.attendance_status = 'completed' THEN 'present'
                WHEN ar.attendance_status IN ('checked_in', 'late', 'very_late') THEN 'present'
                WHEN ar.attendance_status = 'absent' THEN 'absent'
                WHEN day_date < CURRENT_DATE THEN 'absent'
                WHEN day_date = CURRENT_DATE THEN 'today'
                ELSE 'scheduled'
            END
        )
        ORDER BY day_date ASC
    ) INTO v_days
    FROM generate_series(v_month_start, v_month_end, '1 day'::INTERVAL) AS gs(day_date)
    LEFT JOIN employee_schedules es
        ON es.employee_id = p_employee_id
       AND es.work_date   = gs.day_date::DATE
       AND es.tenant_id   = v_emp.tenant_id
    LEFT JOIN attendance_records ar
        ON ar.employee_id = p_employee_id
       AND ar.work_date   = gs.day_date::DATE
       AND ar.tenant_id   = v_emp.tenant_id
    LEFT JOIN leave_requests lr
        ON lr.employee_id = p_employee_id
       AND gs.day_date::DATE BETWEEN lr.start_date AND lr.end_date
       AND lr.tenant_id   = v_emp.tenant_id
       AND lr.leave_status = 'approved';

    -- ----------------------------------------------------------------
    -- 7. Susun response
    -- ----------------------------------------------------------------
    v_result := jsonb_build_object(
        'employee_id',  p_employee_id,
        'month',        p_month,
        'year',         p_year,
        'month_label',  TO_CHAR(v_month_start, 'Month YYYY'),

        'monthly_summary', jsonb_build_object(
            'present_count',    COALESCE(v_summary.present_count, 0),
            'late_count',       COALESCE(v_summary.late_count, 0),
            'absent_count',     COALESCE(v_summary.absent_count, 0),
            'leave_count',      COALESCE(v_summary.leave_count, 0),
            'sick_leave_count', COALESCE(v_summary.sick_leave_count, 0),
            'overtime_hours',   COALESCE(v_summary.overtime_hours, 0)
        ),

        'days',      COALESCE(v_days, '[]'::JSONB),
        'fetched_at', NOW()
    );

    RETURN v_result;

EXCEPTION
    WHEN SQLSTATE 'P0401' THEN RAISE;
    WHEN SQLSTATE 'P0403' THEN RAISE;
    WHEN SQLSTATE 'P0404' THEN RAISE;
    WHEN SQLSTATE 'P0422' THEN RAISE;
    WHEN OTHERS THEN
        RAISE EXCEPTION 'INTERNAL_ERROR: %', SQLERRM USING ERRCODE = 'P0500';
END;
$$;

GRANT EXECUTE ON FUNCTION employee_schedule_calendar(UUID, INT, INT) TO authenticated;
REVOKE EXECUTE ON FUNCTION employee_schedule_calendar(UUID, INT, INT) FROM anon;

COMMENT ON FUNCTION employee_schedule_calendar(UUID, INT, INT) IS
'Kalender bulanan karyawan: summary bulanan + setiap hari dengan status jadwal,
absensi, cuti, dan marker warna. Support: present, late, absent, leave, sick_leave, no_schedule.';
