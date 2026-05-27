// =============================================================================
// TypeScript Types — employee_mobile_context RPC
// Project  : Absensi Bianore (Mobile App)
// =============================================================================

// --------------------------------------------------------------------------
// Enums — harus sinkron dengan PostgreSQL ENUM di migration 001
// --------------------------------------------------------------------------
export type EmploymentStatus = 'full-time' | 'part-time' | 'contract' | 'intern';

export type ActiveStatus = 'active' | 'on-leave' | 'inactive' | 'resigned' | 'terminated';

// --------------------------------------------------------------------------
// Sub-types dalam response
// --------------------------------------------------------------------------
export interface EmployeeDepartment {
    id: string;       // UUID
    name: string;     // Contoh: "Engineering"
}

export interface EmployeePosition {
    id: string;       // UUID
    name: string;     // Contoh: "Software Engineer"
}

export interface EmployeeBranch {
    id: string;       // UUID
    name: string;     // Contoh: "HQ - Jakarta Pusat"
    address: string | null;
    city: string | null;
}

export interface EmployeeManager {
    id: string;       // UUID
    code: string;     // Contoh: "BNR-0003"
    name: string;     // Contoh: "Siti Handayani"
    email: string;
    photo: string | null;
}

// --------------------------------------------------------------------------
// Response utama dari RPC employee_mobile_context()
// --------------------------------------------------------------------------
export interface EmployeeMobileContext {
    // Identitas
    employee_id:    string;             // UUID
    employee_code:  string;             // Contoh: "BNR-0001"
    employee_name:  string;
    email:          string;
    phone:          string | null;
    profile_photo:  string | null;      // URL foto profil

    // Penempatan
    department:     EmployeeDepartment;
    position:       EmployeePosition;
    branch:         EmployeeBranch | null;  // null = tidak ada cabang
    manager:        EmployeeManager | null; // null = top-level, tidak ada atasan

    // Tenant / Perusahaan
    tenant_id:      string;             // UUID
    tenant_name:    string;
    tenant_logo:    string | null;

    // Status kepegawaian
    employment_status: EmploymentStatus;
    active_status:     ActiveStatus;

    // Tanggal
    join_date:      string;             // ISO date: "2023-01-15"
    contract_end:   string | null;      // null = karyawan permanen

    // Metadata
    fetched_at:     string;             // ISO timestamp
}

// --------------------------------------------------------------------------
// Error codes yang dikembalikan RPC (dalam field message dari Supabase)
// --------------------------------------------------------------------------
export type EmployeeMobileContextErrorCode =
    | 'UNAUTHENTICATED'      // User belum login
    | 'EMPLOYEE_NOT_FOUND'   // Tidak ada employee yang terhubung ke akun ini
    | 'EMPLOYEE_INACTIVE'    // is_active = false (dinonaktifkan admin)
    | 'EMPLOYEE_RESIGNED'    // active_status = 'resigned'
    | 'EMPLOYEE_TERMINATED'  // active_status = 'terminated'
    | 'INTERNAL_ERROR';      // Error sistem

// --------------------------------------------------------------------------
// Helper: parse error code dari Supabase error message
// --------------------------------------------------------------------------
export function parseEmployeeContextError(message: string): EmployeeMobileContextErrorCode {
    if (message.includes('UNAUTHENTICATED'))     return 'UNAUTHENTICATED';
    if (message.includes('EMPLOYEE_NOT_FOUND'))  return 'EMPLOYEE_NOT_FOUND';
    if (message.includes('EMPLOYEE_INACTIVE'))   return 'EMPLOYEE_INACTIVE';
    if (message.includes('EMPLOYEE_RESIGNED'))   return 'EMPLOYEE_RESIGNED';
    if (message.includes('EMPLOYEE_TERMINATED')) return 'EMPLOYEE_TERMINATED';
    return 'INTERNAL_ERROR';
}

// --------------------------------------------------------------------------
// Helper: cek apakah karyawan boleh melakukan absensi
// (on-leave bisa buka app tapi tidak bisa check-in)
// --------------------------------------------------------------------------
export function canCheckIn(ctx: EmployeeMobileContext): boolean {
    return ctx.active_status === 'active';
}

// --------------------------------------------------------------------------
// Contoh penggunaan dengan Supabase JS Client
// --------------------------------------------------------------------------
//
// import { createClient } from '@supabase/supabase-js'
// import type { EmployeeMobileContext } from './types/employee_mobile_context'
//
// const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
//
// async function getEmployeeContext(): Promise<EmployeeMobileContext> {
//     const { data, error } = await supabase
//         .rpc('employee_mobile_context')
//
//     if (error) {
//         const code = parseEmployeeContextError(error.message)
//         switch (code) {
//             case 'EMPLOYEE_INACTIVE':
//                 throw new Error('Akun Anda telah dinonaktifkan. Hubungi HR.')
//             case 'EMPLOYEE_RESIGNED':
//             case 'EMPLOYEE_TERMINATED':
//                 throw new Error('Akun Anda tidak dapat mengakses aplikasi ini.')
//             case 'EMPLOYEE_NOT_FOUND':
//                 throw new Error('Data karyawan tidak ditemukan.')
//             default:
//                 throw new Error('Terjadi kesalahan. Silakan coba lagi.')
//         }
//     }
//
//     return data as EmployeeMobileContext
// }
