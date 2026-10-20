


import { HttpError } from "../../lib/errors";

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


export class ChatsService {
  constructor(
    private readonly repository: ChatsRepository = chatsRepository,
  ) {}

  async sendMessage(_ctx: AppContext, payload: Record<string, unknown>) {
    const conversationId = requiredId(payload.conversationId, "Conversación");
    const requestId = optionalString(payload.requestId, 36);
    if (requestId == null || !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(requestId)) {
      throw new HttpError(400, "El mensaje necesita un UUID v4 estable para reintentar.", "validation_error");
    }
    const message = await this.repository.sendMessage({p_conversation_id: conversationId, p_uuid:requestId,
      p_content:optionalString(payload.content,4000),p_file_id:optionalId(asRecord(payload.attachment).id)});
    return { message };
  }

  async markConversationAsRead(
    ctx: AppContext,
    payload: Record<string, unknown>,
  ) {
    const conversationId = requiredId(payload.conversationId, "Conversación");
    return this.repository.rpc("chat_mark_read", { p_conversation_id: conversationId });
  }

  async ensureIndividualConversation(ctx: AppContext, payload: Record<string, unknown>) {
    const otherUserId = requiredId(payload.otherUserId, "Usuario destino");
    const id = await this.repository.rpc("chat_ensure_individual", { p_other_user_id: otherUserId });
    return { conversationId: String(id) };
  }

  // ---------- Lectura (panel web) ----------

  private pageLimit(value: unknown, fallback: number, max: number) {
    const n = requiredId(value ?? fallback,"Límite");
    if (!Number.isInteger(n) || n < 1 || n > max) throw new HttpError(400, "Límite inválido.", "validation_error");
    return n;
  }

  private cursorId(value: unknown) {
    if (value == null || value === "") return null;
    const raw = String(value);
    if (!/^[1-9][0-9]{0,18}$/.test(raw) || BigInt(raw) > 9223372036854775807n) throw new HttpError(400, "Cursor inválido.", "validation_error");
    return raw;
  }

  async listConversations(ctx: AppContext, query: Record<string, unknown> = {}) {
    const after = optionalString(query.afterUpdatedAt, 40);
    if (after != null && !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(after)) throw new HttpError(400, "Cursor inválido.", "validation_error");
    return this.repository.rpc("chat_conversations", {
      p_limit: this.pageLimit(query.limit, 50, 100), p_after_updated_at: after,
      p_after_id: this.cursorId(query.afterId), p_conversation_id: optionalId(query.conversationId),
      p_search: optionalString(query.q, 100),
    });
  }

  async listMessages(ctx: AppContext, conversationIdValue: unknown, query: Record<string, unknown>) {
    return this.repository.rpc("chat_messages", {
      p_conversation_id: requiredId(conversationIdValue, "Conversación"),
      p_limit: this.pageLimit(query.limit, 100, 300), p_before_id: this.cursorId(query.beforeId),
      p_after_id: this.cursorId(query.afterId),
      p_message_id: this.cursorId(query.messageId),
    });
  }

  /** Personas de la institución con las que se puede iniciar una conversación. */
  async listContacts(ctx: AppContext, query: Record<string, unknown>) {
    return this.repository.searchContacts(optionalString(query.q ?? query.query,100),this.pageLimit(query.limit,40,100));
  }

}

export const chatsService = new ChatsService();
