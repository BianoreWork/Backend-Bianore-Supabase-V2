// =============================================================================
// TypeScript Types — Home Backend
// Project  : Absensi Bianore (Mobile App)
// =============================================================================

export type AttendanceStatus =
    | 'not_checked_in'
    | 'checked_in'
    | 'late'
    | 'very_late'
    | 'completed'
    | 'no_schedule'
    | 'absent';

// --------------------------------------------------------------------------
// Sub-types
// --------------------------------------------------------------------------
export interface CheckInOutDetail {
    time:            string;        // "08:05:23"
    latitude:        number;
    longitude:       number;
    distance_meters: number;
    location_name:   string | null;
    selfie_url:      string;
    gps_verified:    boolean;
    selfie_verified: boolean;
}

export interface TodaySchedule {
    schedule_id:   string;
    shift_name:    string;
    start_time:    string;          // "08:00"
    end_time:      string;          // "17:00"
    break_minutes: number;
    branch: {
        id:            string;
        name:          string;
        address:       string | null;
        city:          string | null;
        latitude:      number;
        longitude:     number;
        radius_meters: number;
    } | null;
}

export interface WorkCalculation {
    late_minutes:          number;
    work_duration_minutes: number;
    overtime_minutes:      number;
}

export interface MonthlySummary {
    month:          number;
    year:           number;
    present_count:  number;
    late_count:     number;
    absent_count:   number;
    overtime_hours: number;
}

export interface RecentAttendanceItem {
    work_date:             string;          // "2026-05-11"
    day_name:              string;          // "Sunday   "
    attendance_status:     AttendanceStatus;
    checkin_time:          string | null;   // "08:00"
    checkout_time:         string | null;   // "17:05"
    late_minutes:          number;
    work_duration_minutes: number;
    overtime_minutes:      number;
}

// --------------------------------------------------------------------------
// Response utama: employee_home_summary
// --------------------------------------------------------------------------
export interface EmployeeHomeSummary {
    employee: {
        id:          string;
        code:        string;
        name:        string;
        email:       string;
        photo:       string | null;
        department:  string;
        position:    string;
        tenant_name: string;
    };

    server_date:      string;          // "2026-05-12"
    server_time:      string;          // "08:30:00"
    server_timestamp: string;          // ISO timestamp

    unread_notification_count: number;

    today_status:   AttendanceStatus;
    today_schedule: TodaySchedule | null;

    checkin:  CheckInOutDetail | null;
    checkout: CheckInOutDetail | null;

    work_calculation: WorkCalculation;
    monthly_summary:  MonthlySummary;
    recent_attendance: RecentAttendanceItem[];

    fetched_at: string;
}

// --------------------------------------------------------------------------
// Error codes
// --------------------------------------------------------------------------
export type HomeErrorCode =
    | 'UNAUTHENTICATED'
    | 'EMPLOYEE_NOT_FOUND'
    | 'EMPLOYEE_INACTIVE'
    | 'EMPLOYEE_ACCESS_REVOKED'
    | 'FORBIDDEN'
    | 'GPS_REQUIRED'
    | 'SELFIE_REQUIRED'
    | 'NO_SCHEDULE'
    | 'ALREADY_CHECKED_IN'
    | 'ALREADY_CHECKED_OUT'
    | 'NOT_CHECKED_IN'
    | 'OUT_OF_RANGE'
    | 'INTERNAL_ERROR';

export function parseHomeError(message: string): HomeErrorCode {
    const codes: HomeErrorCode[] = [
        'UNAUTHENTICATED', 'EMPLOYEE_NOT_FOUND', 'EMPLOYEE_INACTIVE',
        'EMPLOYEE_ACCESS_REVOKED', 'FORBIDDEN', 'GPS_REQUIRED',
        'SELFIE_REQUIRED', 'NO_SCHEDULE', 'ALREADY_CHECKED_IN',
        'ALREADY_CHECKED_OUT', 'NOT_CHECKED_IN', 'OUT_OF_RANGE',
    ];
    for (const code of codes) {
        if (message.includes(code)) return code;
    }
    return 'INTERNAL_ERROR';
}

// --------------------------------------------------------------------------
// Contoh penggunaan (Supabase JS)
// --------------------------------------------------------------------------
//
// const { data, error } = await supabase.rpc('employee_home_summary', {
//     p_employee_id: employeeId,
//     p_work_date:   new Date().toISOString().split('T')[0],
// })
//
// const { data, error } = await supabase.rpc('employee_check_in', {
//     p_employee_id:   employeeId,
//     p_latitude:      currentLocation.lat,
//     p_longitude:     currentLocation.lng,
//     p_selfie_url:    uploadedSelfieUrl,
//     p_location_name: 'HQ Jakarta',
// })
