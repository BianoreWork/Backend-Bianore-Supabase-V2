// =============================================================================
// TypeScript Types — Schedule Backend
// Project  : Absensi Bianore (Mobile App)
// =============================================================================

export type CalendarAttendanceStatus =
    | 'present'
    | 'late'
    | 'absent'
    | 'leave'
    | 'sick_leave'
    | 'no_schedule'
    | 'no_attendance'     // hari mendatang, belum ada data

export type CalendarMarker =
    | 'present'
    | 'absent'
    | 'leave'
    | 'sick'
    | 'today'
    | 'scheduled'
    | 'none';

export type LeaveType =
    | 'annual_leave'
    | 'sick_leave'
    | 'emergency_leave'
    | 'unpaid_leave'
    | 'maternity_leave'
    | 'other';

export type LeaveStatus = 'pending' | 'approved' | 'rejected' | 'cancelled';

// --------------------------------------------------------------------------
// Schedule Calendar
// --------------------------------------------------------------------------
export interface CalendarMonthlySummary {
    present_count:    number;
    late_count:       number;
    absent_count:     number;
    leave_count:      number;
    sick_leave_count: number;
    overtime_hours:   number;
}

export interface CalendarDay {
    date:        string;            // "2026-05-12"
    day_name:    string;            // "Monday   "
    day_number:  number;            // 12
    is_today:    boolean;
    is_weekend:  boolean;

    has_schedule:   boolean;
    schedule_id:    string | null;
    shift_name:     string | null;
    start_time:     string | null;  // "08:00"
    end_time:       string | null;  // "17:00"

    attendance_status: CalendarAttendanceStatus;
    checkin_time:      string | null;
    checkout_time:     string | null;
    late_minutes:      number;
    work_duration_minutes: number;

    marker: CalendarMarker;
}

export interface EmployeeScheduleCalendar {
    employee_id:  string;
    month:        number;
    year:         number;
    month_label:  string;           // "May       2026"
    monthly_summary: CalendarMonthlySummary;
    days:         CalendarDay[];
    fetched_at:   string;
}

// --------------------------------------------------------------------------
// Schedule Day Detail
// --------------------------------------------------------------------------
export interface ScheduleDetail {
    has_schedule:   boolean;
    status?:        string;         // 'active' | 'cancelled' | 'no_schedule'
    schedule_id?:   string;
    shift_name?:    string;
    start_time?:    string;
    end_time?:      string;
    break_minutes?: number;
    total_work_hours?: number;
    late_threshold_minutes?:      number;
    very_late_threshold_minutes?: number;
    overtime_threshold_minutes?:  number;
    branch?: {
        id:            string;
        name:          string;
        address:       string | null;
        city:          string | null;
        latitude:      number;
        longitude:     number;
        radius_meters: number;
    } | null;
}

export interface AttendanceCheckDetail {
    time:            string;
    latitude:        number;
    longitude:       number;
    distance_meters: number;
    location_name:   string | null;
    selfie_url:      string;
    gps_verified:    boolean;
    selfie_verified: boolean;
}

export interface AttendanceDetail {
    has_record:            boolean;
    status:                string;
    checkin:               AttendanceCheckDetail | null;
    checkout:              AttendanceCheckDetail | null;
    late_minutes?:         number;
    work_duration_minutes?: number;
    overtime_minutes?:     number;
}

export interface LeaveImpact {
    leave_id:        string;
    leave_type:      LeaveType;
    leave_status:    LeaveStatus;
    start_date:      string;
    end_date:        string;
    total_days:      number;
    reason:          string | null;
    attachment_url:  string | null;
    approver_name:   string | null;
    approved_at:     string | null;
    approver_notes:  string | null;
}

export interface EmployeeScheduleDayDetail {
    date:         string;
    day_name:     string;
    is_today:     boolean;
    schedule:     ScheduleDetail;
    attendance:   AttendanceDetail;
    leave_impact: LeaveImpact | null;
    fetched_at:   string;
}

// --------------------------------------------------------------------------
// Error codes
// --------------------------------------------------------------------------
export type ScheduleErrorCode =
    | 'UNAUTHENTICATED'
    | 'EMPLOYEE_NOT_FOUND'
    | 'EMPLOYEE_INACTIVE'
    | 'FORBIDDEN'
    | 'INVALID_MONTH'
    | 'INVALID_YEAR'
    | 'INTERNAL_ERROR';

// --------------------------------------------------------------------------
// Contoh penggunaan (Supabase JS)
// --------------------------------------------------------------------------
//
// const { data, error } = await supabase.rpc('employee_schedule_calendar', {
//     p_employee_id: employeeId,
//     p_month:       5,
//     p_year:        2026,
// })
//
// const { data, error } = await supabase.rpc('employee_schedule_day_detail', {
//     p_employee_id: employeeId,
//     p_work_date:   '2026-05-12',
// })
