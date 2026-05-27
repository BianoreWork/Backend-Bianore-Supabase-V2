# Schedule Backend — Dokumentasi

**Module:** Schedule Calendar & Day Detail  
**Versi:** 1.0.0 | **Tanggal:** 2026-05-12

---

## Urutan Deploy

```
1. employee_mobile_context/001  → core tables
2. schedule/201                  → shifts, employee_schedules, leave_requests
3. schedule/204                  → RLS schedule tables
4. home/101-104                  → home tables + RPCs (attendance data)
5. schedule/202                  → RPC employee_schedule_calendar
6. schedule/203                  → RPC employee_schedule_day_detail
7. schedule/205                  → seed data
8. schedule/206                  → jalankan test
```

---

## RPC 1: `employee_schedule_calendar`

**Tujuan:** Kalender bulanan — ringkasan + setiap hari dalam bulan.

```typescript
supabase.rpc('employee_schedule_calendar', {
    p_employee_id: 'uuid',
    p_month:       5,       // 1–12
    p_year:        2026,
})
```

### Response

```jsonc
{
  "employee_id":  "uuid",
  "month":        5,
  "year":         2026,
  "month_label":  "May       2026",

  "monthly_summary": {
    "present_count":    15,
    "late_count":       3,
    "absent_count":     1,
    "leave_count":      2,
    "sick_leave_count": 0,
    "overtime_hours":   4.5
  },

  "days": [
    {
      "date":       "2026-05-01",
      "day_name":   "Friday   ",
      "day_number": 1,
      "is_today":   false,
      "is_weekend": false,

      "has_schedule":  true,
      "schedule_id":   "uuid",
      "shift_name":    "Morning Shift",
      "start_time":    "08:00",
      "end_time":      "17:00",

      "attendance_status":     "present",
      "checkin_time":          "07:58",
      "checkout_time":         "17:05",
      "late_minutes":          0,
      "work_duration_minutes": 480,

      "marker": "present"
    }
    // ... satu entry per hari
  ],

  "fetched_at": "2026-05-12T08:30:00Z"
}
```

### Attendance Status di Kalender

| Status | Keterangan |
|--------|------------|
| `present` | Hadir (checked_in / late / very_late / completed) |
| `late` | Terlambat check-in |
| `absent` | Tidak hadir, hari sudah lewat |
| `leave` | Cuti disetujui (bukan sakit) |
| `sick_leave` | Cuti sakit disetujui |
| `no_schedule` | Tidak ada jadwal (libur / akhir pekan) |
| `no_attendance` | Hari mendatang, belum ada data |

### Marker Warna

| Marker | Warna di UI | Kondisi |
|--------|-------------|---------|
| `present` | 🟢 Hijau | Hadir |
| `absent` | 🔴 Merah | Tidak hadir |
| `leave` | 🟡 Kuning | Cuti |
| `sick` | 🟠 Oranye | Sakit |
| `today` | 🔵 Biru | Hari ini belum ada record |
| `scheduled` | ⚪ Abu | Hari mendatang dengan jadwal |
| `none` | — | Tidak ada jadwal |

---

## RPC 2: `employee_schedule_day_detail`

**Tujuan:** Detail lengkap satu tanggal (untuk tap hari di kalender).

```typescript
supabase.rpc('employee_schedule_day_detail', {
    p_employee_id: 'uuid',
    p_work_date:   '2026-05-12',
})
```

### Response

```jsonc
{
  "date":     "2026-05-12",
  "day_name": "Tuesday  ",
  "is_today": true,

  "schedule": {
    "has_schedule": true,
    "schedule_id":  "uuid",
    "status":       "active",
    "shift_name":   "Morning Shift",
    "start_time":   "08:00",
    "end_time":     "17:00",
    "break_minutes": 60,
    "total_work_hours": 8.0,
    "late_threshold_minutes":      15,
    "very_late_threshold_minutes": 60,
    "overtime_threshold_minutes":  30,
    "branch": { "id", "name", "address", "city", "latitude", "longitude", "radius_meters" }
  },

  "attendance": {
    "has_record": true,
    "status":     "late",
    "checkin": {
      "time":            "08:22:00",
      "latitude":        -6.208763,
      "longitude":       106.845599,
      "distance_meters": 45,
      "location_name":   "HQ Jakarta",
      "selfie_url":      "https://cdn.../selfie.jpg",
      "gps_verified":    true,
      "selfie_verified": true
    },
    "checkout":              null,
    "late_minutes":          22,
    "work_duration_minutes": 0,
    "overtime_minutes":      0
  },

  "leave_impact": null
}
```

### `leave_impact` (jika ada cuti disetujui)

```jsonc
{
  "leave_id":       "uuid",
  "leave_type":     "sick_leave",
  "leave_status":   "approved",
  "start_date":     "2026-05-05",
  "end_date":       "2026-05-15",
  "total_days":     11,
  "reason":         "Sakit demam berdarah",
  "attachment_url": "https://cdn.../surat-dokter.jpg",
  "approver_name":  "Siti Handayani",
  "approved_at":    "2026-05-05T07:00:00Z",
  "approver_notes": "Semoga lekas sembuh"
}
```

---

## Checklist Task 4

- [x] Tabel `employee_schedules` (semua field + index)
- [x] Tabel `leave_requests` (semua jenis cuti, status)
- [x] Schedule dikaitkan ke attendance record (via schedule_id)
- [x] Schedule dikaitkan ke branch (via branch_id)
- [x] Index: employee_id, work_date, tenant_id
- [x] Mencegah duplicate schedule per employee per hari (UNIQUE constraint)
- [x] RPC `employee_schedule_calendar` (parameter: employee_id, month, year)
- [x] Return monthly_summary (present, late, absent, leave, sick_leave, overtime)
- [x] Return calendar days (31 field per hari)
- [x] Support semua status: present, late, absent, leave, sick_leave, no_schedule
- [x] Tenant isolation + employee isolation
- [x] RPC `employee_schedule_day_detail` (parameter: employee_id, work_date)
- [x] Return schedule detail (shift, hours, branch, thresholds)
- [x] Return attendance detail (checkin/checkout dengan selfie & GPS proof)
- [x] Return leave_impact jika ada cuti di hari tersebut
- [x] Test: bulan berjalan, pindah bulan, no_schedule, leave/sick, day_detail
