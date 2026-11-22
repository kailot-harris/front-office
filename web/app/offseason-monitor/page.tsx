import { RedirectStub, redirectMetadata } from '@/components/RedirectStub';

export const metadata = redirectMetadata('Offseason Moves');

export default function MovedPage() {
  return <RedirectStub to="/offseason/" label="Offseason Moves" />;
}
