-- =============================================================================
-- MIGRATION 005: Test Script — employee_mobile_context
-- Project  : Absensi Bianore
-- Purpose  : Verifikasi manual RPC dengan cara SET LOCAL ROLE + SET CONFIG
--            untuk mensimulasikan JWT claim auth.uid() di lingkungan dev.
--
-- Cara pakai:
--   1. Jalankan di Supabase SQL Editor (satu blok per skenario)
--   2. Atau gunakan psql: psql $DATABASE_URL -f 005_test_employee_mobile_context.sql
--
-- CATATAN: Ganti 'auth-user-uuid-replace-X' dengan UUID auth.users yang asli.
-- =============================================================================

-- ============================================================================
-- SETUP HELPER: mensimulasikan auth.uid() di SQL Editor tanpa JWT asli
-- ============================================================================
-- Supabase mengirim JWT claim ke PostgreSQL via GUC request.jwt.claims
-- Kita bisa simulasi dengan:
--   SET LOCAL request.jwt.claims = '{"sub": "<user_uuid>", "role": "authenticated"}';
-- Kemudian panggil: SELECT auth.uid();  → harus return UUID tersebut.

-- ============================================================================
-- TEST 1 ✅ Karyawan AKTIF dengan branch & manager (skenario happy path)
-- Expected: return JSON lengkap, branch & manager tidak null
-- ============================================================================
DO $$
DECLARE
    result JSONB;
BEGIN
    -- Simulasi user BNR-0001 (Budi Santoso) sedang login
    PERFORM set_config('request.jwt.claims',
        json_build_object(
            'sub',  'auth-user-uuid-replace-1',
            'role', 'authenticated'
        )::text,
        TRUE  -- local = true (berlaku hanya dalam transaksi ini)
    );

    SELECT employee_mobile_context() INTO result;

    -- Assertions
    ASSERT (result->>'employee_code') = 'BNR-0001',
        'FAIL TEST 1: employee_code harus BNR-0001, dapat: ' || (result->>'employee_code');

    ASSERT (result->>'employee_name') = 'Budi Santoso',
        'FAIL TEST 1: employee_name salah';

    ASSERT (result->>'active_status') = 'active',
        'FAIL TEST 1: active_status harus active';

    ASSERT (result->'branch') IS NOT NULL,
        'FAIL TEST 1: branch harus ada (tidak null)';

    ASSERT (result->'manager') IS NOT NULL,
        'FAIL TEST 1: manager harus ada (tidak null)';

    ASSERT (result->>'tenant_id') = '11111111-0000-0000-0000-000000000001',
        'FAIL TEST 1: tenant_id salah';

    RAISE NOTICE 'TEST 1 PASSED ✅ — Karyawan aktif dengan branch & manager: %', result;
END;
$$;


-- ============================================================================
-- TEST 2 ✅ Karyawan AKTIF tanpa branch
-- Expected: return JSON dengan branch = null, manager tidak null
-- ============================================================================
DO $$
DECLARE
    result JSONB;
BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', 'auth-user-uuid-replace-2', 'role', 'authenticated')::text, TRUE);

    SELECT employee_mobile_context() INTO result;

    ASSERT (result->>'employee_code') = 'BNR-0002',
        'FAIL TEST 2: employee_code salah';

    ASSERT (result->'branch') IS NULL,
        'FAIL TEST 2: branch harus NULL untuk karyawan tanpa cabang, dapat: ' || (result->'branch')::text;

    ASSERT (result->'manager') IS NOT NULL,
        'FAIL TEST 2: manager harus ada';

    RAISE NOTICE 'TEST 2 PASSED ✅ — Karyawan aktif tanpa branch (branch = null): %',
        jsonb_pretty(result);
END;
$$;


-- ============================================================================
-- TEST 3 ✅ Karyawan AKTIF tanpa manager (top-level)
-- Expected: return JSON dengan manager = null
-- ============================================================================
DO $$
DECLARE
    result JSONB;
BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', 'auth-user-uuid-replace-3', 'role', 'authenticated')::text, TRUE);

    SELECT employee_mobile_context() INTO result;

    ASSERT (result->>'employee_code') = 'BNR-0003',
        'FAIL TEST 3: employee_code salah';

    ASSERT (result->'manager') IS NULL,
        'FAIL TEST 3: manager harus NULL untuk karyawan top-level';

    ASSERT (result->'branch') IS NOT NULL,
        'FAIL TEST 3: branch harus ada';

    RAISE NOTICE 'TEST 3 PASSED ✅ — Karyawan aktif tanpa manager (top-level): %',
        jsonb_pretty(result);
END;
$$;


-- ============================================================================
-- TEST 4 ❌ Karyawan INACTIVE (is_active = false)
-- Expected: raise exception dengan pesan EMPLOYEE_INACTIVE
-- ============================================================================
DO $$
DECLARE
    result JSONB;
    err_msg TEXT;
BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', 'auth-user-uuid-replace-4', 'role', 'authenticated')::text, TRUE);

    BEGIN
        SELECT employee_mobile_context() INTO result;
        -- Jika sampai sini tanpa exception = FAIL
        RAISE EXCEPTION 'TEST 4 FAILED ❌ — Seharusnya diblokir, tapi berhasil return: %', result;
    EXCEPTION
        WHEN OTHERS THEN
            err_msg := SQLERRM;
            IF err_msg LIKE '%EMPLOYEE_INACTIVE%' THEN
                RAISE NOTICE 'TEST 4 PASSED ✅ — Karyawan inactive diblokir dengan benar. Error: %', err_msg;
            ELSE
                RAISE EXCEPTION 'TEST 4 FAILED ❌ — Error bukan EMPLOYEE_INACTIVE: %', err_msg;
            END IF;
    END;
END;
$$;


-- ============================================================================
-- TEST 5 ✅ Karyawan ON-LEAVE
-- Expected: berhasil return, active_status = 'on-leave'
-- (on-leave masih boleh akses app, hanya tidak bisa absen)
-- ============================================================================
DO $$
DECLARE
    result JSONB;
BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', 'auth-user-uuid-replace-5', 'role', 'authenticated')::text, TRUE);

    SELECT employee_mobile_context() INTO result;

    ASSERT (result->>'employee_code') = 'BNR-0005',
        'FAIL TEST 5: employee_code salah';

    ASSERT (result->>'active_status') = 'on-leave',
        'FAIL TEST 5: active_status harus on-leave';

    RAISE NOTICE 'TEST 5 PASSED ✅ — Karyawan on-leave bisa akses app: %',
        jsonb_pretty(result);
END;
$$;


-- ============================================================================
-- TEST 6 ❌ Karyawan RESIGNED
-- Expected: raise exception dengan pesan EMPLOYEE_RESIGNED
-- ============================================================================
DO $$
DECLARE
    result JSONB;
    err_msg TEXT;
BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', 'auth-user-uuid-replace-6', 'role', 'authenticated')::text, TRUE);

    BEGIN
        SELECT employee_mobile_context() INTO result;
        RAISE EXCEPTION 'TEST 6 FAILED ❌ — Seharusnya diblokir';
    EXCEPTION
        WHEN OTHERS THEN
            err_msg := SQLERRM;
            IF err_msg LIKE '%EMPLOYEE_RESIGNED%' THEN
                RAISE NOTICE 'TEST 6 PASSED ✅ — Karyawan resigned diblokir. Error: %', err_msg;
            ELSE
                RAISE EXCEPTION 'TEST 6 FAILED ❌ — Error bukan EMPLOYEE_RESIGNED: %', err_msg;
            END IF;
    END;
END;
$$;


-- ============================================================================
-- TEST 7 ❌ Karyawan TERMINATED
-- Expected: raise exception dengan pesan EMPLOYEE_TERMINATED
-- ============================================================================
DO $$
DECLARE
    result JSONB;
    err_msg TEXT;
BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', 'auth-user-uuid-replace-7', 'role', 'authenticated')::text, TRUE);

    BEGIN
        SELECT employee_mobile_context() INTO result;
        RAISE EXCEPTION 'TEST 7 FAILED ❌ — Seharusnya diblokir';
    EXCEPTION
        WHEN OTHERS THEN
            err_msg := SQLERRM;
            IF err_msg LIKE '%EMPLOYEE_TERMINATED%' THEN
                RAISE NOTICE 'TEST 7 PASSED ✅ — Karyawan terminated diblokir. Error: %', err_msg;
            ELSE
                RAISE EXCEPTION 'TEST 7 FAILED ❌ — Error bukan EMPLOYEE_TERMINATED: %', err_msg;
            END IF;
    END;
END;
$$;


-- ============================================================================
-- TEST 8 ❌ User tanpa employee record (auth.uid() valid tapi tidak ada di tabel employees)
-- Expected: raise exception dengan pesan EMPLOYEE_NOT_FOUND
-- ============================================================================
DO $$
DECLARE
    result JSONB;
    err_msg TEXT;
BEGIN
    -- UUID yang tidak ada di tabel employees sama sekali
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', '00000000-dead-beef-0000-000000000000', 'role', 'authenticated')::text, TRUE);

    BEGIN
        SELECT employee_mobile_context() INTO result;
        RAISE EXCEPTION 'TEST 8 FAILED ❌ — Seharusnya EMPLOYEE_NOT_FOUND';
    EXCEPTION
        WHEN OTHERS THEN
            err_msg := SQLERRM;
            IF err_msg LIKE '%EMPLOYEE_NOT_FOUND%' THEN
                RAISE NOTICE 'TEST 8 PASSED ✅ — User tanpa employee diblokir. Error: %', err_msg;
            ELSE
                RAISE EXCEPTION 'TEST 8 FAILED ❌ — Error bukan EMPLOYEE_NOT_FOUND: %', err_msg;
            END IF;
    END;
END;
$$;


-- ============================================================================
-- TEST 9 ❌ User belum login (auth.uid() = NULL / anon)
-- Expected: raise exception UNAUTHENTICATED
-- ============================================================================
DO $$
DECLARE
    result JSONB;
    err_msg TEXT;
BEGIN
    -- Hapus JWT claim (simulasi anon)
    PERFORM set_config('request.jwt.claims', '{}', TRUE);

    BEGIN
        SELECT employee_mobile_context() INTO result;
        RAISE EXCEPTION 'TEST 9 FAILED ❌ — Seharusnya UNAUTHENTICATED';
    EXCEPTION
        WHEN OTHERS THEN
            err_msg := SQLERRM;
            IF err_msg LIKE '%UNAUTHENTICATED%' THEN
                RAISE NOTICE 'TEST 9 PASSED ✅ — Anon diblokir. Error: %', err_msg;
            ELSE
                RAISE EXCEPTION 'TEST 9 FAILED ❌ — Error bukan UNAUTHENTICATED: %', err_msg;
            END IF;
    END;
END;
$$;


-- ============================================================================
-- TEST 10 🔒 Security: User tidak bisa membaca data karyawan LAIN
-- Expected: user BNR-0008 (Maya) hanya melihat datanya sendiri, bukan BNR-0001 (Budi)
-- ============================================================================
DO $$
DECLARE
    result JSONB;
BEGIN
    -- Login sebagai Maya (BNR-0008)
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', 'auth-user-uuid-replace-8', 'role', 'authenticated')::text, TRUE);

    SELECT employee_mobile_context() INTO result;

    ASSERT (result->>'employee_code') = 'BNR-0008',
        'FAIL TEST 10: Harus return BNR-0008 (diri sendiri), bukan: ' || (result->>'employee_code');

    -- Pastikan BUKAN data Budi
    ASSERT (result->>'employee_code') <> 'BNR-0001',
        'FAIL TEST 10: Security breach — user bisa membaca data karyawan lain!';

    RAISE NOTICE 'TEST 10 PASSED 🔒 — User hanya melihat datanya sendiri: %',
        jsonb_pretty(result);
END;
$$;


-- ============================================================================
-- RINGKASAN TEST
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '
============================================================
 EMPLOYEE MOBILE CONTEXT — Test Summary
============================================================
 TEST 1  ✅  Karyawan aktif (branch + manager)   → SUCCESS
 TEST 2  ✅  Karyawan aktif (tanpa branch)        → branch = null
 TEST 3  ✅  Karyawan aktif (tanpa manager)       → manager = null
 TEST 4  ❌  Karyawan inactive                    → BLOCKED (EMPLOYEE_INACTIVE)
 TEST 5  ✅  Karyawan on-leave                    → ALLOWED (hanya status berbeda)
 TEST 6  ❌  Karyawan resigned                    → BLOCKED (EMPLOYEE_RESIGNED)
 TEST 7  ❌  Karyawan terminated                  → BLOCKED (EMPLOYEE_TERMINATED)
 TEST 8  ❌  User tanpa employee record            → BLOCKED (EMPLOYEE_NOT_FOUND)
 TEST 9  ❌  User belum login / anon              → BLOCKED (UNAUTHENTICATED)
 TEST 10 🔒  Security: tidak bisa baca data lain → PASSED
============================================================
';
END;
$$;
