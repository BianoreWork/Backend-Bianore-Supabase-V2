-- =============================================================================
-- MIGRATION 102: RPC employee_home_summary
-- Module   : Home Backend
-- Project  : Absensi Bianore
-- Purpose  : Semua data yang dibutuhkan Home screen mobile app dalam satu call.
-- =============================================================================

CREATE OR REPLACE FUNCTION employee_home_summary(
    p_employee_id  UUID,
    p_work_date    DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_employee_id  UUID;
    v_emp                 RECORD;
    v_schedule            RECORD;
    v_attendance          RECORD;
    v_today_status        TEXT;
    v_monthly             RECORD;
    v_recent              JSONB;
    v_unread_count        INT;
    v_result              JSONB;
BEGIN
    -- ----------------------------------------------------------------
    -- 1. Verifikasi autentikasi
    -- ----------------------------------------------------------------
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0401';
    END IF;

    -- ----------------------------------------------------------------
    -- 2. Verifikasi caller adalah employee yang dimaksud (employee isolation)
    -- ----------------------------------------------------------------
    SELECT id INTO v_caller_employee_id
    FROM employees
    WHERE user_id = auth.uid()
    LIMIT 1;

    IF v_caller_employee_id IS NULL THEN
        RAISE EXCEPTION 'EMPLOYEE_NOT_FOUND' USING ERRCODE = 'P0404';
    END IF;

    IF v_caller_employee_id <> p_employee_id THEN
        RAISE EXCEPTION 'FORBIDDEN: Tidak bisa mengakses data karyawan lain'
            USING ERRCODE = 'P0403';
    END IF;

    -- ----------------------------------------------------------------
    -- 3. Ambil data employee header + tenant isolation
    -- ----------------------------------------------------------------
    SELECT
        e.id, e.employee_code, e.employee_name, e.email, e.profile_photo_url,
        e.active_status, e.is_active, e.tenant_id,
        d.name AS department_name,
        p.name AS position_name,
        t.name AS tenant_name
    INTO v_emp
    FROM employees e
    LEFT JOIN departments d ON d.id = e.department_id
    LEFT JOIN positions   p ON p.id = e.position_id
    LEFT JOIN tenants     t ON t.id = e.tenant_id
    WHERE e.id = p_employee_id;

    -- Validasi status aktif
    IF NOT v_emp.is_active THEN
        RAISE EXCEPTION 'EMPLOYEE_INACTIVE' USING ERRCODE = 'P0403';
    END IF;
    IF v_emp.active_status IN ('resigned', 'terminated') THEN
        RAISE EXCEPTION 'EMPLOYEE_ACCESS_REVOKED' USING ERRCODE = 'P0403';
    END IF;

    -- ----------------------------------------------------------------
    -- 4. Ambil jadwal hari ini (tenant + employee isolation)
    -- ----------------------------------------------------------------
    SELECT
        es.id AS schedule_id, es.shift_name, es.start_time, es.end_time,
        es.break_minutes, es.late_threshold_minutes, es.very_late_threshold_minutes,
        es.overtime_threshold_minutes, es.schedule_status,
        b.id AS branch_id, b.name AS branch_name,
        b.address AS branch_address, b.city AS branch_city,
        b.latitude AS branch_latitude, b.longitude AS branch_longitude,
        b.radius_meters
    INTO v_schedule
    FROM employee_schedules es
    LEFT JOIN branches b ON b.id = es.branch_id
    WHERE es.employee_id = p_employee_id
      AND es.work_date   = p_work_date
      AND es.tenant_id   = v_emp.tenant_id
    LIMIT 1;

    -- ----------------------------------------------------------------
    -- 5. Ambil attendance record hari ini
    -- ----------------------------------------------------------------
    SELECT *
    INTO v_attendance
    FROM attendance_records
    WHERE employee_id = p_employee_id
      AND work_date   = p_work_date
      AND tenant_id   = v_emp.tenant_id
    LIMIT 1;

    -- ----------------------------------------------------------------
    -- 6. Tentukan status hari ini
    -- ----------------------------------------------------------------
    v_today_status := CASE
        WHEN v_schedule IS NULL OR v_schedule.schedule_id IS NULL
            THEN 'no_schedule'
        WHEN v_schedule.schedule_status = 'cancelled'
            THEN 'no_schedule'
        WHEN v_attendance IS NULL
            THEN 'not_checked_in'
        ELSE v_attendance.attendance_status::TEXT
    END;

    -- ----------------------------------------------------------------
    -- 7. Hitung unread notification count
    -- ----------------------------------------------------------------
    SELECT COUNT(*) INTO v_unread_count
    FROM notifications
    WHERE employee_id = p_employee_id
      AND tenant_id   = v_emp.tenant_id
      AND is_read     = FALSE;

    -- ----------------------------------------------------------------
    -- 8. Monthly summary (bulan dari p_work_date)
    -- ----------------------------------------------------------------
    SELECT
        COUNT(*) FILTER (WHERE ar.attendance_status IN ('checked_in', 'late', 'very_late', 'completed'))
            AS present_count,
        COUNT(*) FILTER (WHERE ar.attendance_status IN ('late', 'very_late'))
            AS late_count,
        COUNT(*) FILTER (WHERE ar.attendance_status = 'absent')
            AS absent_count,
        COALESCE(SUM(ar.overtime_minutes) FILTER (WHERE ar.attendance_status = 'completed'), 0)
            AS total_overtime_minutes
    INTO v_monthly
    FROM attendance_records ar
    WHERE ar.employee_id = p_employee_id
      AND ar.tenant_id   = v_emp.tenant_id
      AND DATE_TRUNC('month', ar.work_date) = DATE_TRUNC('month', p_work_date);

    -- ----------------------------------------------------------------
    -- 9. Recent attendance list (5 record terakhir, tidak termasuk hari ini)
    -- ----------------------------------------------------------------
    SELECT jsonb_agg(
        jsonb_build_object(
            'work_date',             r.work_date,
            'day_name',              TO_CHAR(r.work_date, 'Day'),
            'attendance_status',     r.attendance_status,
            'checkin_time',          TO_CHAR(r.checkin_time AT TIME ZONE 'Asia/Jakarta', 'HH24:MI'),
            'checkout_time',         TO_CHAR(r.checkout_time AT TIME ZONE 'Asia/Jakarta', 'HH24:MI'),
            'late_minutes',          r.late_minutes,
            'work_duration_minutes', r.work_duration_minutes,
            'overtime_minutes',      r.overtime_minutes
        )
        ORDER BY r.work_date DESC
    ) INTO v_recent
    FROM (
        SELECT * FROM attendance_records
        WHERE employee_id = p_employee_id
          AND tenant_id   = v_emp.tenant_id
          AND work_date   < p_work_date
        ORDER BY work_date DESC
        LIMIT 5
    ) r;

    -- ----------------------------------------------------------------
    -- 10. Susun response JSON
    -- ----------------------------------------------------------------
    v_result := jsonb_build_object(

        -- Header karyawan
        'employee', jsonb_build_object(
            'id',           v_emp.id,
            'code',         v_emp.employee_code,
            'name',         v_emp.employee_name,
            'email',        v_emp.email,
            'photo',        v_emp.profile_photo_url,
            'department',   v_emp.department_name,
            'position',     v_emp.position_name,
            'tenant_name',  v_emp.tenant_name
        ),

        -- Server date/time
        'server_date',      p_work_date,
        'server_time',      TO_CHAR(NOW() AT TIME ZONE 'Asia/Jakarta', 'HH24:MI:SS'),
        'server_timestamp', NOW(),

        -- Notifikasi
        'unread_notification_count', v_unread_count,

        -- Status hari ini
        'today_status', v_today_status,

        -- Jadwal hari ini (null jika tidak ada)
        'today_schedule', CASE
            WHEN v_schedule IS NULL OR v_schedule.schedule_id IS NULL THEN NULL
            ELSE jsonb_build_object(
                'schedule_id',    v_schedule.schedule_id,
                'shift_name',     v_schedule.shift_name,
                'start_time',     TO_CHAR(v_schedule.start_time, 'HH24:MI'),
                'end_time',       TO_CHAR(v_schedule.end_time, 'HH24:MI'),
                'break_minutes',  v_schedule.break_minutes,
                'branch', CASE
                    WHEN v_schedule.branch_id IS NOT NULL THEN jsonb_build_object(
                        'id',             v_schedule.branch_id,
                        'name',           v_schedule.branch_name,
                        'address',        v_schedule.branch_address,
                        'city',           v_schedule.branch_city,
                        'latitude',       v_schedule.branch_latitude,
                        'longitude',      v_schedule.branch_longitude,
                        'radius_meters',  v_schedule.radius_meters
                    )
                    ELSE NULL
                END
            )
        END,

        -- Data check-in (null jika belum check-in)
        'checkin', CASE
            WHEN v_attendance IS NULL OR v_attendance.checkin_time IS NULL THEN NULL
            ELSE jsonb_build_object(
                'time',           TO_CHAR(v_attendance.checkin_time AT TIME ZONE 'Asia/Jakarta', 'HH24:MI:SS'),
                'latitude',       v_attendance.checkin_latitude,
                'longitude',      v_attendance.checkin_longitude,
                'distance_meters',v_attendance.checkin_distance_meters,
                'location_name',  v_attendance.checkin_location_name,
                'selfie_url',     v_attendance.checkin_selfie_url,
                'gps_verified',   v_attendance.checkin_gps_verified,
                'selfie_verified',v_attendance.checkin_selfie_verified
            )
        END,

        -- Data check-out (null jika belum check-out)
        'checkout', CASE
            WHEN v_attendance IS NULL OR v_attendance.checkout_time IS NULL THEN NULL
            ELSE jsonb_build_object(
                'time',           TO_CHAR(v_attendance.checkout_time AT TIME ZONE 'Asia/Jakarta', 'HH24:MI:SS'),
                'latitude',       v_attendance.checkout_latitude,
                'longitude',      v_attendance.checkout_longitude,
                'distance_meters',v_attendance.checkout_distance_meters,
                'location_name',  v_attendance.checkout_location_name,
                'selfie_url',     v_attendance.checkout_selfie_url,
                'gps_verified',   v_attendance.checkout_gps_verified,
                'selfie_verified',v_attendance.checkout_selfie_verified
            )
        END,

        -- Kalkulasi kerja hari ini
        'work_calculation', jsonb_build_object(
            'late_minutes',          COALESCE(v_attendance.late_minutes, 0),
            'work_duration_minutes', COALESCE(v_attendance.work_duration_minutes, 0),
            'overtime_minutes',      COALESCE(v_attendance.overtime_minutes, 0)
        ),

        -- Summary bulanan
        'monthly_summary', jsonb_build_object(
            'month',            EXTRACT(MONTH FROM p_work_date),
            'year',             EXTRACT(YEAR  FROM p_work_date),
            'present_count',    COALESCE(v_monthly.present_count, 0),
            'late_count',       COALESCE(v_monthly.late_count, 0),
            'absent_count',     COALESCE(v_monthly.absent_count, 0),
            'overtime_hours',   ROUND(COALESCE(v_monthly.total_overtime_minutes, 0) / 60.0, 1)
        ),

        -- Riwayat absensi terakhir
        'recent_attendance', COALESCE(v_recent, '[]'::JSONB),

        -- Metadata
        'fetched_at', NOW()
    );

    RETURN v_result;

EXCEPTION
    WHEN SQLSTATE 'P0401' THEN RAISE;
    WHEN SQLSTATE 'P0403' THEN RAISE;
    WHEN SQLSTATE 'P0404' THEN RAISE;
    WHEN OTHERS THEN
        RAISE EXCEPTION 'INTERNAL_ERROR: %', SQLERRM USING ERRCODE = 'P0500';
END;
$$;

GRANT EXECUTE ON FUNCTION employee_home_summary(UUID, DATE) TO authenticated;
REVOKE EXECUTE ON FUNCTION employee_home_summary(UUID, DATE) FROM anon;

COMMENT ON FUNCTION employee_home_summary(UUID, DATE) IS
'Home screen data: header karyawan, jadwal hari ini, status absensi, check-in/out detail,
kalkulasi kerja, summary bulanan, dan riwayat absensi terakhir.
Hanya bisa dipanggil oleh karyawan yang bersangkutan (employee isolation).';
