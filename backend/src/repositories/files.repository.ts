import { assertNoDbError, expectSingle } from "../lib/db";
import { PageOptions, paged } from "../lib/pagination";
import { currentSupabaseClient, supabaseAdmin } from "../lib/supabase";

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

  async insertFileMetadata(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db.from("files").insert(payload).select("*").single(),
      "No se pudo guardar el archivo.",
    );
  }

  async listFiles(institutionId: number, page: PageOptions) {
    const { data, error, count } = await db
      .from("files")
      .select("id, institution_id, original_name, storage_path, url, size_bytes, mime_type, uploaded_by, created_at, updated_at", {
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
