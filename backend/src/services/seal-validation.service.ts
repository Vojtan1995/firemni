import { prisma } from '../lib/prisma.js';
import { badRequest } from '../lib/errors.js';

export type SealValidationIssue = {
  field: string;
  message: string;
};

type SealForValidation = {
  system: string;
  construction: string;
  location: string;
  fireRating: string;
  entries: Array<{
    entryType: string;
    dimension: string;
    quantity: unknown;
    materials: Array<{ material: string }>;
  }>;
  photos: Array<{ id: string }>;
};

export function validateSealForChecked(seal: SealForValidation): SealValidationIssue[] {
  const issues: SealValidationIssue[] = [];

  if (!seal.system?.trim()) {
    issues.push({ field: 'system', message: 'Chybí systém' });
  }
  if (!seal.construction?.trim()) {
    issues.push({ field: 'construction', message: 'Chybí konstrukce' });
  }
  if (!seal.location?.trim()) {
    issues.push({ field: 'location', message: 'Chybí umístění' });
  }
  if (!seal.fireRating?.trim()) {
    issues.push({ field: 'fireRating', message: 'Chybí požární odolnost' });
  }
  if (!seal.photos?.length) {
    issues.push({ field: 'photos', message: 'Chybí alespoň jedna fotka' });
  }
  if (!seal.entries?.length) {
    issues.push({ field: 'entries', message: 'Chybí alespoň jeden prostup' });
    return issues;
  }

  seal.entries.forEach((entry, index) => {
    const label = `Prostup ${index + 1}`;
    if (!entry.entryType?.trim()) {
      issues.push({ field: `entries.${index}.entryType`, message: `${label}: chybí typ prostupu` });
    }
    if (!entry.dimension?.trim()) {
      issues.push({ field: `entries.${index}.dimension`, message: `${label}: chybí rozměr` });
    }
    const qty = Number(entry.quantity);
    if (!Number.isFinite(qty) || qty <= 0) {
      issues.push({ field: `entries.${index}.quantity`, message: `${label}: chybí počet kusů` });
    }
    if (!entry.materials?.length) {
      issues.push({ field: `entries.${index}.materials`, message: `${label}: chybí materiál` });
    }
  });

  return issues;
}

export async function loadSealForCheckedValidation(sealId: string) {
  return prisma.seal.findFirst({
    where: { id: sealId, deletedAt: null },
    select: {
      system: true,
      construction: true,
      location: true,
      fireRating: true,
      entries: {
        where: { deletedAt: null },
        select: {
          entryType: true,
          dimension: true,
          quantity: true,
          materials: { select: { material: true } },
        },
        orderBy: { sortOrder: 'asc' },
      },
      photos: { select: { id: true } },
    },
  });
}

export async function assertSealReadyForChecked(sealId: string) {
  const seal = await loadSealForCheckedValidation(sealId);
  if (!seal) {
    throw badRequest('Ucpávka nenalezena');
  }
  const issues = validateSealForChecked(seal);
  if (issues.length > 0) {
    throw badRequest(`Ucpávka není kompletní: ${issues.map((i) => i.message).join('; ')}`);
  }
}
