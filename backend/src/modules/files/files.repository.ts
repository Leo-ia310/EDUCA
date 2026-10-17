import { assertNoDbError, expectSingle } from "../../lib/db";
import { PageOptions, paged } from "../../lib/pagination";
import { currentSupabaseClient, requireSupabaseServiceRole, supabaseAdmin } from "../../lib/supabase";

const db = supabaseAdmin as any;

export class FilesRepository {
  async createSignedUploadUrl(path: string) {
    const client = currentSupabaseClient() as any;
    const { data, error } = await client.storage
      .from("files")
      .createSignedUploadUrl(path);
    assertNoDbError(error);
    return data as Record<string, unknown>;
  }

  /**
   * Registra la metadata con el cliente de servicio. Con el token del usuario, `INSERT ... RETURNING` choca
   * con la política restrictiva `portal_file_read` (migración 0026): su función consulta `files` por id y no
   * ve la fila recién insertada, así que devuelve false y rechaza TODA subida. El servicio ya validó
   * institución, ruta y tipo antes de llegar aquí, y `uploaded_by` sale del contexto autenticado.
   */
  async insertFileMetadata(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      requireSupabaseServiceRole().from("files").insert(payload).select("*").single(),
      "No se pudo guardar el archivo.",
    );
  }

  async findFile(institutionId: number, id: number) {
    const { data, error } = await db
      .from("files")
      .select("id, original_name, storage_path, uploaded_by, mime_type")
      .eq("institution_id", institutionId)
      .eq("id", id)
      .is("deleted_at", null)
      .maybeSingle();
    assertNoDbError(error);
    return (data ?? null) as Record<string, any> | null;
  }

  /** Tareas a las que está adjunto el archivo (con las políticas RLS del usuario aplicadas). */
  async assignmentsOfFile(fileId: number) {
    const { data, error } = await db
      .from("assignment_files")
      .select("assignment_id, assignments!inner(published, deleted_at, classes!inner(group_id))")
      .eq("file_id", fileId);
    assertNoDbError(error);
    return (data ?? []) as Array<Record<string, any>>;
  }

  /** Entregas a las que está adjunto el archivo (con las políticas RLS del usuario aplicadas). */
  async submissionsOfFile(fileId: number) {
    const { data, error } = await db
      .from("submission_files")
      .select("submission_id, submissions!inner(student_id)")
      .eq("file_id", fileId);
    assertNoDbError(error);
    return (data ?? []) as Array<Record<string, any>>;
  }

  async groupIdsOfStudents(institutionId: number, studentIds: number[]) {
    if (studentIds.length === 0) return [] as number[];
    const { data, error } = await db
      .from("enrollments")
      .select("group_id")
      .eq("institution_id", institutionId)
      .in("student_id", studentIds);
    assertNoDbError(error);
    return [...new Set(((data ?? []) as any[]).map((r) => Number(r.group_id)))];
  }

  async childIdsOfParent(parentId: number) {
    const { data, error } = await db.from("parent_students").select("student_id").eq("parent_id", parentId);
    assertNoDbError(error);
    return ((data ?? []) as any[]).map((r) => Number(r.student_id));
  }

  async createSignedDownloadUrl(path: string, seconds: number, downloadName: string) {
    const client = currentSupabaseClient() as any;
    const { data, error } = await client.storage.from("files").createSignedUrl(path, seconds, { download: downloadName });
    assertNoDbError(error);
    return String((data as Record<string, unknown>).signedUrl ?? "");
  }

  async listFiles(institutionId: number, page: PageOptions) {
    const { data, error, count } = await db
      .from("files")
      .select("id, institution_id, original_name, storage_path, url, size_bytes, mime_type, uploaded_by, created_at", {
        count: "exact",
      })
      .eq("institution_id", institutionId)
      .is("deleted_at", null)
      .order("created_at", { ascending: false })
      .range(page.from, page.to);
    assertNoDbError(error);
    return paged(data ?? [], count, page);
  }
}

export const filesRepository = new FilesRepository();
