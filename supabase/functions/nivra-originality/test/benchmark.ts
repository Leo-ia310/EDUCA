import { cpuUsage, memoryUsage } from 'node:process';
import { createRequire } from 'node:module';
import { zipSync, strToU8 } from 'npm:fflate@0.8.3';
import { readDocument, prepareExtraction } from '../generated/extract-core.ts';
import { compareTexts, prepareText } from '../generated/domain.ts';
import { readPdfPage } from '../pdf.ts';
import { limits } from '../step.ts';
const {pdf}=createRequire(import.meta.url)('../../../../backend/test/fixtures/originality-pdf.cjs');
const samples: {stage:string;cpuMs:number;wallMs:number;rssBytes:number}[]=[];
async function measure<T>(stage:string, operation:()=>T|Promise<T>) {
  const start=performance.now(),cpu=cpuUsage();const result=await operation();const used=cpuUsage(cpu);
  samples.push({stage,cpuMs:(used.user+used.system)/1000,wallMs:performance.now()-start,rssBytes:memoryUsage().rss});return result;
}
const small=Array.from({length:80},(_,i)=>'word'+i).join(' ');
const maximum=Array.from({length:20000},(_,i)=>'academicword'+i).join(' ');
await measure('pdf-cold-first-page-80-words',()=>readPdfPage(pdf(small),1,50));
const docx=zipSync({'[Content_Types].xml':strToU8('<Types><Override ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'),
  'word/document.xml':strToU8('<w:document><w:body><w:p><w:r><w:t>'+maximum+'</w:t></w:r></w:p></w:body></w:document>')});
const raw=await measure('docx-read-20000-words',()=>readDocument({...limits,bytes:docx,mime:'application/vnd.openxmlformats-officedocument.wordprocessingml.document'},()=>{throw Error('unexpected PDF');}));
const result=await measure('prepare-20000-words',()=>prepareExtraction(raw.text,raw.binaryHash,limits));
if(result.state!=='completed'||result.academic?.tokens.length!==20000)throw Error('Maximum sample did not complete');
const peer=prepareText(maximum.split(' ').reverse().join(' '));
await measure('compare-three-20000-word-peers',()=>{for(let i=0;i<3;i++)compareTexts(result.academic!,peer);});
const checkpoint={stage:'compare',version:'nivra-1-n5-m40',result:{...result,academic:{...result.academic,fingerprints:[]}},pairs:[],after:0};
await measure('checkpoint-json-roundtrip-20000-words',()=>JSON.parse(JSON.stringify(checkpoint)));
const report={recordedAt:new Date().toISOString(),runtime:Deno.version,
  scope:'Offline Deno on Windows: individual phase CPU and sampled process RSS; not hosted Edge, not peak RSS, not HTTP/SQL latency. PDF sample has one page and 80 words; DOCX and comparison samples have 20000 words.',
  samples,allSampleCpuBelow1500ms:samples.every(s=>s.cpuMs<1500),maxSampledRssBytes:Math.max(...samples.map(s=>s.rssBytes)),hostedValidationRequired:true};
const target=new URL('../../../../docs/performance/originality/supabase-edge-local.json',import.meta.url);
await Deno.writeTextFile(target,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));
