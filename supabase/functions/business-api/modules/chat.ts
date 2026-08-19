import { AppContext } from "../shared/auth.ts";
import { expectSingle } from "../shared/db.ts";
import { mapAttachment } from "../shared/files.ts";
import { HttpError } from "../shared/http.ts";
import { db } from "../shared/supabase.ts";
import {
  asRecord,
  optionalId,
  optionalString,
  requiredId,
} from "../shared/validators.ts";

async function assertConversationParticipant(
  ctx: AppContext,
  conversationId: number,
) {
  await expectSingle(
    db
      .from("conversations")
      .select("id")
      .eq("id", conversationId)
      .eq("institution_id", ctx.institutionId)
      .single(),
    "Conversación no encontrada.",
  );
  const { data } = await db
    .from("conversation_participants")
    .select("id")
    .eq("conversation_id", conversationId)
    .eq("user_id", ctx.userId)
    .limit(1);
  if (!data || data.length === 0) {
    throw new HttpError(
      403,
      "No participas en esta conversación.",
      "forbidden",
    );
  }
}

async function hydrateMessage(ctx: AppContext, id: number) {
  const row = await expectSingle<Record<string, unknown>>(
    db
      .from("messages")
      .select(
        "id, uuid, conversation_id, sender_id, content, created_at, files(id, original_name, url, size_bytes, mime_type)",
      )
      .eq("id", id)
      .single(),
    "Mensaje no encontrado.",
  );
  const file = row.files as Record<string, unknown> | null;
  return {
    id: String(row.id),
    uuid: String(row.uuid),
    conversationId: String(row.conversation_id),
    senderId: String(row.sender_id),
    senderName: Number(row.sender_id) === ctx.userId ? ctx.fullName : "Usuario",
    sentAt: String(row.created_at ?? new Date().toISOString()),
    content: row.content ?? null,
    attachment: file == null ? null : mapAttachment(file),
  };
}

export async function sendMessage(
  ctx: AppContext,
  payload: Record<string, unknown>,
) {
  const conversationId = requiredId(payload.conversationId, "Conversación");
  await assertConversationParticipant(ctx, conversationId);
  const content = optionalString(payload.content, 4000);
  const attachment = asRecord(payload.attachment);
  const fileId = optionalId(attachment.id);
  if (content == null && fileId == null) {
    throw new HttpError(
      400,
      "El mensaje necesita texto o adjunto.",
      "validation_error",
    );
  }
  if (fileId != null) {
    await expectSingle(
      db
        .from("files")
        .select("id")
        .eq("id", fileId)
        .eq("institution_id", ctx.institutionId)
        .is("deleted_at", null)
        .single(),
      "Adjunto no encontrado.",
    );
  }

  const row = await expectSingle<Record<string, unknown>>(
    db
      .from("messages")
      .insert({
        uuid: crypto.randomUUID(),
        conversation_id: conversationId,
        sender_id: ctx.userId,
        content,
        file_id: fileId,
      })
      .select("id")
      .single(),
    "No se pudo enviar el mensaje.",
  );
  return { message: await hydrateMessage(ctx, Number(row.id)) };
}

export async function markConversationAsRead(
  ctx: AppContext,
  payload: Record<string, unknown>,
) {
  const conversationId = requiredId(payload.conversationId, "Conversación");
  await assertConversationParticipant(ctx, conversationId);
  const { data: messages, error } = await db
    .from("messages")
    .select("id")
    .eq("conversation_id", conversationId)
    .neq("sender_id", ctx.userId);
  if (error) throw new HttpError(400, error.message, "db_error");
  const rows = (messages ?? []).map((message) => ({
    message_id: Number((message as Record<string, unknown>).id),
    user_id: ctx.userId,
  }));
  if (rows.length > 0) {
    const result = await db
      .from("message_reads")
      .upsert(rows, {
        onConflict: "message_id,user_id",
        ignoreDuplicates: true,
      });
    if (result.error) {
      throw new HttpError(400, result.error.message, "db_error");
    }
  }
  return { ok: true };
}

export async function ensureIndividualConversation(
  ctx: AppContext,
  payload: Record<string, unknown>,
) {
  const otherUserId = requiredId(payload.otherUserId, "Usuario destino");
  if (otherUserId === ctx.userId) {
    throw new HttpError(
      400,
      "No puedes iniciar una conversación contigo mismo.",
      "validation_error",
    );
  }
  await expectSingle(
    db
      .from("users")
      .select("id")
      .eq("id", otherUserId)
      .eq("institution_id", ctx.institutionId)
      .eq("active", true)
      .is("deleted_at", null)
      .single(),
    "Usuario destino no encontrado.",
  );

  const { data: mine } = await db
    .from("conversation_participants")
    .select("conversation_id")
    .eq("user_id", ctx.userId);
  const myIds = (mine ?? []).map((row) =>
    Number((row as Record<string, unknown>).conversation_id)
  );
  if (myIds.length > 0) {
    const { data: theirs } = await db
      .from("conversation_participants")
      .select("conversation_id")
      .eq("user_id", otherUserId)
      .in("conversation_id", myIds);
    const sharedIds = (theirs ?? []).map((row) =>
      Number((row as Record<string, unknown>).conversation_id)
    );
    if (sharedIds.length > 0) {
      const { data: existing } = await db
        .from("conversations")
        .select("id")
        .eq("institution_id", ctx.institutionId)
        .in("id", sharedIds)
        .in("kind", ["individual", "direct"])
        .limit(1)
        .maybeSingle();
      if (existing) return { conversationId: String(existing.id) };
    }
  }

  const created = await expectSingle<Record<string, unknown>>(
    db
      .from("conversations")
      .insert({
        institution_id: ctx.institutionId,
        kind: "individual",
        created_by: ctx.userId,
      })
      .select("id")
      .single(),
    "No se pudo crear la conversación.",
  );
  const conversationId = Number(created.id);
  const result = await db.from("conversation_participants").insert([
    { conversation_id: conversationId, user_id: ctx.userId, role: "member" },
    { conversation_id: conversationId, user_id: otherUserId, role: "member" },
  ]);
  if (result.error) throw new HttpError(400, result.error.message, "db_error");
  return { conversationId: String(conversationId) };
}
