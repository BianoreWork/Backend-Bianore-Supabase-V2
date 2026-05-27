-- =============================================================================
-- MIGRATION 004: Seed Data untuk Testing
-- Project  : Absensi Bianore
-- Purpose  : Data dummy yang mencakup semua skenario test:
--              ✅ Karyawan aktif (dengan branch & manager)
--              ✅ Karyawan aktif (tanpa branch)
--              ✅ Karyawan aktif (tanpa manager / top-level)
--              ✅ Karyawan inactive (is_active = false)
--              ✅ Karyawan on-leave
--              ✅ Karyawan resigned
--              ✅ Karyawan terminated
--
-- CATATAN: UUIDs di sini adalah nilai tetap agar bisa direferensikan di test.
--          Di production, biarkan gen_random_uuid() bekerja.
--          auth.users HARUS diisi terlebih dahulu di Supabase Auth
--          sebelum menjalankan seed ini.
-- =============================================================================

-- Matikan constraint sementara selama seeding (opsional, hanya di dev)
-- SET session_replication_role = replica;

-- ============================================================================
-- TENANT
-- ============================================================================
INSERT INTO tenants (id, name, slug, logo_url, is_active)
VALUES (
    '11111111-0000-0000-0000-000000000001',
    'PT Bianore Indonesia',
    'bianore',
    'https://cdn.bianore.com/logo.png',
    TRUE
)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- BRANCHES
-- ============================================================================
INSERT INTO branches (id, tenant_id, name, address, city, latitude, longitude, radius_meters, is_active)
VALUES
    (
        '22222222-0000-0000-0000-000000000001',
        '11111111-0000-0000-0000-000000000001',
        'HQ - Jakarta Pusat',
        'Jl. Sudirman No. 1, Jakarta Pusat',
        'Jakarta',
        -6.208763, 106.845599,
        150,
        TRUE
    ),
    (
        '22222222-0000-0000-0000-000000000002',
        '11111111-0000-0000-0000-000000000001',
        'Cabang Bandung',
        'Jl. Braga No. 10, Bandung',
        'Bandung',
        -6.921395, 107.607124,
        200,
        TRUE
    )
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- DEPARTMENTS
-- ============================================================================
INSERT INTO departments (id, tenant_id, name, code, is_active)
VALUES
    ('33333333-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001', 'Engineering',  'ENG',  TRUE),
    ('33333333-0000-0000-0000-000000000002', '11111111-0000-0000-0000-000000000001', 'Human Resources', 'HR', TRUE),
    ('33333333-0000-0000-0000-000000000003', '11111111-0000-0000-0000-000000000001', 'Operations',   'OPS',  TRUE),
    ('33333333-0000-0000-0000-000000000004', '11111111-0000-0000-0000-000000000001', 'Finance',      'FIN',  TRUE)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- POSITIONS
-- ============================================================================
INSERT INTO positions (id, tenant_id, department_id, name, level, is_active)
VALUES
    ('44444444-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001', 'Software Engineer',       1, TRUE),
    ('44444444-0000-0000-0000-000000000002', '11111111-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001', 'Engineering Manager',     3, TRUE),
    ('44444444-0000-0000-0000-000000000003', '11111111-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000002', 'HR Specialist',           1, TRUE),
    ('44444444-0000-0000-0000-000000000004', '11111111-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000003', 'Operations Coordinator',  1, TRUE),
    ('44444444-0000-0000-0000-000000000005', '11111111-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000004', 'Financial Analyst',       1, TRUE)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- EMPLOYEES
-- Catatan: user_id harus diisi dengan UUID dari auth.users yang sudah ada.
-- Di sini kita gunakan placeholder UUID — ganti dengan UUID asli saat deploy.
--
-- Format komentar: [SKENARIO TEST]
-- ============================================================================
INSERT INTO employees (
    id, user_id, tenant_id,
    employee_code, employee_name, email, phone, profile_photo_url,
    department_id, position_id, branch_id, manager_id,
    employment_status, active_status, is_active,
    join_date, contract_end
)
VALUES

-- ── [TEST 1] Karyawan AKTIF — dengan branch & manager (skenario normal) ────
(
    'aaaaaaaa-0000-0000-0000-000000000001',
    'auth-user-uuid-replace-1',          -- ganti dengan UUID auth.users asli
    '11111111-0000-0000-0000-000000000001',
    'BNR-0001', 'Budi Santoso',
    'budi.santoso@bianore.com', '081234567001',
    'https://cdn.bianore.com/photos/budi.jpg',
    '33333333-0000-0000-0000-000000000001',  -- Engineering
    '44444444-0000-0000-0000-000000000001',  -- Software Engineer
    '22222222-0000-0000-0000-000000000001',  -- HQ Jakarta (ada branch)
    'aaaaaaaa-0000-0000-0000-000000000003',  -- manager = Siti (ada manager)
    'full-time', 'active', TRUE,
    '2023-01-15', NULL
),

-- ── [TEST 2] Karyawan AKTIF — tanpa branch ────────────────────────────────
(
    'aaaaaaaa-0000-0000-0000-000000000002',
    'auth-user-uuid-replace-2',
    '11111111-0000-0000-0000-000000000001',
    'BNR-0002', 'Dewi Rahayu',
    'dewi.rahayu@bianore.com', '081234567002',
    NULL,
    '33333333-0000-0000-0000-000000000004',  -- Finance
    '44444444-0000-0000-0000-000000000005',  -- Financial Analyst
    NULL,                                     -- branch_id NULL (remote/HO)
    'aaaaaaaa-0000-0000-0000-000000000003',  -- ada manager
    'full-time', 'active', TRUE,
    '2022-06-01', NULL
),

-- ── [TEST 3] Karyawan AKTIF — tanpa manager (top-level / CEO) ─────────────
(
    'aaaaaaaa-0000-0000-0000-000000000003',
    'auth-user-uuid-replace-3',
    '11111111-0000-0000-0000-000000000001',
    'BNR-0003', 'Siti Handayani',
    'siti.handayani@bianore.com', '081234567003',
    'https://cdn.bianore.com/photos/siti.jpg',
    '33333333-0000-0000-0000-000000000002',  -- HR
    '44444444-0000-0000-0000-000000000002',  -- Engineering Manager
    '22222222-0000-0000-0000-000000000001',  -- ada branch
    NULL,                                     -- manager_id NULL (tidak ada atasan)
    'full-time', 'active', TRUE,
    '2021-03-01', NULL
),

-- ── [TEST 4] Karyawan INACTIVE (is_active = false) ────────────────────────
(
    'aaaaaaaa-0000-0000-0000-000000000004',
    'auth-user-uuid-replace-4',
    '11111111-0000-0000-0000-000000000001',
    'BNR-0004', 'Agus Permana',
    'agus.permana@bianore.com', '081234567004',
    NULL,
    '33333333-0000-0000-0000-000000000003',  -- Operations
    '44444444-0000-0000-0000-000000000004',  -- Operations Coordinator
    '22222222-0000-0000-0000-000000000002',  -- Cabang Bandung
    'aaaaaaaa-0000-0000-0000-000000000003',
    'full-time', 'inactive', FALSE,          -- is_active = FALSE → harus diblokir
    '2022-09-01', NULL
),

-- ── [TEST 5] Karyawan ON-LEAVE ─────────────────────────────────────────────
(
    'aaaaaaaa-0000-0000-0000-000000000005',
    'auth-user-uuid-replace-5',
    '11111111-0000-0000-0000-000000000001',
    'BNR-0005', 'Rina Kusuma',
    'rina.kusuma@bianore.com', '081234567005',
    NULL,
    '33333333-0000-0000-0000-000000000002',  -- HR
    '44444444-0000-0000-0000-000000000003',  -- HR Specialist
    '22222222-0000-0000-0000-000000000001',
    'aaaaaaaa-0000-0000-0000-000000000003',
    'full-time', 'on-leave', TRUE,           -- on-leave → BOLEH akses (hanya status)
    '2023-04-10', NULL
),

-- ── [TEST 6] Karyawan RESIGNED ─────────────────────────────────────────────
(
    'aaaaaaaa-0000-0000-0000-000000000006',
    'auth-user-uuid-replace-6',
    '11111111-0000-0000-0000-000000000001',
    'BNR-0006', 'Tono Wibowo',
    'tono.wibowo@bianore.com', '081234567006',
    NULL,
    '33333333-0000-0000-0000-000000000001',  -- Engineering
    '44444444-0000-0000-0000-000000000001',  -- Software Engineer
    NULL,
    'aaaaaaaa-0000-0000-0000-000000000003',
    'full-time', 'resigned', FALSE,          -- resigned → harus diblokir
    '2021-07-01', NULL
),

-- ── [TEST 7] Karyawan TERMINATED ───────────────────────────────────────────
(
    'aaaaaaaa-0000-0000-0000-000000000007',
    'auth-user-uuid-replace-7',
    '11111111-0000-0000-0000-000000000001',
    'BNR-0007', 'Hendra Gunawan',
    'hendra.gunawan@bianore.com', '081234567007',
    NULL,
    '33333333-0000-0000-0000-000000000003',  -- Operations
    '44444444-0000-0000-0000-000000000004',  -- Operations Coordinator
    '22222222-0000-0000-0000-000000000002',
    NULL,
    'contract', 'terminated', FALSE,         -- terminated → harus diblokir
    '2023-01-01', '2024-12-31'
),

-- ── [TEST 8] Karyawan KONTRAK — aktif, dengan branch ─────────────────────
(
    'aaaaaaaa-0000-0000-0000-000000000008',
    'auth-user-uuid-replace-8',
    '11111111-0000-0000-0000-000000000001',
    'BNR-0008', 'Maya Indriati',
    'maya.indriati@bianore.com', '081234567008',
    'https://cdn.bianore.com/photos/maya.jpg',
    '33333333-0000-0000-0000-000000000001',  -- Engineering
    '44444444-0000-0000-0000-000000000001',  -- Software Engineer
    '22222222-0000-0000-0000-000000000002',  -- Cabang Bandung
    'aaaaaaaa-0000-0000-0000-000000000003',
    'contract', 'active', TRUE,
    '2025-01-01', '2026-12-31'
)

ON CONFLICT (id) DO NOTHING;
