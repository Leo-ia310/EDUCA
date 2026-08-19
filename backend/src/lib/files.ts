export function mapAttachment(file: Record<string, unknown>) {
  return {
    id: String(file.id),
    name: String(file.original_name ?? file.name ?? "archivo"),
    url: String(file.url ?? ""),
    sizeBytes: file.size_bytes == null
      ? file.sizeBytes == null ? null : Number(file.sizeBytes)
      : Number(file.size_bytes),
    mimeType: file.mime_type ?? file.mimeType ?? null,
  };
}
