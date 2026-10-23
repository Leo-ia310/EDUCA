// Offline fixture only. Requires npm run build. Never loads production credentials.
process.env.NODE_ENV='test';process.env.SUPABASE_URL='https://fixture.supabase.co';process.env.SUPABASE_ANON_KEY='fixture-public';
global.fetch=async()=>{throw new Error('Network disabled in originality benchmark');};
const assert=require('node:assert/strict');
const {performance}=require('node:perf_hooks');
const {cpus,totalmem,platform}=require('node:os');
const {writeFileSync,mkdirSync}=require('node:fs');
const {join}=require('node:path');
const {gzipSync}=require('node:zlib');
const {prepareText,compareTexts}=require('../dist/modules/assignments/originality/domain');
const {isolatedExtraction}=require('../dist/modules/assignments/originality/worker');
async function main(){
 const start=performance.now(),cpu=process.cpuUsage(),times=[];let comparisons=0;
 for(let cls=0;cls<5;cls++){
  const index=new Map(),docs=[];
  for(let i=0;i<40;i++){
   const t=performance.now(),source=i===38?0:i;
   const text=Array.from({length:400},(_,j)=>`class${cls}student${source}word${j}`).join(' ');
   const doc=prepareText(text),candidates=new Set();
   for(const fingerprint of doc.fingerprints)for(const id of index.get(fingerprint)??[])candidates.add(id);
   for(const id of candidates){const pair=compareTexts(doc,docs[id]);comparisons++;if(i===38)assert.equal(pair.aCoverage,100);}
   for(const fingerprint of doc.fingerprints){const list=index.get(fingerprint)??[];list.push(i);index.set(fingerprint,list);}
   docs.push(doc);times.push(performance.now()-t);
  }
 }
 const notes=Array.from({length:20000},(_,i)=>'academicword'+i).join(' ');
 const input={notes,maxBytes:5*1024*1024,maxPages:50,maxWords:20000,minWords:40,ngram:5};
 const beforeThread=performance.now();const result=await isolatedExtraction(input,30000);
 assert.equal(result.state,'completed');
 await assert.rejects(isolatedExtraction(input,1),/extraction_timeout/);
 times.sort((a,b)=>a-b);
 const profile=process.env.ORIGINALITY_BENCHMARK_PROFILE??'unlimited-local';
 const academicJson=JSON.stringify({...result.academic,fingerprints:[]});
 const fingerprintsJson=JSON.stringify(result.fingerprints);
 const persistedJson=JSON.stringify({academic:{...result.academic,fingerprints:[]},fingerprints:result.fingerprints});
 const data={date:new Date().toISOString(),profile,environment:{platform:platform(),logicalCpus:cpus().length,totalMemoryBytes:totalmem(),node:process.version,parentOldSpaceLimitMb:160,extractionOldSpaceLimitMb:160,extractionV8HeapLimitBytes:result.runtime.heapSizeLimitBytes,renderEquivalent:false},
  fixtures:{classes:5,studentsPerClass:40,wordsPerDocument:400,lateMatchStudent:39,maxWordsExtraction:20000},
  comparisons,p50Ms:times[Math.floor(times.length*.5)],p95Ms:times[Math.floor(times.length*.95)],maxMs:times.at(-1),
  isolatedExtractionMs:performance.now()-beforeThread,durationMs:performance.now()-start,cpuMicros:process.cpuUsage(cpu),rssBytes:process.memoryUsage().rss,maxRssKb:process.resourceUsage().maxRSS,
  storageSample:{words:20000,academicJsonBytes:Buffer.byteLength(academicJson),fingerprintsJsonBytes:Buffer.byteLength(fingerprintsJson),combinedJsonBytes:Buffer.byteLength(persistedJson),gzipAlternativeBytes:gzipSync(persistedJson).length,normalizedTextGzipBytes:gzipSync(result.academic.normalized).length,note:'Synthetic fixture. JSON/gzip sizes only; PostgreSQL TOAST/GIN physical bytes require staging measurements.'},
  limitation:'Offline algorithm/index simulation and bounded thread; not HTTP/PostgreSQL/Render load or a 512MB cgroup. API p95 under load remains to be measured.'};
 const dir=join(__dirname,'../../docs/performance/originality');mkdirSync(dir,{recursive:true});writeFileSync(join(dir,profile==='limited'?'limited-benchmark.json':'local-benchmark.json'),JSON.stringify(data,null,2)+'\n');console.log(JSON.stringify(data));
}
main().catch(error=>{console.error(error);process.exitCode=1;});
