import { assertNoDbError } from "../../lib/db";
import { HttpError } from "../../lib/errors";
import { supabaseAdmin } from "../../lib/supabase";
import { dateOnly } from "../../validators/common.validators";
import type { AppContext } from "../../types/app-context";
import { permissionsService } from "../../services/permissions.service";

// Dentro de una petición este cliente lleva el token del usuario: las políticas RLS limitan
// lo que un padre o alumno puede leer (solo sus hijos o él mismo).
const db = supabaseAdmin as any;

/** Lecturas para las familias (padre y alumno): hijos, asistencia y tareas de un alumno. */
export class FamilyService {
  /** Hijos vinculados al padre (o el propio alumno), con su salón. */
  async children(ctx: AppContext) {
    let studentIds: number[] = [];
    if (ctx.roles.has("parent")) {
      const parentId = await permissionsService.currentParentId(ctx);
      if (parentId == null) return { children: [] };
      const { data, error } = await db.from("parent_students").select("student_id").eq("parent_id", parentId);
      assertNoDbError(error);
      studentIds = (data ?? []).map((r: any) => Number(r.student_id));
    } else if (ctx.roles.has("student")) {
      const own = await permissionsService.currentStudentId(ctx);
      if (own != null) studentIds = [own];
    } else {
      throw new HttpError(403, "Solo padres y alumnos pueden consultar esta información.", "forbidden");
    }
    if (studentIds.length === 0) return { children: [] };

    const [{ data: students, error: e1 }, { data: enrollments, error: e2 }] = await Promise.all([
      db.from("students").select("id, active, persons(first_name, last_name)").in("id", studentIds).eq("institution_id", ctx.institutionId),
      db.from("enrollments").select("student_id, group_id, groups(name)").in("student_id", studentIds).eq("institution_id", ctx.institutionId),
    ]);
    assertNoDbError(e1);
    assertNoDbError(e2);
    const groupOf = new Map<number, any>();
    for (const e of (enrollments ?? []) as any[]) groupOf.set(Number(e.student_id), e);
    return {
      children: ((students ?? []) as any[])
        .filter((s) => s.active !== false)
        .map((s) => {
          const g = groupOf.get(Number(s.id));
          return {
            studentId: String(s.id),
            name: `${s.persons?.first_name ?? ""} ${s.persons?.last_name ?? ""}`.trim() || "Alumno",
            groupId: g ? String(g.group_id) : null,
            groupName: g?.groups?.name ?? null,
          };
        })
        .sort((a, b) => a.name.localeCompare(b.name, "es")),
    };
  }

  /** Asistencia de un alumno en un rango (por defecto, últimos 30 días). */
  async attendance(ctx: AppContext, query: Record<string, unknown>) {
    const studentId = await permissionsService.normalizeStudentId(ctx, query.studentId ?? query.student_id, "estudiante");
    const { from, to } = dateRange(query);
    const [{ data: statuses, error: e1 }, { data: rows, error: e2 }] = await Promise.all([
      db.from("catalog_attendance_statuses").select("id, name, code, counts_as_absent, color").eq("active", true).order("id"),
      db
        .from("attendances")
        .select("id, attendance_status_id, notes, class_sessions!inner(date, classes(subjects(name)))")
        .eq("institution_id", ctx.institutionId)
        .eq("student_id", studentId)
        .gte("class_sessions.date", from)
        .lte("class_sessions.date", to),
    ]);
    assertNoDbError(e1);
    assertNoDbError(e2);
    const absentIds = new Set(((statuses ?? []) as any[]).filter((s) => s.counts_as_absent).map((s) => String(s.id)));
    const records = ((rows ?? []) as any[])
      .map((r) => ({
        id: String(r.id),
        date: String(r.class_sessions?.date ?? "").slice(0, 10),
        subject: String(r.class_sessions?.classes?.subjects?.name ?? "Clase"),
        statusId: String(r.attendance_status_id),
        notes: r.notes ?? null,
      }))
      .sort((a, b) => b.date.localeCompare(a.date) || a.subject.localeCompare(b.subject, "es"));
    const byStatus: Record<string, number> = {};
    for (const r of records) byStatus[r.statusId] = (byStatus[r.statusId] ?? 0) + 1;
    const absent = records.filter((r) => absentIds.has(r.statusId)).length;
    return {
      studentId: String(studentId),
      from,
      to,
      statuses: ((statuses ?? []) as any[]).map((s) => ({
        id: String(s.id),
        name: String(s.name),
        code: String(s.code ?? ""),
        countsAsAbsent: Boolean(s.counts_as_absent),
        color: String(s.color ?? "#999999"),
      })),
      records,
      summary: { marks: records.length, absent, rate: records.length ? (records.length - absent) / records.length : null, byStatus },
    };
  }

  /** Tareas publicadas de las clases del salón del alumno, con el estado de su entrega y su nota. */
  async assignments(ctx: AppContext, query: Record<string, unknown>) {
    const studentId = await permissionsService.normalizeStudentId(ctx, query.studentId ?? query.student_id, "estudiante");
    const { data: enr, error: e0 } = await db
      .from("enrollments")
      .select("group_id")
      .eq("institution_id", ctx.institutionId)
      .eq("student_id", studentId);
    assertNoDbError(e0);
    const groupIds = [...new Set(((enr ?? []) as any[]).map((e) => Number(e.group_id)))];
    if (groupIds.length === 0) return { studentId: String(studentId), assignments: [] };

    const { data: rows, error: e1 } = await db
      .from("assignments")
      .select("id, class_id, title, description, instructions, due_at, max_score, allow_late, classes!inner(group_id, subjects(name))")
      .eq("institution_id", ctx.institutionId)
      .eq("published", true)
      .is("deleted_at", null)
      .in("classes.group_id", groupIds)
      .order("due_at", { ascending: false })
      .limit(300);
    assertNoDbError(e1);
    const list = (rows ?? []) as any[];
    const ids = list.map((a) => Number(a.id));
    if (ids.length === 0) return { studentId: String(studentId), assignments: [] };

    const [{ data: subs, error: e2 }, { data: statuses, error: e3 }, { data: evals, error: e4 }] = await Promise.all([
      db.from("submissions").select("assignment_id, submitted_at, is_late, task_status_id").eq("institution_id", ctx.institutionId).eq("student_id", studentId).in("assignment_id", ids),
      db.from("catalog_task_statuses").select("id, code").eq("code", "CALI"),
      db.from("evaluations").select("id, assignment_id").eq("institution_id", ctx.institutionId).in("assignment_id", ids),
    ]);
    assertNoDbError(e2);
    assertNoDbError(e3);
    assertNoDbError(e4);
    const gradedStatus = (statuses ?? [])[0]?.id == null ? null : Number((statuses as any[])[0].id);
    const evalOf = new Map(((evals ?? []) as any[]).map((e) => [Number(e.assignment_id), Number(e.id)]));
    const evalIds = [...evalOf.values()];
    const { data: grades, error: e5 } = evalIds.length
      ? await db.from("grades").select("evaluation_id, score, notes").eq("institution_id", ctx.institutionId).eq("student_id", studentId).in("evaluation_id", evalIds)
      : { data: [], error: null };
    assertNoDbError(e5);
    const gradeOf = new Map(((grades ?? []) as any[]).map((g) => [Number(g.evaluation_id), g]));
    const subOf = new Map(((subs ?? []) as any[]).map((s) => [Number(s.assignment_id), s]));
    const now = Date.now();

    return {
      studentId: String(studentId),
      assignments: list.map((a) => {
        const sub = subOf.get(Number(a.id));
        const isGraded = !!sub && gradedStatus != null && Number(sub.task_status_id) === gradedStatus;
        const grade = isGraded ? gradeOf.get(evalOf.get(Number(a.id)) ?? -1) : undefined;
        const overdue = !sub && a.due_at != null && new Date(String(a.due_at)).getTime() < now;
        return {
          id: String(a.id),
          title: String(a.title ?? ""),
          description: a.description ?? null,
          instructions: a.instructions ?? null,
          subjectName: String(a.classes?.subjects?.name ?? "Materia"),
          dueAt: String(a.due_at ?? ""),
          maxScore: Number(a.max_score ?? 100),
          allowLate: Boolean(a.allow_late),
          status: !sub ? (overdue ? "overdue" : "pending") : isGraded ? "graded" : sub.is_late ? "late" : "submitted",
          submittedAt: sub?.submitted_at ?? null,
          score: grade?.score == null ? null : Number(grade.score),
          feedback: grade?.notes ?? null,
        };
      }),
    };
  }
}

export const familyService = new FamilyService();

/** Rango `from`/`to` (AAAA-MM-DD); por defecto los últimos 30 días. */
function dateRange(query: Record<string, unknown>) {
  const parse = (value: unknown, label: string) => {
    if (value == null || value === "") return null;
    if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(new Date(value).getTime())) {
      throw new HttpError(400, `${label} inválida (usa AAAA-MM-DD).`, "validation_error");
    }
    return value;
  };
  const to = parse(query.to, "Fecha final") ?? dateOnly(new Date());
  const from = parse(query.from, "Fecha inicial") ?? dateOnly(new Date(new Date(to).getTime() - 29 * 86_400_000));
  if (from > to) throw new HttpError(400, "La fecha inicial no puede ser posterior a la final.", "validation_error");
  return { from, to };
}
