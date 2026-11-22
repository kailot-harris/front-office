import { RedirectStub, redirectMetadata } from '@/components/RedirectStub';

export const metadata = redirectMetadata('Playoff Simulator');

export default function MovedPage() {
  return <RedirectStub to="/playoffs/" label="Playoff Simulator" />;
}
