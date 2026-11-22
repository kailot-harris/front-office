import { RedirectStub, redirectMetadata } from '@/components/RedirectStub';

export const metadata = redirectMetadata('Payroll & Cap');

export default function MovedPage() {
  return <RedirectStub to="/cap-sheet/" label="Payroll & Cap" />;
}
