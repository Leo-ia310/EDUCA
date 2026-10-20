import { transactionRpc } from "../../lib/transaction-rpc";
import { supabaseAdmin as scopedDb } from "../../lib/supabase";
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
  constructor(private readonly scoped:any = scopedDb) {}
  async writePerson(institutionId:number,kind:string,id:number,person:Record<string,unknown>,entity:Record<string,unknown>,relations:Record<string,unknown>) {
    return transactionRpc(this.scoped,"admin_person_write",{p_inst:institutionId,p_kind:kind,p_id:id,p_person:person,p_entity:entity,p_relations:relations});
  }
  async writeAccount(institutionId:number,id:number|null,changes:Record<string,unknown>,roles:string[]|null) {
    return transactionRpc(this.scoped,"admin_account_write",{p_inst:institutionId,p_id:id,p_changes:changes,p_roles:roles});
  }

  async beginProvision(institutionId:number,kind:string,key:string,payload:Record<string,unknown>,passwordProof:string) {
    return transactionRpc(this.scoped,"admin_provision_begin",{p_inst:institutionId,p_kind:kind,p_key:key,p_payload:payload,p_password_proof:passwordProof});
  }
  async completeProvision(id:string) { return transactionRpc(this.scoped,"admin_provision_complete",{p_id:id}); }
  async observeProvision(id:string,authId:string) {
    return transactionRpc<boolean>(this.scoped,"admin_provision_observe",{p_id:id,p_auth_id:authId});
  }
  async rejectProvision(id:string) { return transactionRpc<boolean>(this.scoped,"admin_provision_reject",{p_id:id}); }

  async archivePersonAccount(institutionId:number,kind:string,id:number) {
    return transactionRpc(this.scoped,"admin_person_archive",{p_inst:institutionId,p_kind:kind,p_id:id});
  }
  async directoryOptions(institutionId: number, kind: string, search: string | null, page: PageOptions, ids: number[]) {
    const {data,error} = await db.rpc("admin_directory_options", {p_institution_id:institutionId,p_kind:kind,p_search:search,
      p_page:page.page,p_page_size:page.pageSize,p_include_ids:ids});
    assertNoDbError(error); return data;
  }
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

  async archiveUser(institutionId:number,id:number) {
    return transactionRpc(this.scoped,"admin_account_archive",{p_inst:institutionId,p_id:id});
  }

  async listRoles(institutionId: number | null, page: PageOptions) {
    let query = db
      .from("roles")
      .select("id, institution_id, name, code, description, is_system, active, created_at", {
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

  async listAdminProfiles(institutionId: number, search: string | null, page: PageOptions) {
    const {data,error}=await db.rpc("admin_profiles_page",{p_institution_id:institutionId,p_search:search,p_page:page.page,p_page_size:page.pageSize});
    assertNoDbError(error);return data;
  }

  async directoryCounts(institutionId: number) {
    const {data,error}=await db.rpc("admin_directory_counts",{p_institution_id:institutionId});
    assertNoDbError(error);return data;
  }

  async createRole(payload:Record<string,unknown>) {
    const {institution_id,...changes}=payload;
    return transactionRpc(this.scoped,"admin_role_write",{p_inst:institution_id,p_id:null,p_changes:changes,p_archive:false});
  }

  async updateRole(institutionId:number,id:number,payload:Record<string,unknown>) {
    return transactionRpc(this.scoped,"admin_role_write",{p_inst:institutionId,p_id:id,p_changes:payload,p_archive:false});
  }

  async archiveRole(institutionId:number,id:number) {
    return transactionRpc(this.scoped,"admin_role_write",{p_inst:institutionId,p_id:id,p_changes:{},p_archive:true});
  }

  async listPeopleResource(
    table: "students" | "teachers" | "parents" | "all",
    institutionId: number | null,
    filters: Record<string, unknown> = {},
    page: PageOptions,
  ) {
    const { data, error } = await db.rpc("admin_people_page", {
      p_institution_id: institutionId, p_resource: table, p_search: filters.search ?? null,
      p_active: filters.active ?? null, p_page: page.page, p_page_size: page.pageSize,
      p_id: filters.id ?? null,
      p_group_id: filters.groupId ?? null,
    });
    assertNoDbError(error);
    return data;
  }

  async listDirectory(institutionId: number, kind: string, search: string | null, page: PageOptions, groupId: number | null) {
    const {data,error}=await db.rpc("admin_catalog_page",{p_institution_id:institutionId,p_kind:kind,p_search:search,
      p_page:page.page,p_page_size:page.pageSize,p_group_id:groupId});
    assertNoDbError(error);return data;
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

  async findClasses(institutionId: number, classIds: number[]) {
    const uniqueIds = [...new Set(classIds)];
    if (uniqueIds.length === 0) return [];
    const { data, error } = await db
      .from("classes")
      .select("id, group_id, teacher_id, active")
      .eq("institution_id", institutionId)
      .in("id", uniqueIds)
      .eq("active", true);
    assertNoDbError(error);
    return data ?? [];
  }

  async archiveClass(institutionId: number, id: number) {
    return this.updateClass(institutionId, id, { active: false });
  }
}

export const adminRepository = new AdminRepository();
