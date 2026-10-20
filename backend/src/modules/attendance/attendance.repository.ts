import { assertNoDbError, expectSingle } from "../../lib/db";
import { supabaseAdmin } from "../../lib/supabase";
import { readAllPages } from "../../lib/read-all";
const db = supabaseAdmin as any;
export class AttendanceRepository {
    async ensureClassSession(classId: number, date: string) {
        return expectSingle<number>(db.rpc("ensure_collaborative_class_session", { p_class_id: classId, p_date: date }), "No se pudo crear la sesión de clase.");
    }
    async findClassSessionById(institutionId: number, classId: number, classSessionId: number) {
        return expectSingle<Record<string, unknown>>(db
            .from("class_sessions")
            .select("id, group_id, date")
            .eq("id", classSessionId)
            .eq("institution_id", institutionId)
            .eq("class_id", classId)
            .single(), "Sesión de clase no encontrada.");
    }
    async findSessionOfClassDate(institutionId: number, classId: number, date: string) {
        const { data, error } = await db
            .from("class_sessions")
            .select("id, group_id, date")
            .eq("institution_id", institutionId)
            .eq("class_id", classId)
            .eq("date", date)
            .order("id")
            .limit(1);
        assertNoDbError(error);
        return ((data ?? [])[0] ?? null) as Record<string, unknown> | null;
    }
    async marksOfSession(institutionId: number, sessionId: number) {
        return readAllPages<Record<string, unknown>>((from, to) => db
            .from("attendances")
            .select("id, uuid, student_id, attendance_status_id, notes, recorded_at, version")
            .eq("institution_id", institutionId)
            .eq("class_session_id", sessionId).order("id").range(from, to));
    }
    async classLabel(institutionId: number, classId: number) {
        const { data, error } = await db
            .from("classes")
            .select("id, group_id, academic_year_id, subjects(name), groups(name)")
            .eq("institution_id", institutionId)
            .eq("id", classId)
            .maybeSingle();
        assertNoDbError(error);
        return data as Record<string, any> | null;
    }
    async statuses() {
        const { data, error } = await db
            .from("catalog_attendance_statuses")
            .select("id, name, code, counts_as_absent, color")
            .eq("active", true)
            .order("id");
        assertNoDbError(error);
        return (data ?? []) as Array<Record<string, unknown>>;
    }
    async sessionsInRange(institutionId: number, from: string, to: string, groupId?: number) {
        return readAllPages<Record<string, unknown>>((start, end) => {
            let query = db
                .from("class_sessions")
                .select("id, class_id, group_id, date, topic, classes(subjects(name))")
                .eq("institution_id", institutionId)
                .gte("date", from)
                .lte("date", to)
                .order("date", { ascending: false }).order("id");
            if (groupId != null)
                query = query.eq("group_id", groupId);
            return query.range(start, end);
        });
    }
    async marksOfSessions(institutionId: number, sessionIds: number[]) {
        const rows: Array<Record<string, unknown>> = [];
        for (let i = 0; i < sessionIds.length; i += 150) {
            rows.push(...await readAllPages<Record<string, unknown>>((from, to) => db
                .from("attendances")
                .select("class_session_id, student_id, attendance_status_id")
                .eq("institution_id", institutionId)
                .in("class_session_id", sessionIds.slice(i, i + 150))
                .order("id").range(from, to)));
        }
        return rows;
    }
    async groupNames(institutionId: number, groupId?: number) {
        let query = db.from("groups").select("id, name").eq("institution_id", institutionId).eq("active", true);
        if (groupId != null)
            query = query.eq("id", groupId);
        const { data, error } = await query;
        assertNoDbError(error);
        return (data ?? []) as Array<Record<string, unknown>>;
    }
    async enrolledStudents(institutionId: number, groupId: number, academicYearId?: number | null) {
        const rows = await readAllPages<Record<string, unknown>>((from, to) => {
            let query = db
                .from("enrollments")
                .select("student_id, students!inner(id, active, persons(first_name, last_name)), catalog_enrollment_statuses!inner(code)")
                .eq("institution_id", institutionId)
                .eq("group_id", groupId)
                .eq("catalog_enrollment_statuses.code", "ACT")
                .eq("students.active", true);
            if (academicYearId != null)
                query = query.eq("academic_year_id", academicYearId);
            return query.order("id", { ascending: false }).range(from, to);
        });
        return [...new Map(rows.map(row => [Number(row.student_id), row])).values()];
    }
}
export const attendanceRepository = new AttendanceRepository();
