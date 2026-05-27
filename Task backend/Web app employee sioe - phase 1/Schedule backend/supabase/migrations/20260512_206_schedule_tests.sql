-- =============================================================================
-- MIGRATION 206: Test Scripts — Schedule Backend
-- =============================================================================

-- ============================================================================
-- TEST 1 ✅ schedule_calendar — bulan berjalan, return semua hari
-- ============================================================================
DO $$ DECLARE r JSONB; days_count INT; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-1','role','authenticated')::text, TRUE);

    SELECT employee_schedule_calendar(
        'aaaaaaaa-0000-0000-0000-000000000001',
        EXTRACT(MONTH FROM CURRENT_DATE)::INT,
        EXTRACT(YEAR  FROM CURRENT_DATE)::INT
    ) INTO r;

    days_count := jsonb_array_length(r->'days');

    ASSERT days_count = EXTRACT(DAY FROM (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month - 1 day'))::INT,
        'FAIL T1: jumlah hari tidak sesuai, dapat: ' || days_count;
    ASSERT (r->'monthly_summary') IS NOT NULL, 'FAIL T1: monthly_summary harus ada';
    ASSERT (r->>'month')::INT = EXTRACT(MONTH FROM CURRENT_DATE)::INT, 'FAIL T1: month tidak sesuai';
    RAISE NOTICE 'TEST 1 PASSED ✅ — calendar % hari di bulan ini', days_count;
END $$;

-- ============================================================================
-- TEST 2 ✅ schedule_calendar — hari dengan jadwal punya has_schedule = true
-- ============================================================================
DO $$ DECLARE r JSONB; today_day JSONB; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-1','role','authenticated')::text, TRUE);

    SELECT employee_schedule_calendar(
        'aaaaaaaa-0000-0000-0000-000000000001',
        EXTRACT(MONTH FROM CURRENT_DATE)::INT,
        EXTRACT(YEAR  FROM CURRENT_DATE)::INT
    ) INTO r;

    -- Ambil entry hari ini dari array days
    SELECT elem INTO today_day
    FROM jsonb_array_elements(r->'days') elem
    WHERE (elem->>'date') = CURRENT_DATE::TEXT
    LIMIT 1;

    ASSERT today_day IS NOT NULL, 'FAIL T2: hari ini tidak ada di calendar';
    ASSERT (today_day->>'has_schedule')::BOOLEAN = TRUE,
        'FAIL T2: has_schedule harus true untuk hari ini';
    ASSERT (today_day->>'shift_name') IS NOT NULL, 'FAIL T2: shift_name harus ada';
    RAISE NOTICE 'TEST 2 PASSED ✅ — hari ini punya jadwal: %', today_day->>'shift_name';
END $$;

-- ============================================================================
-- TEST 3 ✅ schedule_calendar — pindah bulan (bulan depan)
-- ============================================================================
DO $$ DECLARE r JSONB; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-1','role','authenticated')::text, TRUE);

    SELECT employee_schedule_calendar(
        'aaaaaaaa-0000-0000-0000-000000000001',
        CASE WHEN EXTRACT(MONTH FROM CURRENT_DATE) = 12 THEN 1
             ELSE EXTRACT(MONTH FROM CURRENT_DATE)::INT + 1 END,
        CASE WHEN EXTRACT(MONTH FROM CURRENT_DATE) = 12 THEN EXTRACT(YEAR FROM CURRENT_DATE)::INT + 1
             ELSE EXTRACT(YEAR FROM CURRENT_DATE)::INT END
    ) INTO r;

    ASSERT (r->'days') IS NOT NULL, 'FAIL T3: days harus ada untuk bulan depan';
    RAISE NOTICE 'TEST 3 PASSED ✅ — pindah ke bulan depan berhasil: %', r->>'month_label';
END $$;

-- ============================================================================
-- TEST 4 ✅ schedule_calendar — cuti sakit ditampilkan di kalender (Rina)
-- ============================================================================
DO $$ DECLARE r JSONB; leave_day JSONB; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-5','role','authenticated')::text, TRUE);

    SELECT employee_schedule_calendar(
        'aaaaaaaa-0000-0000-0000-000000000005',  -- Rina (on-leave/sick)
        EXTRACT(MONTH FROM CURRENT_DATE)::INT,
        EXTRACT(YEAR  FROM CURRENT_DATE)::INT
    ) INTO r;

    SELECT elem INTO leave_day
    FROM jsonb_array_elements(r->'days') elem
    WHERE (elem->>'date') = CURRENT_DATE::TEXT LIMIT 1;

    ASSERT (leave_day->>'attendance_status') IN ('sick_leave', 'leave', 'no_schedule'),
        'FAIL T4: Rina harusnya sick_leave/leave di hari ini';
    RAISE NOTICE 'TEST 4 PASSED ✅ — Rina on-leave, status hari ini: %',
        leave_day->>'attendance_status';
END $$;

-- ============================================================================
-- TEST 5 ✅ schedule_day_detail — hari dengan jadwal & attendance selesai
-- ============================================================================
DO $$ DECLARE r JSONB; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-1','role','authenticated')::text, TRUE);

    SELECT employee_schedule_day_detail(
        'aaaaaaaa-0000-0000-0000-000000000001',
        CURRENT_DATE - 1  -- kemarin (ada jadwal + attendance completed dari seed)
    ) INTO r;

    ASSERT (r->'schedule'->>'has_schedule')::BOOLEAN = TRUE,
        'FAIL T5: kemarin harus punya jadwal';
    ASSERT (r->'attendance'->>'has_record')::BOOLEAN = TRUE,
        'FAIL T5: kemarin harus punya attendance record';
    ASSERT (r->'attendance'->>'status') = 'completed',
        'FAIL T5: status kemarin harus completed, dapat: ' || (r->'attendance'->>'status');
    ASSERT (r->'attendance'->'checkin') IS NOT NULL, 'FAIL T5: checkin harus ada';
    ASSERT (r->'attendance'->'checkout') IS NOT NULL, 'FAIL T5: checkout harus ada';
    RAISE NOTICE 'TEST 5 PASSED ✅ — day_detail kemarin: completed';
END $$;

-- ============================================================================
-- TEST 6 ✅ schedule_day_detail — tanpa jadwal (no_schedule)
-- Tanggal yang memang tidak ada di seed schedules
-- ============================================================================
DO $$ DECLARE r JSONB; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-1','role','authenticated')::text, TRUE);

    SELECT employee_schedule_day_detail(
        'aaaaaaaa-0000-0000-0000-000000000001',
        CURRENT_DATE - 4  -- 4 hari lalu, tidak ada seed schedule
    ) INTO r;

    ASSERT (r->'schedule'->>'has_schedule')::BOOLEAN = FALSE,
        'FAIL T6: harus no_schedule, dapat: ' || (r->'schedule'->>'has_schedule');
    ASSERT (r->'attendance'->>'status') = 'no_schedule'
        OR (r->'attendance'->>'status') = 'absent',
        'FAIL T6: status harus no_schedule/absent';
    RAISE NOTICE 'TEST 6 PASSED ✅ — day_detail no_schedule: %',
        r->'attendance'->>'status';
END $$;

-- ============================================================================
-- TEST 7 ✅ schedule_day_detail — hari dengan cuti sakit (Rina)
-- ============================================================================
DO $$ DECLARE r JSONB; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-5','role','authenticated')::text, TRUE);

    SELECT employee_schedule_day_detail(
        'aaaaaaaa-0000-0000-0000-000000000005',  -- Rina
        CURRENT_DATE
    ) INTO r;

    ASSERT (r->'leave_impact') IS NOT NULL,
        'FAIL T7: leave_impact harus ada untuk Rina';
    ASSERT (r->'leave_impact'->>'leave_type') = 'sick_leave',
        'FAIL T7: leave_type harus sick_leave';
    RAISE NOTICE 'TEST 7 PASSED ✅ — day_detail Rina: sick_leave terdapat di leave_impact';
END $$;

-- ============================================================================
-- TEST 8 ❌ schedule_calendar — bulan tidak valid
-- ============================================================================
DO $$ DECLARE r JSONB; err TEXT; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-1','role','authenticated')::text, TRUE);
    BEGIN
        SELECT employee_schedule_calendar('aaaaaaaa-0000-0000-0000-000000000001', 13, 2026) INTO r;
        RAISE EXCEPTION 'FAIL T8: Harus diblokir bulan tidak valid';
    EXCEPTION WHEN OTHERS THEN
        err := SQLERRM;
        IF err LIKE '%INVALID_MONTH%' THEN
            RAISE NOTICE 'TEST 8 PASSED ✅ — bulan 13 diblokir: %', err;
        ELSE RAISE EXCEPTION 'FAIL T8: error bukan INVALID_MONTH: %', err; END IF;
    END;
END $$;

DO $$ BEGIN
RAISE NOTICE '
=================================================
 SCHEDULE BACKEND — Test Summary
=================================================
 T1  ✅  calendar bulan berjalan (jumlah hari sesuai)
 T2  ✅  hari ini punya jadwal (has_schedule = true)
 T3  ✅  pindah ke bulan depan
 T4  ✅  cuti sakit tampil di kalender (Rina)
 T5  ✅  day_detail: kemarin completed (checkin + checkout)
 T6  ✅  day_detail: no_schedule
 T7  ✅  day_detail: leave_impact ada di hari cuti
 T8  ❌  bulan 13 → BLOCKED (INVALID_MONTH)
=================================================';
END $$;
