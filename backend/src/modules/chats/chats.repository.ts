import { assertNoDbError, expectSingle } from "../../lib/db";
import { supabaseAdmin } from "../../lib/supabase";

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
    const { data, error } = await db
      .from("conversation_participants")
      .select("id")
      .eq("conversation_id", conversationId)
      .eq("user_id", userId)
      .limit(1);
    assertNoDbError(error);
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

  /** Usuarios de la conversación distintos de [userId]. */
  async otherParticipantIds(conversationId: number, userId: number) {
    const { data, error } = await db
      .from("conversation_participants")
      .select("user_id")
      .eq("conversation_id", conversationId)
      .neq("user_id", userId);
    assertNoDbError(error);
    return ((data ?? []) as Array<Record<string, unknown>>).map((row) =>
      Number(row.user_id)
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

  async unreadMessageIds(conversationId: number, userId: number, readAt: string) {
    return db
      .from("messages")
      .select("id")
      .eq("conversation_id", conversationId)
      .neq("sender_id", userId)
      .lte("created_at", readAt);
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

  // ---------- Lectura (panel web) ----------

  /** Conversaciones del usuario de la institución, con su tipo y título. */
  async conversationsOfUser(institutionId: number, userId: number) {
    const { data, error } = await db
      .from("conversation_participants")
      .select("conversation_id, conversations!inner(id, kind, title, created_at, institution_id)")
      .eq("user_id", userId)
      .eq("conversations.institution_id", institutionId);
    assertNoDbError(error);
    return ((data ?? []) as Array<Record<string, any>>).map((r) => r.conversations as Record<string, unknown>);
  }

  async participantsOf(conversationIds: number[]) {
    if (conversationIds.length === 0) return [] as Array<Record<string, unknown>>;
    const { data, error } = await db
      .from("conversation_participants")
      .select("conversation_id, user_id, users(id, full_name, avatar_url, user_roles(roles(code)))")
      .in("conversation_id", conversationIds);
    assertNoDbError(error);
    return (data ?? []) as Array<Record<string, unknown>>;
  }

  async lastMessageOf(conversationId: number) {
    const { data, error } = await db
      .from("messages")
      .select("id, conversation_id, sender_id, content, file_id, created_at")
      .eq("conversation_id", conversationId)
      .order("created_at", { ascending: false })
      .limit(1);
    assertNoDbError(error);
    return ((data ?? [])[0] ?? null) as Record<string, unknown> | null;
  }

  /** Mensajes ajenos de varias conversaciones (para contar no leídos). */
  async incomingMessageIds(conversationIds: number[], userId: number) {
    if (conversationIds.length === 0) return [] as Array<Record<string, unknown>>;
    const { data, error } = await db
      .from("messages")
      .select("id, conversation_id")
      .in("conversation_id", conversationIds)
      .neq("sender_id", userId);
    assertNoDbError(error);
    return (data ?? []) as Array<Record<string, unknown>>;
  }

  async readMessageIds(userId: number, messageIds: number[]) {
    if (messageIds.length === 0) return new Set<number>();
    const { data, error } = await db
      .from("message_reads")
      .select("message_id")
      .eq("user_id", userId)
      .in("message_id", messageIds);
    assertNoDbError(error);
    return new Set(((data ?? []) as Array<Record<string, unknown>>).map((r) => Number(r.message_id)));
  }

  async messagesOf(conversationId: number, limit: number) {
    const { data, error } = await db
      .from("messages")
      .select("id, uuid, conversation_id, sender_id, content, created_at, files(id, original_name, url, size_bytes, mime_type)")
      .eq("conversation_id", conversationId)
      .order("created_at", { ascending: false })
      .limit(limit);
    assertNoDbError(error);
    return ((data ?? []) as Array<Record<string, unknown>>).reverse();
  }

  async messageReadsOf(messageIds: number[]) {
    if (messageIds.length === 0) return [] as Array<Record<string, unknown>>;
    const { data, error } = await db
      .from("message_reads")
      .select("message_id, user_id")
      .in("message_id", messageIds);
    assertNoDbError(error);
    return (data ?? []) as Array<Record<string, unknown>>;
  }

  async searchContacts(institutionId: number, userId: number) {
    const { data, error } = await db
      .from("users")
      .select("id, full_name, email, avatar_url, user_roles(roles(code))")
      .eq("institution_id", institutionId)
      .eq("active", true)
      .is("deleted_at", null)
      .neq("id", userId)
      .order("full_name")
      .limit(300);
    assertNoDbError(error);
    return (data ?? []) as Array<Record<string, unknown>>;
  }
}

export const chatsRepository = new ChatsRepository();

