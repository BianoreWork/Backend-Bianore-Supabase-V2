# Dashboard Data Contracts — Reference
> Task 6 · Untuk Backend Support & Frontend Lead

---

## Cara Memanggil RPC dari Frontend (Supabase JS)

```ts
const { data, error } = await supabase.rpc('get_admin_attendance_overview', {
  p_date: '2026-05-13',
  p_branch_id: null,
  p_department_id: null
})
```

---

## 6.1 `get_admin_attendance_overview`

**Kegunaan:** Header summary card — total karyawan, checked-in, late, absent, dll.

| Parameter        | Tipe   | Default       | Wajib |
|------------------|--------|---------------|-------|
| `p_date`         | DATE   | `CURRENT_DATE`| Tidak |
| `p_branch_id`    | UUID   | NULL          | Tidak |
| `p_department_id`| UUID   | NULL          | Tidak |

**Response fields:**
```
date, total_employees_today, checked_in_count, not_checked_in_count,
late_count, overtime_count, absent_count, leave_count, sick_count, flagged_count
```

---

## 6.2 `get_admin_attendance_logs`

**Kegunaan:** Tabel/list absensi harian.

| Parameter         | Tipe    | Default       |
|-------------------|---------|---------------|
| `p_date`          | DATE    | `CURRENT_DATE`|
| `p_branch_id`     | UUID    | NULL          |
| `p_department_id` | UUID    | NULL          |
| `p_status`        | TEXT    | NULL          |
| `p_flagged_only`  | BOOLEAN | FALSE         |
| `p_search`        | TEXT    | NULL (nama/NIK)|
| `p_limit`         | INTEGER | 50            |
| `p_offset`        | INTEGER | 0             |

**Response fields (per row):**
```
attendance_id, employee_id, employee_name, employee_nik,
department_name, branch_name,
shift_name, shift_start_time, shift_end_time,
date, clock_in_at, clock_out_at,
final_status, system_status, is_overridden,
late_minutes, overtime_minutes, work_duration_minutes,
has_fraud_flag, flag_count,
total_rows   ← untuk pagination
```

**Notes:**
- `final_status` = `override_status` jika `is_overridden`, else `system_status`
- `p_status` filter menggunakan `final_status`
- `total_rows` adalah total semua baris tanpa LIMIT (untuk pagination)

---

## 6.3 `get_admin_attendance_detail`

**Kegunaan:** Modal / halaman detail satu attendance record.

| Parameter         | Tipe | Wajib |
|-------------------|------|-------|
| `p_attendance_id` | UUID | Ya    |

**Response:** JSONB dengan struktur:
```jsonc
{
  "employee":  { id, full_name, nik, department, branch, position },
  "schedule":  { shift_id, shift_name, start_time, end_time, grace_period_minutes, require_face, date },
  "attendance": {
    id, clock_in_at, clock_out_at,
    system_status, override_status, is_overridden,
    override_reason, overridden_by, overridden_at,
    final_status,
    late_minutes, overtime_minutes, work_duration_minutes,
    has_fraud_flag, flag_count
  },
  "events": [
    { id, event_type, captured_at, latitude, longitude, photo_url,
      device_id, device_platform, verification_status,
      face_match_score, liveness_score, biometric_provider, biometric_message,
      actor_id, actor_role, notes }
  ],
  "fraud_checks": [
    { id, check_type, result, details, checked_at }
  ],
  "override_history": [
    { id, action, previous_status, new_status, reason, performed_by, performed_at }
  ]
}
```

---

## 6.4 `get_monthly_attendance_summary`

**Kegunaan:** Laporan bulanan per employee (HR & payroll).

| Parameter         | Tipe    | Wajib |
|-------------------|---------|-------|
| `p_year`          | INTEGER | Ya    |
| `p_month`         | INTEGER | Ya    |
| `p_branch_id`     | UUID    | Tidak |
| `p_department_id` | UUID    | Tidak |
| `p_employee_id`   | UUID    | Tidak |

**Response fields (per row):**
```
employee_id, employee_name, employee_nik, department_name, branch_name,
year, month,
total_scheduled_days,
total_present, total_late, total_absent, total_leave, total_sick, total_overtime,
total_late_minutes, total_overtime_minutes, total_work_minutes
```

---

## 6.5 `get_attendance_fraud_flags`

**Kegunaan:** Halaman monitoring fraud / red flags.

| Parameter         | Tipe    | Default         |
|-------------------|---------|-----------------|
| `p_date_from`     | DATE    | `today - 7`     |
| `p_date_to`       | DATE    | `today`         |
| `p_branch_id`     | UUID    | NULL            |
| `p_department_id` | UUID    | NULL            |
| `p_check_type`    | TEXT    | NULL            |
| `p_result`        | TEXT    | `'failed'`      |
| `p_limit`         | INTEGER | 50              |
| `p_offset`        | INTEGER | 0               |

**`p_check_type` values:**
`location_mismatch`, `face_not_match`, `camera_failed`, `abnormal_time`,
`device_untrusted`, `missing_checkout`, `duplicate_checkin`, `outside_schedule_window`

**Response fields (per row):**
```
attendance_id, employee_id, employee_name, branch_name, department_name,
date, final_status, clock_in_at, flag_count,
checks: [{ check_type, result, details }],
total_rows
```

---

## 6.6 `admin_override_attendance` & `revert_attendance_override`

**Kegunaan:** Admin override status absensi.

### Override
```ts
const { data, error } = await supabase.rpc('admin_override_attendance', {
  p_attendance_id: '<uuid>',
  p_new_status:    'present',  // atau: late|absent|overtime|leave|sick|manual_adjustment
  p_reason:        'Verifikasi manual dengan HRD'
})
```

**Response:**
```jsonc
{
  "success": true,
  "attendance_id": "...",
  "previous_status": "absent",
  "new_status": "present",
  "audit_id": "...",
  "event_id": "...",
  "overridden_by": "...",
  "overridden_at": "2026-05-13T10:00:00Z"
}
```

### Revert
```ts
const { data, error } = await supabase.rpc('revert_attendance_override', {
  p_attendance_id: '<uuid>',
  p_reason:        'Reversi setelah pengecekan ulang'
})
```

---

## Sign-off Checklist

| Contract                           | Backend | Frontend | HR/Ops |
|------------------------------------|---------|----------|--------|
| `get_admin_attendance_overview`    | [ ]     | [ ]      | [ ]    |
| `get_admin_attendance_logs`        | [ ]     | [ ]      | [ ]    |
| `get_admin_attendance_detail`      | [ ]     | [ ]      | [ ]    |
| `get_monthly_attendance_summary`   | [ ]     | [ ]      | [ ]    |
| `get_attendance_fraud_flags`       | [ ]     | [ ]      | [ ]    |
| `admin_override_attendance`        | [ ]     | [ ]      |        |
