/**
 * Client-side CSV export utility.
 *
 * Builds CSV text from an array of row objects + an ordered column
 * definition, then triggers a browser download via a Blob + object URL.
 * No server/API involvement — safe to call from a fully static export.
 */

export interface CsvColumn {
  key: string;
  label: string;
}

function toCsvCell(value: unknown): string {
  if (value === null || value === undefined) {
    return '';
  }

  let str: string;
  if (typeof value === 'number' || typeof value === 'boolean') {
    str = String(value);
  } else if (value instanceof Date) {
    str = value.toISOString();
  } else if (typeof value === 'object') {
    str = JSON.stringify(value);
  } else {
    str = String(value);
  }

  if (/[",\n\r]/.test(str)) {
    str = `"${str.replace(/"/g, '""')}"`;
  }

  return str;
}

export function exportToCsv(
  data: Record<string, unknown>[],
  columns: CsvColumn[],
  filename: string
): void {
  if (typeof window === 'undefined' || typeof document === 'undefined') {
    return;
  }

  const header = columns.map((col) => toCsvCell(col.label)).join(',');
  const rows = data.map((row) =>
    columns.map((col) => toCsvCell(row[col.key])).join(',')
  );
  const csvText = [header, ...rows].join('\r\n');

  const blob = new Blob(['﻿' + csvText], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);

  const normalizedFilename = filename.toLowerCase().endsWith('.csv')
    ? filename
    : `${filename}.csv`;

  const link = document.createElement('a');
  link.href = url;
  link.download = normalizedFilename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}
