import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { GalleryClient } from '@/components/GalleryClient';
import { toGalleryItems, type VisualMediaIndexEntry } from '@/lib/visualMedia';

const fixtureIndex: VisualMediaIndexEntry[] = [
  {
    id: 'fixture_one', filename: 'fixture_one.gif', title: 'Fixture One Title', category: 'standings',
    description: 'First fixture description.', type: 'gif', size_bytes: 2048,
    generated_at: '2026-11-19T12:00:00Z', duration_ms: 3000,
  },
  {
    id: 'fixture_two', filename: 'fixture_two.png', title: 'Fixture Two Title', category: 'shots',
    description: 'Second fixture description.', type: 'image', size_bytes: 1024,
    generated_at: '2026-11-18T12:00:00Z',
  },
];

describe('GalleryClient reads the visual media index', () => {
  it('gallery renders every index item and nothing else', () => {
    render(<GalleryClient mediaItems={toGalleryItems(fixtureIndex)} />);
    const headings = screen.getAllByRole('heading', { level: 2 }).map((h) => h.textContent);
    expect(headings).toEqual(['Fixture One Title', 'Fixture Two Title']);
    expect(screen.getByText('First fixture description.')).toBeInTheDocument();
    expect(screen.getByText('Second fixture description.')).toBeInTheDocument();
    expect(screen.getByText('2 Visual Artifacts Synced')).toBeInTheDocument();
  });
});
