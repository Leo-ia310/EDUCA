import assert from 'node:assert/strict';
import { test } from 'node:test';
import { prepareText } from '../src/modules/assignments/originality/domain';
import { originalityConfig } from '../src/modules/assignments/originality/config';
import type { OriginalityRepository, DocumentRow } from '../src/modules/assignments/originality/originality.repository';
process.env.NODE_ENV = 'test'; process.env.SUPABASE_URL = 'https://fixture.supabase.co'; process.env.SUPABASE_ANON_KEY = 'fixture-public';
const { OriginalityWorker } = require('../src/modules/assignments/originality/worker') as typeof import('../src/modules/assignments/originality/worker');
const body = Array.from({length:100},(_,i)=>'word'+i).join(' '), academic = prepareText(body);
type Repo = Pick<OriginalityRepository,'rpc'|'document'|'shared'|'file'|'sourceUrl'|'candidates'>;
function fixture() {
  const calls: {name:string; args:Record<string,unknown>}[] = [];
  const doc: DocumentRow = {id:1,institution_id:1,assignment_id:1,submission_id:1,file_id:null,source_notes:body,academic:null,binary_hash:null,text_hash:null,algorithm_version:'nivra-1',active:true};
  let claimed = false;
  const repo: Repo = {
    async rpc<T>(name:string,args:Record<string,unknown>={}) { calls.push({name,args});
      if(name==='originality_claim') {if(claimed)return null as T;claimed=true;return {id:1,document_id:1,lock_token:'lock',attempts:1,enqueued_at:new Date().toISOString()} as T;} return null as T; },
    document: async()=>doc,shared:async()=>[],file:async()=>{throw new Error('unexpected file');},sourceUrl:async()=>{throw new Error('unexpected download');},
    candidates:async(_doc,_binary,_text,_fps,after)=>after===0?[{...doc,id:2,submission_id:2,academic,text_hash:academic.textHash}]:[],
  };
  return {repo,calls};
}
test('worker drains all candidates, saves later exact match, and admits only one active call',async()=>{
 const f=fixture();let release!:()=>void;
 const gate=new Promise<void>(r=>{release=r;});
 const worker=new OriginalityWorker(f.repo,originalityConfig(),async()=>{await gate;return {state:'completed',binaryHash:null,textHash:academic.textHash,academic,fingerprints:academic.fingerprints};});
 const running=worker.runOnce();await worker.runOnce();release();await running;
 assert.equal(f.calls.filter(c=>c.name==='originality_claim').length,1);
 const finish=f.calls.find(c=>c.name==='originality_finish')!;
 assert.equal((finish.args.p_pairs as {aCoverage:number}[])[0].aCoverage,100);
});
test('analysis failure is sanitized and persisted without touching delivery or grade',async()=>{
 const f=fixture();const worker=new OriginalityWorker(f.repo,originalityConfig(),async()=>{throw new Error('secret text in parser failure');});
 await worker.runOnce();const fail=f.calls.find(c=>c.name==='originality_fail')!;
 assert.equal(fail.args.p_code,'analysis_unavailable');assert.ok(!f.calls.some(c=>c.name==='originality_finish'));
});
test('a 95 percent candidate cannot hide a later 98 percent source',async()=>{
 const f=fixture();
 f.repo.candidates=async(_doc,_binary,_text,_fps,after)=>{
  if(after>=3)return [];
  const kept=after===0?95:98;
  const candidate=prepareText(body.split(' ').slice(0,kept).concat(Array.from({length:100-kept},(_,i)=>'different'+i)).join(' '));
  return [{id:after===0?2:3,institution_id:1,assignment_id:1,submission_id:after===0?2:3,file_id:null,source_notes:null,academic:candidate,binary_hash:null,text_hash:candidate.textHash,algorithm_version:'nivra-1',active:true}];
 };
 await new OriginalityWorker(f.repo,originalityConfig(),async()=>({state:'completed',binaryHash:null,textHash:academic.textHash,academic,fingerprints:academic.fingerprints})).runOnce();
 const pairs=f.calls.find(c=>c.name==='originality_finish')!.args.p_pairs as {aCoverage:number}[];
 assert.deepEqual(pairs.map(p=>p.aCoverage),[95,98]);
});
test('invalid configured limits fail at startup',()=>{
 process.env.ORIGINALITY_NGRAM='200';try {assert.throws(()=>originalityConfig(),/ORIGINALITY_NGRAM/);}finally {delete process.env.ORIGINALITY_NGRAM;}
});
test('binary identity survives insufficient text without inventing textual coverage',async()=>{
 const f=fixture();
 f.repo.candidates=async(_doc,_binary,_text,_fps,after)=>after===0?[{...(await f.repo.document(1)),id:2,submission_id:2,academic:null,binary_hash:'same-binary'}]:[];
 await new OriginalityWorker(f.repo,originalityConfig(),async()=>({state:'insufficient_text',binaryHash:'same-binary',textHash:null,academic:null,fingerprints:[]})).runOnce();
 const pair=(f.calls.find(c=>c.name==='originality_finish')!.args.p_pairs as {binaryIdentical:boolean;aCoverage:number}[])[0];
 assert.equal(pair.binaryIdentical,true);assert.equal(pair.aCoverage,0);
});
