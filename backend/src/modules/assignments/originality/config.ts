function limit(name: string, fallback: number, max: number, min = 1) {
  const value = Number(process.env[name] ?? fallback);
  if (!Number.isInteger(value) || value < min || value > max) throw new Error(`Invalid ${name}`);
  return value;
}
export function originalityConfig() {
  const ngram = limit('ORIGINALITY_NGRAM', 5, 10, 3), minWords = limit('ORIGINALITY_MIN_WORDS', 40, 500, 10);
  return { maxBytes: limit('ORIGINALITY_MAX_BYTES', 5 * 1024 * 1024, 8 * 1024 * 1024),
    maxPages: limit('ORIGINALITY_MAX_PAGES', 50, 100), maxWords: limit('ORIGINALITY_MAX_WORDS', 20000, 20000), minWords, ngram,
    timeoutMs: limit('ORIGINALITY_EXTRACTION_MS', 30000, 40000),
    pollMs: limit('ORIGINALITY_POLL_MS', 5000, 60000, 1000), algorithmVersion: `nivra-1-n${ngram}-m${minWords}` };
}
