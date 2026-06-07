import fs from 'fs';
import path from 'path';
import {
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { config } from '../config.js';
import { forbidden } from '../lib/errors.js';

export function sanitizeObjectKey(key: string): string {
  const base = path.basename(key.trim());
  if (!base || base === '.' || base === '..') {
    throw forbidden('Neplatný název souboru');
  }
  return base;
}

export interface ObjectStorage {
  put(key: string, body: Buffer, contentType: string): Promise<void>;
  get(key: string): Promise<Buffer>;
  delete(key: string): Promise<void>;
  exists(key: string): Promise<boolean>;
}

export class LocalObjectStorage implements ObjectStorage {
  constructor(private readonly rootDir: string) {
    if (!fs.existsSync(rootDir)) {
      fs.mkdirSync(rootDir, { recursive: true });
    }
  }

  private resolveKey(key: string) {
    const safeKey = sanitizeObjectKey(key);
    const root = path.resolve(this.rootDir);
    const filePath = path.resolve(root, safeKey);
    if (!filePath.startsWith(root + path.sep) && filePath !== root) {
      throw forbidden('Neplatná cesta souboru');
    }
    return { safeKey, filePath };
  }

  async put(key: string, body: Buffer, _contentType: string): Promise<void> {
    const { filePath } = this.resolveKey(key);
    await fs.promises.writeFile(filePath, body);
  }

  async get(key: string): Promise<Buffer> {
    const { filePath } = this.resolveKey(key);
    return fs.promises.readFile(filePath);
  }

  async delete(key: string): Promise<void> {
    const { filePath } = this.resolveKey(key);
    if (fs.existsSync(filePath)) {
      await fs.promises.unlink(filePath);
    }
  }

  async exists(key: string): Promise<boolean> {
    const { filePath } = this.resolveKey(key);
    return fs.existsSync(filePath);
  }
}

async function streamToBuffer(body: unknown): Promise<Buffer> {
  if (!body) return Buffer.alloc(0);
  if (Buffer.isBuffer(body)) return body;
  if (body instanceof Uint8Array) return Buffer.from(body);
  const chunks: Buffer[] = [];
  for await (const chunk of body as AsyncIterable<Buffer | Uint8Array | string>) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

export class S3ObjectStorage implements ObjectStorage {
  private readonly client: S3Client;
  private readonly bucket: string;
  private readonly keyPrefix: string;

  constructor() {
    const { s3 } = config;
    this.bucket = s3.bucket;
    this.keyPrefix = s3.keyPrefix.replace(/^\/+|\/+$/g, '');
    this.client = new S3Client({
      region: s3.region,
      ...(s3.endpoint ? { endpoint: s3.endpoint } : {}),
      forcePathStyle: s3.forcePathStyle,
      credentials: {
        accessKeyId: s3.accessKeyId,
        secretAccessKey: s3.secretAccessKey,
      },
    });
  }

  private objectKey(key: string) {
    const safeKey = sanitizeObjectKey(key);
    return this.keyPrefix ? `${this.keyPrefix}/${safeKey}` : safeKey;
  }

  async put(key: string, body: Buffer, contentType: string): Promise<void> {
    await this.client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: this.objectKey(key),
        Body: body,
        ContentType: contentType,
      }),
    );
  }

  async get(key: string): Promise<Buffer> {
    const res = await this.client.send(
      new GetObjectCommand({
        Bucket: this.bucket,
        Key: this.objectKey(key),
      }),
    );
    return streamToBuffer(res.Body);
  }

  async delete(key: string): Promise<void> {
    await this.client.send(
      new DeleteObjectCommand({
        Bucket: this.bucket,
        Key: this.objectKey(key),
      }),
    );
  }

  async exists(key: string): Promise<boolean> {
    try {
      await this.client.send(
        new HeadObjectCommand({
          Bucket: this.bucket,
          Key: this.objectKey(key),
        }),
      );
      return true;
    } catch {
      return false;
    }
  }
}

let storageInstance: ObjectStorage | null = null;

export function getObjectStorage(): ObjectStorage {
  if (!storageInstance) {
    storageInstance =
      config.storageDriver === 's3'
        ? new S3ObjectStorage()
        : new LocalObjectStorage(config.uploadPath);
  }
  return storageInstance;
}

/** Test-only reset of cached storage singleton. */
export function resetObjectStorageForTests() {
  storageInstance = null;
}
