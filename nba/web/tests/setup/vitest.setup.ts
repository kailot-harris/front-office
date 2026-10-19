import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach, vi } from 'vitest';
import React from 'react';
import fs from 'fs';
import path from 'path';

afterEach(() => cleanup());

vi.mock('next/image', () => ({
  default: ({ src, alt, ...rest }: Record<string, unknown>) =>
    React.createElement('img', { src, alt, ...rest }),
}));

vi.mock('next/navigation', () => ({
  usePathname: () => '/',
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn(), back: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));

if (!Element.prototype.getBoundingClientRect.call(document.body).width) {
  Element.prototype.getBoundingClientRect = function () {
    return { width: 800, height: 400, top: 0, left: 0, bottom: 400, right: 800, x: 0, y: 0, toJSON: () => ({}) } as DOMRect;
  };
}

// Mock global fetch for ShotsExplorerClient resolving /data/shots/<id>.json from local public directory
const originalFetch = global.fetch;
global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
  const url = typeof input === 'string' ? input : input.toString();
  if (url.includes('/data/shots/')) {
    const filename = url.split('/data/shots/')[1]?.split('?')[0];
    const filePath = path.join(process.cwd(), 'public', 'data', 'shots', filename);
    if (fs.existsSync(filePath)) {
      const data = JSON.parse(fs.readFileSync(filePath, 'utf-8'));
      return {
        ok: true,
        status: 200,
        json: async () => data,
      } as Response;
    }
    return {
      ok: false,
      status: 404,
      json: async () => ({ error: 'Not found' }),
    } as Response;
  }
  return originalFetch ? originalFetch(input, init) : ({} as Response);
}) as any;
