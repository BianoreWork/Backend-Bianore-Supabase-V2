-- =============================================================================
-- MIGRATION 104: RPC employee_check_out
-- Module   : Home Backend
-- Project  : Absensi Bianore
-- Purpose  : Proses check-out karyawan. Validasi sudah check-in, belum check-out,
--            hitung work_duration dan overtime otomatis.
-- =============================================================================

CREATE OR REPLACE FUNCTION employee_check_out(
    p_employee_id   UUID,
    p_latitude      NUMERIC,
    p_longitude     NUMERIC,
    p_selfie_url    TEXT,
    p_location_name TEXT    DEFAULT NULL,
    p_work_date     DATE    DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_id        UUID;
    v_emp              RECORD;
    v_schedule         RECORD;
    v_attendance       RECORD;
    v_checkout_time    TIMESTAMPTZ := NOW();
    v_distance_m       INT;
    v_gps_verified     BOOLEAN := FALSE;
    v_selfie_verified  BOOLEAN := FALSE;
    v_work_duration_m  INT := 0;
    v_overtime_m       INT := 0;
    v_shift_end_today  TIMESTAMPTZ;
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
        RAISE EXCEPTION 'FORBIDDEN: Tidak bisa check-out atas nama karyawan lain'
            USING ERRCODE = 'P0403';
    END IF;

    -- ----------------------------------------------------------------
    -- 2. Ambil data karyawan + validasi aktif
    -- ----------------------------------------------------------------
    SELECT * INTO v_emp FROM employees WHERE id = p_employee_id;

    IF NOT v_emp.is_active OR v_emp.active_status IN ('resigned', 'terminated', 'inactive') THEN
        RAISE EXCEPTION 'EMPLOYEE_INACTIVE' USING ERRCODE = 'P0403';
    END IF;

    -- ----------------------------------------------------------------
    -- 3. Validasi GPS wajib ada
    -- ----------------------------------------------------------------
    IF p_latitude IS NULL OR p_longitude IS NULL THEN
        RAISE EXCEPTION 'GPS_REQUIRED: Koordinat GPS wajib disertakan saat check-out'
            USING ERRCODE = 'P0422';
    END IF;

    -- ----------------------------------------------------------------
    -- 4. Validasi selfie wajib ada
    -- ----------------------------------------------------------------
    IF p_selfie_url IS NULL OR TRIM(p_selfie_url) = '' THEN
        RAISE EXCEPTION 'SELFIE_REQUIRED: Foto selfie wajib disertakan saat check-out'
            USING ERRCODE = 'P0422';
    END IF;

    -- ----------------------------------------------------------------
    -- 5. Ambil attendance record — validasi sudah check-in
    -- ----------------------------------------------------------------
    SELECT * INTO v_attendance
    FROM attendance_records
    WHERE employee_id = p_employee_id
      AND work_date   = p_work_date
      AND tenant_id   = v_emp.tenant_id
    LIMIT 1;

    IF v_attendance IS NULL THEN
        RAISE EXCEPTION 'NOT_CHECKED_IN: Karyawan belum check-in hari ini, tidak bisa check-out'
            USING ERRCODE = 'P0409';
    END IF;

    -- ----------------------------------------------------------------
    -- 6. Validasi belum check-out (tidak bisa check-out dua kali)
    -- ----------------------------------------------------------------
    IF v_attendance.checkout_time IS NOT NULL THEN
        RAISE EXCEPTION 'ALREADY_CHECKED_OUT: Karyawan sudah check-out hari ini pada %',
            TO_CHAR(v_attendance.checkout_time AT TIME ZONE 'Asia/Jakarta', 'HH24:MI')
            USING ERRCODE = 'P0409';
    END IF;

    -- ----------------------------------------------------------------
    -- 7. Ambil jadwal untuk hitung overtime
    -- ----------------------------------------------------------------
    SELECT es.*, b.latitude AS br_lat, b.longitude AS br_lon, b.radius_meters
    INTO v_schedule
    FROM employee_schedules es
    LEFT JOIN branches b ON b.id = es.branch_id
    WHERE es.employee_id = p_employee_id
      AND es.work_date   = p_work_date
      AND es.tenant_id   = v_emp.tenant_id
    LIMIT 1;

    -- ----------------------------------------------------------------
    -- 8. Hitung jarak ke lokasi kerja
    -- ----------------------------------------------------------------
    IF v_schedule IS NOT NULL AND v_schedule.br_lat IS NOT NULL AND v_schedule.br_lon IS NOT NULL THEN
        v_distance_m := calculate_distance_meters(
            p_latitude, p_longitude,
            v_schedule.br_lat, v_schedule.br_lon
        );
        -- Check-out tidak wajib dalam radius (karyawan bisa pergi setelah selesai)
        -- Hanya dicatat, tidak diblokir
        v_gps_verified := (v_distance_m <= COALESCE(v_schedule.radius_meters, 200));
    ELSE
        v_distance_m   := 0;
        v_gps_verified := TRUE;
    END IF;

    v_selfie_verified := TRUE;

    -- ----------------------------------------------------------------
    -- 9. Hitung work_duration dan overtime
    -- ----------------------------------------------------------------
    v_work_duration_m := GREATEST(
        0,
        EXTRACT(EPOCH FROM (v_checkout_time - v_attendance.checkin_time)) / 60 -
        COALESCE(v_schedule.break_minutes, 60)
    )::INT;

    IF v_schedule IS NOT NULL THEN
        v_shift_end_today := (p_work_date::TEXT || ' ' || v_schedule.end_time::TEXT)::TIMESTAMPTZ
                             AT TIME ZONE 'Asia/Jakarta';

        v_overtime_m := GREATEST(
            0,
            EXTRACT(EPOCH FROM (v_checkout_time - v_shift_end_today)) / 60 -
            COALESCE(v_schedule.overtime_threshold_minutes, 30)
        )::INT;
    END IF;

    -- ----------------------------------------------------------------
    -- 10. Update attendance_record
    -- ----------------------------------------------------------------
    UPDATE attendance_records
    SET
        checkout_time            = v_checkout_time,
        checkout_latitude        = p_latitude,
        checkout_longitude       = p_longitude,
        checkout_distance_meters = v_distance_m,
        checkout_location_name   = COALESCE(p_location_name, checkout_location_name),
        checkout_selfie_url      = p_selfie_url,
        checkout_gps_verified    = v_gps_verified,
        checkout_selfie_verified = v_selfie_verified,
        work_duration_minutes    = v_work_duration_m,
        overtime_minutes         = v_overtime_m,
        attendance_status        = 'completed'
    WHERE id = v_attendance.id;

    -- ----------------------------------------------------------------
    -- 11. Simpan attendance event log
    -- ----------------------------------------------------------------
    INSERT INTO attendance_events (
        tenant_id, employee_id, attendance_record_id, work_date,
        event_type, event_time,
        latitude, longitude, distance_meters, location_name,
        selfie_url, gps_verified, selfie_verified
    )
    VALUES (
        v_emp.tenant_id, p_employee_id, v_attendance.id, p_work_date,
        'check_out', v_checkout_time,
        p_latitude, p_longitude, v_distance_m, p_location_name,
        p_selfie_url, v_gps_verified, v_selfie_verified
    );

    -- ----------------------------------------------------------------
    -- 12. Return updated home summary
    -- ----------------------------------------------------------------
    RETURN employee_home_summary(p_employee_id, p_work_date);

EXCEPTION
    WHEN SQLSTATE 'P0401' THEN RAISE;
    WHEN SQLSTATE 'P0403' THEN RAISE;
    WHEN SQLSTATE 'P0404' THEN RAISE;
    WHEN SQLSTATE 'P0409' THEN RAISE;
    WHEN SQLSTATE 'P0422' THEN RAISE;
    WHEN OTHERS THEN
        RAISE EXCEPTION 'INTERNAL_ERROR: %', SQLERRM USING ERRCODE = 'P0500';
END;
$$;

GRANT EXECUTE ON FUNCTION employee_check_out(UUID, NUMERIC, NUMERIC, TEXT, TEXT, DATE) TO authenticated;
REVOKE EXECUTE ON FUNCTION employee_check_out(UUID, NUMERIC, NUMERIC, TEXT, TEXT, DATE) FROM anon;

COMMENT ON FUNCTION employee_check_out(UUID, NUMERIC, NUMERIC, TEXT, TEXT, DATE) IS
'Check-out karyawan. Validasi: sudah check-in, belum check-out, GPS & selfie wajib.
Menghitung work_duration_minutes dan overtime_minutes otomatis.
GPS check-out tidak memblokir (hanya dicatat) karena karyawan bisa sudah keluar area.
Return: employee_home_summary yang sudah diupdate.';
