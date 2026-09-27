import { assertNoDbError, expectSingle } from "../lib/db";
import { requireSupabaseServiceRole } from "../lib/supabase";

const db = new Proxy({} as any, {
  get(_target, property, receiver) {
    const client = requireSupabaseServiceRole();
    const value = Reflect.get(client, property, receiver);
    return typeof value === "function" ? value.bind(client) : value;
  },
});

export class AdminRepository {
  async listInstitutions(filters: Record<string, unknown> = {}) {
    let query = db
      .from("institutions")
      .select("*")
      .is("deleted_at", null)
      .order("name");
    if (filters.active != null) query = query.eq("active", filters.active);
    if (filters.search) {
      const search = String(filters.search).replace(/[%_]/g, "");
      query = query.or(`name.ilike.%${search}%,commercial_name.ilike.%${search}%,code.ilike.%${search}%`);
    }
    const { data, error } = await query;
    assertNoDbError(error);
    return data ?? [];
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

  async listUsers(institutionId: number | null, filters: Record<string, unknown> = {}) {
    let query = db
      .from("users")
      .select("*, persons(*), user_roles(roles(id, code, name))")
      .is("deleted_at", null)
      .order("full_name");
    if (institutionId != null) query = query.eq("institution_id", institutionId);
    if (filters.search) {
      const search = String(filters.search).replace(/[%_]/g, "");
      query = query.or(`full_name.ilike.%${search}%,email.ilike.%${search}%,username.ilike.%${search}%`);
    }
    if (filters.active != null) query = query.eq("active", filters.active);
    const { data, error } = await query;
    assertNoDbError(error);
    return data ?? [];
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

  async listRoles(institutionId: number | null) {
    let query = db
      .from("roles")
      .select("*")
      .eq("active", true)
      .order("is_system", { ascending: false })
      .order("name");
    if (institutionId != null) {
      query = query.or(`institution_id.is.null,institution_id.eq.${institutionId}`);
    }
    const { data, error } = await query;
    assertNoDbError(error);
    return data ?? [];
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
  ) {
    let query = db
      .from(table)
      .select("*, persons(*)")
      .order("created_at", { ascending: false });
    if (institutionId != null) query = query.eq("institution_id", institutionId);
    if (filters.active != null && table !== "parents") {
      query = query.eq("active", filters.active);
    }
    const { data, error } = await query;
    assertNoDbError(error);
    let rows = (data ?? []).filter((row: Record<string, unknown>) => {
      const person = row.persons as Record<string, unknown> | null;
      return person?.deleted_at == null;
    });
    if (filters.search) {
      const search = String(filters.search).toLowerCase();
      rows = rows.filter((row: Record<string, unknown>) => {
        const person = row.persons as Record<string, unknown> | null;
        const haystack = [
          person?.first_name,
          person?.last_name,
          person?.email,
          row.student_code,
          row.teacher_code,
        ].join(" ").toLowerCase();
        return haystack.includes(search);
      });
    }
    return rows;
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
}

export const adminRepository = new AdminRepository();
