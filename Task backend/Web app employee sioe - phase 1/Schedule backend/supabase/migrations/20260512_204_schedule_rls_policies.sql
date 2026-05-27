-- =============================================================================
-- MIGRATION 204: RLS Policies — Schedule Tables
-- Module   : Schedule Backend
-- =============================================================================

ALTER TABLE employee_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_requests     ENABLE ROW LEVEL SECURITY;

-- employee_schedules: karyawan hanya baca jadwal milik sendiri
CREATE POLICY "employee: read own schedules"
    ON employee_schedules FOR SELECT TO authenticated
    USING (employee_id = (SELECT id FROM employees WHERE user_id = auth.uid() LIMIT 1));

-- admin/HR bisa baca semua jadwal dalam tenant
CREATE POLICY "admin: read all schedules in tenant"
    ON employee_schedules FOR SELECT TO authenticated
    USING (is_tenant_admin() AND tenant_id = my_tenant_id());

-- leave_requests: karyawan hanya baca milik sendiri
CREATE POLICY "employee: read own leave requests"
    ON leave_requests FOR SELECT TO authenticated
    USING (employee_id = (SELECT id FROM employees WHERE user_id = auth.uid() LIMIT 1));

-- admin/HR bisa baca semua leave requests dalam tenant
CREATE POLICY "admin: read all leave requests in tenant"
    ON leave_requests FOR SELECT TO authenticated
    USING (is_tenant_admin() AND tenant_id = my_tenant_id());
