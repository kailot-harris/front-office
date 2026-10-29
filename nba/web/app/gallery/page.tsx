import GalleryClient from '@/components/GalleryClient';

export const metadata = {
  title: 'Visual Media Gallery & Race Animations | NBA Analytics',
  description: 'Automated animated races, Elo trajectory bump charts, and net rating quadrant scatter plots.',
};

export default function GalleryPage() {
  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <GalleryClient />
    </div>
  );
}
