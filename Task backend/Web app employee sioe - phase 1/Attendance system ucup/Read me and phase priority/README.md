# Attendance Backend Handoff

Dokumen ini berisi hasil backend untuk attendance system yang belum ada di Supabase, dipisahkan per task dan lokasi file.

## Output

| Task | File |
| --- | --- |
| Task 7 - RLS Security Policy Design | `docs/task-07-rls-security-policy-design.md` |
| Task 7 - SQL draft RLS policies | `supabase/policies/task_07_rls_policies.sql` |
| Task 7 - RLS test plan | `supabase/tests/task_07_rls_test_plan.sql` |
| Task 8 - Audit Log Specification | `docs/task-08-audit-log-specification.md` |
| Task 9 - Final Sign-off & Handoff | `docs/task-09-final-signoff-handoff.md` |
| Phase Priority | `docs/phase-priority.md` |

## Important Notes

- SQL RLS di folder `supabase/policies/` masih draft review. Jangan langsung enable di production sebelum semua test RLS lulus.
- Policy memakai asumsi umum schema Supabase attendance. Cocokkan nama kolom dengan schema Supabase existing sebelum apply.
- RLS tidak bisa membatasi update per kolom secara sempurna. Untuk field sensitif seperti `status`, `tenant_id`, `employee_id`, dan `role`, gunakan column privileges, trigger validation, atau RPC backend.

## Assumed Core Columns

Policy dan dokumen memakai asumsi minimal berikut:

- Semua tabel tenant-scoped punya `tenant_id uuid`.
- `users` punya `id uuid`, `tenant_id uuid`, `role text`, `employee_id uuid`.
- `employees` punya `id uuid`, `tenant_id uuid`, `user_id uuid`.
- Attendance-related tables punya `employee_id uuid` dan `tenant_id uuid`.
- `attendance_records` punya `status`, `override_status`, `override_reason`, `overridden_by`.
- `audit_logs` punya `tenant_id uuid`, `actor_user_id uuid`, `action text`, `metadata jsonb`, `created_at timestamptz`.

