import type { Response } from "express";
import { requireAppContext } from "../../middleware/auth.middleware";
import { eventsService } from "./events.service";
import type { AppRequest } from "../../types/app-context";
import { asRecord } from "../../validators/common.validators";
export async function listAnnouncements(req: AppRequest, res: Response) {
    const data = await eventsService.listAnnouncements(requireAppContext(req), asRecord(req.query));
    return res.json({ ok: true, data });
}
export async function createEvent(req: AppRequest, res: Response) {
    const data = await eventsService.createEvent(requireAppContext(req), asRecord(req.body));
    return res.status(202).json({ ok: true, data });
}
export async function retryDelivery(req: AppRequest, res: Response) {
    const data = await eventsService.retryDelivery(requireAppContext(req), String(req.params.id));
    return res.status(202).json({ ok: true, data });
}
export async function deliveryStates(req: AppRequest, res: Response) {
    return res.json({ ok: true, data: await eventsService.deliveryStates(requireAppContext(req), asRecord(req.query)) });
}
