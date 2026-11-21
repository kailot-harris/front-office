/** One entry of public/data/visual_media_index.json (written by export_visual_media_index.R). */
export interface VisualMediaIndexEntry {
  id: string;
  filename: string;
  title: string;
  category: VisualMediaItem['category'];
  categoryLabel: string;
  phase: number;
  description: string;
  type: 'gif' | 'image';
  previewPng: string;
  size_bytes: number;
  generated_at: string;
  duration_ms?: number | null;
}

export interface VisualMediaItem {
  id: string;
  filename: string;
  title: string;
  phase: number;
  category: 'standings' | 'postseason' | 'trends' | 'sabermetrics' | 'meta';
  categoryLabel: string;
  description: string;
  type: 'gif';
  previewPng: string;
}

/** Gallery items are exactly the index GIF entries: nothing added, nothing hand-typed. */
export function toVisualMediaItems(index: VisualMediaIndexEntry[]): VisualMediaItem[] {
  return index
    .filter((e) => e.type === 'gif')
    .map((e) => ({
      id: e.id,
      filename: e.filename,
      title: e.title,
      phase: e.phase,
      category: e.category,
      categoryLabel: e.categoryLabel,
      description: e.description,
      type: 'gif' as const,
      previewPng: e.previewPng,
    }));
}
