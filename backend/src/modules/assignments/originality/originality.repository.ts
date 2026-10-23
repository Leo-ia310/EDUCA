import { supabaseAdmin } from '../../../lib/supabase';
import { assertNoDbError } from '../../../lib/db';
import type { AcademicText } from './domain';
export type DocumentRow = { id: number; institution_id: number; assignment_id: number; submission_id: number; file_id: number | null; source_notes: string | null; academic: AcademicText | null; binary_hash: string | null; text_hash: string | null; algorithm_version: string; active: boolean; };
export type Job = { id: number; document_id: number; lock_token: string; attempts: number; enqueued_at: string };

export class OriginalityRepository {
  private queryCount = 0;
  get databaseRequests() { return this.queryCount; }
  constructor(private readonly client = supabaseAdmin) {}
  async rpc<T>(name: string, args: Record<string, unknown> = {}): Promise<T> {
    this.queryCount++;
    const { data, error } = await this.client.rpc(name, args); assertNoDbError(error); return data as T;
  }
  report(submissionId: number, evidence: boolean, retry: boolean) {
    return this.rpc('originality_report', { p_submission: submissionId, p_evidence: evidence, p_retry: retry });
  }
  async document(id: number): Promise<DocumentRow> {
    this.queryCount++;
    const { data, error } = await this.client.from('originality_documents').select('*').eq('id', id).single();
    assertNoDbError(error); return data as DocumentRow;
  }
  async file(institution: number, id: number) {
    this.queryCount++;
    const { data, error } = await this.client.from('files').select('storage_path,mime_type,size_bytes').eq('institution_id', institution).eq('id', id).is('deleted_at', null).single();
    assertNoDbError(error); return data as { storage_path: string; mime_type: string; size_bytes: number };
  }
  async shared(institution: number, assignment: number): Promise<string[]> {
    this.queryCount++;
    const { data, error } = await this.client.from('assignments').select('instructions,description').eq('institution_id', institution).eq('id', assignment).is('deleted_at', null).single();
    assertNoDbError(error); return [data?.instructions ?? '', data?.description ?? ''];
  }
  async sourceUrl(path: string) {
    const { data, error } = await this.client.storage.from('files').createSignedUrl(path, 60); assertNoDbError(error); return data!.signedUrl;
  }
  async candidates(doc: DocumentRow, binaryHash: string | null, textHash: string | null, fingerprints: string[], after: number): Promise<DocumentRow[]> {
    return this.rpc('originality_candidates', { p_document: doc.id, p_binary: binaryHash, p_text: textHash, p_fingerprints: fingerprints, p_after: after, p_version: doc.algorithm_version });
  }
}
