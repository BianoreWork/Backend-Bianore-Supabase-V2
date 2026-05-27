-- =============================================================================
-- MIGRATION 002: RPC employee_mobile_context
-- Project  : Absensi Bianore
-- Purpose  : Kembalikan konteks lengkap karyawan yang sedang login di mobile app.
--            Dipanggil oleh mobile app setelah user berhasil login via Supabase Auth.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- TIPE RETURN (composite) — dipakai sebagai referensi dokumentasi.
-- RPC ini mengembalikan JSON agar fleksibel di semua client.
-- ----------------------------------------------------------------------------

-- Error codes yang dipakai:
--   UNAUTHENTICATED     → user belum login (auth.uid() = null)
--   EMPLOYEE_NOT_FOUND  → tidak ada employee yang terhubung ke user ini
--   EMPLOYEE_INACTIVE   → is_active = false (admin menonaktifkan akun)
--   EMPLOYEE_RESIGNED   → active_status = 'resigned'
--   EMPLOYEE_TERMINATED → active_status = 'terminated'

CREATE OR REPLACE FUNCTION employee_mobile_context()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
-- search_path dikunci agar tidak bisa di-hijack
SET search_path = public, auth
AS $$
DECLARE
    v_user_id   UUID;
    v_emp       RECORD;
    v_result    JSONB;
BEGIN
    -- ----------------------------------------------------------------
    -- 1. Ambil user yang sedang terautentikasi dari JWT
    -- ----------------------------------------------------------------
    v_user_id := auth.uid();

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: User harus login terlebih dahulu'
            USING ERRCODE = 'P0401';
    END IF;

    -- ----------------------------------------------------------------
    -- 2. Cari employee berdasarkan user_id (dari JWT)
    --    JOIN ke semua tabel terkait sekaligus.
    --    Hanya data milik user sendiri yang bisa dibaca (WHERE e.user_id = v_user_id),
    --    sehingga tidak mungkin membaca employee lain.
    -- ----------------------------------------------------------------
    SELECT
        e.id                            AS employee_id,
        e.employee_code,
        e.employee_name,
        e.email,
        e.phone,
        e.profile_photo_url,
        e.tenant_id,
        e.employment_status::TEXT,
        e.active_status::TEXT,
        e.is_active,
        e.join_date,
        e.contract_end,

        -- Department
        d.id                            AS department_id,
        d.name                          AS department_name,

        -- Position
        p.id                            AS position_id,
        p.name                          AS position_name,

        -- Branch (nullable)
        b.id                            AS branch_id,
        b.name                          AS branch_name,
        b.address                       AS branch_address,
        b.city                          AS branch_city,

        -- Manager / Approver (nullable)
        m.id                            AS manager_id,
        m.employee_code                 AS manager_code,
        m.employee_name                 AS manager_name,
        m.email                         AS manager_email,
        m.profile_photo_url             AS manager_photo,

        -- Tenant
        t.name                          AS tenant_name,
        t.logo_url                      AS tenant_logo

    INTO v_emp
    FROM       employees   e
    LEFT JOIN  departments d  ON d.id = e.department_id
    LEFT JOIN  positions   p  ON p.id = e.position_id
    LEFT JOIN  branches    b  ON b.id = e.branch_id
    LEFT JOIN  employees   m  ON m.id = e.manager_id
    LEFT JOIN  tenants     t  ON t.id = e.tenant_id
    WHERE e.user_id = v_user_id
    LIMIT 1;

    -- ----------------------------------------------------------------
    -- 3. Validasi: employee harus ada
    -- ----------------------------------------------------------------
    IF v_emp IS NULL THEN
        RAISE EXCEPTION 'EMPLOYEE_NOT_FOUND: Tidak ada karyawan yang terhubung ke akun ini'
            USING ERRCODE = 'P0404';
    END IF;

    -- ----------------------------------------------------------------
    -- 4. Validasi: employee yang di-nonaktifkan admin tidak bisa akses
    -- ----------------------------------------------------------------
    IF NOT v_emp.is_active THEN
        RAISE EXCEPTION 'EMPLOYEE_INACTIVE: Akun karyawan ini telah dinonaktifkan oleh administrator'
            USING ERRCODE = 'P0403';
    END IF;

    -- ----------------------------------------------------------------
    -- 5. Validasi: karyawan yang sudah resign tidak bisa akses
    -- ----------------------------------------------------------------
    IF v_emp.active_status = 'resigned' THEN
        RAISE EXCEPTION 'EMPLOYEE_RESIGNED: Karyawan yang sudah mengundurkan diri tidak dapat mengakses aplikasi'
            USING ERRCODE = 'P0403';
    END IF;

    -- ----------------------------------------------------------------
    -- 6. Validasi: karyawan yang sudah di-PHK tidak bisa akses
    -- ----------------------------------------------------------------
    IF v_emp.active_status = 'terminated' THEN
        RAISE EXCEPTION 'EMPLOYEE_TERMINATED: Karyawan yang sudah diberhentikan tidak dapat mengakses aplikasi'
            USING ERRCODE = 'P0403';
    END IF;

    -- ----------------------------------------------------------------
    -- 7. Susun response JSON
    -- ----------------------------------------------------------------
    v_result := jsonb_build_object(
        -- Identitas karyawan
        'employee_id',          v_emp.employee_id,
        'employee_code',        v_emp.employee_code,
        'employee_name',        v_emp.employee_name,
        'email',                v_emp.email,
        'phone',                v_emp.phone,
        'profile_photo',        v_emp.profile_photo_url,

        -- Departemen
        'department', jsonb_build_object(
            'id',   v_emp.department_id,
            'name', v_emp.department_name
        ),

        -- Posisi / Jabatan
        'position', jsonb_build_object(
            'id',   v_emp.position_id,
            'name', v_emp.position_name
        ),

        -- Cabang (null jika tidak ada cabang)
        'branch', CASE
            WHEN v_emp.branch_id IS NOT NULL THEN jsonb_build_object(
                'id',      v_emp.branch_id,
                'name',    v_emp.branch_name,
                'address', v_emp.branch_address,
                'city',    v_emp.branch_city
            )
            ELSE NULL
        END,

        -- Manager / Approver (null jika tidak ada atasan)
        'manager', CASE
            WHEN v_emp.manager_id IS NOT NULL THEN jsonb_build_object(
                'id',    v_emp.manager_id,
                'code',  v_emp.manager_code,
                'name',  v_emp.manager_name,
                'email', v_emp.manager_email,
                'photo', v_emp.manager_photo
            )
            ELSE NULL
        END,

        -- Tenant / Perusahaan
        'tenant_id',   v_emp.tenant_id,
        'tenant_name', v_emp.tenant_name,
        'tenant_logo', v_emp.tenant_logo,

        -- Status kepegawaian
        'employment_status', v_emp.employment_status,
        'active_status',     v_emp.active_status,

        -- Tanggal
        'join_date',     v_emp.join_date,
        'contract_end',  v_emp.contract_end,

        -- Metadata
        'fetched_at', NOW()
    );

    RETURN v_result;

EXCEPTION
    -- Re-raise exception yang sudah kita definisikan agar error code-nya tetap
    WHEN SQLSTATE 'P0401' THEN RAISE;
    WHEN SQLSTATE 'P0403' THEN RAISE;
    WHEN SQLSTATE 'P0404' THEN RAISE;
    -- Tangkap error tak terduga dan jangan bocorkan detail internal ke client
    WHEN OTHERS THEN
        RAISE EXCEPTION 'INTERNAL_ERROR: Terjadi kesalahan sistem. Silakan coba lagi.'
            USING ERRCODE = 'P0500';
END;
$$;

-- Grant eksekusi hanya ke role 'authenticated' (user yang sudah login)
-- role 'anon' (belum login) tidak punya akses
GRANT EXECUTE ON FUNCTION employee_mobile_context() TO authenticated;
REVOKE EXECUTE ON FUNCTION employee_mobile_context() FROM anon;

COMMENT ON FUNCTION employee_mobile_context() IS
'RPC untuk mobile app: mengembalikan data lengkap karyawan yang sedang login.
Hanya bisa diakses oleh user yang terautentikasi.
Karyawan inactive / resigned / terminated akan mendapat error 403.
User tidak dapat membaca data karyawan lain karena lookup dilakukan via auth.uid().';
