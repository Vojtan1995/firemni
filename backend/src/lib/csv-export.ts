/** UTF-8 CSV with BOM for Excel on Windows. */
export function csvWithBom(content: string): string {
  return `\uFEFF${content}`;
}

export const CSV_CONTENT_TYPE = 'text/csv; charset=utf-8';
