import { randomUUID } from "node:crypto";

import { assertNoDbError } from "../../lib/db";
import { HttpError } from "../../lib/errors";
import { mapAttachment } from "../../lib/files";
import {
  asRecord,
  optionalId,
  optionalString,
  requiredId,
} from "../../validators/common.validators";
import {
  chatsRepository,
  ChatsRepository,
} from "./chats.repository";
import type { AppContext } from "../../types/app-context";
import { notificationsService, NotificationsService } from "../notifications/notifications.service";

export class ChatsService {
  constructor(
    private readonly repository: ChatsRepository = chatsRepository,
    private readonly notifications: NotificationsService = notificationsService,
  ) {}

  async sendMessage(ctx: AppContext, payload: Record<string, unknown>) {
    const conversationId = requiredId(payload.conversationId, "Conversación");
    await this.assertConversationParticipant(ctx, conversationId);
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
      await this.repository.findInstitutionFile(ctx.institutionId, fileId);
    }

    const row = await this.repository.insertMessage({
      uuid: randomUUID(),
      conversation_id: conversationId,
      sender_id: ctx.userId,
      content,
      file_id: fileId,
    });
    await this.notifyRecipients(ctx, conversationId, Number(row.id), content);
    return { message: await this.hydrateMessage(ctx, Number(row.id)) };
  }

  /** Notificación real (y push) para los demás participantes del chat. */
  private async notifyRecipients(
    ctx: AppContext,
    conversationId: number,
    messageId: number,
    content: string | null,
  ) {
    try {
      const recipients = await this.repository.otherParticipantIds(
        conversationId,
        ctx.userId,
      );
      const preview = content == null || content.trim() === ""
        ? "Te envió un adjunto"
        : content.trim().length > 140
        ? `${content.trim().slice(0, 137)}...`
        : content.trim();
      await notificationsService.notifyUsers(ctx, recipients, {
        typeCode: "MSG",
        title: ctx.fullName || "Nuevo mensaje",
        message: preview,
        data: {
          module: "chat",
          conversationId,
          messageId,
          deepLink: `/chat/${conversationId}`,
        },
      });
    } catch (error) {
      // El mensaje ya se guardó: no se pierde por un fallo de notificación.
      console.error({
        level: "warn",
        event: "chat_notification_failed",
        conversationId,
        messageId,
        error,
      });
    }
  }

  async markConversationAsRead(
    ctx: AppContext,
    payload: Record<string, unknown>,
  ) {
    const conversationId = requiredId(payload.conversationId, "Conversación");
    await this.assertConversationParticipant(ctx, conversationId);
    const readAt = new Date().toISOString();
    const { data: messages, error } = await this.repository.unreadMessageIds(
      conversationId,
      ctx.userId,
      readAt,
    );
    if (error) throw new HttpError(400, error.message, "db_error");
    const rows = (messages ?? []).map((message: Record<string, unknown>) => ({
      message_id: Number(message.id),
      user_id: ctx.userId,
      read_at: readAt,
    }));
    if (rows.length > 0) {
      await this.repository.upsertMessageReads(rows);
    }
    // La notificación de esos mensajes deja de estar pendiente.
    await this.notifications.markConversationRead(ctx, conversationId, readAt);
    return { ok: true, conversationId: String(conversationId), readAt };
  }

  async ensureIndividualConversation(
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
    await this.repository.findActiveUser(ctx.institutionId, otherUserId);

    const myIds = await this.repository.conversationIdsForUser(ctx.userId);
    if (myIds.length > 0) {
      const sharedIds = await this.repository.sharedConversationIds(
        otherUserId,
        myIds,
      );
      if (sharedIds.length > 0) {
        const existing =
          await this.repository.findExistingIndividualConversation(
            ctx.institutionId,
            sharedIds,
          );
        if (existing) return { conversationId: String(existing.id) };
      }
    }

    const created = await this.repository.insertConversation({
      institution_id: ctx.institutionId,
      kind: "individual",
      created_by: ctx.userId,
    });
    const conversationId = Number(created.id);
    // RLS en `conversation_participants` permite insertar al usuario actual y
    // permite agregar otros usuarios solo después de que la conversación ya sea
    // visible como propia. Por eso los inserts deben ser secuenciales.
    await this.repository.insertConversationParticipants([
      { conversation_id: conversationId, user_id: ctx.userId, role: "member" },
    ]);
    await this.repository.insertConversationParticipants([
      { conversation_id: conversationId, user_id: otherUserId, role: "member" },
    ]);
    return { conversationId: String(conversationId) };
  }

  // ---------- Lectura (panel web) ----------

  private roleOfUser(u: any) {
    const codes = ((u?.user_roles ?? []) as any[]).map((r) => r?.roles?.code).filter(Boolean) as string[];
    return codes[0] ?? "student";
  }

  /** Conversaciones del usuario con participantes, último mensaje y no leídos. */
  async listConversations(ctx: AppContext) {
    const convs = await this.repository.conversationsOfUser(ctx.institutionId, ctx.userId);
    const ids = convs.map((c: any) => Number(c.id));
    const [participants, incoming, lastRows] = await Promise.all([
      this.repository.participantsOf(ids),
      this.repository.incomingMessageIds(ids, ctx.userId),
      Promise.all(ids.map((id) => this.repository.lastMessageOf(id))),
    ]);
    const readSet = await this.repository.readMessageIds(ctx.userId, incoming.map((m) => Number(m.id)));
    const unread = new Map<number, number>();
    for (const m of incoming) {
      if (!readSet.has(Number(m.id))) unread.set(Number(m.conversation_id), (unread.get(Number(m.conversation_id)) ?? 0) + 1);
    }
    const lastById = new Map<number, Record<string, unknown>>();
    for (const row of lastRows) if (row) lastById.set(Number(row.conversation_id), row);

    const conversations = convs.map((c: any) => {
      const id = Number(c.id);
      const people = (participants as any[])
        .filter((p) => Number(p.conversation_id) === id)
        .map((p) => ({
          userId: String(p.user_id),
          name: String(p.users?.full_name ?? "—"),
          role: this.roleOfUser(p.users),
          avatarUrl: p.users?.avatar_url ?? null,
          isMe: Number(p.user_id) === ctx.userId,
        }));
      const last = lastById.get(id) as any;
      const title = c.title && String(c.title).length > 0
        ? String(c.title)
        : people.filter((p) => !p.isMe).map((p) => p.name).join(", ");
      return {
        id: String(id),
        kind: c.kind === "group" ? "group" : "individual",
        title,
        participants: people,
        lastMessage: last
          ? {
            id: String(last.id),
            senderId: String(last.sender_id),
            senderName: people.find((p) => p.userId === String(last.sender_id))?.name ?? "Usuario",
            content: last.content ?? null,
            hasAttachment: last.file_id != null,
            sentAt: String(last.created_at),
          }
          : null,
        unreadCount: unread.get(id) ?? 0,
        updatedAt: String(last?.created_at ?? c.created_at),
      };
    });
    conversations.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
    return { conversations };
  }

  /** Mensajes de una conversación (los últimos `limit`), con nombre del remitente y quién los leyó. */
  async listMessages(ctx: AppContext, conversationIdValue: unknown, query: Record<string, unknown>) {
    const conversationId = requiredId(conversationIdValue, "Conversación");
    await this.assertConversationParticipant(ctx, conversationId);
    const limit = Math.min(Math.max(Number(query.limit ?? 100) || 100, 1), 300);
    const [rows, participants] = await Promise.all([
      this.repository.messagesOf(conversationId, limit),
      this.repository.participantsOf([conversationId]),
    ]);
    const names = new Map<string, string>();
    for (const p of participants as any[]) names.set(String(p.user_id), String(p.users?.full_name ?? "Usuario"));
    const reads = await this.repository.messageReadsOf(rows.map((r) => Number(r.id)));
    const readers = new Map<number, Set<string>>();
    for (const r of reads) {
      const set = readers.get(Number(r.message_id)) ?? new Set<string>();
      set.add(String(r.user_id));
      readers.set(Number(r.message_id), set);
    }
    return {
      messages: (rows as any[]).map((row) => {
        const sender = String(row.sender_id);
        const seenBy = [...(readers.get(Number(row.id)) ?? [])].filter((u) => u !== sender);
        return {
          id: String(row.id),
          uuid: String(row.uuid),
          conversationId: String(row.conversation_id),
          senderId: sender,
          senderName: names.get(sender) ?? "Usuario",
          sentAt: String(row.created_at ?? ""),
          content: row.content ?? null,
          attachment: row.files == null ? null : mapAttachment(row.files),
          /** Otro participante ya lo leyó. */
          read: seenBy.length > 0,
        };
      }),
    };
  }

  /** Personas de la institución con las que se puede iniciar una conversación. */
  async listContacts(ctx: AppContext, query: Record<string, unknown>) {
    const needle = (optionalString(query.q ?? query.query, 80) ?? "").toLowerCase();
    const rows = await this.repository.searchContacts(ctx.institutionId, ctx.userId);
    const contacts = (rows as any[])
      .map((u) => ({
        userId: String(u.id),
        name: String(u.full_name ?? "—"),
        email: u.email ?? null,
        role: this.roleOfUser(u),
        avatarUrl: u.avatar_url ?? null,
      }))
      .filter((c) => !needle || c.name.toLowerCase().includes(needle) || c.role.toLowerCase().includes(needle))
      .slice(0, 40);
    return { contacts };
  }

  private async assertConversationParticipant(
    ctx: AppContext,
    conversationId: number,
  ) {
    await this.repository.findConversation(ctx.institutionId, conversationId);
    const participant = await this.repository.participantExists(
      conversationId,
      ctx.userId,
    );
    if (!participant) {
      throw new HttpError(
        403,
        "No participas en esta conversación.",
        "forbidden",
      );
    }
  }

  private async hydrateMessage(ctx: AppContext, id: number) {
    const row = await this.repository.findMessageForHydration(id);
    const file = row.files as Record<string, unknown> | null;
    return {
      id: String(row.id),
      uuid: String(row.uuid),
      conversationId: String(row.conversation_id),
      senderId: String(row.sender_id),
      senderName: Number(row.sender_id) === ctx.userId
        ? ctx.fullName
        : "Usuario",
      sentAt: String(row.created_at ?? new Date().toISOString()),
      content: row.content ?? null,
      attachment: file == null ? null : mapAttachment(file),
    };
  }
}

export const chatsService = new ChatsService();

