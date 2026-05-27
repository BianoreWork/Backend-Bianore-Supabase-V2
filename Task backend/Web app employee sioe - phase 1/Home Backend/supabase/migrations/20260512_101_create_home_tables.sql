-- =============================================================================
-- MIGRATION 101: Home Tables
-- Module   : Home Backend
-- Project  : Absensi Bianore
-- Deploy   : SESUDAH schedule/201 karena attendance_records menyimpan schedule_id
-- =============================================================================

-- ----------------------------------------------------------------------------
-- HELPER FUNCTION — Hitung jarak dua koordinat GPS (Haversine Formula)
-- Return: jarak dalam meter (INTEGER)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calculate_distance_meters(
    lat1 NUMERIC, lon1 NUMERIC,
    lat2 NUMERIC, lon2 NUMERIC
)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    R      CONSTANT NUMERIC := 6371000; -- radius bumi dalam meter
    phi1   NUMERIC := radians(lat1);
    phi2   NUMERIC := radians(lat2);
    dphi   NUMERIC := radians(lat2 - lat1);
    dlambda NUMERIC := radians(lon2 - lon1);
    a      NUMERIC;
    c      NUMERIC;
BEGIN
    a := sin(dphi / 2) ^ 2 + cos(phi1) * cos(phi2) * sin(dlambda / 2) ^ 2;
    c := 2 * atan2(sqrt(a), sqrt(1 - a));
    RETURN ROUND(R * c)::INTEGER;
END;
$$;

-- ----------------------------------------------------------------------------
-- ATTENDANCE STATUS ENUM
-- ----------------------------------------------------------------------------
CREATE TYPE attendance_status_enum AS ENUM (
    'checked_in',   -- check-in tepat waktu
    'late',         -- check-in terlambat (> late_threshold)
    'very_late',    -- check-in sangat terlambat (> very_late_threshold)
    'completed',    -- sudah check-out
    'absent'        -- tidak hadir (set oleh scheduled job / admin)
);

-- Status gabungan yang dikembalikan ke mobile (termasuk computed state)
-- 'not_checked_in' dan 'no_schedule' tidak disimpan di DB, hanya dikembalikan RPC

-- ----------------------------------------------------------------------------
-- ATTENDANCE_RECORDS — Satu record per karyawan per hari kerja
-- Dibuat saat check-in, diupdate saat check-out.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS attendance_records (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES tenants(id)     ON DELETE CASCADE,
    employee_id     UUID        NOT NULL REFERENCES employees(id)   ON DELETE CASCADE,
    schedule_id     UUID,       -- referensi ke employee_schedules.id (tanpa FK constraint)
    work_date       DATE        NOT NULL,

    -- Status
    attendance_status attendance_status_enum NOT NULL DEFAULT 'checked_in',

    -- Check-in
    checkin_time        TIMESTAMPTZ,
    checkin_latitude    NUMERIC(10, 7),
    checkin_longitude   NUMERIC(10, 7),
    checkin_distance_meters INT,        -- jarak ke lokasi kerja (meter)
    checkin_location_name   TEXT,       -- nama lokasi / alamat
    checkin_selfie_url      TEXT,       -- URL foto selfie check-in
    checkin_gps_verified    BOOLEAN     DEFAULT FALSE,
    checkin_selfie_verified BOOLEAN     DEFAULT FALSE,

    -- Check-out
    checkout_time        TIMESTAMPTZ,
    checkout_latitude    NUMERIC(10, 7),
    checkout_longitude   NUMERIC(10, 7),
    checkout_distance_meters INT,
    checkout_location_name   TEXT,
    checkout_selfie_url      TEXT,
    checkout_gps_verified    BOOLEAN    DEFAULT FALSE,
    checkout_selfie_verified BOOLEAN    DEFAULT FALSE,

    -- Kalkulasi (dihitung otomatis saat check-in / check-out)
    late_minutes            INT         NOT NULL DEFAULT 0,
    work_duration_minutes   INT         NOT NULL DEFAULT 0,
    overtime_minutes        INT         NOT NULL DEFAULT 0,

    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Satu attendance record per karyawan per hari
    UNIQUE (tenant_id, employee_id, work_date)
);

-- ----------------------------------------------------------------------------
-- ATTENDANCE_EVENTS — Audit log setiap event check-in / check-out
-- Berguna untuk history dan dispute resolution.
-- ----------------------------------------------------------------------------
CREATE TYPE attendance_event_type_enum AS ENUM (
    'check_in',
    'check_out',
    'check_in_correction',   -- koreksi absensi oleh admin/HR
    'check_out_correction'
);

CREATE TABLE IF NOT EXISTS attendance_events (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL REFERENCES tenants(id)     ON DELETE CASCADE,
    employee_id         UUID        NOT NULL REFERENCES employees(id)   ON DELETE CASCADE,
    attendance_record_id UUID       REFERENCES attendance_records(id)   ON DELETE SET NULL,
    work_date           DATE        NOT NULL,

    event_type          attendance_event_type_enum NOT NULL,
    event_time          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    latitude            NUMERIC(10, 7),
    longitude           NUMERIC(10, 7),
    distance_meters     INT,
    location_name       TEXT,
    selfie_url          TEXT,
    gps_verified        BOOLEAN     DEFAULT FALSE,
    selfie_verified     BOOLEAN     DEFAULT FALSE,

    -- Untuk koreksi: simpan actor dan alasan
    actor_id            UUID        REFERENCES employees(id) ON DELETE SET NULL,
    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- NOTIFICATIONS — Untuk unread notification count di home screen
-- ----------------------------------------------------------------------------
CREATE TYPE notification_type_enum AS ENUM (
    'attendance_reminder',    -- pengingat check-in / check-out
    'leave_approved',
    'leave_rejected',
    'schedule_changed',
    'overtime_approved',
    'announcement',
    'system'
);

CREATE TABLE IF NOT EXISTS notifications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES tenants(id)     ON DELETE CASCADE,
    employee_id     UUID        NOT NULL REFERENCES employees(id)   ON DELETE CASCADE,

    notification_type notification_type_enum NOT NULL DEFAULT 'system',
    title           TEXT        NOT NULL,
    body            TEXT,
    deep_link       TEXT,       -- navigasi dalam app, misal "schedule/2026-05-12"
    is_read         BOOLEAN     NOT NULL DEFAULT FALSE,
    read_at         TIMESTAMPTZ,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- INDEXES
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_attendance_records_employee_date
    ON attendance_records(employee_id, work_date);

CREATE INDEX IF NOT EXISTS idx_attendance_records_tenant_date
    ON attendance_records(tenant_id, work_date);

CREATE INDEX IF NOT EXISTS idx_attendance_events_employee_date
    ON attendance_events(employee_id, work_date);

CREATE INDEX IF NOT EXISTS idx_notifications_employee_unread
    ON notifications(employee_id, is_read) WHERE is_read = FALSE;

-- ----------------------------------------------------------------------------
-- updated_at triggers
-- ----------------------------------------------------------------------------
CREATE TRIGGER trg_attendance_records_updated_at
    BEFORE UPDATE ON attendance_records
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
