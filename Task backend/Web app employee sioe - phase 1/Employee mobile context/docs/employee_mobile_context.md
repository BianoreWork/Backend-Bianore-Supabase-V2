# `employee_mobile_context` — Dokumentasi RPC

**Project:** Absensi Bianore  
**Module:** Employee Mobile Context  
**Versi:** 1.0.0  
**Tanggal:** 2026-05-12

---

## Ringkasan

RPC `employee_mobile_context` adalah endpoint utama yang dipanggil oleh mobile app segera setelah user berhasil login melalui Supabase Auth. Fungsi ini mengembalikan semua data konteks karyawan yang dibutuhkan untuk menjalankan fitur absensi.

**Keamanan:** Fungsi ini hanya dapat mengembalikan data milik user yang sedang login. Tidak ada cara bagi satu karyawan untuk membaca data karyawan lain.

---

## Cara Memanggil

### Supabase JS Client

```typescript
const { data, error } = await supabase.rpc('employee_mobile_context')
```

### cURL (untuk testing)

```bash
curl -X POST 'https://<project-ref>.supabase.co/rest/v1/rpc/employee_mobile_context' \
  -H "apikey: <anon-key>" \
  -H "Authorization: Bearer <user-jwt-token>" \
  -H "Content-Type: application/json"
```

---

## Request

Tidak ada parameter. Identitas user diambil otomatis dari JWT Bearer token.

| Parameter | Tipe | Keterangan |
|-----------|------|------------|
| *(tidak ada)* | — | auth.uid() diambil dari JWT |

---

## Response — Sukses (HTTP 200)

```jsonc
{
  "employee_id":    "aaaaaaaa-0000-0000-0000-000000000001",
  "employee_code":  "BNR-0001",
  "employee_name":  "Budi Santoso",
  "email":          "budi.santoso@bianore.com",
  "phone":          "081234567001",
  "profile_photo":  "https://cdn.bianore.com/photos/budi.jpg",

  "department": {
    "id":   "33333333-0000-0000-0000-000000000001",
    "name": "Engineering"
  },

  "position": {
    "id":   "44444444-0000-0000-0000-000000000001",
    "name": "Software Engineer"
  },

  "branch": {
    "id":      "22222222-0000-0000-0000-000000000001",
    "name":    "HQ - Jakarta Pusat",
    "address": "Jl. Sudirman No. 1, Jakarta Pusat",
    "city":    "Jakarta"
  },

  "manager": {
    "id":    "aaaaaaaa-0000-0000-0000-000000000003",
    "code":  "BNR-0003",
    "name":  "Siti Handayani",
    "email": "siti.handayani@bianore.com",
    "photo": "https://cdn.bianore.com/photos/siti.jpg"
  },

  "tenant_id":   "11111111-0000-0000-0000-000000000001",
  "tenant_name": "PT Bianore Indonesia",
  "tenant_logo": "https://cdn.bianore.com/logo.png",

  "employment_status": "full-time",
  "active_status":     "active",

  "join_date":    "2023-01-15",
  "contract_end": null,

  "fetched_at": "2026-05-12T08:30:00.000Z"
}
```

### Field Nullable

| Field | Nullable | Kondisi |
|-------|----------|---------|
| `phone` | ✅ | Nomor telepon belum diisi |
| `profile_photo` | ✅ | Foto belum diunggah |
| `branch` | ✅ | Karyawan remote / tidak ditugaskan ke cabang tertentu |
| `manager` | ✅ | Karyawan level teratas (CEO, direktur) |
| `contract_end` | ✅ | Karyawan permanen (`full-time`) |
| `tenant_logo` | ✅ | Logo tenant belum diunggah |

---

## Response — Error

| HTTP Code | Error Code | Penyebab | Pesan untuk User |
|-----------|------------|----------|-----------------|
| 401 | `UNAUTHENTICATED` | JWT tidak ada / expired | "Silakan login kembali" |
| 403 | `EMPLOYEE_INACTIVE` | `is_active = false` di-set admin | "Akun Anda dinonaktifkan. Hubungi HR." |
| 403 | `EMPLOYEE_RESIGNED` | `active_status = 'resigned'` | "Akun Anda tidak dapat mengakses aplikasi." |
| 403 | `EMPLOYEE_TERMINATED` | `active_status = 'terminated'` | "Akun Anda tidak dapat mengakses aplikasi." |
| 404 | `EMPLOYEE_NOT_FOUND` | User login tapi belum punya record employee | "Data karyawan tidak ditemukan. Hubungi HR." |
| 500 | `INTERNAL_ERROR` | Error tak terduga di server | "Terjadi kesalahan sistem. Coba lagi." |

### Contoh Body Error (Supabase format)

```json
{
  "code":    "P0403",
  "details": null,
  "hint":    null,
  "message": "EMPLOYEE_RESIGNED: Karyawan yang sudah mengundurkan diri tidak dapat mengakses aplikasi"
}
```

---

## Logika Validasi Akses

```
User login (JWT valid)
        │
        ▼
   auth.uid() ada?  ─── TIDAK ──► Error: UNAUTHENTICATED
        │
       YA
        │
        ▼
   Ada employee dengan user_id = auth.uid()?  ─── TIDAK ──► Error: EMPLOYEE_NOT_FOUND
        │
       YA
        │
        ▼
   is_active = true?  ─── TIDAK ──► Error: EMPLOYEE_INACTIVE
        │
       YA
        │
        ▼
   active_status = 'resigned'?  ─── YA ──► Error: EMPLOYEE_RESIGNED
        │
       TIDAK
        │
        ▼
   active_status = 'terminated'?  ─── YA ──► Error: EMPLOYEE_TERMINATED
        │
       TIDAK
        │
        ▼
   Return data karyawan ✅
   (active_status bisa: 'active' atau 'on-leave')
```

### Catatan `on-leave`

Karyawan dengan `active_status = 'on-leave'` **diizinkan** membuka app dan melihat profilnya. Pembatasan aktivitas (misalnya tidak bisa absen) ditangani di level fitur, **bukan** di `employee_mobile_context`.

---

## Keamanan

### 1. Isolasi Data (Row-Level Security)

`employee_mobile_context` menggunakan `SECURITY DEFINER` namun lookup dilakukan dengan `WHERE e.user_id = auth.uid()`. Tidak mungkin memanipulasi query untuk membaca data karyawan lain karena:

- `auth.uid()` berasal dari JWT yang ditandatangani Supabase Auth
- Tidak ada parameter eksternal yang bisa diinjeksi
- `search_path` dikunci ke `public, auth`

### 2. Role & Grant

```sql
GRANT EXECUTE ON FUNCTION employee_mobile_context() TO authenticated;
REVOKE EXECUTE ON FUNCTION employee_mobile_context() FROM anon;
```

User yang belum login (`anon`) tidak bisa memanggil fungsi ini sama sekali.

### 3. RLS pada Tabel `employees`

Meski `employee_mobile_context` menggunakan `SECURITY DEFINER` (bypass RLS), tabel `employees` tetap punya RLS policy aktif yang melindungi akses langsung via PostgREST `/rest/v1/employees`.

---

## Contoh Penggunaan di Mobile App (TypeScript)

```typescript
import { createClient } from '@supabase/supabase-js'
import type { EmployeeMobileContext } from '../types/employee_mobile_context'
import { parseEmployeeContextError } from '../types/employee_mobile_context'

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)

async function loadEmployeeContext(): Promise<EmployeeMobileContext> {
    const { data, error } = await supabase.rpc('employee_mobile_context')

    if (error) {
        const code = parseEmployeeContextError(error.message)

        switch (code) {
            case 'UNAUTHENTICATED':
                // Redirect ke halaman login
                await supabase.auth.signOut()
                router.push('/login')
                throw new Error('Sesi berakhir.')

            case 'EMPLOYEE_INACTIVE':
                throw new Error('Akun Anda telah dinonaktifkan. Hubungi tim HR.')

            case 'EMPLOYEE_RESIGNED':
            case 'EMPLOYEE_TERMINATED':
                throw new Error('Akun Anda tidak memiliki akses ke aplikasi ini.')

            case 'EMPLOYEE_NOT_FOUND':
                throw new Error('Data karyawan tidak ditemukan. Hubungi tim HR.')

            default:
                throw new Error('Terjadi kesalahan sistem. Silakan coba lagi.')
        }
    }

    return data as EmployeeMobileContext
}
```

---

## Struktur File Backend

```
Backend/
├── supabase/
│   └── migrations/
│       ├── 20260512_001_create_core_tables.sql        ← Tabel: tenants, branches, departments, positions, employees
│       ├── 20260512_002_employee_mobile_context_rpc.sql ← RPC employee_mobile_context()
│       ├── 20260512_003_rls_policies.sql              ← Row Level Security
│       ├── 20260512_004_seed_test_data.sql            ← Data testing (8 skenario)
│       └── 20260512_005_test_employee_mobile_context.sql ← Test script SQL
├── types/
│   └── employee_mobile_context.ts                     ← TypeScript types & helpers
└── docs/
    └── employee_mobile_context.md                     ← Dokumentasi ini
```

---

## Cara Deploy ke Supabase

```bash
# 1. Login ke Supabase CLI
supabase login

# 2. Link ke project
supabase link --project-ref <your-project-ref>

# 3. Jalankan migrations secara berurutan
supabase db push

# Atau manual via psql:
psql $DATABASE_URL -f supabase/migrations/20260512_001_create_core_tables.sql
psql $DATABASE_URL -f supabase/migrations/20260512_002_employee_mobile_context_rpc.sql
psql $DATABASE_URL -f supabase/migrations/20260512_003_rls_policies.sql
psql $DATABASE_URL -f supabase/migrations/20260512_004_seed_test_data.sql

# 4. Jalankan test (ganti UUID dengan UUID auth.users yang asli dulu)
psql $DATABASE_URL -f supabase/migrations/20260512_005_test_employee_mobile_context.sql
```

---

## Checklist Task

- [x] Buat RPC `employee_mobile_context`
- [x] Ambil employee berdasarkan JWT user (`auth.uid()`)
- [x] Return `employee_id`
- [x] Return `employee_code`
- [x] Return `employee_name`
- [x] Return `profile_photo`
- [x] Return `department`
- [x] Return `position`
- [x] Return `branch` (nullable)
- [x] Return `manager / approver` (nullable)
- [x] Return `tenant_id`
- [x] Return `employment_status`
- [x] Return `active_status`
- [x] Validasi employee inactive tidak bisa akses app (`is_active = false`)
- [x] Validasi employee resigned tidak bisa akses app
- [x] Validasi employee terminated tidak bisa akses app
- [x] Validasi user tidak bisa membaca employee lain (via `auth.uid()` lookup)
- [x] Test karyawan aktif (dengan branch & manager)
- [x] Test karyawan aktif (tanpa branch)
- [x] Test karyawan aktif (tanpa manager)
- [x] Test karyawan inactive
- [x] Test karyawan on-leave
- [x] Test karyawan resigned
- [x] Test karyawan terminated
- [x] Dokumentasikan response `employee_mobile_context`
