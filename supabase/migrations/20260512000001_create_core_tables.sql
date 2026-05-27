-- =============================================================================
-- MIGRATION 001: Core Tables
-- Project  : Absensi Bianore
-- Purpose  : Tabel inti untuk sistem absensi multi-tenant
-- =============================================================================

-- ----------------------------------------------------------------------------
-- TENANTS
-- Setiap perusahaan / organisasi yang menggunakan sistem ini.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tenants (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT        NOT NULL,
    slug        TEXT        NOT NULL UNIQUE,
    logo_url    TEXT,
    is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- BRANCHES
-- Cabang / lokasi kerja milik sebuah tenant.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS branches (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name        TEXT        NOT NULL,
    address     TEXT,
    city        TEXT,
    latitude    NUMERIC(10, 7),
    longitude   NUMERIC(10, 7),
    radius_meters INT       DEFAULT 200,  -- radius valid check-in (meter)
    is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- DEPARTMENTS
-- Divisi / departemen milik sebuah tenant.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS departments (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name        TEXT        NOT NULL,
    code        TEXT,
    is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, name)
);

-- ----------------------------------------------------------------------------
-- POSITIONS
-- Jabatan / posisi pekerjaan milik sebuah tenant.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS positions (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    department_id UUID        REFERENCES departments(id) ON DELETE SET NULL,
    name          TEXT        NOT NULL,
    level         INT         DEFAULT 1,  -- 1 = staff, 2 = lead, 3 = manager, dst
    is_active     BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- EMPLOYEES
-- Karyawan yang terdaftar dalam sistem. Setiap employee terhubung ke
-- satu user Supabase Auth melalui kolom user_id.
-- ----------------------------------------------------------------------------
CREATE TYPE employment_status_enum AS ENUM (
    'full-time',
    'part-time',
    'contract',
    'intern'
);

CREATE TYPE active_status_enum AS ENUM (
    'active',
    'on-leave',
    'inactive',
    'resigned',
    'terminated'
);

CREATE TABLE IF NOT EXISTS employees (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Auth link
    user_id         UUID        UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,

    -- Identitas
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    employee_code   TEXT        NOT NULL,          -- EMP0001, BNR-001, dst
    employee_name   TEXT        NOT NULL,
    email           TEXT        NOT NULL,
    phone           TEXT,
    profile_photo_url TEXT,

    -- Penempatan
    department_id   UUID        REFERENCES departments(id) ON DELETE SET NULL,
    position_id     UUID        REFERENCES positions(id)   ON DELETE SET NULL,
    branch_id       UUID        REFERENCES branches(id)    ON DELETE SET NULL,  -- nullable
    manager_id      UUID        REFERENCES employees(id)   ON DELETE SET NULL,  -- nullable

    -- Status
    employment_status employment_status_enum NOT NULL DEFAULT 'full-time',
    active_status     active_status_enum     NOT NULL DEFAULT 'active',
    is_active         BOOLEAN NOT NULL DEFAULT TRUE,  -- flag eksplisit dari admin

    -- Tanggal
    join_date       DATE        NOT NULL DEFAULT CURRENT_DATE,
    contract_end    DATE,                              -- null = permanen
    resign_date     DATE,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (tenant_id, employee_code)
);

-- ----------------------------------------------------------------------------
-- INDEXES
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_employees_user_id      ON employees(user_id);
CREATE INDEX IF NOT EXISTS idx_employees_tenant_id    ON employees(tenant_id);
CREATE INDEX IF NOT EXISTS idx_employees_branch_id    ON employees(branch_id);
CREATE INDEX IF NOT EXISTS idx_employees_manager_id   ON employees(manager_id);
CREATE INDEX IF NOT EXISTS idx_employees_active_status ON employees(active_status);
CREATE INDEX IF NOT EXISTS idx_branches_tenant_id     ON branches(tenant_id);
CREATE INDEX IF NOT EXISTS idx_departments_tenant_id  ON departments(tenant_id);
CREATE INDEX IF NOT EXISTS idx_positions_tenant_id    ON positions(tenant_id);

-- ----------------------------------------------------------------------------
-- updated_at trigger
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_tenants_updated_at
    BEFORE UPDATE ON tenants
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_branches_updated_at
    BEFORE UPDATE ON branches
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_departments_updated_at
    BEFORE UPDATE ON departments
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_positions_updated_at
    BEFORE UPDATE ON positions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_employees_updated_at
    BEFORE UPDATE ON employees
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
