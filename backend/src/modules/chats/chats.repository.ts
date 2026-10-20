import { transactionRpc } from "../../lib/transaction-rpc";
import { HttpError } from "../../lib/errors";

import { supabaseAdmin } from "../../lib/supabase";

const db = supabaseAdmin as any;

export class ChatsRepository {
  async sendMessage(args: Record<string, unknown>) {
    return transactionRpc(db,"chat_send_message",args);
  }

  async rpc(name: string, params: Record<string, unknown>) {
    const { data, error } = await db.rpc(name, params);
    if (error) {
      const status = error.code === "42501" ? 403 : error.code === "P0002" ? 404 : error.code === "22023" || error.code === "22007" || error.code === "22008" ? 400 : 503;
      throw new HttpError(status, status === 403 ? "Acceso denegado." : status === 404 ? "Recurso no encontrado." : status === 400 ? "Datos de chat inválidos." : "No se pudo acceder al chat. Intenta nuevamente.", "chat_query_error");
    }
    return data;
  }

  async searchContacts(search: string | null, limit: number) {
    return this.rpc("chat_contacts",{p_search:search,p_limit:limit});
  }
}

export const chatsRepository = new ChatsRepository();
