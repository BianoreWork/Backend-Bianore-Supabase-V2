-- =============================================================================
-- MIGRATION 107: Test Scripts — Home Backend
-- Ganti 'auth-user-uuid-replace-X' dengan UUID auth.users asli sebelum dijalankan.
-- =============================================================================

-- ============================================================================
-- TEST 1 ✅ home_summary — belum check-in (today_status = not_checked_in)
-- ============================================================================
DO $$ DECLARE r JSONB; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-1','role','authenticated')::text, TRUE);

    SELECT employee_home_summary('aaaaaaaa-0000-0000-0000-000000000001', CURRENT_DATE) INTO r;

    ASSERT (r->>'today_status') = 'not_checked_in', 'FAIL T1: status harus not_checked_in, dapat: ' || (r->>'today_status');
    ASSERT (r->'today_schedule') IS NOT NULL,       'FAIL T1: today_schedule harus ada';
    ASSERT (r->'checkin')        IS NULL,            'FAIL T1: checkin harus null';
    ASSERT (r->'monthly_summary') IS NOT NULL,       'FAIL T1: monthly_summary harus ada';
    ASSERT jsonb_array_length(r->'recent_attendance') > 0, 'FAIL T1: recent_attendance harus ada isinya';
    ASSERT (r->>'unread_notification_count')::INT = 2, 'FAIL T1: unread notif harus 2';
    RAISE NOTICE 'TEST 1 PASSED ✅ — home_summary: not_checked_in';
END $$;

-- ============================================================================
-- TEST 2 ✅ employee_check_in — sukses, GPS dalam radius
-- ============================================================================
DO $$ DECLARE r JSONB; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-1','role','authenticated')::text, TRUE);

    SELECT employee_check_in(
        'aaaaaaaa-0000-0000-0000-000000000001',
        -6.208763,  106.845599,       -- koordinat tepat di HQ Jakarta
        'https://cdn.bianore.com/selfie/test-checkin.jpg',
        'HQ Jakarta Pusat',
        CURRENT_DATE
    ) INTO r;

    ASSERT (r->>'today_status') IN ('checked_in', 'late', 'very_late'),
        'FAIL T2: status harus checked_in/late/very_late, dapat: ' || (r->>'today_status');
    ASSERT (r->'checkin') IS NOT NULL, 'FAIL T2: checkin harus ada setelah check-in';
    ASSERT (r->'checkin'->>'gps_verified') = 'true', 'FAIL T2: gps_verified harus true';
    RAISE NOTICE 'TEST 2 PASSED ✅ — check_in sukses, status: %', r->>'today_status';
END $$;

-- ============================================================================
-- TEST 3 ❌ employee_check_in — sudah check-in (double check-in)
-- ============================================================================
DO $$ DECLARE r JSONB; err TEXT; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-1','role','authenticated')::text, TRUE);
    BEGIN
        SELECT employee_check_in('aaaaaaaa-0000-0000-0000-000000000001',
            -6.208763, 106.845599, 'https://cdn.bianore.com/selfie/test.jpg', NULL, CURRENT_DATE) INTO r;
        RAISE EXCEPTION 'FAIL T3: Harus diblokir double check-in';
    EXCEPTION WHEN OTHERS THEN
        err := SQLERRM;
        IF err LIKE '%ALREADY_CHECKED_IN%' THEN
            RAISE NOTICE 'TEST 3 PASSED ✅ — double check-in diblokir: %', err;
        ELSE RAISE EXCEPTION 'FAIL T3: error bukan ALREADY_CHECKED_IN: %', err; END IF;
    END;
END $$;

-- ============================================================================
-- TEST 4 ✅ home_summary — setelah check-in (today_status = checked_in/late/very_late)
-- ============================================================================
DO $$ DECLARE r JSONB; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-1','role','authenticated')::text, TRUE);

    SELECT employee_home_summary('aaaaaaaa-0000-0000-0000-000000000001', CURRENT_DATE) INTO r;

    ASSERT (r->>'today_status') IN ('checked_in','late','very_late'),
        'FAIL T4: status harus checked_in/late/very_late';
    ASSERT (r->'checkin') IS NOT NULL, 'FAIL T4: checkin harus ada';
    ASSERT (r->'checkout') IS NULL,    'FAIL T4: checkout harus null (belum checkout)';
    RAISE NOTICE 'TEST 4 PASSED ✅ — home_summary setelah check-in: %', r->>'today_status';
END $$;

-- ============================================================================
-- TEST 5 ✅ employee_check_out — sukses
-- ============================================================================
DO $$ DECLARE r JSONB; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-1','role','authenticated')::text, TRUE);

    SELECT employee_check_out(
        'aaaaaaaa-0000-0000-0000-000000000001',
        -6.208763, 106.845599,
        'https://cdn.bianore.com/selfie/test-checkout.jpg',
        'HQ Jakarta Pusat',
        CURRENT_DATE
    ) INTO r;

    ASSERT (r->>'today_status') = 'completed', 'FAIL T5: status harus completed, dapat: ' || (r->>'today_status');
    ASSERT (r->'checkout') IS NOT NULL,         'FAIL T5: checkout harus ada';
    ASSERT (r->'work_calculation'->'work_duration_minutes')::INT > 0,
        'FAIL T5: work_duration_minutes harus > 0';
    RAISE NOTICE 'TEST 5 PASSED ✅ — check_out sukses, work_duration: % menit',
        r->'work_calculation'->>'work_duration_minutes';
END $$;

-- ============================================================================
-- TEST 6 ❌ employee_check_out — double check-out
-- ============================================================================
DO $$ DECLARE r JSONB; err TEXT; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-1','role','authenticated')::text, TRUE);
    BEGIN
        SELECT employee_check_out('aaaaaaaa-0000-0000-0000-000000000001',
            -6.208763, 106.845599, 'https://cdn.bianore.com/selfie/x.jpg', NULL, CURRENT_DATE) INTO r;
        RAISE EXCEPTION 'FAIL T6: Harus diblokir double check-out';
    EXCEPTION WHEN OTHERS THEN
        err := SQLERRM;
        IF err LIKE '%ALREADY_CHECKED_OUT%' THEN
            RAISE NOTICE 'TEST 6 PASSED ✅ — double check-out diblokir';
        ELSE RAISE EXCEPTION 'FAIL T6: error bukan ALREADY_CHECKED_OUT: %', err; END IF;
    END;
END $$;

-- ============================================================================
-- TEST 7 ❌ check_in tanpa GPS
-- ============================================================================
DO $$ DECLARE r JSONB; err TEXT; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-8','role','authenticated')::text, TRUE);
    BEGIN
        SELECT employee_check_in('aaaaaaaa-0000-0000-0000-000000000008',
            NULL, NULL, 'https://cdn.bianore.com/selfie/x.jpg', NULL, CURRENT_DATE) INTO r;
        RAISE EXCEPTION 'FAIL T7: Harus diblokir tanpa GPS';
    EXCEPTION WHEN OTHERS THEN
        err := SQLERRM;
        IF err LIKE '%GPS_REQUIRED%' THEN
            RAISE NOTICE 'TEST 7 PASSED ✅ — check-in tanpa GPS diblokir';
        ELSE RAISE EXCEPTION 'FAIL T7: error bukan GPS_REQUIRED: %', err; END IF;
    END;
END $$;

-- ============================================================================
-- TEST 8 ❌ check_in tanpa selfie
-- ============================================================================
DO $$ DECLARE r JSONB; err TEXT; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-8','role','authenticated')::text, TRUE);
    BEGIN
        SELECT employee_check_in('aaaaaaaa-0000-0000-0000-000000000008',
            -6.921395, 107.607124, NULL, NULL, CURRENT_DATE) INTO r;
        RAISE EXCEPTION 'FAIL T8: Harus diblokir tanpa selfie';
    EXCEPTION WHEN OTHERS THEN
        err := SQLERRM;
        IF err LIKE '%SELFIE_REQUIRED%' THEN
            RAISE NOTICE 'TEST 8 PASSED ✅ — check-in tanpa selfie diblokir';
        ELSE RAISE EXCEPTION 'FAIL T8: error bukan SELFIE_REQUIRED: %', err; END IF;
    END;
END $$;

-- ============================================================================
-- TEST 9 ❌ check_in di luar radius (koordinat jauh dari branch)
-- ============================================================================
DO $$ DECLARE r JSONB; err TEXT; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-8','role','authenticated')::text, TRUE);
    BEGIN
        SELECT employee_check_in('aaaaaaaa-0000-0000-0000-000000000008',
            -7.797068, 110.370529,  -- koordinat Yogyakarta (jauh dari Bandung)
            'https://cdn.bianore.com/selfie/x.jpg', NULL, CURRENT_DATE) INTO r;
        RAISE EXCEPTION 'FAIL T9: Harus diblokir karena di luar radius';
    EXCEPTION WHEN OTHERS THEN
        err := SQLERRM;
        IF err LIKE '%OUT_OF_RANGE%' THEN
            RAISE NOTICE 'TEST 9 PASSED ✅ — check-in di luar radius diblokir: %', err;
        ELSE RAISE EXCEPTION 'FAIL T9: error bukan OUT_OF_RANGE: %', err; END IF;
    END;
END $$;

-- ============================================================================
-- TEST 10 ✅ home_summary — karyawan tanpa jadwal (no_schedule)
-- Menggunakan Dewi (BNR-0002) yang tidak punya schedule hari ini di seed
-- ============================================================================
DO $$ DECLARE r JSONB; BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub','auth-user-uuid-replace-2','role','authenticated')::text, TRUE);

    SELECT employee_home_summary('aaaaaaaa-0000-0000-0000-000000000002', CURRENT_DATE) INTO r;

    ASSERT (r->>'today_status') = 'no_schedule',
        'FAIL T10: status harus no_schedule, dapat: ' || (r->>'today_status');
    ASSERT (r->'today_schedule') IS NULL, 'FAIL T10: today_schedule harus null';
    RAISE NOTICE 'TEST 10 PASSED ✅ — home_summary no_schedule';
END $$;

DO $$ BEGIN
RAISE NOTICE '
=================================================
 HOME BACKEND — Test Summary
=================================================
 T1  ✅  home_summary: not_checked_in
 T2  ✅  check_in sukses (GPS dalam radius)
 T3  ❌  double check-in → BLOCKED
 T4  ✅  home_summary setelah check-in
 T5  ✅  check_out sukses + kalkulasi durasi
 T6  ❌  double check-out → BLOCKED
 T7  ❌  check_in tanpa GPS → BLOCKED
 T8  ❌  check_in tanpa selfie → BLOCKED
 T9  ❌  check_in luar radius → BLOCKED
 T10 ✅  home_summary: no_schedule
=================================================';
END $$;
