import { getSalaryCapData } from '@/lib/data';
import SalaryCapClient from '@/components/SalaryCapClient';

export const metadata = {
  title: 'Salary Cap & Positional Allocation | NFL Analytics',
  description: 'NFL salary cap tracker, positional cash spending breakdown, and top 100 contracts from OverTheCap.',
};

export default function SalaryCapPage() {
  const data = getSalaryCapData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <SalaryCapClient data={data} />
    </div>
  );
}
