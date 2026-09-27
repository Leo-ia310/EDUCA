import { assertNoDbError, expectSingle } from "../lib/db";
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

  async listFiles(institutionId: number) {
    const { data, error } = await db
      .from("files")
      .select("*")
      .eq("institution_id", institutionId)
      .is("deleted_at", null)
      .order("created_at", { ascending: false });
    assertNoDbError(error);
    return data ?? [];
  }
}

export const filesRepository = new FilesRepository();
