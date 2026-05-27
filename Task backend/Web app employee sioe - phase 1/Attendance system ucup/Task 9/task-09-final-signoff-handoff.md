# Task 9 - Final Sign-off & Handoff

## Goal

Memastikan semua rules dan contracts sudah jelas sebelum Backend Support dan Frontend mulai implementasi.

## Stakeholder Review

Review dengan HR dan Operations:

- [ ] Attendance business rules sudah sesuai operasional.
- [ ] Status model sudah disetujui.
- [ ] Fraud rules sudah realistis dan tidak terlalu agresif.
- [ ] Override rules sudah punya approval dan audit trail.
- [ ] Dashboard contracts sudah sesuai kebutuhan reporting.
- [ ] RLS tenant isolation sudah disetujui.
- [ ] Audit log retention sudah sesuai compliance internal.

## Backend Support Sign-off

Backend Support harus menerima:

- [ ] Final schema contract dari Supabase.
- [ ] RLS policy design.
- [ ] Required RPC list untuk status override dan audit-safe writes.
- [ ] Audit log action list.
- [ ] Audit metadata schema.
- [ ] Fraud check write contract.
- [ ] Attendance status calculation contract.
- [ ] RLS staging test result.

Recommended Backend Support tasks:

- Implement RPC `override_attendance_status(...)`.
- Implement attendance status calculation job/function.
- Implement absent generation job.
- Implement audit log writer utility or database trigger.
- Implement fraud check writer.
- Add integration tests for RLS and audit log writes.

## Frontend Sign-off

Frontend harus menerima:

- [ ] Role access matrix.
- [ ] Dashboard API/view contracts.
- [ ] Attendance event create contract.
- [ ] Leave request contract.
- [ ] Override status contract.
- [ ] Error cases for RLS denied access.
- [ ] Fraud visibility rules.

Recommended Frontend tasks:

- Employee attendance page reads only self attendance.
- Employee check-in/check-out creates attendance event only.
- Admin/HR dashboard reads same-tenant summary.
- Admin/HR override flow requires reason.
- Fraud checks page visible only to admin/HR/super_admin.
- Audit log page visible only to admin/HR/super_admin.

## Kickoff Meeting

Recommended agenda:

1. Confirm schema assumptions against existing Supabase schema.
2. Confirm role names and permission boundaries.
3. Confirm attendance status lifecycle.
4. Confirm override approval and audit requirements.
5. Confirm RLS staging test process.
6. Confirm frontend API contracts.
7. Confirm release and rollback plan.

Recommended attendees:

- HR stakeholder
- Operations stakeholder
- Backend support
- Frontend engineer
- QA engineer
- Product owner

## Communication Channel

Setup channel for technical questions:

- Channel name: `attendance-system-dev`
- Purpose: schema decisions, RLS questions, API contract clarifications, QA findings.
- Required pinned docs:
  - Task 7 RLS Security Policy Design
  - Task 8 Audit Log Specification
  - Dashboard Contracts
  - Status Model
  - Final Architecture Decisions

## Final Architecture Decisions

| Area | Decision |
| --- | --- |
| Main backend | Supabase |
| Tenant isolation | RLS with `tenant_id` boundary |
| Auth identity | `auth.uid()` maps to `users.id` |
| App role source | `users.role` |
| Employee self-access | `users.employee_id` maps to `employees.id` |
| Attendance write flow | Employee creates immutable `attendance_events` |
| Status calculation | Backend/service computes `attendance_records.status` |
| Override flow | Admin/HR/Super Admin uses trusted RPC |
| Fraud checks | Backend/service writes `fraud_checks` |
| Audit log | Append-only `audit_logs` with `metadata jsonb` |
| Production RLS enablement | Enable only after staging tests pass |

## Sign-off Checklist

- [ ] HR approved rules.
- [ ] Operations approved rules.
- [ ] Backend Support accepted implementation tasks.
- [ ] Frontend accepted integration contract.
- [ ] QA accepted RLS and audit test plan.
- [ ] Kickoff meeting scheduled.
- [ ] Technical communication channel created.
- [ ] Final architecture decisions documented.

