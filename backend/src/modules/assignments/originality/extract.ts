import { dirname, join } from 'node:path';
import { extract as extractCore, type ExtractionInput, type ExtractionResult } from './extract-core';
export type { ExtractionInput, ExtractionResult } from './extract-core';

export async function extract(input: ExtractionInput): Promise<ExtractionResult> {
  return extractCore(input, async (bytes, options) => {
      // Native dynamic import survives CommonJS compilation (Node >=22).
      const pdfjs = await (new Function('return import("pdfjs-dist/legacy/build/pdf.mjs")')() as Promise<typeof import('pdfjs-dist/legacy/build/pdf.mjs')>);
      const task = pdfjs.getDocument({ data: new Uint8Array(bytes), useSystemFonts: false, disableFontFace: true, useWasm: false,
        standardFontDataUrl: join(dirname(require.resolve('pdfjs-dist/package.json')), 'standard_fonts').replace(/\\/gu, '/') + '/', verbosity: 0,
        useWorkerFetch: false, isOffscreenCanvasSupported: false, isImageDecoderSupported: false, stopAtErrors: true });
      try {
        const pdf = await task.promise;
        if (pdf.numPages > options.maxPages) throw new Error('resource_limit');
        const pages: string[] = [];
        let length = 0;
        for (let i = 1; i <= pdf.numPages; i++) {
          const page = await pdf.getPage(i);
          const content = await page.getTextContent();
          const value = content.items.map(item => 'str' in item ? item.str + (item.hasEOL ? '\n' : ' ') : '').join('');
          length += value.length;
          if (length > 500000) throw new Error('resource_limit');
          pages.push(value); page.cleanup();
        }
        return pages.join('\n');
      } finally { await task.destroy(); }
  });
}
