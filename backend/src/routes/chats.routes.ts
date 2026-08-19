import { Router } from "express";

import {
  ensureIndividualConversation,
  markConversationAsRead,
  sendMessage,
} from "../controllers/chats.controller";
import { authMiddleware } from "../middleware/auth.middleware";
import { asyncHandler } from "../middleware/error.middleware";

export const chatsRoutes = Router();

chatsRoutes.use(authMiddleware);
chatsRoutes.post("/messages", asyncHandler(sendMessage));
chatsRoutes.post("/mark-as-read", asyncHandler(markConversationAsRead));
chatsRoutes.patch(
  "/conversations/:conversationId/read",
  asyncHandler(markConversationAsRead),
);
chatsRoutes.post("/individual", asyncHandler(ensureIndividualConversation));
