import type { Response } from "express";

import { requireAppContext } from "../../middleware/auth.middleware";
import { chatsService } from "./chats.service";
import type { AppRequest } from "../../types/app-context";
import { asRecord } from "../../validators/common.validators";

export async function sendMessage(req: AppRequest, res: Response) {
  const data = await chatsService.sendMessage(
    requireAppContext(req),
    asRecord(req.body),
  );
  return res.json({ ok: true, data });
}

export async function markConversationAsRead(req: AppRequest, res: Response) {
  const body = {
    ...asRecord(req.body),
    conversationId: req.params.conversationId ?? req.body?.conversationId,
  };
  const data = await chatsService.markConversationAsRead(
    requireAppContext(req),
    body,
  );
  return res.json({ ok: true, data });
}

export async function ensureIndividualConversation(
  req: AppRequest,
  res: Response,
) {
  const data = await chatsService.ensureIndividualConversation(
    requireAppContext(req),
    asRecord(req.body),
  );
  return res.json({ ok: true, data });
}

export async function listConversations(req: AppRequest, res: Response) {
  const data = await chatsService.listConversations(requireAppContext(req), asRecord(req.query));
  return res.json({ ok: true, data });
}

export async function listMessages(req: AppRequest, res: Response) {
  const data = await chatsService.listMessages(
    requireAppContext(req),
    req.params.conversationId,
    asRecord(req.query),
  );
  return res.json({ ok: true, data });
}

export async function listContacts(req: AppRequest, res: Response) {
  const data = await chatsService.listContacts(requireAppContext(req), asRecord(req.query));
  return res.json({ ok: true, data });
}
