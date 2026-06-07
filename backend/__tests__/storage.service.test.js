import fs from 'fs';
import os from 'os';
import path from 'path';
import { describe, it, expect, beforeEach, afterEach } from '@jest/globals';
import {
  LocalObjectStorage,
  sanitizeObjectKey,
} from '../dist/services/storage.service.js';

describe('storage.service', () => {
  describe('sanitizeObjectKey', () => {
    it('strips directory traversal', () => {
      expect(sanitizeObjectKey('../../etc/passwd')).toBe('passwd');
      expect(sanitizeObjectKey('nested/evil.webp')).toBe('evil.webp');
    });

    it('rejects empty or dot keys', () => {
      expect(() => sanitizeObjectKey('..')).toThrow();
      expect(() => sanitizeObjectKey('')).toThrow();
    });
  });

  describe('LocalObjectStorage', () => {
    let tempDir;
    let storage;

    beforeEach(() => {
      tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ucpavky-storage-'));
      storage = new LocalObjectStorage(tempDir);
    });

    afterEach(() => {
      fs.rmSync(tempDir, { recursive: true, force: true });
    });

    it('put/get/delete roundtrip', async () => {
      const body = Buffer.from('webp-bytes');
      await storage.put('photo.webp', body, 'image/webp');
      expect(await storage.exists('photo.webp')).toBe(true);
      expect(await storage.get('photo.webp')).toEqual(body);
      await storage.delete('photo.webp');
      expect(await storage.exists('photo.webp')).toBe(false);
    });

    it('blocks path escape on get', async () => {
      await expect(storage.get('../outside.webp')).rejects.toThrow();
    });
  });
});
