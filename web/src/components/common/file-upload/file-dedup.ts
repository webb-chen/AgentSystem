import type { UploadedFile } from '@/services/types/dataset';
import type { FileItem } from '@/services/types/file';

interface ExistingUploadItem {
  id: string;
  file: File;
  contentHash?: string;
  serverFile?: UploadedFile;
}

function normalizeHash(hash: unknown): string {
  return typeof hash === 'string' ? hash.trim().toLowerCase() : '';
}

function fallbackContentHash(buffer: ArrayBuffer): string {
  // WebCrypto (crypto.subtle) is only available in secure contexts. Intranet
  // deployments are commonly served over plain HTTP (e.g. http://10.x.x.x),
  // where crypto.subtle is undefined. Use a deterministic, fast non-crypto
  // hash so file selection and duplicate detection still work there. The
  // server independently computes the authoritative SHA-256.
  const bytes = new Uint8Array(buffer);
  let h1 = 0x811c9dc5;
  let h2 = 0x9e3779b9;
  for (let index = 0; index < bytes.length; index += 1) {
    const byte = bytes[index];
    h1 = Math.imul(h1 ^ byte, 0x01000193) >>> 0;
    h2 = Math.imul(h2 ^ byte, 0x85ebca6b) >>> 0;
    h2 = (h2 + index) >>> 0;
  }
  return `fnv1a-${h1.toString(16).padStart(8, '0')}${h2.toString(16).padStart(8, '0')}`;
}

export async function calculateFileHash(file: File): Promise<string> {
  const buffer = await file.arrayBuffer();
  if (typeof crypto !== 'undefined' && crypto.subtle?.digest) {
    try {
      const digest = await crypto.subtle.digest('SHA-256', buffer);
      return Array.from(new Uint8Array(digest))
        .map(byte => byte.toString(16).padStart(2, '0'))
        .join('');
    } catch {
      // Some browsers expose crypto.subtle but reject digest() outside a
      // secure context; fall through to the deterministic fallback.
    }
  }
  return fallbackContentHash(buffer);
}

export function getFileFallbackKey(file: File): string {
  return [file.name, file.size, file.type, file.lastModified].join('|');
}

export function getExistingFileKeys(items: ExistingUploadItem[]): Set<string> {
  const keys = new Set<string>();
  items.forEach(item => {
    const itemHash = normalizeHash(item.contentHash) || normalizeHash(item.serverFile?.hash);
    if (itemHash) keys.add(`hash:${itemHash}`);
    if (item.serverFile?.id) keys.add(`id:${item.serverFile.id}`);
    keys.add(`local:${getFileFallbackKey(item.file)}`);
  });
  return keys;
}

export function getUploadedFileKeys(file: UploadedFile | FileItem): string[] {
  const keys: string[] = [];
  const hash = normalizeHash(file.hash);
  if (hash) keys.push(`hash:${hash}`);
  if (file.id) keys.push(`id:${file.id}`);
  return keys;
}

export function hasAnyFileKey(existingKeys: Set<string>, keys: string[]): boolean {
  return keys.some(key => existingKeys.has(key));
}
