import { assertNoDbError, expectSingle } from "../lib/db";
import { supabaseAdmin } from "../lib/supabase";

const db = supabaseAdmin as any;

export class ChatsRepository {
  async findConversation(institutionId: number, conversationId: number) {
    return expectSingle(
      db
        .from("conversations")
        .select("id")
        .eq("id", conversationId)
        .eq("institution_id", institutionId)
        .single(),
      "Conversación no encontrada.",
    );
  }

  async participantExists(conversationId: number, userId: number) {
    const { data } = await db
      .from("conversation_participants")
      .select("id")
      .eq("conversation_id", conversationId)
      .eq("user_id", userId)
      .limit(1);
    return Array.isArray(data) && data.length > 0;
  }

  async findMessageForHydration(id: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("messages")
        .select(
          "id, uuid, conversation_id, sender_id, content, created_at, files(id, original_name, url, size_bytes, mime_type)",
        )
        .eq("id", id)
        .single(),
      "Mensaje no encontrado.",
    );
  }

  async findInstitutionFile(institutionId: number, fileId: number) {
    return expectSingle(
      db
        .from("files")
        .select("id")
        .eq("id", fileId)
        .eq("institution_id", institutionId)
        .is("deleted_at", null)
        .single(),
      "Adjunto no encontrado.",
    );
  }

  async insertMessage(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db.from("messages").insert(payload).select("id").single(),
      "No se pudo enviar el mensaje.",
    );
  }

  async unreadMessageIds(conversationId: number, userId: number) {
    return db
      .from("messages")
      .select("id")
      .eq("conversation_id", conversationId)
      .neq("sender_id", userId);
  }

  async upsertMessageReads(rows: Array<Record<string, unknown>>) {
    const { error } = await db
      .from("message_reads")
      .upsert(rows, {
        onConflict: "message_id,user_id",
        ignoreDuplicates: true,
      });
    assertNoDbError(error);
  }

  async findActiveUser(institutionId: number, userId: number) {
    return expectSingle(
      db
        .from("users")
        .select("id")
        .eq("id", userId)
        .eq("institution_id", institutionId)
        .eq("active", true)
        .is("deleted_at", null)
        .single(),
      "Usuario destino no encontrado.",
    );
  }

  async conversationIdsForUser(userId: number) {
    const { data } = await db
      .from("conversation_participants")
      .select("conversation_id")
      .eq("user_id", userId);
    return (data ?? []).map((row: Record<string, unknown>) =>
      Number(row.conversation_id)
    );
  }

  async sharedConversationIds(otherUserId: number, conversationIds: number[]) {
    const { data } = await db
      .from("conversation_participants")
      .select("conversation_id")
      .eq("user_id", otherUserId)
      .in("conversation_id", conversationIds);
    return (data ?? []).map((row: Record<string, unknown>) =>
      Number(row.conversation_id)
    );
  }

  async findExistingIndividualConversation(
    institutionId: number,
    conversationIds: number[],
  ) {
    const { data } = await db
      .from("conversations")
      .select("id")
      .eq("institution_id", institutionId)
      .in("id", conversationIds)
      .in("kind", ["individual", "direct"])
      .limit(1)
      .maybeSingle();
    return data;
  }

  async insertConversation(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db.from("conversations").insert(payload).select("id").single(),
      "No se pudo crear la conversación.",
    );
  }

  async insertConversationParticipants(rows: Array<Record<string, unknown>>) {
    const { error } = await db.from("conversation_participants").insert(rows);
    assertNoDbError(error);
  }
}

export const chatsRepository = new ChatsRepository();
