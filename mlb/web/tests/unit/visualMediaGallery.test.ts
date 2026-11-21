import { describe, expect, it } from 'vitest';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { VisualMediaGalleryClient } from '@/components/VisualMediaGalleryClient';
import { toVisualMediaItems, type VisualMediaIndexEntry } from '@/lib/visualMedia';

const fixtureIndex: VisualMediaIndexEntry[] = [
  {
    id: 'fixture_one', filename: 'fixture_one.gif', previewPng: 'fixture_one.png', title: 'Fixture One Title',
    category: 'standings', categoryLabel: 'Standings & Parity', phase: 1,
    description: 'First fixture description.', type: 'gif', size_bytes: 2048,
    generated_at: '2026-11-19T12:00:00Z', duration_ms: 3000,
  },
  {
    id: 'fixture_two', filename: 'fixture_two.gif', previewPng: 'fixture_two.png', title: 'Fixture Two Title',
    category: 'postseason', categoryLabel: 'October Postseason', phase: 2,
    description: 'Second fixture description.', type: 'gif', size_bytes: 1024,
    generated_at: '2026-11-18T12:00:00Z', duration_ms: null,
  },
];

describe('VisualMediaGalleryClient reads the visual media index', () => {
  it('gallery renders every index item and nothing else', () => {
    const html = renderToStaticMarkup(
      React.createElement(VisualMediaGalleryClient, { mediaItems: toVisualMediaItems(fixtureIndex) }),
    );
    const h3 = [...html.matchAll(/<h3[^>]*>\s*([^<]*?)\s*<\/h3>/g)].map((m) => m[1]);
    expect(h3.filter((t) => t.startsWith('Fixture'))).toEqual(['Fixture One Title', 'Fixture Two Title']);
    expect(html).toContain('First fixture description.');
    expect(html).toContain('Second fixture description.');
    expect(html).toContain('All 2 Animations');
    expect(html).not.toContain('Division Standings Win Race');
  });
});
