import assert from "node:assert/strict";
import { ChatsService } from "../src/modules/chats/chats.service";
import type { ChatsRepository } from "../src/modules/chats/chats.repository";
import type { NotificationsService } from "../src/modules/notifications/notifications.service";
import type { AppContext } from "../src/types/app-context";

const ctx = { institutionId: 7, userId: 42 } as AppContext;
const receipts = new Map<number, Record<string, unknown>>();
let participant = true;
let failNotifications = false;
let failReads = false;
let notified = 0;
let cutoff = "";
const repository = {
  async findConversation(institutionId: number, conversationId: number) {
    assert.equal(institutionId, 7);
    assert.equal(conversationId, 10);
    return { id: 10 };
  },
  async participantExists(conversationId: number, userId: number) {
    assert.equal(conversationId, 10);
    assert.equal(userId, 42);
    return participant;
  },
  async unreadMessageIds(conversationId: number, userId: number, readAt: string) {
    assert.equal(conversationId, 10);
    assert.equal(userId, 42);
    assert.ok(Number.isFinite(Date.parse(readAt)));
    cutoff = readAt;
    return { data: [{ id: 100 }, { id: 101 }], error: null };
  },
  async upsertMessageReads(rows: Array<Record<string, unknown>>) {
    if (failReads) throw new Error("receipts failed");
    for (const row of rows) {
      assert.equal(row.user_id, ctx.userId, "Ignore any user supplied by the caller");
      assert.equal(row.read_at, cutoff);
      if (!receipts.has(Number(row.message_id))) receipts.set(Number(row.message_id), row);
    }
  },
} as unknown as ChatsRepository;
const notifications = {
  async markConversationRead(context: AppContext, conversationId: number, readAt: string) {
    assert.equal(context, ctx);
    assert.equal(conversationId, 10);
    assert.equal(readAt, cutoff, "Notifications and receipts use the same cutoff");
    if (failNotifications) throw new Error("notifications failed");
    notified++;
  },
} as unknown as NotificationsService;

async function main() {
  const service = new ChatsService(repository, notifications);
  const payload = { conversationId: 10, userId: 999 };
  const result = await service.markConversationAsRead(ctx, payload);
  assert.equal(result.ok, true);
  assert.equal(result.conversationId, "10");
  assert.equal(receipts.size, 2);
  await service.markConversationAsRead(ctx, payload);
  assert.equal(receipts.size, 2, "Repeated reads are idempotent");
  assert.equal(notified, 2);
  participant = false;
  await assert.rejects(service.markConversationAsRead(ctx, payload), /No participas/);
  assert.equal(notified, 2);
  participant = true;
  failNotifications = true;
  await assert.rejects(service.markConversationAsRead(ctx, payload), /notifications failed/);
  failNotifications = false;
  failReads = true;
  await assert.rejects(service.markConversationAsRead(ctx, payload), /receipts failed/);
  assert.equal(notified, 2);
  console.log("Chat read checks passed: participant, tenant, authenticated user, timestamps, idempotence and retryable failures.");
}

void main();
