import { HttpError } from '../../lib/errors';
import { asRecord, requiredId } from '../../validators/common.validators';

/** Omission preserves links for legacy callers; an explicit [] replaces with no files. */
export function parseSubmissionFiles(value: unknown): number[] | null {
  if (value == null) return null;
  if (!Array.isArray(value) || value.length > 20) throw new HttpError(400, 'Los adjuntos deben ser una lista de hasta 20 archivos.', 'validation_error');
  return value.map(item => requiredId(asRecord(item).id, 'Archivo'));
}
