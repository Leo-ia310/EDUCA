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
export function parseOriginalityAssignment(id: unknown, query: unknown) {
  if (query != null && typeof query === 'object' && Object.keys(query).length) throw new HttpError(400, 'Consulta de coincidencias inválida.', 'validation_error');
  return requiredId(id, 'Actividad');
}
export function parseOriginalityTemplate(id: unknown, body: unknown): { assignmentId: number; template: string } {
  if (body == null || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).some(key => key !== 'template')) throw new HttpError(400, 'Cuerpo de plantilla inválido.', 'validation_error');
  const template = (body as { template?: unknown }).template;
  if (typeof template !== 'string' || template.length > 20000) throw new HttpError(400, 'La plantilla debe ser texto de hasta 20.000 caracteres.', 'validation_error');
  return { assignmentId: requiredId(id, 'Actividad'), template };
}
