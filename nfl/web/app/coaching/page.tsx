import { RedirectStub, redirectMetadata } from '@/components/RedirectStub';

export const metadata = redirectMetadata('Coaching Staffs');

export default function MovedPage() {
  return <RedirectStub to="/coaches/" label="Coaching Staffs" />;
}
