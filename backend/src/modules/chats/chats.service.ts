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

