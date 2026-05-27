# Phase Priority

## Phase 1 - Must Have

- [ ] Task 1: Business Rules
- [ ] Task 2: Status Model
- [ ] Task 6: Dashboard Contracts

## Phase 2 - Important

- [ ] Task 3: Event Model
- [ ] Task 4: Fraud Rules
- [ ] Task 5: Override Rules
- [ ] Task 8: Audit Log Spec

## Phase 3 - Security

- [ ] Task 7: RLS Policies
- [ ] Task 9: Final Sign-off

## Recommended Execution Order

1. Freeze business rules, status model, and dashboard contracts.
2. Finalize event, fraud, override, and audit log contracts.
3. Review Supabase schema against RLS assumptions.
4. Apply RLS policies in staging.
5. Run RLS test plan.
6. Enable RLS table by table in production after sign-off.

