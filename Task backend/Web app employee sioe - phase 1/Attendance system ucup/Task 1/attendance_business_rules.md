# Attendance Business Rules — Final Definition
> Task 1 · Signed-off reference document

---

## 1. Status List

| Status              | Code                | Siapa yang generate      |
|---------------------|---------------------|--------------------------|
| Scheduled           | `scheduled`         | Sistem (saat shift dibuat) |
| Present / On-time   | `present`           | Sistem (setelah check-in) |
| Late                | `late`              | Sistem (setelah check-in) |
| Absent              | `absent`            | Sistem (setelah shift selesai) |
| Overtime            | `overtime`          | Sistem (setelah check-out) |
| Leave               | `leave`             | Sistem (dari approved leave) |
| Sick                | `sick`              | Sistem (dari approved sick leave) |
| Holiday             | `holiday`           | Sistem (dari tabel holidays — future) |
| Manual Adjustment   | `manual_adjustment` | Admin override           |

---

## 2. Business Rules Per Status

### 2.1 Present (On-time)
```
CONDITION:
  attendance_record EXISTS
  AND clock_in_at <= (shift.start_time + grace_period_minutes * INTERVAL '1 minute')

FORMULA:
  system_status = 'present'
  late_minutes   = 0
```

### 2.2 Late
```
CONDITION:
  attendance_record EXISTS
  AND clock_in_at > (shift.start_time + grace_period_minutes * INTERVAL '1 minute')

FORMULA:
  system_status = 'late'
  late_minutes   = EXTRACT(EPOCH FROM (clock_in_at - shift.start_time)) / 60
                   -- selalu positif; lebih transparan untuk payroll
```
> `grace_period_minutes` disimpan di tabel `shifts` (default: 15 menit jika NULL).

### 2.3 Overtime
```
CONDITION:
  attendance_record EXISTS
  AND clock_out_at > shift.end_time

FORMULA:
  system_status      = 'overtime'  (status tambahan, bisa combine dengan present/late)
  overtime_minutes   = EXTRACT(EPOCH FROM (clock_out_at - shift.end_time)) / 60
```
> Overtime bukan exclusive — karyawan bisa `late` DAN `overtime` dalam hari yang sama.
> `system_status` dalam attendance_records = status **kehadiran** (present/late/absent).
> `overtime_minutes` disimpan sebagai kolom numerik terpisah.

### 2.4 Absent
```
CONDITION:
  schedule EXISTS (employee punya shift hari ini)
  AND attendance_record TIDAK ADA (tidak ada clock-in)
  AND TIDAK ADA approved leave yang mencakup tanggal ini
  AND tanggal sudah lewat shift.end_time (shift sudah selesai)

FORMULA:
  system_status = 'absent'

TIMING:
  Absent record di-generate oleh scheduled job / pg_cron
  SETELAH shift.end_time + buffer 15 menit
  (agar tidak flag absent saat karyawan sedang dalam perjalanan check-in)
```

### 2.5 Leave / Sick
```
CONDITION:
  EXISTS approved leave WHERE
    leave.employee_id = schedule.employee_id
    AND schedule.date BETWEEN leave.start_date AND leave.end_date
    AND leave.status = 'approved'

FORMULA:
  system_status = 'leave'  -- jika leave_type = 'annual' / 'personal'
  system_status = 'sick'   -- jika leave_type = 'sick'
```

### 2.6 Holiday *(future)*
```
CONDITION:
  EXISTS holiday WHERE holiday.date = schedule.date
  AND holiday.branch_id = employee.branch_id (atau global)

FORMULA:
  system_status = 'holiday'
  -- Karyawan tidak perlu check-in; tidak dihitung absent
```

---

## 3. late_minutes Formula
```sql
late_minutes = GREATEST(0,
  EXTRACT(EPOCH FROM (
    clock_in_at - (shift.start_time::timestamptz)
  )) / 60
)::integer
```
- Dibulatkan ke menit terdekat (FLOOR)
- Nol jika on-time
- Transparan untuk payroll — bisa langsung dihitung potongan

---

## 4. work_duration_minutes Formula
```sql
work_duration_minutes = EXTRACT(EPOCH FROM (clock_out_at - clock_in_at)) / 60
```
- NULL jika belum clock-out

---

## 5. Kapan Absent Record Di-generate
- **Trigger**: pg_cron job jalan setiap jam (`0 * * * *`)
- **Kondisi**: `NOW() > shift.end_time + INTERVAL '15 minutes'`
- **Target**: semua schedule yang belum punya attendance_record dan tidak ada approved leave
- **Hati-hati**: jangan generate ulang jika sudah ada record dengan system_status = 'absent'

---

## 6. Status Compute Priority (urutan evaluasi)
```
1. Holiday    → cek tabel holidays dulu
2. Leave/Sick → cek approved leaves
3. Present    → ada check-in, on-time
4. Late       → ada check-in, terlambat
5. Absent     → tidak ada check-in, shift sudah selesai
6. Scheduled  → shift belum dimulai (status sementara)
```

---

## 7. Sign-off
| Role            | Nama | Tanggal |
|-----------------|------|---------|
| Backend Lead    |      |         |
| HR / Operations |      |         |
| Frontend Lead   |      |         |
