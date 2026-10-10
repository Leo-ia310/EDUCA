import type { AppContext } from "../../types/app-context";
import { HttpError } from "../../lib/errors";
import {
  businessApiHandlers,
  type BusinessApiHandler,
} from "./business-api.handlers";

export class BusinessApiService {
  constructor(
    private readonly handlers: Record<string, BusinessApiHandler> =
      businessApiHandlers,
  ) {}

  async dispatch(
    ctx: AppContext,
    action: string,
    payload: Record<string, unknown>,
  ) {
    const handler = this.handlers[action];
    if (handler == null) {
      throw new HttpError(404, `Acción no soportada: ${action}`, "not_found");
    }
    return handler(ctx, payload);
  }
}

export const businessApiService = new BusinessApiService();
