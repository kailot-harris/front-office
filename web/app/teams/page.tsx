import { Metadata } from 'next';
import { redirect } from 'next/navigation';

export const metadata: Metadata = {
  title: 'Team Standings',
  description: 'Full sortable WNBA standings table for all 15 franchises — redirects to the home dashboard table view.',
};

export default function TeamsPage() {
  redirect('/?tab=table');
}
