# Task 7 - RLS Security Policy Design

## Goal

Mendesain Row Level Security policies untuk tenant isolation, role-based access, dan employee self-access pada Supabase.

## Role Definitions

| Role | Scope | Allowed Access |
| --- | --- | --- |
| employee | Own employee profile only | Read own attendance, create own attendance events, read own leave requests |
| admin | Same tenant | Read/manage attendance operation data, view fraud checks, override attendance status |
| hr | Same tenant | Same as admin for attendance and employee operation data |
| super_admin | Same tenant | Manage tenant-level modules, master data, policies, users, branches, shifts |

## Global RLS Rules

1. Every tenant-scoped table must filter by `tenant_id = current_tenant_id()`.
2. Employee can only access data connected to their own `employee_id`.
3. Employee can create attendance events, but cannot update attendance records or override status.
4. Admin and HR can read all attendance data inside the same tenant.
5. Admin and HR can override status only through a trusted RPC or backend service flow.
6. Super Admin can manage all modules within the same tenant, but must not cross tenant boundary.
7. Audit logs must be append-only for application users.
8. RLS must be tested before enabling on production tables.

## Employee Access Rules

Employee is allowed to:

- Read own row in `users`.
- Read own row in `employees`.
- Read own `employee_schedules`.
- Read own `attendance_records`.
- Insert own `attendance_events`.
- Read own `attendance_events`.
- Read own `fraud_checks` only if product decision allows employee visibility. Default recommendation: employee cannot read fraud checks.
- Create/read own `leave_requests`.
- Read public tenant master data needed by frontend, such as active `branches`, `shifts`, and attendance policy summary.

Employee is not allowed to:

- Read other employee attendance, schedule, leave, fraud, or profile data.
- Update `attendance_records.status`.
- Override attendance status.
- Update/delete attendance events after creation.
- Change `tenant_id`, `employee_id`, `role`, or policy-level fields.

## Admin / HR Access Rules

Admin and HR are allowed to:

- Read all attendance records inside the same tenant.
- Read attendance events inside the same tenant.
- Read employee schedules inside the same tenant.
- Read fraud checks inside the same tenant.
- View attendance dashboard summary inside the same tenant.
- Override attendance status through an auditable flow.
- Manage employee schedules and leave requests inside the same tenant.

Admin and HR are not allowed to:

- Access another tenant.
- Directly delete audit logs.
- Change their own role or tenant assignment through public client access.

## Super Admin Access Rules

Super Admin is allowed to:

- Manage tenant-level users, employees, branches, shifts, schedules, attendance policies, and operational settings.
- Access all modules inside their own tenant.
- Read audit logs inside tenant.

Super Admin is not allowed to:

- Access data from other tenants.
- Delete audit logs from public client.
- Bypass audit trail for sensitive changes.

## Table Policy Design

### users

Policies:

- Employee can select own `users` row.
- Admin/HR can select users in same tenant.
- Super Admin can select, insert, update, and soft-delete users in same tenant.

Additional guard:

- Restrict updates to `role`, `tenant_id`, and `employee_id` using column privileges or backend RPC.

### employees

Policies:

- Employee can select own employee row.
- Admin/HR can select and manage employees in same tenant.
- Super Admin can manage employees in same tenant.

### employee_schedules

Policies:

- Employee can read own schedules.
- Admin/HR can read and manage schedules in same tenant.
- Super Admin can manage schedules in same tenant.

### attendance_records

Policies:

- Employee can read own attendance records.
- Employee cannot insert/update/delete attendance records directly.
- Admin/HR can read attendance records in same tenant.
- Admin/HR can update status through trusted backend/RPC only.
- Super Admin can read and manage records in same tenant.

Recommended implementation:

- Client inserts into `attendance_events`.
- Backend function calculates/updates `attendance_records`.
- Override status is done through RPC `override_attendance_status(...)`, which writes `audit_logs`.

### attendance_events

Policies:

- Employee can insert own event when `employee_id = current_employee_id()`.
- Employee can read own events.
- Employee cannot update/delete events.
- Admin/HR can read all tenant events.
- Admin/HR and Super Admin should not manually insert events except through backend repair/import flows.

### fraud_checks

Policies:

- Employee cannot read fraud checks by default.
- Admin/HR can read fraud checks in same tenant.
- Backend service role can insert fraud checks.
- Super Admin can read fraud checks in same tenant.

### leave_requests

Policies:

- Employee can create and read own leave requests.
- Employee can update own pending request only for editable fields.
- Admin/HR can read and approve/reject leave requests in same tenant.
- Super Admin can manage leave requests in same tenant.

Additional guard:

- Prevent employee from setting approval fields using column privileges, trigger validation, or RPC.

### branches

Policies:

- Employee can read active branches in same tenant if needed by frontend.
- Admin/HR can read branches in same tenant.
- Super Admin can manage branches in same tenant.

### shifts

Policies:

- Employee can read active shifts in same tenant if needed by frontend.
- Admin/HR can read and manage shifts in same tenant.
- Super Admin can manage shifts in same tenant.

### attendance_policies

Policies:

- Employee can read active attendance policy summary in same tenant.
- Admin/HR can read policies in same tenant.
- Super Admin can manage policies in same tenant.

### audit_logs

Policies:

- Employee cannot read audit logs.
- Admin/HR can read audit logs in same tenant.
- Super Admin can read audit logs in same tenant.
- Application users cannot update/delete audit logs.
- Insert audit logs only via backend service role, triggers, or trusted RPC.

## Production Safety Checklist

- [ ] Confirm all tenant-scoped tables have `tenant_id`.
- [ ] Confirm `users.id` matches `auth.users.id`.
- [ ] Confirm `users.employee_id` maps to `employees.id`.
- [ ] Confirm every policy references same tenant boundary.
- [ ] Create policies before enabling RLS in production.
- [ ] Run RLS test plan in staging.
- [ ] Test employee cannot access another employee data.
- [ ] Test admin cannot access another tenant data.
- [ ] Test employee cannot update attendance status.
- [ ] Test audit logs are append-only.
- [ ] Enable RLS table by table after test passes.

## Deliverables

- SQL draft: `supabase/policies/task_07_rls_policies.sql`
- Test plan: `supabase/tests/task_07_rls_test_plan.sql`

