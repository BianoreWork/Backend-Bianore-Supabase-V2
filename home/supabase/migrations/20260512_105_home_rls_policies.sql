-- =============================================================================
-- MIGRATION 105: RLS Policies — Home Tables
-- Module   : Home Backend
-- =============================================================================

ALTER TABLE shifts              ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_records  ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_events   ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications       ENABLE ROW LEVEL SECURITY;

-- shifts: karyawan bisa baca semua shift dalam tenant mereka
CREATE POLICY "employee: read shifts in own tenant"
    ON shifts FOR SELECT TO authenticated
    USING (tenant_id = my_tenant_id());

-- attendance_records: karyawan HANYA baca milik sendiri
CREATE POLICY "employee: read own attendance records"
    ON attendance_records FOR SELECT TO authenticated
    USING (employee_id = (SELECT id FROM employees WHERE user_id = auth.uid() LIMIT 1));

-- admin: baca semua attendance dalam tenant
CREATE POLICY "admin: read all attendance in tenant"
    ON attendance_records FOR SELECT TO authenticated
    USING (is_tenant_admin() AND tenant_id = my_tenant_id());

-- attendance_events: karyawan hanya baca event milik sendiri
CREATE POLICY "employee: read own attendance events"
    ON attendance_events FOR SELECT TO authenticated
    USING (employee_id = (SELECT id FROM employees WHERE user_id = auth.uid() LIMIT 1));

-- notifications: karyawan hanya baca notifikasi milik sendiri
CREATE POLICY "employee: read own notifications"
    ON notifications FOR SELECT TO authenticated
    USING (employee_id = (SELECT id FROM employees WHERE user_id = auth.uid() LIMIT 1));

-- Semua INSERT/UPDATE pada attendance_records dan events dilakukan
-- via SECURITY DEFINER functions (check_in / check_out), bukan langsung.
