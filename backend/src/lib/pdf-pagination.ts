import PDFDocument from 'pdfkit';

type PdfDoc = InstanceType<typeof PDFDocument>;

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
