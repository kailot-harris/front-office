import { getVisualMediaIndex } from '@/lib/data';
import GalleryClient from '@/components/GalleryClient';

export const metadata = {
  title: 'Visual Media Gallery & Race Animations | NFL Analytics',
  description: '17+ automated animated races, division trajectory plots, and point differential heatmaps.',
};

export default function GalleryPage() {
  const mediaItems = getVisualMediaIndex();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <GalleryClient mediaItems={mediaItems} />
    </div>
  );
}
