import { NextFunction, Request, Response, Router } from 'express';
import multer from 'multer';
import path from 'path';
import sharp from 'sharp';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { prisma } from '../lib/prisma.js';
import { AppError, badRequest, forbidden, notFound } from '../lib/errors.js';
import { assertSealReadable } from '../services/authorization.service.js';
import { assertSealEditable } from '../services/seal.service.js';
import { requirePermission } from '../lib/permissions.js';
import { getObjectStorage, sanitizeObjectKey } from '../services/storage.service.js';
import { logActivity } from '../services/audit.service.js';
import { UserRole } from '@prisma/client';
import { paramId } from '../lib/params.js';

const router = Router();
router.use(authMiddleware);
const maxPhotoSizeBytes = 50 * 1024 * 1024;

function isAllowedImageMime(mimetype: string, originalname: string): boolean {
  const allowed = ['image/jpeg', 'image/png', 'image/webp', 'image/jpg'];
  if (allowed.includes(mimetype)) return true;
  if (mimetype === 'application/octet-stream' || mimetype === 'application/x-unknown') {
    const ext = path.extname(originalname).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.webp'].includes(ext);
  }
  return false;
}

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: maxPhotoSizeBytes },
  fileFilter: (_req, file, cb) => {
    if (isAllowedImageMime(file.mimetype, file.originalname)) cb(null, true);
    else cb(badRequest(`Nepodporovaný formát souboru (${file.mimetype})`));
  },
});

const uploadSinglePhoto = upload.single('photo');

async function convertBufferToWebp(input: Buffer): Promise<Buffer> {
  const meta = await sharp(input, { failOn: 'error' }).metadata();
  if (!meta.format) {
    throw badRequest('Soubor není platný obrázek (nelze rozpoznat formát)');
  }
  return sharp(input, { failOn: 'error' })
    .resize(1920, 1920, { fit: 'inside', withoutEnlargement: true })
    .webp({ quality: 85 })
    .toBuffer();
}

function photoUploadMiddleware(req: Request, res: Response, next: NextFunction) {
  uploadSinglePhoto(req, res, (err) => {
    if (!err) return next();
    if (err instanceof AppError) return next(err);
    if (err instanceof multer.MulterError && err.code === 'LIMIT_FILE_SIZE') {
      return next(new AppError(413, 'UPLOAD_TOO_LARGE', `Fotka nesmí být větší než ${maxPhotoSizeBytes} B`));
    }
    if (err instanceof multer.MulterError && err.code === 'LIMIT_UNEXPECTED_FILE') {
      return next(badRequest('Očekáváno multipart pole „photo“'));
    }
    return next(badRequest(`Fotku se nepodařilo nahrát: ${err instanceof Error ? err.message : 'neznámá chyba'}`));
  });
}

router.post('/seals/:sealId/photos', photoUploadMiddleware, async (req, res, next) => {
  let outputName: string | undefined;
  const storage = getObjectStorage();
  try {
    const sealId = paramId(req.params.sealId);
    if (!req.file) {
      throw badRequest('Chybí multipart pole „photo“ se souborem fotky');
    }

    if (req.user!.role === UserRole.worker) {
      await assertSealEditable(sealId, req.user!.role, req.user!.id);
    } else {
      await assertSealReadable(sealId, req.user!.role, req.user!.id);
    }

    outputName = sanitizeObjectKey(`${Date.now()}-${Math.random().toString(36).slice(2)}.webp`);
    let webpBuffer: Buffer;
    try {
      webpBuffer = await convertBufferToWebp(req.file.buffer);
    } catch (e) {
      if (e instanceof AppError) throw e;
      throw badRequest('Soubor není platný obrázek (poškozený nebo nepodporovaný formát)');
    }
    await storage.put(outputName, webpBuffer, 'image/webp');

    const photo = await prisma.sealPhoto.create({
      data: {
        sealId,
        filePath: outputName,
        mimeType: 'image/webp',
        fileSize: webpBuffer.length,
        uploadedById: req.user!.id,
      },
    });

    await logActivity(req.user!.id, 'photo_upload', 'seal', sealId, { photoId: photo.id });
    res.status(201).json({
      ...photo,
      url: `/uploads/${outputName}`,
      authUrl: `/api/photos/${photo.id}/file`,
    });
  } catch (e) {
    if (outputName) {
      try {
        await storage.delete(outputName);
      } catch {
        // Best-effort rollback when DB write fails after upload.
      }
    }
    next(e);
  }
});

router.get('/photos/:photoId/file', async (req, res, next) => {
  try {
    const photo = await prisma.sealPhoto.findUnique({
      where: { id: paramId(req.params.photoId) },
      include: { seal: true },
    });
    if (!photo || photo.deletedAt || photo.seal.deletedAt)
      throw notFound('Fotka nenalezena');
    await assertSealReadable(photo.sealId, req.user!.role, req.user!.id);

    const storage = getObjectStorage();
    if (!(await storage.exists(photo.filePath))) {
      throw notFound('Soubor fotky nenalezen');
    }

    const body = await storage.get(photo.filePath);
    res.type(photo.mimeType);
    res.send(body);
  } catch (e) {
    next(e);
  }
});

// Měkké smazání fotky (vedení/admin). Soubor v úložišti zůstává kvůli auditní
// stopě; v UI i v exportech se smazaná fotka nezobrazuje. Důvod je povinný.
router.delete(
  '/photos/:photoId',
  requirePermission('photo.delete'),
  async (req, res, next) => {
    try {
      const photo = await prisma.sealPhoto.findUnique({
        where: { id: paramId(req.params.photoId) },
        include: { seal: true },
      });
      if (!photo || photo.deletedAt || photo.seal.deletedAt)
        throw notFound('Fotka nenalezena');
      // Vedení/admin mají přístup ke čtení všech ucpávek; nemažeme soubor, jen
      // záznam označíme jako smazaný (i u zamčené/vyfakturované ucpávky).
      await assertSealReadable(photo.sealId, req.user!.role, req.user!.id);
      const reason =
        typeof req.body?.reason === 'string' ? req.body.reason.trim() : '';
      if (!reason) throw badRequest('Důvod smazání fotky je povinný');
      await prisma.sealPhoto.update({
        where: { id: photo.id },
        data: {
          deletedAt: new Date(),
          deletedById: req.user!.id,
          deleteReason: reason.slice(0, 2000),
        },
      });
      await logActivity(req.user!.id, 'photo_delete', 'seal_photo', photo.id, {
        sealId: photo.sealId,
        reason: reason.slice(0, 2000),
      });
      res.status(204).send();
    } catch (e) {
      next(e);
    }
  },
);

export default router;
