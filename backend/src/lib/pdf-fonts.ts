import fs from 'fs';
import path from 'path';
import PDFDocument from 'pdfkit';

type PdfDoc = InstanceType<typeof PDFDocument>;

const FONT_REGULAR = 'DejaVuSans';
const FONT_BOLD = 'DejaVuSans-Bold';

const registeredDocs = new WeakSet<PdfDoc>();

function fontPath(fileName: string) {
  return path.join(process.cwd(), 'assets', 'fonts', fileName);
}

export function initCzechPdf(doc: PdfDoc) {
  if (!registeredDocs.has(doc)) {
    doc.registerFont(FONT_REGULAR, fontPath('DejaVuSans.ttf'));
    const boldPath = fontPath('DejaVuSans-Bold.ttf');
    if (fs.existsSync(boldPath)) {
      doc.registerFont(FONT_BOLD, boldPath);
    }
    registeredDocs.add(doc);
  }
  doc.font(FONT_REGULAR);
}

export function setCzechPdfBold(doc: PdfDoc) {
  const boldPath = fontPath('DejaVuSans-Bold.ttf');
  if (fs.existsSync(boldPath)) {
    doc.font(FONT_BOLD);
  } else {
    doc.font(FONT_REGULAR);
  }
}

export function setCzechPdfRegular(doc: PdfDoc) {
  doc.font(FONT_REGULAR);
}
