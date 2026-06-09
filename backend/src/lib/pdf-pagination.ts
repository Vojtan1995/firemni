import PDFDocument from 'pdfkit';
import { initCzechPdf } from './pdf-fonts.js';

type PdfDoc = InstanceType<typeof PDFDocument>;

export function createCzechPdfDocument(options?: ConstructorParameters<typeof PDFDocument>[0]) {
  const doc = new PDFDocument(options ?? { margin: 40, size: 'A4' });
  initCzechPdf(doc);
  return doc;
}

const PDF_PAGE_BOTTOM_Y = 750;

export function writePdfTextLine(
  doc: PdfDoc,
  text: string,
  options?: { fontSize?: number; bottomY?: number },
) {
  const fontSize = options?.fontSize ?? 8;
  const bottomY = options?.bottomY ?? PDF_PAGE_BOTTOM_Y;
  doc.fontSize(fontSize);
  if (doc.y > bottomY) {
    doc.addPage();
  }
  doc.text(text);
}

export function writePdfHeading(
  doc: PdfDoc,
  text: string,
  fontSize = 12,
) {
  if (doc.y > PDF_PAGE_BOTTOM_Y - 40) {
    doc.addPage();
  }
  doc.fontSize(fontSize).text(text, { underline: true });
  doc.moveDown(0.3);
}
