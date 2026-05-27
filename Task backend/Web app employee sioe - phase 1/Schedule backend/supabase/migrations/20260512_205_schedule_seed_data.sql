-- =============================================================================
-- MIGRATION 205: Seed Data — Schedule Backend Testing
-- Module   : Schedule Backend
-- Prerequisite: employee_mobile_context/004 sudah dijalankan
-- =============================================================================

-- ============================================================================
-- SHIFTS (master data)
-- ============================================================================
INSERT INTO shifts (id, tenant_id, name, start_time, end_time, break_minutes,
                    late_threshold_minutes, very_late_threshold_minutes, overtime_threshold_minutes, color)
VALUES
    ('shift-001-0000-0000-0000-000000000001',
     '11111111-0000-0000-0000-000000000001',
     'Morning Shift', '08:00', '17:00', 60, 15, 60, 30, '#3B82F6'),

    ('shift-002-0000-0000-0000-000000000001',
     '11111111-0000-0000-0000-000000000001',
     'Full Day', '09:00', '18:00', 60, 15, 60, 30, '#10B981'),

    ('shift-003-0000-0000-0000-000000000001',
     '11111111-0000-0000-0000-000000000001',
     'Evening Shift', '13:00', '22:00', 60, 15, 60, 30, '#8B5CF6')

ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- EMPLOYEE SCHEDULES
-- Karyawan: Budi (BNR-0001) — minggu berjalan + minggu depan
-- ============================================================================
INSERT INTO employee_schedules (
    id, tenant_id, employee_id, branch_id, shift_id,
    work_date, shift_name, start_time, end_time, break_minutes,
    late_threshold_minutes, very_late_threshold_minutes, overtime_threshold_minutes,
    schedule_status
)
VALUES
    -- Hari ini
    ('sched-001-0000-0000-0000-000000000001',
     '11111111-0000-0000-0000-000000000001',
     'aaaaaaaa-0000-0000-0000-000000000001',
     '22222222-0000-0000-0000-000000000001',
     'shift-001-0000-0000-0000-000000000001',
     CURRENT_DATE, 'Morning Shift', '08:00', '17:00', 60, 15, 60, 30, 'active'),

    -- Kemarin (untuk test riwayat)
    ('sched-002-0000-0000-0000-000000000001',
     '11111111-0000-0000-0000-000000000001',
     'aaaaaaaa-0000-0000-0000-000000000001',
     '22222222-0000-0000-0000-000000000001',
     'shift-001-0000-0000-0000-000000000001',
     CURRENT_DATE - 1, 'Morning Shift', '08:00', '17:00', 60, 15, 60, 30, 'active'),

    -- 2 hari lalu (telat)
    ('sched-003-0000-0000-0000-000000000001',
     '11111111-0000-0000-0000-000000000001',
     'aaaaaaaa-0000-0000-0000-000000000001',
     '22222222-0000-0000-0000-000000000001',
     'shift-001-0000-0000-0000-000000000001',
     CURRENT_DATE - 2, 'Morning Shift', '08:00', '17:00', 60, 15, 60, 30, 'active'),

    -- 3 hari lalu (overtime)
    ('sched-004-0000-0000-0000-000000000001',
     '11111111-0000-0000-0000-000000000001',
     'aaaaaaaa-0000-0000-0000-000000000001',
     '22222222-0000-0000-0000-000000000001',
     'shift-001-0000-0000-0000-000000000001',
     CURRENT_DATE - 3, 'Morning Shift', '08:00', '17:00', 60, 15, 60, 30, 'active'),

    -- 5 hari lalu (absent — ada jadwal tapi tidak hadir)
    ('sched-005-0000-0000-0000-000000000001',
     '11111111-0000-0000-0000-000000000001',
     'aaaaaaaa-0000-0000-0000-000000000001',
     '22222222-0000-0000-0000-000000000001',
     'shift-001-0000-0000-0000-000000000001',
     CURRENT_DATE - 5, 'Morning Shift', '08:00', '17:00', 60, 15, 60, 30, 'active'),

    -- Besok (belum hadir — future)
    ('sched-006-0000-0000-0000-000000000001',
     '11111111-0000-0000-0000-000000000001',
     'aaaaaaaa-0000-0000-0000-000000000001',
     '22222222-0000-0000-0000-000000000001',
     'shift-002-0000-0000-0000-000000000001',
     CURRENT_DATE + 1, 'Full Day', '09:00', '18:00', 60, 15, 60, 30, 'active'),

    -- 3 hari ke depan (untuk Maya — karyawan kontrak)
    ('sched-007-0000-0000-0000-000000000001',
     '11111111-0000-0000-0000-000000000001',
     'aaaaaaaa-0000-0000-0000-000000000008',
     '22222222-0000-0000-0000-000000000002',
     'shift-001-0000-0000-0000-000000000001',
     CURRENT_DATE, 'Morning Shift', '08:00', '17:00', 60, 15, 60, 30, 'active')

ON CONFLICT (tenant_id, employee_id, work_date) DO NOTHING;

-- ============================================================================
-- LEAVE REQUESTS (untuk test calendar dengan cuti)
-- ============================================================================
INSERT INTO leave_requests (
    id, tenant_id, employee_id, approver_id,
    leave_type, leave_status,
    start_date, end_date, total_days, reason,
    approved_at, approver_notes
)
VALUES
    -- Rina (on-leave) — cuti sakit disetujui
    ('leave-001-0000-0000-0000-000000000001',
     '11111111-0000-0000-0000-000000000001',
     'aaaaaaaa-0000-0000-0000-000000000005',  -- Rina
     'aaaaaaaa-0000-0000-0000-000000000003',  -- Siti (manager)
     'sick_leave', 'approved',
     CURRENT_DATE - 7, CURRENT_DATE + 3, 11,
     'Sakit demam berdarah, surat dokter terlampir',
     NOW() - INTERVAL '7 days', 'Semoga lekas sembuh'),

    -- Budi — cuti tahunan (masa mendatang, pending)
    ('leave-002-0000-0000-0000-000000000001',
     '11111111-0000-0000-0000-000000000001',
     'aaaaaaaa-0000-0000-0000-000000000001',  -- Budi
     'aaaaaaaa-0000-0000-0000-000000000003',
     'annual_leave', 'pending',
     CURRENT_DATE + 14, CURRENT_DATE + 16, 3,
     'Keperluan keluarga',
     NULL, NULL)

ON CONFLICT (id) DO NOTHING;
