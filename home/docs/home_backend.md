# Home Backend — Dokumentasi

**Module:** Home + Check-in/Check-out  
**Versi:** 1.0.0 | **Tanggal:** 2026-05-12

---

## Urutan Deploy (WAJIB diikuti)

```
1. employee_mobile_context/001  → core tables
2. schedule/201                  → shifts, employee_schedules, leave_requests
3. home/101                      → attendance_records, attendance_events, notifications
4. home/102                      → RPC employee_home_summary
5. home/103                      → RPC employee_check_in
6. home/104                      → RPC employee_check_out
7. home/105                      → RLS home tables
8. schedule/205                  → seed shifts & schedules
9. home/106                      → seed attendance & notifications
10. home/107                     → jalankan test
```

---

## RPC 1: `employee_home_summary`

**Tujuan:** Semua data Home screen dalam satu call.

```typescript
supabase.rpc('employee_home_summary', {
    p_employee_id: 'uuid',
    p_work_date:   '2026-05-12',   // opsional, default hari ini
})
```

### Response

```jsonc
{
  "employee":    { "id", "code", "name", "email", "photo", "department", "position", "tenant_name" },
  "server_date": "2026-05-12",
  "server_time": "08:30:00",
  "unread_notification_count": 2,

  "today_status": "not_checked_in",  // lihat tabel status di bawah

  "today_schedule": {
    "schedule_id": "uuid",
    "shift_name":  "Morning Shift",
    "start_time":  "08:00",
    "end_time":    "17:00",
    "break_minutes": 60,
    "branch": { "id", "name", "address", "city", "latitude", "longitude", "radius_meters" }
  },

  "checkin":  null,  // atau { time, latitude, longitude, distance_meters, location_name, selfie_url, gps_verified, selfie_verified }
  "checkout": null,

  "work_calculation": { "late_minutes": 0, "work_duration_minutes": 0, "overtime_minutes": 0 },
  "monthly_summary":  { "month", "year", "present_count", "late_count", "absent_count", "overtime_hours" },
  "recent_attendance": [ ... ]
}
```

### Status Hari Ini

| Status | Kondisi |
|--------|---------|
| `no_schedule` | Tidak ada jadwal / jadwal cancelled |
| `not_checked_in` | Ada jadwal, belum check-in |
| `checked_in` | Sudah check-in, tepat waktu |
| `late` | Sudah check-in, terlambat |
| `very_late` | Sudah check-in, sangat terlambat |
| `completed` | Sudah check-out |
| `absent` | Ada jadwal, tidak hadir (hari sudah lewat) |

---

## RPC 2: `employee_check_in`

```typescript
supabase.rpc('employee_check_in', {
    p_employee_id:   'uuid',
    p_latitude:      -6.208763,
    p_longitude:     106.845599,
    p_selfie_url:    'https://cdn.../selfie.jpg',
    p_location_name: 'HQ Jakarta',   // opsional
    p_work_date:     '2026-05-12',   // opsional, default hari ini
})
```

**Return:** `employee_home_summary` yang sudah diupdate.

### Validasi Check-in

| Validasi | Error Code | Keterangan |
|----------|------------|------------|
| Employee aktif | `EMPLOYEE_INACTIVE` | is_active = false atau status resign/terminated |
| GPS wajib | `GPS_REQUIRED` | latitude/longitude null |
| Selfie wajib | `SELFIE_REQUIRED` | selfie_url null/kosong |
| Ada jadwal hari ini | `NO_SCHEDULE` | Tidak ada employee_schedule untuk tanggal ini |
| Belum check-in | `ALREADY_CHECKED_IN` | Sudah ada attendance record |
| Dalam radius | `OUT_OF_RANGE` | Jarak > radius_meters di branch |

### Kalkulasi Otomatis

- `late_minutes` = menit antara `checkin_time` vs `schedule.start_time`
- `attendance_status`:
  - `late_minutes = 0` → `checked_in`
  - `0 < late_minutes < very_late_threshold` → `late`
  - `late_minutes >= very_late_threshold` → `very_late`

---

## RPC 3: `employee_check_out`

```typescript
supabase.rpc('employee_check_out', {
    p_employee_id: 'uuid',
    p_latitude:    -6.208763,
    p_longitude:   106.845599,
    p_selfie_url:  'https://cdn.../selfie.jpg',
})
```

**Return:** `employee_home_summary` yang sudah diupdate.

### Validasi Check-out

| Validasi | Error Code |
|----------|------------|
| GPS wajib | `GPS_REQUIRED` |
| Selfie wajib | `SELFIE_REQUIRED` |
| Sudah check-in | `NOT_CHECKED_IN` |
| Belum check-out | `ALREADY_CHECKED_OUT` |

> GPS check-out **tidak memblokir** (hanya mencatat `gps_verified = false`) karena karyawan bisa sudah meninggalkan area kerja.

### Kalkulasi Otomatis

- `work_duration_minutes` = (checkout - checkin) - break_minutes
- `overtime_minutes` = menit setelah (end_time + overtime_threshold)

---

## Error Codes Lengkap

| Code | HTTP | Keterangan |
|------|------|------------|
| `UNAUTHENTICATED` | 401 | Belum login |
| `EMPLOYEE_NOT_FOUND` | 404 | User tidak punya employee record |
| `EMPLOYEE_INACTIVE` | 403 | is_active = false |
| `EMPLOYEE_ACCESS_REVOKED` | 403 | resigned/terminated |
| `FORBIDDEN` | 403 | Coba akses data employee lain |
| `GPS_REQUIRED` | 422 | GPS null |
| `SELFIE_REQUIRED` | 422 | Selfie null |
| `NO_SCHEDULE` | 404 | Tidak ada jadwal |
| `ALREADY_CHECKED_IN` | 409 | Double check-in |
| `ALREADY_CHECKED_OUT` | 409 | Double check-out |
| `NOT_CHECKED_IN` | 409 | Check-out sebelum check-in |
| `OUT_OF_RANGE` | 422 | Di luar radius lokasi kerja |

---

## Checklist Task 3

- [x] RPC `employee_home_summary` (parameter: employee_id, work_date)
- [x] Return employee header (name, department, position, photo)
- [x] Return server date & time
- [x] Return unread notification count
- [x] Return today attendance status (6 status)
- [x] Return today schedule (shift, time, branch, radius)
- [x] Return check-in data (time, GPS, selfie, verified)
- [x] Return check-out data (time, GPS, selfie, verified)
- [x] Return work calculation (duration, late, overtime)
- [x] Return monthly summary (present, late, absent, overtime hours)
- [x] Return recent attendance list
- [x] Tenant isolation + employee isolation
- [x] Tabel `attendance_records` (semua field check-in/out)
- [x] Tabel `attendance_events` (audit log)
- [x] RPC `employee_check_in` (GPS, selfie, radius, late calc)
- [x] RPC `employee_check_out` (duration, overtime calc)
- [x] Validasi tidak bisa check-in dua kali
- [x] Validasi tidak bisa check-out sebelum check-in
- [x] Validasi tidak bisa check-out dua kali
- [x] Test: belum check-in, sudah check-in, sudah check-out, no schedule, late
