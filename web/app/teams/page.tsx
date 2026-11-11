import { redirect } from 'next/navigation';

export const metadata = {
  title: 'Team Standings & Projections',
  description:
    'All 30 NBA franchises ranked by ensemble projected wins, playoff odds, and title probability, with a sortable full standings table.',
};

export default function TeamsPage() {
  redirect('/?tab=table');
}

