-- =============================================================
-- Task 5: Admin Override — Flow, Audit Log, RPC
-- =============================================================

-- ── 1. Audit log table ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS attendance_override_audit (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  attendance_id   UUID NOT NULL REFERENCES attendance_records(id) ON DELETE CASCADE,
  action          TEXT NOT NULL DEFAULT 'override',  -- 'override' | 'revert'
  previous_status TEXT,
  new_status      TEXT NOT NULL,
  reason          TEXT NOT NULL,
  performed_by    UUID NOT NULL REFERENCES auth.users(id),
  performed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  metadata        JSONB  -- extra context jika perlu
);

COMMENT ON TABLE attendance_override_audit IS
  'Immutable audit trail untuk setiap admin override. Tidak boleh di-UPDATE atau di-DELETE.';

-- Prevent update/delete pada audit log
CREATE OR REPLACE FUNCTION trg_protect_audit_log()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'attendance_override_audit adalah immutable audit log.';
END;
$$;

DROP TRIGGER IF EXISTS trg_no_mutate_audit ON attendance_override_audit;
CREATE TRIGGER trg_no_mutate_audit
  BEFORE UPDATE OR DELETE ON attendance_override_audit
  FOR EACH ROW EXECUTE FUNCTION trg_protect_audit_log();

CREATE INDEX IF NOT EXISTS idx_audit_attendance_id  ON attendance_override_audit(attendance_id);
CREATE INDEX IF NOT EXISTS idx_audit_performed_by   ON attendance_override_audit(performed_by);
CREATE INDEX IF NOT EXISTS idx_audit_performed_at   ON attendance_override_audit(performed_at DESC);

-- ── 2. RPC: admin_override_attendance ────────────────────────
--
-- Flow:
--   Admin buka detail → pilih status baru → isi reason → confirm
--   → RPC ini dipanggil → update attendance_records →
--   → insert audit log → insert attendance_event (admin_override)
--
-- Dipanggil dari: Frontend admin panel / Supabase Edge Function
--
CREATE OR REPLACE FUNCTION admin_override_attendance(
  p_attendance_id  UUID,
  p_new_status     attendance_override_status,
  p_reason         TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_caller_id    UUID;
  v_caller_role  TEXT;
  v_ar           attendance_records%ROWTYPE;
  v_prev_status  TEXT;
  v_audit_id     UUID;
  v_event_id     UUID;
BEGIN
  -- ── Auth check ───────────────────────────────────────────────
  v_caller_id := auth.uid();

  SELECT role INTO v_caller_role
  FROM employees
  WHERE auth_user_id = v_caller_id;

  IF v_caller_role NOT IN ('admin', 'hr', 'super_admin') THEN
    RAISE EXCEPTION 'Akses ditolak: hanya admin, hr, atau super_admin yang dapat melakukan override.';
  END IF;

  -- ── Validasi input ───────────────────────────────────────────
  IF p_reason IS NULL OR TRIM(p_reason) = '' THEN
    RAISE EXCEPTION 'Override reason wajib diisi.';
  END IF;

  IF p_attendance_id IS NULL THEN
    RAISE EXCEPTION 'attendance_id tidak boleh NULL.';
  END IF;

  -- ── Ambil record ─────────────────────────────────────────────
  SELECT * INTO v_ar FROM attendance_records WHERE id = p_attendance_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Attendance record tidak ditemukan: %', p_attendance_id;
  END IF;

  -- Simpan previous status untuk audit
  v_prev_status := CASE
    WHEN v_ar.is_overridden THEN v_ar.override_status::TEXT
    ELSE v_ar.system_status::TEXT
  END;

  -- ── Update attendance_records ─────────────────────────────────
  UPDATE attendance_records
  SET
    is_overridden   = TRUE,
    override_status = p_new_status,
    override_reason = TRIM(p_reason),
    overridden_by   = v_caller_id,
    overridden_at   = NOW(),
    updated_at      = NOW()
  WHERE id = p_attendance_id;

  -- ── Insert audit log ──────────────────────────────────────────
  INSERT INTO attendance_override_audit
    (attendance_id, action, previous_status, new_status, reason, performed_by)
  VALUES
    (p_attendance_id, 'override', v_prev_status, p_new_status::TEXT, TRIM(p_reason), v_caller_id)
  RETURNING id INTO v_audit_id;

  -- ── Insert attendance_event (admin_override) ───────────────────
  INSERT INTO attendance_events
    (attendance_id, event_type, captured_at, verification_status, actor_id, actor_role, notes)
  VALUES
    (p_attendance_id, 'admin_override', NOW(), 'skipped', v_caller_id, v_caller_role, TRIM(p_reason))
  RETURNING id INTO v_event_id;

  RETURN jsonb_build_object(
    'success',        TRUE,
    'attendance_id',  p_attendance_id,
    'previous_status', v_prev_status,
    'new_status',     p_new_status,
    'audit_id',       v_audit_id,
    'event_id',       v_event_id,
    'overridden_by',  v_caller_id,
    'overridden_at',  NOW()
  );
END;
$$;

COMMENT ON FUNCTION admin_override_attendance IS
  'Override system_status attendance. Hanya admin/hr/super_admin. Membuat audit log + attendance_event otomatis.';

-- ── 3. RPC: revert_attendance_override ───────────────────────
-- Kembalikan ke system_status (hapus override)
CREATE OR REPLACE FUNCTION revert_attendance_override(
  p_attendance_id  UUID,
  p_reason         TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_caller_id    UUID;
  v_caller_role  TEXT;
  v_ar           attendance_records%ROWTYPE;
  v_prev_status  TEXT;
BEGIN
  v_caller_id := auth.uid();

  SELECT role INTO v_caller_role
  FROM employees WHERE auth_user_id = v_caller_id;

  IF v_caller_role NOT IN ('admin', 'hr', 'super_admin') THEN
    RAISE EXCEPTION 'Akses ditolak.';
  END IF;

  IF p_reason IS NULL OR TRIM(p_reason) = '' THEN
    RAISE EXCEPTION 'Reason wajib diisi untuk revert.';
  END IF;

  SELECT * INTO v_ar FROM attendance_records WHERE id = p_attendance_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Attendance record tidak ditemukan.';
  END IF;

  IF NOT v_ar.is_overridden THEN
    RAISE EXCEPTION 'Record ini belum di-override — tidak ada yang perlu di-revert.';
  END IF;

  v_prev_status := v_ar.override_status::TEXT;

  UPDATE attendance_records
  SET
    is_overridden   = FALSE,
    override_status = NULL,
    override_reason = NULL,
    overridden_by   = NULL,
    overridden_at   = NULL,
    updated_at      = NOW()
  WHERE id = p_attendance_id;

  INSERT INTO attendance_override_audit
    (attendance_id, action, previous_status, new_status, reason, performed_by)
  VALUES
    (p_attendance_id, 'revert', v_prev_status, v_ar.system_status::TEXT, TRIM(p_reason), v_caller_id);

  INSERT INTO attendance_events
    (attendance_id, event_type, captured_at, verification_status, actor_id, actor_role, notes)
  VALUES
    (p_attendance_id, 'admin_override', NOW(), 'skipped', v_caller_id, v_caller_role,
     'REVERT: ' || TRIM(p_reason));

  RETURN jsonb_build_object(
    'success',         TRUE,
    'attendance_id',   p_attendance_id,
    'reverted_from',   v_prev_status,
    'restored_status', v_ar.system_status
  );
END;
$$;

-- ── 4. RLS ────────────────────────────────────────────────────
ALTER TABLE attendance_override_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rls_audit_admin_select ON attendance_override_audit;
CREATE POLICY rls_audit_admin_select ON attendance_override_audit
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM employees
      WHERE auth_user_id = auth.uid()
        AND role IN ('admin', 'hr', 'super_admin')
    )
  );
