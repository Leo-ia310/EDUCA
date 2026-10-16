import { Router } from "express";

import {
  ensureIndividualConversation,
  listContacts,
  listConversations,
  listMessages,
  markConversationAsRead,
  sendMessage,
} from "./chats.controller";
import { authMiddleware } from "../../middleware/auth.middleware";
import { asyncHandler } from "../../middleware/error.middleware";

export const chatsRoutes = Router();

chatsRoutes.use(authMiddleware);
chatsRoutes.post("/messages", asyncHandler(sendMessage));
chatsRoutes.post("/mark-as-read", asyncHandler(markConversationAsRead));
chatsRoutes.patch(
  "/conversations/:conversationId/read",
  asyncHandler(markConversationAsRead),
);
chatsRoutes.get("/conversations", asyncHandler(listConversations));
chatsRoutes.get("/conversations/:conversationId/messages", asyncHandler(listMessages));
chatsRoutes.get("/contacts", asyncHandler(listContacts));
chatsRoutes.post("/individual", asyncHandler(ensureIndividualConversation));

