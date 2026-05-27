-- =============================================================================
-- MIGRATION 003: Row Level Security (RLS) Policies
-- Project  : Absensi Bianore
-- Note     : Adapted for Laravel bigint IDs + supabase_uid column for Auth
-- =============================================================================

-- ----------------------------------------------------------------------------
-- Patch employees: tambah kolom supabase_uid sebelum RLS dibuat
-- ----------------------------------------------------------------------------
ALTER TABLE employees
    ADD COLUMN IF NOT EXISTS email             TEXT,
    ADD COLUMN IF NOT EXISTS phone             TEXT,
    ADD COLUMN IF NOT EXISTS profile_photo_url TEXT,
    ADD COLUMN IF NOT EXISTS manager_id        BIGINT REFERENCES employees(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS active_status     TEXT NOT NULL DEFAULT 'active',
    ADD COLUMN IF NOT EXISTS is_active         BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS contract_end      DATE,
    ADD COLUMN IF NOT EXISTS resign_date       DATE,
    ADD COLUMN IF NOT EXISTS approver_id       BIGINT REFERENCES employees(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS supabase_uid      UUID REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_employees_supabase_uid  ON employees(supabase_uid);
CREATE INDEX IF NOT EXISTS idx_employees_manager_id    ON employees(manager_id);
CREATE INDEX IF NOT EXISTS idx_employees_active_status ON employees(active_status);

-- ----------------------------------------------------------------------------
-- Enable RLS
-- ----------------------------------------------------------------------------
ALTER TABLE tenants     ENABLE ROW LEVEL SECURITY;
ALTER TABLE branches    ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE positions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees   ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- HELPER FUNCTION: Ambil tenant_id (bigint) milik user yang sedang login
-- Mapping dari Supabase Auth UUID → employees.supabase_uid → tenant_id
-- ============================================================================
CREATE OR REPLACE FUNCTION my_tenant_id()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT tenant_id
    FROM   employees
    WHERE  supabase_uid = auth.uid()
    LIMIT  1;
$$;

-- ============================================================================
-- HELPER FUNCTION: Cek apakah user yang login adalah admin/HR
-- ============================================================================
CREATE OR REPLACE FUNCTION is_tenant_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT COALESCE(
        (auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'hr', 'owner', 'super_admin'),
        FALSE
    );
$$;

-- ============================================================================
-- TABLE: tenants
-- ============================================================================
CREATE POLICY "employee: read own tenant"
    ON tenants FOR SELECT
    TO authenticated
    USING (id = my_tenant_id());

CREATE POLICY "admin: read all tenants"
    ON tenants FOR SELECT
    TO authenticated
    USING (is_tenant_admin());

-- ============================================================================
-- TABLE: branches
-- ============================================================================
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
CREATE POLICY "employee: read own profile only"
    ON employees FOR SELECT
    TO authenticated
    USING (supabase_uid = auth.uid());

CREATE POLICY "admin: read all employees in own tenant"
    ON employees FOR SELECT
    TO authenticated
    USING (
        is_tenant_admin()
        AND tenant_id = my_tenant_id()
    );
