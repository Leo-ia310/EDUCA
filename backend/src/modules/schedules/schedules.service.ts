import { paginationFromQuery } from "../../lib/pagination";
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
} from "./schedules.repository";

const SHIFTS = ["morning", "afternoon", "evening"] as const;
const KINDS = ["class", "break"] as const;
type Kind = (typeof KINDS)[number];

/** "HH:mm" o "HH:mm:ss" -> minutos desde medianoche. */
function toMinutes(raw: unknown, label: string) {
  const match = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(String(raw ?? "").trim());
  const hours = match ? Number(match[1]) : NaN;
  const minutes = match ? Number(match[2]) : NaN;
  if (!match || hours > 23 || minutes > 59 || Number(match[3] ?? 0) !== 0) {
    throw new HttpError(400, `${label} no es una hora válida (HH:mm).`, "validation_error");
  }
  return hours * 60 + minutes;
}

function toTime(minutes: number) {
  const h = String(Math.floor(minutes / 60)).padStart(2, "0");
  const m = String(minutes % 60).padStart(2, "0");
  return `${h}:${m}:00`;
}

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

    const pagination = paginationFromQuery(query);
    return this.repository.list(institutionId, { groupId, teacherId, classId, weekdayId: weekdayId == null ? null : this.weekdayOf(weekdayId), shift: this.shiftOf(shift), page: pagination.page, pageSize: pagination.pageSize });
  }

  async create(ctx: AppContext, payload: Record<string, unknown>) {
    const { start, end } = this.timesOf(payload);
    const kind = this.kindOf(payload.kind);
    return this.repository.write(this.targetInstitutionId(ctx, payload), "create", {
      ...this.targetPayload(kind, payload), kind, weekdayIds: this.weekdaysOf(payload),
      startTime: toTime(start), endTime: toTime(end), shift: this.shiftOf(payload.shift),
    });
  }

  async update(ctx: AppContext, idValue: unknown, payload: Record<string, unknown>) {
    const canonical: Record<string, unknown> = {};
    // Only supplied fields are patched. SQL locks and merges the current row,
    // so unrelated edits cannot be overwritten by a stale pre-read.
    for (const key of ["classId", "groupId", "weekdayId", "startTime", "endTime"] as const) {
      const snake = key.replace(/[A-Z]/g, (char) => `_${char.toLowerCase()}`);
      if (payload[key] !== undefined || payload[snake] !== undefined) {
        const value = payload[key] !== undefined ? payload[key] : payload[snake];
        canonical[key] = key === "weekdayId" ? this.weekdayOf(value) : key.endsWith("Time") ? toTime(toMinutes(value, "Hora")) : optionalId(value);
      }
    }
    if (payload.kind !== undefined) canonical.kind = this.kindOf(payload.kind);
    if (payload.label !== undefined) canonical.label = optionalString(payload.label, 80);
    if (payload.room !== undefined) canonical.room = optionalString(payload.room, 50);
    if (payload.shift !== undefined) canonical.shift = this.shiftOf(payload.shift);
    return this.repository.write(this.targetInstitutionId(ctx, payload), "update", canonical, requiredId(idValue, "Horario"));
  }

  async remove(ctx: AppContext, idValue: unknown, query: Record<string, unknown>) {
    return this.repository.write(this.targetInstitutionId(ctx, query), "delete", {}, requiredId(idValue, "Horario"));
  }

  async mine(ctx: AppContext, query: Record<string, unknown>) {
    if (this.permissions.isAdmin(ctx)) throw new HttpError(400, "Consulta el listado administrativo de horarios.", "validation_error");
    const studentId = ctx.roles.has("teacher") ? null : await this.permissions.normalizeStudentId(ctx, query.studentId ?? query.student_id, "estudiante");
    return this.repository.list(ctx.institutionId, {}, true, studentId);
  }

  // ---------- Validación ----------

  private targetPayload(kind: Kind, payload: Record<string, unknown>) {
    return {
      classId: kind === "class" ? requiredId(payload.classId ?? payload.class_id, "Clase") : null,
      groupId: kind === "break" ? optionalId(payload.groupId ?? payload.group_id) : null,
      label: optionalString(payload.label, 80), room: optionalString(payload.room, 50),
    };
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
    const id = requiredId(value,"Día de la semana");
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

  private targetInstitutionId(ctx: AppContext, payload: Record<string, unknown>) {
    const requested = optionalId(payload.institutionId ?? payload.institution_id);
    if (this.permissions.isSuperAdmin(ctx)) return requested ?? ctx.institutionId;
    if (requested != null && requested !== ctx.institutionId) {
      throw new HttpError(403, "No puedes gestionar otra institución.", "forbidden");
    }
    return ctx.institutionId;
  }

}

export const schedulesService = new SchedulesService();
