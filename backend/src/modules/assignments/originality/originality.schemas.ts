import { HttpError } from '../../../lib/errors';
import { requiredId } from '../../../validators/common.validators';
export type OriginalityQuery = { submissionId: number; evidence: boolean };
export function parseOriginalityQuery(id: unknown, query: Record<string, unknown>): OriginalityQuery {
  if (Object.keys(query).some(key => key !== 'evidence') || query.evidence != null && (typeof query.evidence !== 'string' || !['true','false'].includes(query.evidence))) throw new HttpError(400, 'Consulta de coincidencias inválida.', 'validation_error');
  return { submissionId: requiredId(id, 'Entrega'), evidence: query.evidence === 'true' };
}
export function parseOriginalityRetry(id: unknown, body: unknown) {
  if (body != null && (typeof body !== 'object' || Array.isArray(body) || Object.keys(body).length)) throw new HttpError(400, 'El cuerpo debe estar vacío.', 'validation_error');
  return requiredId(id, 'Entrega');
}
