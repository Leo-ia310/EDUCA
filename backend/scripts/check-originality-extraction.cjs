process.env.NODE_ENV='test';process.env.SUPABASE_URL='https://fixture.supabase.co';process.env.SUPABASE_ANON_KEY='fixture-public';
global.fetch=async()=>{throw new Error('Network disabled in extraction verification');};
const assert=require('node:assert/strict');
const {writeFileSync,mkdirSync}=require('node:fs');
const {join}=require('node:path');
const {zipSync,strToU8}=require('fflate');
const {pdf}=require('../test/fixtures/originality-pdf.cjs');
const {isolatedExtraction}=require('../dist/modules/assignments/originality/worker');
const body=Array.from({length:80},(_,i)=>'word'+i).join(' ');
const options={maxBytes:5*1024*1024,maxPages:50,maxWords:20000,minWords:40,ngram:5};
async function main(){
 const docx=zipSync({'[Content_Types].xml':strToU8('<Types><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'),
  'word/document.xml':strToU8(`<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>${body}</w:t></w:r></w:p></w:body></w:document>`)});
 const fixtures=[{format:'editor',notes:body},{format:'txt',bytes:Buffer.from(body),mime:'text/plain'},
  {format:'docx',bytes:docx,mime:'application/vnd.openxmlformats-officedocument.wordprocessingml.document'},
  {format:'pdf',bytes:pdf(body),mime:'application/pdf'}, {format:'pdf-empty',bytes:pdf(''),mime:'application/pdf'}];
 const results=[];
 for(const fixture of fixtures){
  const result=await isolatedExtraction({...options,...fixture},30000);
  assert.equal(result.state,fixture.format==='pdf-empty'?'insufficient_text':'completed');
  assert.ok(result.runtime.heapSizeLimitBytes<=200*1024*1024);
  results.push({format:fixture.format,state:result.state,words:result.academic?.tokens.length??0,heapLimitBytes:result.runtime.heapSizeLimitBytes});
 }
 const directory=join(__dirname,'../../docs/performance/originality');mkdirSync(directory,{recursive:true});
 writeFileSync(join(directory,'isolated-extractors.json'),JSON.stringify(results,null,2)+'\n');console.log(JSON.stringify(results));
}
main().catch(error=>{console.error(error);process.exitCode=1;});
