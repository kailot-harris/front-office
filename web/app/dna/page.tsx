import { RedirectStub, redirectMetadata } from '@/components/RedirectStub';

export const metadata = redirectMetadata('Player DNA & Peer Comps');

export default function MovedPage() {
  return <RedirectStub to="/player-dna/" label="Player DNA & Peer Comps" />;
}
