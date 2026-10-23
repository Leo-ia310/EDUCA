import { createClient } from 'npm:@supabase/supabase-js@2.112.3';
import { createWorkerHandler } from './app.ts';
import type { QueuePort } from './step.ts';

const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false, autoRefreshToken: false },
  global: { fetch: (input,init) => fetch(input, { ...init, signal: AbortSignal.timeout(15000) }) },
});
const port: QueuePort = {
  async rpc<T>(name: string, args?: Record<string, unknown>) {
    const { data,error } = await client.rpc(name,args); if (error) throw Error('queue_unavailable'); return data as T;
  },
  async document(id) {
    const { data,error } = await client.from('originality_documents')
      .select('id,institution_id,assignment_id,submission_id,file_id,source_notes').eq('id',id).single();
    if (error) throw Error('document_unavailable'); return data;
  },
  async shared(institution,assignment) {
    const { data,error } = await client.from('assignments').select('instructions,description')
      .eq('institution_id',institution).eq('id',assignment).is('deleted_at',null).single();
    if (error) throw Error('assignment_unavailable'); return [data.instructions ?? '', data.description ?? ''];
  },
  async file(institution,id) {
    const { data,error } = await client.from('files').select('storage_path,mime_type,size_bytes')
      .eq('institution_id',institution).eq('id',id).is('deleted_at',null).single();
    if (error) throw Error('file_unavailable'); return data;
  },
  async sourceUrl(path) {
    const { data,error } = await client.storage.from('files').createSignedUrl(path,60);
    if (error) throw Error('storage_unavailable'); return data.signedUrl;
  },
};
Deno.serve(createWorkerHandler({ secret: Deno.env.get('ORIGINALITY_CRON_SECRET'),
  enabled: Deno.env.get('ORIGINALITY_EDGE_ENABLED') === 'true' }, port));
