import type { VisualMediaItem } from '@/components/GalleryClient';

/** One entry of public/data/visual_media_index.json (written by export_visual_media_index.R). */
export interface VisualMediaIndexEntry {
  id: string;
  filename: string;
  title: string;
  category: VisualMediaItem['category'];
  description: string;
  type: 'gif' | 'image';
  size_bytes: number;
  generated_at: string;
  duration_ms?: number | null;
}

/** Gallery items are exactly the index entries: nothing added, nothing hand-typed. */
export function toGalleryItems(index: VisualMediaIndexEntry[]): VisualMediaItem[] {
  return index.map((e) => ({
    id: e.id,
    filename: e.filename,
    title: e.title,
    category: e.category,
    description: e.description,
    type: e.type,
    sizeBytes: e.size_bytes,
  }));
}
