import fs from 'fs';
import os from 'os';
import path from 'path';
import { describe, it, expect, beforeEach, afterEach, jest } from '@jest/globals';
import {
  LocalObjectStorage,
  sanitizeObjectKey,
  verifyObjectStorageAccess,
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

    it('verifyObjectStorageAccess performs a clean roundtrip', async () => {
      await verifyObjectStorageAccess(storage);
      expect(fs.readdirSync(tempDir)).toHaveLength(0);
    });
  });

  describe('verifyObjectStorageAccess', () => {
    it('fails when uploaded object is not visible', async () => {
      const brokenStorage = {
        put: jest.fn().mockResolvedValue(undefined),
        exists: jest.fn().mockResolvedValue(false),
        get: jest.fn(),
        delete: jest.fn().mockResolvedValue(undefined),
      };

      await expect(verifyObjectStorageAccess(brokenStorage)).rejects.toThrow(
        /uploaded object is not visible/,
      );
      expect(brokenStorage.delete).toHaveBeenCalled();
    });
  });
});
