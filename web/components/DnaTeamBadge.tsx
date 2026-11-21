'use client';

import React from 'react';
import { TeamLogo, TeamLogoProps } from '@/components/TeamLogo';
import { MULTI_TEAM_LABEL, MULTI_TEAM_NOTE } from '@/lib/playerDnaTypes';

interface DnaTeamBadgeProps {
  // null = the player played for 2+ clubs this season (no single team to show)
  team: string | null;
  size?: TeamLogoProps['size'];
}

const SIZE_MAP = { xs: 'w-4 h-4', sm: 'w-6 h-6', md: 'w-8 h-8', lg: 'w-10 h-10', xl: 'w-12 h-12' };

/** Team logo for a /player-dna player; a null team gets a neutral "2+" badge, never a logo lookup. */
export const DnaTeamBadge: React.FC<DnaTeamBadgeProps> = ({ team, size = 'md' }) => {
  if (team) return <TeamLogo team={team} size={size} />;
  return (
    <span
      className={`${SIZE_MAP[size]} rounded bg-slate-800 border border-slate-700/80 flex items-center justify-center font-bold text-[11px] sm:text-[10px] text-slate-300 font-mono flex-shrink-0`}
      title={`${MULTI_TEAM_LABEL}: ${MULTI_TEAM_NOTE}`}
      aria-label={MULTI_TEAM_LABEL}
      role="img"
    >
      2+
    </span>
  );
};
