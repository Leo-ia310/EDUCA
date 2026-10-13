import { assertNoDbError, expectSingle } from "../../lib/db";
import { HttpError } from "../../lib/errors";
import { PageOptions, paged } from "../../lib/pagination";
import { requireSupabaseServiceRole } from "../../lib/supabase";

const db = new Proxy({} as any, {
  get(_target, property, receiver) {
    const client = requireSupabaseServiceRole();
    const value = Reflect.get(client, property, receiver);
    return typeof value === "function" ? value.bind(client) : value;
  },
});

export class AdminRepository {
  async listInstitutions(
    filters: Record<string, unknown> = {},
    page: PageOptions,
  ) {
    let query = db
      .from("institutions")
      .select(
        "id, code, name, commercial_name, subdomain, email, phone, timezone, active, created_at, updated_at",
        { count: "exact" },
      )
      .is("deleted_at", null)
      .order("name");
    if (filters.active != null) query = query.eq("active", filters.active);
    if (filters.search) {
      const search = String(filters.search).replace(/[%_]/g, "");
      query = query.or(`name.ilike.%${search}%,commercial_name.ilike.%${search}%,code.ilike.%${search}%`);
    }
    const { data, error, count } = await query.range(page.from, page.to);
    assertNoDbError(error);
    return paged(data ?? [], count, page);
  }

  async findInstitution(id: number) {
    return expectSingle<Record<string, unknown>>(
      db.from("institutions").select("*").eq("id", id).is("deleted_at", null).single(),
      "Institución no encontrada.",
    );
  }

  async createInstitution(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db.from("institutions").insert(payload).select("*").single(),
      "No se pudo crear la institución.",
    );
  }

  async updateInstitution(id: number, payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("institutions")
        .update({ ...payload, updated_at: new Date().toISOString() })
        .eq("id", id)
        .is("deleted_at", null)
        .select("*")
        .single(),
      "No se pudo actualizar la institución.",
    );
  }

  async archiveInstitution(id: number) {
    return this.updateInstitution(id, {
      active: false,
      deleted_at: new Date().toISOString(),
    });
  }

  async listUsers(
    institutionId: number | null,
    filters: Record<string, unknown> = {},
    page: PageOptions,
  ) {
    let query = db
      .from("users")
      .select(
        "id, institution_id, person_id, auth_user_id, username, email, phone, full_name, avatar_url, active, last_sign_in, created_at, updated_at, persons(id, first_name, last_name, email, phone, deleted_at), user_roles(roles(id, code, name))",
        { count: "exact" },
      )
      .is("deleted_at", null)
      .order("full_name");
    if (institutionId != null) query = query.eq("institution_id", institutionId);
    if (filters.search) {
      const search = String(filters.search).replace(/[%_]/g, "");
      query = query.or(`full_name.ilike.%${search}%,email.ilike.%${search}%,username.ilike.%${search}%`);
    }
    if (filters.active != null) query = query.eq("active", filters.active);
    const { data, error, count } = await query.range(page.from, page.to);
    assertNoDbError(error);
    return paged(data ?? [], count, page);
  }

  async findUser(institutionId: number, id: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("users")
        .select("*, persons(*), user_roles(roles(id, code, name))")
        .eq("institution_id", institutionId)
        .eq("id", id)
        .is("deleted_at", null)
        .single(),
      "Usuario no encontrado.",
    );
  }

  async createUser(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db.from("users").insert(payload).select("*").single(),
      "No se pudo crear el usuario.",
    );
  }

  async updateUser(institutionId: number, id: number, payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("users")
        .update({ ...payload, updated_at: new Date().toISOString() })
        .eq("institution_id", institutionId)
        .eq("id", id)
        .is("deleted_at", null)
        .select("*")
        .single(),
      "No se pudo actualizar el usuario.",
    );
  }

  async archiveUser(institutionId: number, id: number) {
    return this.updateUser(institutionId, id, {
      active: false,
      deleted_at: new Date().toISOString(),
    });
  }

  async listRoles(institutionId: number | null, page: PageOptions) {
    let query = db
      .from("roles")
      .select("id, institution_id, name, code, description, is_system, active, created_at, updated_at", {
        count: "exact",
      })
      .eq("active", true)
      .order("is_system", { ascending: false })
      .order("name");
    if (institutionId != null) {
      query = query.or(`institution_id.is.null,institution_id.eq.${institutionId}`);
    }
    const { data, error, count } = await query.range(page.from, page.to);
    assertNoDbError(error);
    return paged(data ?? [], count, page);
  }

  async findRoleForAssignment(institutionId: number, code: string) {
    const { data } = await db
      .from("roles")
      .select("id, code, institution_id")
      .or(`institution_id.is.null,institution_id.eq.${institutionId}`)
      .eq("code", code)
      .eq("active", true)
      .limit(1);
    return Array.isArray(data) && data.length > 0
      ? data[0] as Record<string, unknown>
      : null;
  }

  async createRole(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db.from("roles").insert(payload).select("*").single(),
      "No se pudo crear el rol.",
    );
  }

  async updateRole(institutionId: number, id: number, payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("roles")
        .update(payload)
        .eq("id", id)
        .eq("institution_id", institutionId)
        .eq("is_system", false)
        .select("*")
        .single(),
      "No se pudo actualizar el rol.",
    );
  }

  async archiveRole(institutionId: number, id: number) {
    return this.updateRole(institutionId, id, { active: false });
  }

  async replaceUserRoles(institutionId: number, userId: number, roleIds: number[]) {
    const { error: deleteError } = await db
      .from("user_roles")
      .delete()
      .eq("institution_id", institutionId)
      .eq("user_id", userId);
    assertNoDbError(deleteError);
    if (roleIds.length === 0) return;
    const { error } = await db.from("user_roles").insert(
      roleIds.map((roleId) => ({
        institution_id: institutionId,
        user_id: userId,
        role_id: roleId,
      })),
    );
    assertNoDbError(error);
  }

  async createPerson(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db.from("persons").insert(payload).select("*").single(),
      "No se pudo crear la persona.",
    );
  }

  async updatePerson(institutionId: number, id: number, payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("persons")
        .update({ ...payload, updated_at: new Date().toISOString() })
        .eq("institution_id", institutionId)
        .eq("id", id)
        .is("deleted_at", null)
        .select("*")
        .single(),
      "No se pudo actualizar la persona.",
    );
  }

  async archivePerson(institutionId: number, id: number) {
    return this.updatePerson(institutionId, id, {
      deleted_at: new Date().toISOString(),
    });
  }

  async listPeopleResource(
    table: "students" | "teachers" | "parents",
    institutionId: number | null,
    filters: Record<string, unknown> = {},
    page: PageOptions,
  ) {
    const extraSelect = table === "students"
      ? "student_code, enrollment_date, blood_type, allergies, medical_notes, active"
      : table === "teachers"
        ? "teacher_code, specialty, academic_title, hired_at, active"
        : "occupation, workplace, work_phone, is_emergency_contact";
    let query = db
      .from(table)
      .select(
        `id, institution_id, person_id, ${extraSelect}, created_at, persons!inner(id, first_name, last_name, document_number, birth_date, email, phone, address, photo_url, deleted_at)`,
        { count: "exact" },
      )
      .is("persons.deleted_at", null)
      .order("created_at", { ascending: false });
    if (institutionId != null) query = query.eq("institution_id", institutionId);
    if (filters.active != null && table !== "parents") {
      query = query.eq("active", filters.active);
    }
    if (filters.search) {
      const search = String(filters.search).replace(/[%_]/g, "");
      query = query.or(
        `first_name.ilike.%${search}%,last_name.ilike.%${search}%,email.ilike.%${search}%`,
        { referencedTable: "persons" },
      );
    }
    const { data, error, count } = await query.range(page.from, page.to);
    assertNoDbError(error);
    return paged(data ?? [], count, page);
  }

  async findPeopleResource(
    table: "students" | "teachers" | "parents",
    institutionId: number,
    id: number,
  ) {
    return expectSingle<Record<string, unknown>>(
      db
        .from(table)
        .select("*, persons(*)")
        .eq("institution_id", institutionId)
        .eq("id", id)
        .single(),
      "Registro no encontrado.",
    );
  }

  async createPeopleResource(
    table: "students" | "teachers" | "parents",
    payload: Record<string, unknown>,
  ) {
    return expectSingle<Record<string, unknown>>(
      db.from(table).insert(payload).select("*, persons(*)").single(),
      "No se pudo crear el registro.",
    );
  }

  async updatePeopleResource(
    table: "students" | "teachers" | "parents",
    institutionId: number,
    id: number,
    payload: Record<string, unknown>,
  ) {
    return expectSingle<Record<string, unknown>>(
      db
        .from(table)
        .update(payload)
        .eq("institution_id", institutionId)
        .eq("id", id)
        .select("*, persons(*)")
        .single(),
      "No se pudo actualizar el registro.",
    );
  }

  async archivePeopleResource(
    table: "students" | "teachers",
    institutionId: number,
    id: number,
  ) {
    return this.updatePeopleResource(table, institutionId, id, { active: false });
  }

  async listDirectory(institutionId: number) {
    const [students, teachers, parents, parentLinks, enrollments, groups, classes] =
      await Promise.all([
        this.listDirectoryPeople("students", institutionId),
        this.listDirectoryPeople("teachers", institutionId),
        this.listDirectoryPeople("parents", institutionId),
        db
          .from("parent_students")
          .select("student_id, parent_id, parents!inner(institution_id)")
          .eq("parents.institution_id", institutionId),
        db
          .from("enrollments")
          .select("student_id, group_id, academic_year_id")
          .eq("institution_id", institutionId),
        db
          .from("groups")
          .select(
            "id, name, max_capacity, active, classroom_id, guide_teacher_id, classrooms(name)",
          )
          .eq("institution_id", institutionId)
          .eq("active", true)
          .order("name"),
        db
          .from("classes")
          .select(
            "id, group_id, teacher_id, active, subjects(name), groups(name, classrooms(name))",
          )
          .eq("institution_id", institutionId)
          .eq("active", true)
          .order("created_at"),
      ]);
    for (const result of [parentLinks, enrollments, groups, classes]) {
      assertNoDbError(result.error);
    }
    return {
      people: [
        ...students.map((row: Record<string, unknown>) =>
          this.directoryPerson(row, "student", enrollments.data ?? [], parentLinks.data ?? [])
        ),
        ...teachers.map((row: Record<string, unknown>) =>
          this.directoryPerson(row, "teacher", enrollments.data ?? [], parentLinks.data ?? [])
        ),
        ...parents.map((row: Record<string, unknown>) =>
          this.directoryPerson(row, "parent", enrollments.data ?? [], parentLinks.data ?? [])
        ),
      ],
      groups: groups.data ?? [],
      classes: classes.data ?? [],
    };
  }

  private async listDirectoryPeople(
    table: "students" | "teachers" | "parents",
    institutionId: number,
  ) {
    const extraSelect = table === "students"
      ? "student_code, active"
      : table === "teachers"
        ? "teacher_code, active"
        : "is_emergency_contact";
    const { data, error } = await db
      .from(table)
      .select(
        `id, institution_id, person_id, ${extraSelect}, persons!inner(id, first_name, last_name, email, phone, deleted_at)`,
      )
      .eq("institution_id", institutionId)
      .is("persons.deleted_at", null);
    assertNoDbError(error);
    return data ?? [];
  }

  private directoryPerson(
    row: Record<string, unknown>,
    role: "student" | "teacher" | "parent",
    enrollments: Record<string, unknown>[],
    parentLinks: Record<string, unknown>[],
  ) {
    const person = row.persons as Record<string, unknown> | null;
    return {
      ...row,
      role,
      group_id: role === "student"
        ? enrollments.find((e) => String(e.student_id) === String(row.id))?.group_id ?? null
        : null,
      child_ids: role === "parent"
        ? parentLinks
          .filter((link) => String(link.parent_id) === String(row.id))
          .map((link) => String(link.student_id))
        : [],
      persons: person,
    };
  }

  async currentAcademicYear(institutionId: number) {
    const current = await db
      .from("academic_years")
      .select("*")
      .eq("institution_id", institutionId)
      .eq("is_current", true)
      .eq("active", true)
      .maybeSingle();
    assertNoDbError(current.error);
    if (current.data) return current.data as Record<string, unknown>;

    const year = new Date().getFullYear();
    return expectSingle<Record<string, unknown>>(
      db
        .from("academic_years")
        .insert({
          institution_id: institutionId,
          name: `Año Escolar ${year}`,
          year,
          active: true,
          is_current: true,
        })
        .select("*")
        .single(),
      "No se pudo crear el año académico actual.",
    );
  }

  async findOrCreateGradeLevel(institutionId: number, name: string) {
    const found = await db
      .from("grade_levels")
      .select("*")
      .eq("institution_id", institutionId)
      .ilike("name", name)
      .eq("active", true)
      .maybeSingle();
    assertNoDbError(found.error);
    if (found.data) return found.data as Record<string, unknown>;
    return expectSingle<Record<string, unknown>>(
      db
        .from("grade_levels")
        .insert({ institution_id: institutionId, name, active: true })
        .select("*")
        .single(),
      "No se pudo crear el grado.",
    );
  }

  async findOrCreateSection(institutionId: number, name: string) {
    const found = await db
      .from("sections")
      .select("*")
      .eq("institution_id", institutionId)
      .ilike("name", name)
      .eq("active", true)
      .maybeSingle();
    assertNoDbError(found.error);
    if (found.data) return found.data as Record<string, unknown>;
    return expectSingle<Record<string, unknown>>(
      db
        .from("sections")
        .insert({ institution_id: institutionId, name, active: true })
        .select("*")
        .single(),
      "No se pudo crear la sección.",
    );
  }

  async findOrCreateClassroom(institutionId: number, name: string | null) {
    if (name == null || name.trim().length === 0) return null;
    const found = await db
      .from("classrooms")
      .select("*")
      .eq("institution_id", institutionId)
      .ilike("name", name)
      .eq("active", true)
      .maybeSingle();
    assertNoDbError(found.error);
    if (found.data) return found.data as Record<string, unknown>;
    return expectSingle<Record<string, unknown>>(
      db
        .from("classrooms")
        .insert({ institution_id: institutionId, name, active: true })
        .select("*")
        .single(),
      "No se pudo crear el aula.",
    );
  }

  async createGroup(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db.from("groups").insert(payload).select("*, classrooms(name)").single(),
      "No se pudo crear el salón.",
    );
  }

  async updateGroup(institutionId: number, id: number, payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("groups")
        .update(payload)
        .eq("institution_id", institutionId)
        .eq("id", id)
        .select("*, classrooms(name)")
        .single(),
      "No se pudo actualizar el salón.",
    );
  }

  async archiveGroup(institutionId: number, id: number) {
    const group = await this.updateGroup(institutionId, id, { active: false });
    const { error } = await db
      .from("classes")
      .update({ active: false })
      .eq("institution_id", institutionId)
      .eq("group_id", id);
    assertNoDbError(error);
    return group;
  }

  async findOrCreateSubject(institutionId: number, name: string) {
    const found = await db
      .from("subjects")
      .select("*")
      .eq("institution_id", institutionId)
      .ilike("name", name)
      .eq("active", true)
      .maybeSingle();
    assertNoDbError(found.error);
    if (found.data) return found.data as Record<string, unknown>;
    return expectSingle<Record<string, unknown>>(
      db
        .from("subjects")
        .insert({ institution_id: institutionId, name, active: true })
        .select("*")
        .single(),
      "No se pudo crear la materia.",
    );
  }

  async findGroup(institutionId: number, groupId: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("groups")
        .select("id")
        .eq("institution_id", institutionId)
        .eq("id", groupId)
        .eq("active", true)
        .single(),
      "Salón no encontrado.",
    );
  }

  async createClass(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("classes")
        .insert(payload)
        .select("*, subjects(name), groups(name, classrooms(name))")
        .single(),
      "No se pudo crear la clase.",
    );
  }

  async updateClass(institutionId: number, id: number, payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("classes")
        .update(payload)
        .eq("institution_id", institutionId)
        .eq("id", id)
        .select("*, subjects(name), groups(name, classrooms(name))")
        .single(),
      "No se pudo actualizar la clase.",
    );
  }

  async archiveClass(institutionId: number, id: number) {
    return this.updateClass(institutionId, id, { active: false });
  }

  async replaceStudentEnrollment(
    institutionId: number,
    studentId: number,
    groupId: number | null,
  ) {
    const year = await this.currentAcademicYear(institutionId);
    if (groupId == null) {
      const { error } = await db
        .from("enrollments")
        .delete()
        .eq("institution_id", institutionId)
        .eq("student_id", studentId)
        .eq("academic_year_id", year.id);
      assertNoDbError(error);
      return;
    }
    await this.findGroup(institutionId, groupId);
    const status = await db
      .from("catalog_enrollment_statuses")
      .select("id")
      .eq("code", "ACT")
      .maybeSingle();
    assertNoDbError(status.error);
    const { error } = await db.from("enrollments").upsert(
      {
        institution_id: institutionId,
        student_id: studentId,
        group_id: groupId,
        academic_year_id: year.id,
        enrollment_status_id: status.data?.id ?? null,
        enrolled_at: new Date().toISOString().slice(0, 10),
      },
      { onConflict: "student_id,academic_year_id" },
    );
    assertNoDbError(error);
  }

  async replaceParentStudents(
    institutionId: number,
    parentId: number,
    studentIds: number[],
  ) {
    await expectSingle<Record<string, unknown>>(
      db
        .from("parents")
        .select("id")
        .eq("institution_id", institutionId)
        .eq("id", parentId)
        .single(),
      "Padre o tutor no encontrado.",
    );
    const uniqueStudentIds = [...new Set(studentIds)];
    if (uniqueStudentIds.length > 0) {
      const { data, error } = await db
        .from("students")
        .select("id")
        .eq("institution_id", institutionId)
        .in("id", uniqueStudentIds);
      assertNoDbError(error);
      const validIds = new Set((data ?? []).map((row: Record<string, unknown>) => Number(row.id)));
      const invalid = uniqueStudentIds.filter((id) => !validIds.has(id));
      if (invalid.length > 0) {
        throw new HttpError(
          400,
          "Uno o más estudiantes no pertenecen a la institución.",
          "validation_error",
        );
      }
    }
    const { error: deleteError } = await db
      .from("parent_students")
      .delete()
      .eq("parent_id", parentId);
    assertNoDbError(deleteError);
    if (uniqueStudentIds.length === 0) return;
    const { error } = await db.from("parent_students").insert(
      uniqueStudentIds.map((studentId, index) => ({
        parent_id: parentId,
        student_id: studentId,
        is_main_responsible: index === 0,
        can_pickup: true,
        lives_with: index === 0,
      })),
    );
    assertNoDbError(error);
  }
}

export const adminRepository = new AdminRepository();
