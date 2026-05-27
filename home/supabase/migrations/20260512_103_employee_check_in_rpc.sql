-- =============================================================================
-- MIGRATION 103: RPC employee_check_in
-- Module   : Home Backend
-- Project  : Absensi Bianore
-- Purpose  : Proses check-in karyawan dengan validasi GPS, selfie, jadwal,
--            radius lokasi, dan kalkulasi status keterlambatan.
-- =============================================================================

CREATE OR REPLACE FUNCTION employee_check_in(
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
    v_caller_id       UUID;
    v_emp             RECORD;
    v_schedule        RECORD;
    v_existing        RECORD;
    v_checkin_time    TIMESTAMPTZ := NOW();
    v_distance_m      INT;
    v_gps_verified    BOOLEAN := FALSE;
    v_selfie_verified BOOLEAN := FALSE;
    v_late_mins       INT := 0;
    v_attend_status   attendance_status_enum;
    v_record_id       UUID;
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
        RAISE EXCEPTION 'FORBIDDEN: Tidak bisa check-in atas nama karyawan lain'
            USING ERRCODE = 'P0403';
    END IF;

    -- ----------------------------------------------------------------
    -- 2. Ambil dan validasi data karyawan
    -- ----------------------------------------------------------------
    SELECT e.*, t.name AS tenant_name
    INTO v_emp
    FROM employees e
    JOIN tenants t ON t.id = e.tenant_id
    WHERE e.id = p_employee_id;

    IF NOT v_emp.is_active OR v_emp.active_status IN ('resigned', 'terminated', 'inactive') THEN
        RAISE EXCEPTION 'EMPLOYEE_INACTIVE: Karyawan tidak aktif, tidak bisa check-in'
            USING ERRCODE = 'P0403';
    END IF;

    -- ----------------------------------------------------------------
    -- 3. Validasi GPS wajib ada
    -- ----------------------------------------------------------------
    IF p_latitude IS NULL OR p_longitude IS NULL THEN
        RAISE EXCEPTION 'GPS_REQUIRED: Koordinat GPS wajib disertakan saat check-in'
            USING ERRCODE = 'P0422';
    END IF;

    -- ----------------------------------------------------------------
    -- 4. Validasi selfie wajib ada
    -- ----------------------------------------------------------------
    IF p_selfie_url IS NULL OR TRIM(p_selfie_url) = '' THEN
        RAISE EXCEPTION 'SELFIE_REQUIRED: Foto selfie wajib disertakan saat check-in'
            USING ERRCODE = 'P0422';
    END IF;

    -- ----------------------------------------------------------------
    -- 5. Ambil jadwal hari ini (validasi schedule tersedia & milik employee ini)
    -- ----------------------------------------------------------------
    SELECT es.*, b.latitude AS br_lat, b.longitude AS br_lon, b.radius_meters
    INTO v_schedule
    FROM employee_schedules es
    LEFT JOIN branches b ON b.id = es.branch_id
    WHERE es.employee_id = p_employee_id
      AND es.work_date   = p_work_date
      AND es.tenant_id   = v_emp.tenant_id
      AND es.schedule_status = 'active'
    LIMIT 1;

    IF v_schedule IS NULL THEN
        RAISE EXCEPTION 'NO_SCHEDULE: Tidak ada jadwal kerja untuk tanggal ini'
            USING ERRCODE = 'P0404';
    END IF;

    -- ----------------------------------------------------------------
    -- 6. Validasi belum check-in (tidak bisa check-in dua kali)
    -- ----------------------------------------------------------------
    SELECT * INTO v_existing
    FROM attendance_records
    WHERE employee_id = p_employee_id
      AND work_date   = p_work_date
      AND tenant_id   = v_emp.tenant_id
    LIMIT 1;

    IF v_existing IS NOT NULL THEN
        RAISE EXCEPTION 'ALREADY_CHECKED_IN: Karyawan sudah check-in hari ini pada %',
            TO_CHAR(v_existing.checkin_time AT TIME ZONE 'Asia/Jakarta', 'HH24:MI')
            USING ERRCODE = 'P0409';
    END IF;

    -- ----------------------------------------------------------------
    -- 7. Hitung jarak ke lokasi kerja & validasi radius
    -- ----------------------------------------------------------------
    IF v_schedule.br_lat IS NOT NULL AND v_schedule.br_lon IS NOT NULL THEN
        v_distance_m := calculate_distance_meters(
            p_latitude, p_longitude,
            v_schedule.br_lat, v_schedule.br_lon
        );

        IF v_distance_m <= COALESCE(v_schedule.radius_meters, 200) THEN
            v_gps_verified := TRUE;
        ELSE
            RAISE EXCEPTION 'OUT_OF_RANGE: Lokasi kamu (% m) di luar radius kerja (% m). Pastikan kamu berada di lokasi yang benar.',
                v_distance_m, COALESCE(v_schedule.radius_meters, 200)
                USING ERRCODE = 'P0422';
        END IF;
    ELSE
        -- Tidak ada branch / lokasi kerja → GPS verified by default (remote/WFH)
        v_distance_m   := 0;
        v_gps_verified := TRUE;
    END IF;

    -- ----------------------------------------------------------------
    -- 8. Selfie verified = TRUE (validasi liveness/face detection dilakukan
    --    di sisi mobile sebelum upload; URL yang ada = sudah valid)
    -- ----------------------------------------------------------------
    v_selfie_verified := TRUE;

    -- ----------------------------------------------------------------
    -- 9. Hitung late_minutes dan attendance_status
    -- ----------------------------------------------------------------
    DECLARE
        v_scheduled_start TIMESTAMPTZ;
        v_shift_start_today TIMESTAMPTZ;
    BEGIN
        -- Konversi start_time ke TIMESTAMPTZ di hari ini (WIB = UTC+7)
        v_shift_start_today := (p_work_date::TEXT || ' ' || v_schedule.start_time::TEXT)::TIMESTAMPTZ
                               AT TIME ZONE 'Asia/Jakarta';

        v_late_mins := GREATEST(
            0,
            EXTRACT(EPOCH FROM (v_checkin_time - v_shift_start_today)) / 60
        )::INT;

        v_attend_status := CASE
            WHEN v_late_mins >= v_schedule.very_late_threshold_minutes THEN 'very_late'
            WHEN v_late_mins >  0                                       THEN 'late'
            ELSE 'checked_in'
        END;
    END;

    -- ----------------------------------------------------------------
    -- 10. Simpan attendance_record
    -- ----------------------------------------------------------------
    INSERT INTO attendance_records (
        tenant_id, employee_id, schedule_id, work_date,
        attendance_status,
        checkin_time, checkin_latitude, checkin_longitude,
        checkin_distance_meters, checkin_location_name,
        checkin_selfie_url, checkin_gps_verified, checkin_selfie_verified,
        late_minutes
    )
    VALUES (
        v_emp.tenant_id, p_employee_id, v_schedule.id, p_work_date,
        v_attend_status,
        v_checkin_time, p_latitude, p_longitude,
        v_distance_m, COALESCE(p_location_name, v_schedule.shift_name || ' — ' || COALESCE(v_schedule.branch_id::TEXT, 'Remote')),
        p_selfie_url, v_gps_verified, v_selfie_verified,
        v_late_mins
    )
    RETURNING id INTO v_record_id;

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
        v_emp.tenant_id, p_employee_id, v_record_id, p_work_date,
        'check_in', v_checkin_time,
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

GRANT EXECUTE ON FUNCTION employee_check_in(UUID, NUMERIC, NUMERIC, TEXT, TEXT, DATE) TO authenticated;
REVOKE EXECUTE ON FUNCTION employee_check_in(UUID, NUMERIC, NUMERIC, TEXT, TEXT, DATE) FROM anon;

COMMENT ON FUNCTION employee_check_in(UUID, NUMERIC, NUMERIC, TEXT, TEXT, DATE) IS
'Check-in karyawan. Validasi: GPS wajib, selfie wajib, jadwal harus ada,
radius lokasi kerja, tidak bisa check-in dua kali.
Menghitung late_minutes dan attendance_status otomatis.
Return: employee_home_summary yang sudah diupdate.';
