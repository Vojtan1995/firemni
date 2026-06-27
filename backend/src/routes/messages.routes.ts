import { Router } from 'express';
import { z } from 'zod';
import { UserRole } from '@prisma/client';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { messageRateLimiter } from '../middleware/security.middleware.js';
import { prisma } from '../lib/prisma.js';
import { badRequest, forbidden, notFound } from '../lib/errors.js';
import { paramId } from '../lib/params.js';
import { mapMessageUsers } from '../lib/user-privacy.js';

const router = Router();
router.use(authMiddleware);

const messageUserSelect = { id: true, displayName: true, username: true, role: true } as const;

const sendSchema = z.object({
  recipientId: z.string().uuid(),
  body: z.string().min(1).max(4000),
});

router.get('/contacts', async (req, res, next) => {
  try {
    const users = await prisma.user.findMany({
      where: {
        isActive: true,
        id: { not: req.user!.id },
        role: { not: UserRole.admin },
      },
      select: { id: true, displayName: true, username: true, role: true },
      orderBy: { displayName: 'asc' },
    });
    res.json(users);
  } catch (e) {
    next(e);
  }
});

router.get('/', async (req, res, next) => {
  try {
    const userId = req.user!.id;
    const box = (req.query.box as string | undefined) ?? 'inbox';
    const where =
      box === 'sent'
        ? { senderId: userId }
        : { recipientId: userId };

    const messages = await prisma.privateMessage.findMany({
      where,
      include: {
        sender: { select: messageUserSelect },
        recipient: { select: messageUserSelect },
      },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    res.json(mapMessageUsers(messages, req.user!.role));
  } catch (e) {
    next(e);
  }
});

router.get('/unread-count', async (req, res, next) => {
  try {
    const count = await prisma.privateMessage.count({
      where: { recipientId: req.user!.id, readAt: null },
    });
    res.json({ count });
  } catch (e) {
    next(e);
  }
});

router.post('/', messageRateLimiter, async (req, res, next) => {
  try {
    const body = sendSchema.parse(req.body);
    if (body.recipientId === req.user!.id) {
      throw badRequest('Nelze poslat zprávu sobě');
    }
    const recipient = await prisma.user.findFirst({
      where: { id: body.recipientId, isActive: true },
    });
    if (!recipient) throw notFound('Příjemce nenalezen');

    const message = await prisma.privateMessage.create({
      data: {
        senderId: req.user!.id,
        recipientId: body.recipientId,
        body: body.body.trim(),
      },
      include: {
        sender: { select: messageUserSelect },
        recipient: { select: messageUserSelect },
      },
    });
    res.status(201).json(mapMessageUsers([message], req.user!.role)[0]);
  } catch (e) {
    next(e);
  }
});

router.patch('/:id/read', async (req, res, next) => {
  try {
    const id = paramId(req.params.id);
    const message = await prisma.privateMessage.findUnique({ where: { id } });
    if (!message) throw notFound('Zpráva nenalezena');
    if (message.recipientId !== req.user!.id) throw forbidden();

    const updated = await prisma.privateMessage.update({
      where: { id },
      data: { readAt: message.readAt ?? new Date() },
    });
    res.json(updated);
  } catch (e) {
    next(e);
  }
});

export default router;
