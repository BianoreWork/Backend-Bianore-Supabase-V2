-- =============================================================================
-- MIGRATION 006: Patch existing tables created by Laravel migrations
-- Purpose  : Add missing columns to tables that already exist
-- =============================================================================

-- ----------------------------------------------------------------------------
-- Patch employees table: add missing columns from Supabase schema
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

CREATE INDEX IF NOT EXISTS idx_employees_supabase_uid ON employees(supabase_uid);

-- Indexes for new columns
CREATE INDEX IF NOT EXISTS idx_employees_manager_id    ON employees(manager_id);
CREATE INDEX IF NOT EXISTS idx_employees_active_status ON employees(active_status);
CREATE INDEX IF NOT EXISTS idx_employees_user_id       ON employees(user_id);
CREATE INDEX IF NOT EXISTS idx_employees_tenant_id     ON employees(tenant_id);
CREATE INDEX IF NOT EXISTS idx_employees_branch_id     ON employees(branch_id);

-- ----------------------------------------------------------------------------
-- Patch branches: add missing indexes
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_branches_tenant_id    ON branches(tenant_id);

-- ----------------------------------------------------------------------------
-- Patch departments: add missing indexes
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_departments_tenant_id ON departments(tenant_id);

-- ----------------------------------------------------------------------------
-- Patch positions: add missing indexes
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_positions_tenant_id   ON positions(tenant_id);
