-- =============================================================================
-- MIGRATION 003: Row Level Security (RLS) Policies
-- Project  : Absensi Bianore
-- Purpose  : Memastikan setiap user hanya bisa membaca datanya sendiri.
--            Admin / HR bisa membaca semua data dalam tenant mereka.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- Enable RLS pada semua tabel sensitif
-- ----------------------------------------------------------------------------
ALTER TABLE tenants     ENABLE ROW LEVEL SECURITY;
ALTER TABLE branches    ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE positions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees   ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- HELPER FUNCTION: Ambil tenant_id milik user yang sedang login
-- Digunakan di semua policy agar query tidak redundan.
-- ============================================================================
CREATE OR REPLACE FUNCTION my_tenant_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT tenant_id
    FROM   employees
    WHERE  user_id = auth.uid()
    LIMIT  1;
$$;

-- ============================================================================
-- HELPER FUNCTION: Cek apakah user yang login adalah admin/HR dari tenant mereka
-- Digunakan untuk memberi akses baca lebih luas ke admin dashboard.
-- ============================================================================
CREATE OR REPLACE FUNCTION is_tenant_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
    -- Ambil role dari JWT claims (set oleh Supabase Auth custom claims)
    SELECT COALESCE(
        (auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'hr', 'owner', 'super_admin'),
        FALSE
    );
$$;

-- ============================================================================
-- TABLE: tenants
-- ============================================================================

-- Karyawan hanya bisa READ tenant mereka sendiri
CREATE POLICY "employee: read own tenant"
    ON tenants FOR SELECT
    TO authenticated
    USING (id = my_tenant_id());

-- Admin bisa READ semua tenant (untuk keperluan super admin dashboard)
CREATE POLICY "admin: read all tenants"
    ON tenants FOR SELECT
    TO authenticated
    USING (is_tenant_admin());

-- Hanya service_role (backend) yang bisa INSERT / UPDATE / DELETE
-- (tidak ada policy publik untuk write — hanya via SECURITY DEFINER functions)

-- ============================================================================
-- TABLE: branches
-- ============================================================================

-- Karyawan bisa READ semua branch dalam tenant mereka
-- (dibutuhkan agar app bisa menampilkan daftar lokasi valid saat check-in)
CREATE POLICY "employee: read branches in own tenant"
    ON branches FOR SELECT
    TO authenticated
    USING (tenant_id = my_tenant_id());

-- ============================================================================
-- TABLE: departments
-- ============================================================================

CREATE POLICY "employee: read departments in own tenant"
    ON departments FOR SELECT
    TO authenticated
    USING (tenant_id = my_tenant_id());

-- ============================================================================
-- TABLE: positions
-- ============================================================================

CREATE POLICY "employee: read positions in own tenant"
    ON positions FOR SELECT
    TO authenticated
    USING (tenant_id = my_tenant_id());

-- ============================================================================
-- TABLE: employees
-- ============================================================================

-- Kebijakan utama keamanan:
-- 1. Karyawan biasa HANYA bisa membaca data dirinya sendiri
-- 2. Admin / HR dalam tenant yang sama bisa membaca SEMUA karyawan
--
-- Ini mencegah satu karyawan membaca profil karyawan lain.

CREATE POLICY "employee: read own profile only"
    ON employees FOR SELECT
    TO authenticated
    USING (
        -- Diri sendiri
        user_id = auth.uid()
    );

CREATE POLICY "admin: read all employees in own tenant"
    ON employees FOR SELECT
    TO authenticated
    USING (
        -- Admin/HR bisa lihat semua karyawan dalam tenant mereka
        is_tenant_admin()
        AND tenant_id = my_tenant_id()
    );

-- Karyawan tidak bisa UPDATE / DELETE data employee melalui API langsung.
-- Semua mutasi harus melalui SECURITY DEFINER functions yang tervalidasi.
-- (Policy write sengaja tidak dibuat untuk tabel employees pada role authenticated)

-- ============================================================================
-- Pastikan anon tidak bisa akses apapun
-- ============================================================================
-- Semua policy di atas hanya berlaku untuk role 'authenticated'.
-- Role 'anon' tidak punya policy → tidak bisa akses → RLS akan menolak.
