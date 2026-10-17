import { HttpError } from "../../lib/errors";
import {
  permissionsService,
  PermissionsService,
} from "../../services/permissions.service";
import type { AppContext } from "../../types/app-context";
import {
  asList,
  optionalId,
  optionalString,
  requiredId,
} from "../../validators/common.validators";
import {
  schedulesRepository,
  SchedulesRepository,
  type ScheduleRow,
} from "./schedules.repository";

const SHIFTS = ["morning", "afternoon", "evening"] as const;
const KINDS = ["class", "break"] as const;
type Kind = (typeof KINDS)[number];

/** "HH:mm" o "HH:mm:ss" -> minutos desde medianoche. */
function toMinutes(raw: unknown, label: string) {
  const match = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(String(raw ?? "").trim());
  const hours = match ? Number(match[1]) : NaN;
  const minutes = match ? Number(match[2]) : NaN;
  if (!match || hours > 23 || minutes > 59) {
    throw new HttpError(400, `${label} no es una hora válida (HH:mm).`, "validation_error");
  }
  return hours * 60 + minutes;
}

function toTime(minutes: number) {
  const h = String(Math.floor(minutes / 60)).padStart(2, "0");
  const m = String(minutes % 60).padStart(2, "0");
  return `${h}:${m}:00`;
}

function hhmm(raw: unknown) {
  return String(raw ?? "").slice(0, 5);
}

type Candidate = {
  weekdayId: number;
  start: number;
  end: number;
  kind: Kind;
  classId: number | null;
  groupId: number | null;
  teacherId: number | null;
  classroomId: number | null;
};

export class SchedulesService {
  constructor(
    private readonly repository: SchedulesRepository = schedulesRepository,
    private readonly permissions: PermissionsService = permissionsService,
  ) {}

  // ---------- Administración ----------

  async list(ctx: AppContext, query: Record<string, unknown>) {
    const institutionId = this.targetInstitutionId(ctx, query);
    const groupId = optionalId(query.groupId ?? query.group_id);
    const teacherId = optionalId(query.teacherId ?? query.teacher_id);
    const classId = optionalId(query.classId ?? query.class_id);
    const weekdayId = optionalId(query.weekdayId ?? query.weekday_id);
    const shift = optionalString(query.shift, 20);

    const rows = await this.repository.listByInstitution(institutionId);
    const items = rows
      .filter((row) => weekdayId == null || Number(row.weekday_id) === weekdayId)
      .filter((row) => classId == null || Number(row.class_id) === classId)
      .filter((row) => shift == null || row.shift === shift)
      .filter((row) => {
        const rowGroup = this.groupOf(row);
        // Los recesos de toda la institución aparecen en cualquier grupo.
        return groupId == null || rowGroup == null || rowGroup === groupId;
      })
      .filter((row) =>
        teacherId == null || Number(row.classes?.teacher_id) === teacherId
      )
      .map((row) => this.view(row));
    return { schedules: items };
  }

  async create(ctx: AppContext, payload: Record<string, unknown>) {
    const institutionId = this.targetInstitutionId(ctx, payload);
    const kind = this.kindOf(payload.kind);
    const weekdays = this.weekdaysOf(payload);
    const { start, end } = this.timesOf(payload);
    const resolved = await this.resolveTarget(institutionId, kind, payload);

    for (const weekdayId of weekdays) {
      await this.assertNoConflicts(institutionId, {
        weekdayId,
        start,
        end,
        kind,
        ...resolved.candidate,
      });
    }

    const ids = await this.repository.insertMany(
      weekdays.map((weekdayId) => ({
        institution_id: institutionId,
        kind,
        class_id: resolved.classId,
        group_id: resolved.groupId,
        label: resolved.label,
        shift: this.shiftOf(payload.shift),
        weekday_id: weekdayId,
        start_time: toTime(start),
        end_time: toTime(end),
        classroom_id: resolved.classroomId,
      })),
    );
    const created = await Promise.all(
      ids.map((id) => this.repository.findById(institutionId, id)),
    );
    return { schedules: created.map((row) => this.view(row)) };
  }

  async update(ctx: AppContext, idValue: unknown, payload: Record<string, unknown>) {
    const institutionId = this.targetInstitutionId(ctx, payload);
    const id = requiredId(idValue, "Horario");
    const current = await this.repository.findById(institutionId, id);
    const kind = this.kindOf(payload.kind ?? current.kind);

    const weekdayId = payload.weekdayId !== undefined || payload.weekday_id !== undefined
      ? this.weekdayOf(payload.weekdayId ?? payload.weekday_id)
      : Number(current.weekday_id);
    const { start, end } = this.timesOf({
      startTime: payload.startTime ?? payload.start_time ?? hhmm(current.start_time),
      endTime: payload.endTime ?? payload.end_time ?? hhmm(current.end_time),
    });
    const merged = {
      classId: current.class_id,
      groupId: current.group_id,
      label: current.label,
      room: current.classrooms?.name,
      ...payload,
    };
    const resolved = await this.resolveTarget(institutionId, kind, merged);

    await this.assertNoConflicts(
      institutionId,
      { weekdayId, start, end, kind, ...resolved.candidate },
      id,
    );

    await this.repository.update(institutionId, id, {
      kind,
      class_id: resolved.classId,
      group_id: resolved.groupId,
      label: resolved.label,
      shift: payload.shift === undefined
        ? current.shift
        : this.shiftOf(payload.shift),
      weekday_id: weekdayId,
      start_time: toTime(start),
      end_time: toTime(end),
      classroom_id: resolved.classroomId,
    });
    return {
      schedule: this.view(await this.repository.findById(institutionId, id)),
    };
  }

  async remove(ctx: AppContext, idValue: unknown, query: Record<string, unknown>) {
    const institutionId = this.targetInstitutionId(ctx, query);
    const id = requiredId(idValue, "Horario");
    await this.repository.findById(institutionId, id);
    await this.repository.delete(institutionId, id);
    return { ok: true };
  }

  // ---------- Consulta filtrada para alumno / padre / maestro ----------

  async mine(ctx: AppContext, query: Record<string, unknown>) {
    const institutionId = ctx.institutionId;
    let groupIds: number[] = [];
    let classIds: number[] = [];

    if (this.permissions.isAdmin(ctx)) {
      throw new HttpError(
        400,
        "Los administradores consultan los horarios desde el listado general.",
        "validation_error",
      );
    }
    if (ctx.roles.has("teacher")) {
      const teacherId = await this.permissions.currentTeacherId(ctx);
      if (teacherId == null) return { schedules: [] };
      const classes = await this.repository.classesOfTeacher(institutionId, teacherId);
      classIds = classes.map((c) => Number(c.id));
      groupIds = [...new Set(classes.map((c) => Number(c.group_id)))];
    } else {
      // Alumno (el suyo) o padre (uno de sus hijos).
      const studentId = await this.permissions.normalizeStudentId(
        ctx,
        query.studentId ?? query.student_id,
        "estudiante",
      );
      groupIds = await this.repository.groupIdsOfStudent(institutionId, studentId);
      const classes = await this.repository.classesOfGroups(institutionId, groupIds);
      classIds = classes.map((c) => Number(c.id));
    }

    const rows = await this.repository.listForClasses(institutionId, classIds, groupIds);
    return { schedules: rows.map((row) => this.view(row)) };
  }

  // ---------- Validación ----------

  private async resolveTarget(
    institutionId: number,
    kind: Kind,
    payload: Record<string, unknown>,
  ) {
    const room = optionalString(payload.room, 50);
    if (kind === "class") {
      const classId = requiredId(payload.classId ?? payload.class_id, "Clase");
      const cls = await this.repository.findClass(institutionId, classId);
      if (cls == null) {
        throw new HttpError(
          400,
          "La clase no existe o no pertenece a la institución.",
          "validation_error",
        );
      }
      const classroomId = room
        ? await this.repository.ensureClassroom(institutionId, room)
        : null;
      return {
        classId,
        groupId: null as number | null,
        label: null as string | null,
        classroomId,
        candidate: {
          classId,
          groupId: Number(cls.group_id),
          teacherId: cls.teacher_id == null ? null : Number(cls.teacher_id),
          classroomId,
        },
      };
    }

    const groupId = optionalId(payload.groupId ?? payload.group_id);
    if (groupId != null && await this.repository.findGroup(institutionId, groupId) == null) {
      throw new HttpError(
        400,
        "El grupo no existe o no pertenece a la institución.",
        "validation_error",
      );
    }
    const label = optionalString(payload.label, 80) ?? "Receso";
    return {
      classId: null as number | null,
      groupId,
      label,
      classroomId: null as number | null,
      candidate: { classId: null, groupId, teacherId: null, classroomId: null },
    };
  }

  /** Choques: mismo grupo, mismo maestro o misma aula en el mismo tramo. */
  private async assertNoConflicts(
    institutionId: number,
    candidate: Candidate,
    excludeId?: number,
  ) {
    const rows = await this.repository.listByInstitution(institutionId);
    for (const row of rows) {
      if (excludeId != null && Number(row.id) === excludeId) continue;
      if (Number(row.weekday_id) !== candidate.weekdayId) continue;
      const otherStart = toMinutes(row.start_time, "Inicio");
      const otherEnd = toMinutes(row.end_time, "Fin");
      if (!(candidate.start < otherEnd && candidate.end > otherStart)) continue;

      const reason = this.conflictReason(candidate, row);
      if (reason != null) {
        throw new HttpError(
          409,
          `Choque de horario: ${reason} (${hhmm(row.start_time)}–${hhmm(row.end_time)}).`,
          "schedule_conflict",
        );
      }
    }
  }

  private conflictReason(candidate: Candidate, row: ScheduleRow) {
    const otherGroup = this.groupOf(row);
    const name = row.kind === "break"
      ? (row.label ?? "Receso")
      : (row.classes?.subjects?.name ?? "otra clase");

    if (candidate.kind === "break") {
      // Un receso choca con lo que ocurra en su grupo (o con todo si es general).
      if (candidate.groupId == null || otherGroup == null || otherGroup === candidate.groupId) {
        return `se cruza con ${name}`;
      }
      return null;
    }
    if (row.kind === "break") {
      if (otherGroup == null || otherGroup === candidate.groupId) {
        return `se cruza con el receso "${name}"`;
      }
      return null;
    }
    if (otherGroup != null && otherGroup === candidate.groupId) {
      return `el grupo ya tiene ${name}`;
    }
    const otherTeacher = row.classes?.teacher_id;
    if (
      candidate.teacherId != null && otherTeacher != null &&
      Number(otherTeacher) === candidate.teacherId
    ) {
      return `el maestro ya tiene ${name}`;
    }
    if (
      candidate.classroomId != null && row.classroom_id != null &&
      Number(row.classroom_id) === candidate.classroomId
    ) {
      return `el aula ya está ocupada por ${name}`;
    }
    return null;
  }

  private kindOf(value: unknown): Kind {
    const kind = String(value ?? "class");
    if (!KINDS.includes(kind as Kind)) {
      throw new HttpError(400, "El tipo debe ser clase o receso.", "validation_error");
    }
    return kind as Kind;
  }

  private shiftOf(value: unknown) {
    const shift = optionalString(value, 20);
    if (shift == null) return null;
    if (!SHIFTS.includes(shift as (typeof SHIFTS)[number])) {
      throw new HttpError(
        400,
        "El turno debe ser mañana, tarde o noche.",
        "validation_error",
      );
    }
    return shift;
  }

  private weekdayOf(value: unknown) {
    const id = Number(value);
    if (!Number.isInteger(id) || id < 1 || id > 7) {
      throw new HttpError(400, "Día de la semana no válido (1 = lunes … 7 = domingo).", "validation_error");
    }
    return id;
  }

  private weekdaysOf(payload: Record<string, unknown>) {
    const raw = payload.weekdayIds ?? payload.weekday_ids ??
      (payload.weekdayId ?? payload.weekday_id) ?? undefined;
    const list = Array.isArray(raw) ? raw : asList(raw === undefined ? [] : [raw]);
    const days = [...new Set(list.map((d) => this.weekdayOf(d)))];
    if (days.length === 0) {
      throw new HttpError(400, "Elige al menos un día de la semana.", "validation_error");
    }
    return days;
  }

  private timesOf(payload: Record<string, unknown>) {
    const start = toMinutes(payload.startTime ?? payload.start_time, "La hora de inicio");
    const end = toMinutes(payload.endTime ?? payload.end_time, "La hora de fin");
    if (start >= end) {
      throw new HttpError(
        400,
        "La hora de fin debe ser posterior a la de inicio.",
        "validation_error",
      );
    }
    return { start, end };
  }

  private groupOf(row: ScheduleRow): number | null {
    const value = row.kind === "break" ? row.group_id : row.classes?.group_id;
    return value == null ? null : Number(value);
  }

  private targetInstitutionId(ctx: AppContext, payload: Record<string, unknown>) {
    const requested = optionalId(payload.institutionId ?? payload.institution_id);
    if (this.permissions.isSuperAdmin(ctx)) return requested ?? ctx.institutionId;
    if (requested != null && requested !== ctx.institutionId) {
      throw new HttpError(403, "No puedes gestionar otra institución.", "forbidden");
    }
    return ctx.institutionId;
  }

  private view(row: ScheduleRow) {
    const isBreak = row.kind === "break";
    const person = row.classes?.teachers?.persons;
    const teacher = person
      ? `${person.first_name ?? ""} ${person.last_name ?? ""}`.trim()
      : "";
    const groupId = this.groupOf(row);
    return {
      id: String(row.id),
      kind: row.kind ?? "class",
      weekdayId: Number(row.weekday_id),
      weekdayIndex: Number(row.weekday_id) - 1,
      startTime: hhmm(row.start_time),
      endTime: hhmm(row.end_time),
      classId: row.class_id == null ? null : String(row.class_id),
      subject: isBreak ? (row.label ?? "Receso") : (row.classes?.subjects?.name ?? "Clase"),
      groupId: groupId == null ? null : String(groupId),
      groupName: isBreak
        ? (row.groups?.name ?? null)
        : (row.classes?.groups?.name ?? null),
      teacher: teacher || null,
      teacherId: row.classes?.teacher_id == null ? null : String(row.classes.teacher_id),
      room: row.classrooms?.name ?? null,
      shift: row.shift ?? null,
    };
  }
}

export const schedulesService = new SchedulesService();
