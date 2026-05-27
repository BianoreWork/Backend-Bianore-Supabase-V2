-- =============================================================================
-- MIGRATION 106: Seed Data — Home Backend Testing
-- Module   : Home Backend
-- Prerequisite: seed data dari employee_mobile_context/004 sudah dijalankan
--               (tenant, branches, departments, positions, employees sudah ada)
--               schedule/205 sudah dijalankan (shifts, employee_schedules ada)
-- =============================================================================

-- ============================================================================
-- NOTIFICATIONS (untuk test unread count)
-- ============================================================================
INSERT INTO notifications (id, tenant_id, employee_id, notification_type, title, body, is_read)
VALUES
    ('notif-001-0000-0000-0000-000000000001',
     '11111111-0000-0000-0000-000000000001',
     'aaaaaaaa-0000-0000-0000-000000000001',  -- Budi (aktif)
     'attendance_reminder', 'Jangan lupa check-in!', 'Shift kamu dimulai pukul 08:00', FALSE),

    ('notif-002-0000-0000-0000-000000000001',
     '11111111-0000-0000-0000-000000000001',
     'aaaaaaaa-0000-0000-0000-000000000001',
     'schedule_changed', 'Jadwal diubah', 'Jadwal Rabu depan dipindah ke Morning Shift', FALSE),

    ('notif-003-0000-0000-0000-000000000001',
     '11111111-0000-0000-0000-000000000001',
     'aaaaaaaa-0000-0000-0000-000000000001',
     'announcement', 'Libur Nasional', 'Besok tanggal merah, kantor tutup', TRUE) -- sudah dibaca
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- ATTENDANCE RECORDS — riwayat bulan lalu (untuk monthly summary & recent list)
-- employee: Budi Santoso (BNR-0001)
-- ============================================================================
INSERT INTO attendance_records (
    id, tenant_id, employee_id, schedule_id, work_date,
    attendance_status,
    checkin_time, checkin_latitude, checkin_longitude,
    checkin_distance_meters, checkin_location_name,
    checkin_selfie_url, checkin_gps_verified, checkin_selfie_verified,
    checkout_time, checkout_latitude, checkout_longitude,
    checkout_distance_meters, checkout_location_name,
    checkout_selfie_url, checkout_gps_verified, checkout_selfie_verified,
    late_minutes, work_duration_minutes, overtime_minutes
)
VALUES
-- Hadir tepat waktu (minggu lalu)
('attend-001-0000-0000-0000-000000000001',
 '11111111-0000-0000-0000-000000000001',
 'aaaaaaaa-0000-0000-0000-000000000001',
 NULL, CURRENT_DATE - 1,
 'completed',
 (CURRENT_DATE - 1 + TIME '07:58:00') AT TIME ZONE 'Asia/Jakarta',
 -6.208763, 106.845599, 45, 'HQ Jakarta Pusat',
 'https://cdn.bianore.com/selfie/budi-checkin-1.jpg', TRUE, TRUE,
 (CURRENT_DATE - 1 + TIME '17:05:00') AT TIME ZONE 'Asia/Jakarta',
 -6.208763, 106.845599, 50, 'HQ Jakarta Pusat',
 'https://cdn.bianore.com/selfie/budi-checkout-1.jpg', TRUE, TRUE,
 0, 480, 0),

-- Telat (2 hari lalu)
('attend-002-0000-0000-0000-000000000001',
 '11111111-0000-0000-0000-000000000001',
 'aaaaaaaa-0000-0000-0000-000000000001',
 NULL, CURRENT_DATE - 2,
 'completed',
 (CURRENT_DATE - 2 + TIME '08:22:00') AT TIME ZONE 'Asia/Jakarta',
 -6.208763, 106.845599, 80, 'HQ Jakarta Pusat',
 'https://cdn.bianore.com/selfie/budi-checkin-2.jpg', TRUE, TRUE,
 (CURRENT_DATE - 2 + TIME '17:30:00') AT TIME ZONE 'Asia/Jakarta',
 -6.208763, 106.845599, 60, 'HQ Jakarta Pusat',
 'https://cdn.bianore.com/selfie/budi-checkout-2.jpg', TRUE, TRUE,
 22, 490, 0),

-- Hadir + overtime (3 hari lalu)
('attend-003-0000-0000-0000-000000000001',
 '11111111-0000-0000-0000-000000000001',
 'aaaaaaaa-0000-0000-0000-000000000001',
 NULL, CURRENT_DATE - 3,
 'completed',
 (CURRENT_DATE - 3 + TIME '07:55:00') AT TIME ZONE 'Asia/Jakarta',
 -6.208763, 106.845599, 30, 'HQ Jakarta Pusat',
 'https://cdn.bianore.com/selfie/budi-checkin-3.jpg', TRUE, TRUE,
 (CURRENT_DATE - 3 + TIME '19:10:00') AT TIME ZONE 'Asia/Jakarta',
 -6.208763, 106.845599, 40, 'HQ Jakarta Pusat',
 'https://cdn.bianore.com/selfie/budi-checkout-3.jpg', TRUE, TRUE,
 0, 595, 100),

-- Absent (5 hari lalu)
('attend-004-0000-0000-0000-000000000001',
 '11111111-0000-0000-0000-000000000001',
 'aaaaaaaa-0000-0000-0000-000000000001',
 NULL, CURRENT_DATE - 5,
 'absent',
 NULL, NULL, NULL, NULL, NULL, NULL, FALSE, FALSE,
 NULL, NULL, NULL, NULL, NULL, NULL, FALSE, FALSE,
 0, 0, 0)

ON CONFLICT (tenant_id, employee_id, work_date) DO NOTHING;
