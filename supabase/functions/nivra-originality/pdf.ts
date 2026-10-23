import { getDocumentProxy } from 'npm:unpdf@1.9.1';

// The serverless PDF.js build embeds its parser; no Node threads, canvas or remote fonts.
export async function readPdfPage(bytes: Uint8Array, pageNumber: number, maxPages: number) {
  const pdf = await getDocumentProxy(new Uint8Array(bytes), {
    disableFontFace: true, useSystemFonts: false,
    useWasm: false, useWorkerFetch: false, stopAtErrors: true,
    disableAutoFetch: true, disableStream: true, disableRange: true,
  });
  try {
    if (pdf.numPages > maxPages) throw Error('resource_limit');
    if (!Number.isSafeInteger(pageNumber) || pageNumber < 1 || pageNumber > pdf.numPages) throw Error('invalid_document');
    const page = await pdf.getPage(pageNumber);
    try {
      const content = await page.getTextContent();
      const text = content.items.map(item => 'str' in item ? item.str + (item.hasEOL ? '\n' : ' ') : '').join('');
      if (text.length > 500000) throw Error('resource_limit');
      return { text, totalPages: pdf.numPages };
    } finally { page.cleanup(); }
  } finally { await pdf.loadingTask.destroy(); }
}
