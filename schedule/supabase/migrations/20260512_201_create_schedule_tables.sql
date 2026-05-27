-- =============================================================================
-- MIGRATION 201: Schedule Tables
-- Module   : Schedule Backend
-- Project  : Absensi Bianore
-- Deploy   : SEBELUM home/101 karena attendance_records mereferensikan schedule
-- =============================================================================

-- ----------------------------------------------------------------------------
-- SHIFTS — Template definisi shift kerja (master data)
-- Contoh: "Morning Shift" 08:00–17:00, break 60 menit
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS shifts (
    id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                 UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name                      TEXT        NOT NULL,          -- "Morning Shift"
    start_time                TIME        NOT NULL,          -- 08:00
    end_time                  TIME        NOT NULL,          -- 17:00
    break_minutes             INT         NOT NULL DEFAULT 60,
    late_threshold_minutes    INT         NOT NULL DEFAULT 15,   -- telat ringan
    very_late_threshold_minutes INT       NOT NULL DEFAULT 60,   -- telat berat
    overtime_threshold_minutes INT        NOT NULL DEFAULT 30,   -- mulai lembur
    color                     TEXT        DEFAULT '#3B82F6',  -- warna di kalender
    is_active                 BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- EMPLOYEE_SCHEDULES — Jadwal kerja karyawan per hari (applied schedule)
-- Menghubungkan employee + shift + branch pada tanggal tertentu.
-- ----------------------------------------------------------------------------
CREATE TYPE schedule_status_enum AS ENUM (
    'active',      -- jadwal aktif
    'cancelled',   -- dibatalkan (libur mendadak, dll)
    'swapped'      -- jadwal ditukar (swap shift)
);

CREATE TABLE IF NOT EXISTS employee_schedules (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES tenants(id)     ON DELETE CASCADE,
    employee_id     UUID        NOT NULL REFERENCES employees(id)   ON DELETE CASCADE,
    branch_id       UUID        REFERENCES branches(id)             ON DELETE SET NULL,
    shift_id        UUID        REFERENCES shifts(id)               ON DELETE SET NULL,
    work_date       DATE        NOT NULL,

    -- Snapshot nilai shift (disalin saat assign agar tahan perubahan master)
    shift_name      TEXT        NOT NULL,
    start_time      TIME        NOT NULL,
    end_time        TIME        NOT NULL,
    break_minutes   INT         NOT NULL DEFAULT 60,
    late_threshold_minutes      INT NOT NULL DEFAULT 15,
    very_late_threshold_minutes INT NOT NULL DEFAULT 60,
    overtime_threshold_minutes  INT NOT NULL DEFAULT 30,

    schedule_status schedule_status_enum NOT NULL DEFAULT 'active',
    notes           TEXT,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Satu employee hanya boleh punya satu jadwal aktif per hari
    UNIQUE (tenant_id, employee_id, work_date)
);

-- ----------------------------------------------------------------------------
-- LEAVE_REQUESTS — Request cuti, sakit, izin
-- Dipakai schedule calendar untuk menampilkan impact di hari tersebut.
-- ----------------------------------------------------------------------------
CREATE TYPE leave_type_enum AS ENUM (
    'annual_leave',    -- cuti tahunan
    'sick_leave',      -- sakit (dengan surat dokter)
    'emergency_leave', -- cuti darurat / keluarga
    'unpaid_leave',    -- cuti tanpa bayar
    'maternity_leave', -- cuti melahirkan
    'other'
);

CREATE TYPE leave_status_enum AS ENUM (
    'pending',   -- menunggu approval
    'approved',  -- disetujui manager
    'rejected',  -- ditolak
    'cancelled'  -- dibatalkan oleh karyawan
);

CREATE TABLE IF NOT EXISTS leave_requests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES tenants(id)     ON DELETE CASCADE,
    employee_id     UUID        NOT NULL REFERENCES employees(id)   ON DELETE CASCADE,
    approver_id     UUID        REFERENCES employees(id)            ON DELETE SET NULL,

    leave_type      leave_type_enum   NOT NULL,
    leave_status    leave_status_enum NOT NULL DEFAULT 'pending',

    start_date      DATE        NOT NULL,
    end_date        DATE        NOT NULL,
    total_days      INT         NOT NULL DEFAULT 1,
    reason          TEXT,
    attachment_url  TEXT,       -- foto surat sakit, dll

    approved_at     TIMESTAMPTZ,
    approver_notes  TEXT,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_date_range CHECK (end_date >= start_date)
);

-- ----------------------------------------------------------------------------
-- INDEXES
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_shifts_tenant_id
    ON shifts(tenant_id);

CREATE INDEX IF NOT EXISTS idx_employee_schedules_employee_date
    ON employee_schedules(employee_id, work_date);

CREATE INDEX IF NOT EXISTS idx_employee_schedules_tenant_date
    ON employee_schedules(tenant_id, work_date);

CREATE INDEX IF NOT EXISTS idx_leave_requests_employee_date
    ON leave_requests(employee_id, start_date, end_date);

CREATE INDEX IF NOT EXISTS idx_leave_requests_tenant
    ON leave_requests(tenant_id);

-- ----------------------------------------------------------------------------
-- updated_at triggers
-- ----------------------------------------------------------------------------
CREATE TRIGGER trg_shifts_updated_at
    BEFORE UPDATE ON shifts
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_employee_schedules_updated_at
    BEFORE UPDATE ON employee_schedules
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_leave_requests_updated_at
    BEFORE UPDATE ON leave_requests
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
