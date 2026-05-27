-- =============================================================================
-- MIGRATION 203: RPC employee_schedule_day_detail
-- Module   : Schedule Backend
-- Project  : Absensi Bianore
-- Purpose  : Detail lengkap satu hari: jadwal, absensi, dan impact cuti jika ada.
-- =============================================================================

CREATE OR REPLACE FUNCTION employee_schedule_day_detail(
    p_employee_id  UUID,
    p_work_date    DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_id  UUID;
    v_emp        RECORD;
    v_schedule   RECORD;
    v_attendance RECORD;
    v_leave      RECORD;
    v_result     JSONB;
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
    -- 2. Ambil data karyawan (tenant isolation)
    -- ----------------------------------------------------------------
    SELECT e.*, d.name AS dept_name, p.name AS pos_name
    INTO v_emp
    FROM employees e
    LEFT JOIN departments d ON d.id = e.department_id
    LEFT JOIN positions   p ON p.id = e.position_id
    WHERE e.id = p_employee_id;

    -- ----------------------------------------------------------------
    -- 3. Ambil jadwal hari itu
    -- ----------------------------------------------------------------
    SELECT
        es.*,
        b.name      AS branch_name,
        b.address   AS branch_address,
        b.city      AS branch_city,
        b.latitude  AS branch_lat,
        b.longitude AS branch_lon,
        b.radius_meters,
        -- work hours = (end - start) - break
        ROUND(
            (EXTRACT(EPOCH FROM (es.end_time - es.start_time)) / 3600.0) -
            (COALESCE(es.break_minutes, 60) / 60.0),
            1
        ) AS total_work_hours
    INTO v_schedule
    FROM employee_schedules es
    LEFT JOIN branches b ON b.id = es.branch_id
    WHERE es.employee_id = p_employee_id
      AND es.work_date   = p_work_date
      AND es.tenant_id   = v_emp.tenant_id
    LIMIT 1;

    -- ----------------------------------------------------------------
    -- 4. Ambil attendance record hari itu
    -- ----------------------------------------------------------------
    SELECT * INTO v_attendance
    FROM attendance_records
    WHERE employee_id = p_employee_id
      AND work_date   = p_work_date
      AND tenant_id   = v_emp.tenant_id
    LIMIT 1;

    -- ----------------------------------------------------------------
    -- 5. Ambil leave request yang disetujui pada hari itu
    -- ----------------------------------------------------------------
    SELECT lr.*, approver.employee_name AS approver_name
    INTO v_leave
    FROM leave_requests lr
    LEFT JOIN employees approver ON approver.id = lr.approver_id
    WHERE lr.employee_id = p_employee_id
      AND p_work_date BETWEEN lr.start_date AND lr.end_date
      AND lr.tenant_id   = v_emp.tenant_id
      AND lr.leave_status = 'approved'
    LIMIT 1;

    -- ----------------------------------------------------------------
    -- 6. Susun response
    -- ----------------------------------------------------------------
    v_result := jsonb_build_object(

        'date',     p_work_date,
        'day_name', TO_CHAR(p_work_date, 'Day'),
        'is_today', p_work_date = CURRENT_DATE,

        -- Detail jadwal
        'schedule', CASE
            WHEN v_schedule IS NULL THEN jsonb_build_object(
                'has_schedule', FALSE,
                'status',       'no_schedule'
            )
            ELSE jsonb_build_object(
                'has_schedule',   TRUE,
                'schedule_id',    v_schedule.id,
                'status',         v_schedule.schedule_status,
                'shift_name',     v_schedule.shift_name,
                'start_time',     TO_CHAR(v_schedule.start_time, 'HH24:MI'),
                'end_time',       TO_CHAR(v_schedule.end_time, 'HH24:MI'),
                'break_minutes',  v_schedule.break_minutes,
                'total_work_hours', v_schedule.total_work_hours,
                'late_threshold_minutes',      v_schedule.late_threshold_minutes,
                'very_late_threshold_minutes', v_schedule.very_late_threshold_minutes,
                'overtime_threshold_minutes',  v_schedule.overtime_threshold_minutes,
                'branch', CASE
                    WHEN v_schedule.branch_id IS NOT NULL THEN jsonb_build_object(
                        'id',            v_schedule.branch_id,
                        'name',          v_schedule.branch_name,
                        'address',       v_schedule.branch_address,
                        'city',          v_schedule.branch_city,
                        'latitude',      v_schedule.branch_lat,
                        'longitude',     v_schedule.branch_lon,
                        'radius_meters', v_schedule.radius_meters
                    )
                    ELSE NULL
                END
            )
        END,

        -- Detail absensi
        'attendance', CASE
            WHEN v_attendance IS NULL THEN jsonb_build_object(
                'has_record', FALSE,
                'status', CASE
                    WHEN v_leave IS NOT NULL THEN
                        CASE v_leave.leave_type::TEXT
                            WHEN 'sick_leave' THEN 'sick_leave'
                            ELSE 'leave'
                        END
                    WHEN v_schedule IS NULL THEN 'no_schedule'
                    WHEN p_work_date < CURRENT_DATE THEN 'absent'
                    ELSE 'not_checked_in'
                END
            )
            ELSE jsonb_build_object(
                'has_record',   TRUE,
                'status',       v_attendance.attendance_status,

                -- Check-in detail
                'checkin', CASE
                    WHEN v_attendance.checkin_time IS NULL THEN NULL
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

                -- Check-out detail
                'checkout', CASE
                    WHEN v_attendance.checkout_time IS NULL THEN NULL
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

                -- Kalkulasi
                'late_minutes',          v_attendance.late_minutes,
                'work_duration_minutes', v_attendance.work_duration_minutes,
                'overtime_minutes',      v_attendance.overtime_minutes
            )
        END,

        -- Impact cuti (null jika tidak ada)
        'leave_impact', CASE
            WHEN v_leave IS NULL THEN NULL
            ELSE jsonb_build_object(
                'leave_id',       v_leave.id,
                'leave_type',     v_leave.leave_type,
                'leave_status',   v_leave.leave_status,
                'start_date',     v_leave.start_date,
                'end_date',       v_leave.end_date,
                'total_days',     v_leave.total_days,
                'reason',         v_leave.reason,
                'attachment_url', v_leave.attachment_url,
                'approver_name',  v_leave.approver_name,
                'approved_at',    v_leave.approved_at,
                'approver_notes', v_leave.approver_notes
            )
        END,

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

GRANT EXECUTE ON FUNCTION employee_schedule_day_detail(UUID, DATE) TO authenticated;
REVOKE EXECUTE ON FUNCTION employee_schedule_day_detail(UUID, DATE) FROM anon;

COMMENT ON FUNCTION employee_schedule_day_detail(UUID, DATE) IS
'Detail satu hari: jadwal kerja lengkap (shift, branch, threshold), detail absensi
(check-in/out dengan GPS & selfie proof), kalkulasi (late/duration/overtime),
dan impact cuti yang disetujui jika ada.';
