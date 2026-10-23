import { zipSync, strToU8 } from 'npm:fflate@0.8.3';
import { readDocument, prepareExtraction } from './generated/extract-core.ts';
import { compareTexts, sha256, type AcademicText } from './generated/domain.ts';
import { limits, algorithmVersion } from './step.ts';

// Fixed synthetic fixtures only. Validation cannot claim jobs, reconcile, or read Storage.
export async function runProbe(format: string) {
  if (!['txt','docx','pdf','prepare','compare'].includes(format)) throw Error('invalid_probe');
  const started=performance.now();
  const text=Array.from({length:format==='pdf'?80:20000},(_,i)=>'word'+i).join(' ');
  let words=0;
  if(format==='prepare') {
    words=prepareExtraction(text,null,limits).academic!.tokens.length;
  } else if(format==='compare') {
    // Comparison receives already prepared tokens from a checkpoint in production.
    const prepared=(source:string):AcademicText=>{
      let offset=0;const tokens=source.split(' ').map(word=>{const start=offset;offset+=word.length+1;return {word,start,end:offset-1};});
      return {text:source,normalized:source,textHash:sha256(source),tokens,fingerprints:[],excluded:[]};
    };
    const a=prepared(text),b=prepared(text.split(' ').reverse().join(' '));
    compareTexts(a,b);words=a.tokens.length;
  } else if(format==='pdf') {
    const lines=text.match(/(?:\S+\s*){1,8}/gu)!;
    const stream=`BT /F1 9 Tf 12 TL 20 750 Td ${lines.map(line=>'('+line+') Tj T*').join(' ')} ET`;
    const objects=['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',`<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`];
    let source='%PDF-1.4\n';const offsets=[0];
    objects.forEach((obj,i)=>{offsets.push(source.length);source+=`${i+1} 0 obj\n${obj}\nendobj\n`;});
    const xref=source.length;
    source+=`xref\n0 6\n0000000000 65535 f \n${offsets.slice(1).map(n=>String(n).padStart(10,'0')+' 00000 n \n').join('')}trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
    const {readPdfPage}=await import('./pdf.ts');
    const page=await readPdfPage(new TextEncoder().encode(source),1,limits.maxPages);
    words=prepareExtraction(page.text,null,limits).academic!.tokens.length;
  } else {
    const bytes=format==='txt'?strToU8(text):zipSync({
      '[Content_Types].xml':strToU8('<Types><Override ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'),
      'word/document.xml':strToU8('<w:document><w:body><w:p><w:r><w:t>'+text+'</w:t></w:r></w:p></w:body></w:document>'),
    });
    const raw=await readDocument({...limits,bytes,mime:format==='txt'?'text/plain':'application/vnd.openxmlformats-officedocument.wordprocessingml.document'},()=>{throw Error('unexpected_pdf');});
    // Probe only the extraction phase; preparation has its own invocation.
    words=raw.text.trim().split(/\s+/u).length;
  }
  const expected=format==='pdf'?80:20000;if(words!==expected)throw Error('probe_failed');
  return {status:'validated',mode:'validate',format,words,elapsedMs:Math.ceil(performance.now()-started),algorithmVersion};
}
