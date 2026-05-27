import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import sharp from 'sharp';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { prisma } from '../lib/prisma.js';
import { config } from '../config.js';
import { forbidden, notFound } from '../lib/errors.js';
import { assertSealEditable } from '../services/seal.service.js';
import { logActivity } from '../services/audit.service.js';
import { UserRole } from '@prisma/client';
import { paramId } from '../lib/params.js';

const router = Router();
router.use(authMiddleware);

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

const upload = multer({
  storage,
  limits: { fileSize: 15 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const allowed = ['image/jpeg', 'image/png', 'image/webp', 'image/jpg'];
    if (allowed.includes(file.mimetype)) cb(null, true);
    else cb(new Error('Nepodporovaný formát souboru'));
  },
});

router.post('/seals/:sealId/photos', upload.single('photo'), async (req, res, next) => {
  try {
    const sealId = paramId(req.params.sealId);
    if (!req.file) {
      const { badRequest } = await import('../lib/errors.js');
      throw badRequest('Soubor photo je povinný');
    }

    if (req.user!.role === UserRole.worker) {
      await assertSealEditable(sealId, req.user!.role, req.user!.id);
    } else {
      const seal = await prisma.seal.findFirst({ where: { id: sealId, deletedAt: null } });
      if (!seal) throw notFound('Ucpávka nenalezena');
    }

    const outputName = `${path.parse(req.file.filename).name}.webp`;
    const outputPath = path.join(config.uploadPath, outputName);

    await sharp(req.file.path)
      .resize(1920, 1920, { fit: 'inside', withoutEnlargement: true })
      .webp({ quality: 85 })
      .toFile(outputPath);

    fs.unlinkSync(req.file.path);

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
    });
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

    const filePath = path.join(config.uploadPath, photo.filePath);
    if (fs.existsSync(filePath)) fs.unlinkSync(filePath);

    await prisma.sealPhoto.delete({ where: { id: photo.id } });
    await logActivity(req.user!.id, 'photo_delete', 'seal', photo.sealId);
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

export default router;
