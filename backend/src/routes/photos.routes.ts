import { NextFunction, Request, Response, Router } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import sharp from 'sharp';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { prisma } from '../lib/prisma.js';
import { config } from '../config.js';
import { AppError, badRequest, forbidden, notFound } from '../lib/errors.js';
import { assertSealEditable } from '../services/seal.service.js';
import { logActivity } from '../services/audit.service.js';
import { UserRole } from '@prisma/client';
import { paramId } from '../lib/params.js';

const router = Router();
router.use(authMiddleware);
const maxPhotoSizeBytes = 15 * 1024 * 1024;

if (!fs.existsSync(config.uploadPath)) {
  fs.mkdirSync(config.uploadPath, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, config.uploadPath),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    cb(null, `${Date.now()}-${Math.random().toString(36).slice(2)}${ext}`);
  },
});

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
  storage,
  limits: { fileSize: maxPhotoSizeBytes },
  fileFilter: (_req, file, cb) => {
    if (isAllowedImageMime(file.mimetype, file.originalname)) cb(null, true);
    else cb(badRequest(`Nepodporovaný formát souboru (${file.mimetype})`));
  },
});

const uploadSinglePhoto = upload.single('photo');

function removeFileIfExists(filePath: string | undefined) {
  if (!filePath || !fs.existsSync(filePath)) return;
  try {
    fs.unlinkSync(filePath);
  } catch {
    // Ignore EBUSY on Windows when sharp/multer still holds the handle.
  }
}

function resolveUploadFilePath(fileName: string) {
  const uploadRoot = path.resolve(config.uploadPath);
  const filePath = path.resolve(uploadRoot, fileName);
  if (!filePath.startsWith(uploadRoot + path.sep) && filePath !== uploadRoot) {
    throw forbidden('Neplatna cesta souboru');
  }
  return filePath;
}

async function convertUploadToWebp(inputPath: string, outputPath: string) {
  const meta = await sharp(inputPath, { failOn: 'error' }).metadata();
  if (!meta.format) {
    throw badRequest('Soubor není platný obrázek (nelze rozpoznat formát)');
  }
  await sharp(inputPath, { failOn: 'error' })
    .resize(1920, 1920, { fit: 'inside', withoutEnlargement: true })
    .webp({ quality: 85 })
    .toFile(outputPath);
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
  let outputPath: string | undefined;
  try {
    const sealId = paramId(req.params.sealId);
    if (!req.file) {
      throw badRequest('Chybí multipart pole „photo“ se souborem fotky');
    }

    if (req.user!.role === UserRole.worker) {
      await assertSealEditable(sealId, req.user!.role, req.user!.id);
    } else {
      const seal = await prisma.seal.findFirst({ where: { id: sealId, deletedAt: null } });
      if (!seal) throw notFound('Ucpávka nenalezena');
    }

    const outputName = `${path.parse(req.file.filename).name}-${Date.now()}.webp`;
    outputPath = resolveUploadFilePath(outputName);

    try {
      await convertUploadToWebp(req.file.path, outputPath);
    } catch (e) {
      if (e instanceof AppError) throw e;
      throw badRequest('Soubor není platný obrázek (poškozený nebo nepodporovaný formát)');
    } finally {
      removeFileIfExists(req.file.path);
    }

    const stats = fs.statSync(outputPath);
    const photo = await prisma.sealPhoto.create({
      data: {
        sealId,
        filePath: outputName,
        mimeType: 'image/webp',
        fileSize: stats.size,
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
    removeFileIfExists(req.file?.path);
    removeFileIfExists(outputPath);
    next(e);
  }
});

router.get('/photos/:photoId/file', async (req, res, next) => {
  try {
    const photo = await prisma.sealPhoto.findUnique({
      where: { id: paramId(req.params.photoId) },
      include: { seal: true },
    });
    if (!photo || photo.seal.deletedAt) throw notFound('Fotka nenalezena');

    const filePath = resolveUploadFilePath(photo.filePath);
    if (!fs.existsSync(filePath)) throw notFound('Soubor fotky nenalezen');

    res.type(photo.mimeType);
    res.sendFile(filePath);
  } catch (e) {
    next(e);
  }
});

router.delete('/photos/:photoId', async (req, res, next) => {
  try {
    if (req.user!.role === UserRole.worker) {
      throw forbidden('Worker nemůže mazat fotky');
    }
    const photo = await prisma.sealPhoto.findUnique({ where: { id: paramId(req.params.photoId) } });
    if (!photo) throw notFound('Fotka nenalezena');

    removeFileIfExists(resolveUploadFilePath(photo.filePath));

    await prisma.sealPhoto.delete({ where: { id: photo.id } });
    await logActivity(req.user!.id, 'photo_delete', 'seal', photo.sealId);
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

export default router;
