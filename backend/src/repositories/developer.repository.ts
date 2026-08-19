import { assertNoDbError, expectSingle } from "../lib/db";
import { supabaseAdmin } from "../lib/supabase";

const db = supabaseAdmin as any;

export type DeveloperTable =
  | "developer_dashboard_modules"
  | "developer_api_registry"
  | "developer_tasks"
  | "developer_feature_flags"
  | "developer_system_checks";

export class DeveloperRepository {
  async summaryCounts() {
    const [
      institutions,
      users,
      modules,
      pendingApis,
      openTasks,
      featureFlags,
      failingChecks,
    ] = await Promise.all([
      this.count("institutions", (query) =>
        query.eq("active", true).is("deleted_at", null)
      ),
      this.count("users", (query) =>
        query.eq("active", true).is("deleted_at", null)
      ),
      this.count("developer_dashboard_modules", (query) =>
        query.eq("enabled", true).is("deleted_at", null)
      ),
      this.count("developer_api_registry", (query) =>
        query.eq("frontend_status", "pending").is("deleted_at", null)
      ),
      this.count("developer_tasks", (query) =>
        query.in("status", ["pending", "ready", "in_progress", "blocked"])
          .is("deleted_at", null)
      ),
      this.count("developer_feature_flags", (query) =>
        query.is("deleted_at", null)
      ),
      this.count("developer_system_checks", (query) =>
        query.in("status", ["warning", "failing"]).is("deleted_at", null)
      ),
    ]);

    return {
      institutions,
      users,
      modules,
      pendingApis,
      openTasks,
      featureFlags,
      failingChecks,
    };
  }

  async listPendingTasks(limit = 10) {
    const { data, error } = await db
      .from("developer_tasks")
      .select("*")
      .in("status", ["pending", "ready", "in_progress", "blocked"])
      .is("deleted_at", null)
      .order("priority", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(limit);
    assertNoDbError(error);
    return data ?? [];
  }

  async listRecentAuditEvents(limit = 10) {
    const { data, error } = await db
      .from("developer_audit_events")
      .select("*")
      .order("created_at", { ascending: false })
      .limit(limit);
    assertNoDbError(error);
    return data ?? [];
  }

  async listInstitutions() {
    const { data, error } = await db
      .from("institutions")
      .select(
        "id, code, name, commercial_name, subdomain, email, active, timezone, created_at, updated_at",
      )
      .is("deleted_at", null)
      .order("name");
    assertNoDbError(error);
    return data ?? [];
  }

  async listUsers() {
    const { data, error } = await db
      .from("users")
      .select(
        "id, institution_id, email, full_name, active, last_sign_in, created_at, updated_at, user_roles(roles(code, name))",
      )
      .is("deleted_at", null)
      .order("full_name");
    assertNoDbError(error);
    return data ?? [];
  }

  async list(table: DeveloperTable, filters: Record<string, unknown> = {}) {
    let query = db.from(table).select("*").is("deleted_at", null);
    query = this.applyFilters(query, filters);
    const { data, error } = await query.order("created_at", {
      ascending: false,
    });
    assertNoDbError(error);
    return data ?? [];
  }

  async findById(table: DeveloperTable, id: number) {
    return expectSingle<Record<string, unknown>>(
      db.from(table).select("*").eq("id", id).is("deleted_at", null).single(),
      "Registro no encontrado.",
    );
  }

  async create(table: DeveloperTable, payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db.from(table).insert(payload).select("*").single(),
      "No se pudo crear el registro.",
    );
  }

  async update(
    table: DeveloperTable,
    id: number,
    payload: Record<string, unknown>,
  ) {
    return expectSingle<Record<string, unknown>>(
      db
        .from(table)
        .update(payload)
        .eq("id", id)
        .is("deleted_at", null)
        .select("*")
        .single(),
      "No se pudo actualizar el registro.",
    );
  }

  async archive(table: DeveloperTable, id: number, userId: number) {
    return this.update(table, id, {
      deleted_at: new Date().toISOString(),
      updated_by: userId,
    });
  }

  async audit(payload: Record<string, unknown>) {
    const { error } = await db.from("developer_audit_events").insert(payload);
    assertNoDbError(error);
  }

  private async count(
    table: string,
    configure: (query: any) => any = (query) => query,
  ) {
    const { count, error } = await configure(
      db.from(table).select("id", { count: "exact", head: true }),
    );
    assertNoDbError(error);
    return count ?? 0;
  }

  private applyFilters(query: any, filters: Record<string, unknown>) {
    let next = query;
    for (const [key, value] of Object.entries(filters)) {
      if (value == null || value === "") continue;
      next = next.eq(key, value);
    }
    return next;
  }
}

export const developerRepository = new DeveloperRepository();
