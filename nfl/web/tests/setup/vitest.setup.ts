import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach, vi } from 'vitest';
import React from 'react';

afterEach(() => cleanup());

/**
 * `next/image` needs the Next build pipeline to resolve its loader, which does
 * not exist under vitest. GalleryClient is the only consumer; swap in a plain
 * <img> so the component's own logic (filtering, lightbox, download links) is
 * what gets exercised.
 */
vi.mock('next/image', () => ({
  default: ({ src, alt, ...rest }: Record<string, unknown>) =>
    React.createElement('img', { src, alt, ...rest }),
}));

/** Components rendered outside a Next router still call usePathname()/useRouter(). */
vi.mock('next/navigation', () => ({
  usePathname: () => '/',
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn(), back: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));

/** jsdom has no layout engine, so chart components that measure DOM get zeros. */
if (!Element.prototype.getBoundingClientRect.call(document.body).width) {
  Element.prototype.getBoundingClientRect = function () {
    return { width: 800, height: 400, top: 0, left: 0, bottom: 400, right: 800, x: 0, y: 0, toJSON: () => ({}) } as DOMRect;
  };
}
