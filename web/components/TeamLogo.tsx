'use client';

import React, { useState } from 'react';
import { getTeamLogoUrl, NFL_TEAMS_METADATA } from '@/lib/teams';

export interface TeamLogoProps {
  team: string;
  size?: 'xs' | 'sm' | 'md' | 'lg' | 'xl' | '2xl';
  className?: string;
  showFallbackText?: boolean;
}

const SIZE_MAP = {
  xs: 'w-4 h-4',   // 16px - compact tables
  sm: 'w-6 h-6',   // 24px - lists / badge cards
  md: 'w-8 h-8',   // 32px - standings rows
  lg: 'w-10 h-10', // 40px - game cards
  xl: 'w-12 h-12', // 48px - matchup hero cards
  '2xl': 'w-16 h-16', // 64px - team profiles
};

export const TeamLogo: React.FC<TeamLogoProps> = ({
  team,
  size = 'md',
  className = '',
  showFallbackText = true,
}) => {
  const [hasError, setHasError] = useState(false);
  const normalized = team?.toUpperCase();
  const meta = NFL_TEAMS_METADATA[normalized];
  const logoUrl = getTeamLogoUrl(normalized);
  const sizeClass = SIZE_MAP[size] || SIZE_MAP.md;

  if (hasError || !logoUrl) {
    if (!showFallbackText) return null;
    return (
      <span
        className={`${sizeClass} rounded-md bg-slate-800 border border-slate-700/80 flex items-center justify-center font-bold text-[10px] tracking-wider text-emerald-400 font-mono flex-shrink-0 select-none shadow-sm ${className}`}
        title={meta?.fullName || team}
      >
        {normalized?.slice(0, 3)}
      </span>
    );
  }

  return (
    <div
      className={`relative inline-flex items-center justify-center flex-shrink-0 ${className}`}
      title={meta?.fullName || team}
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={logoUrl}
        alt={`${meta?.fullName || team} logo`}
        className={`${sizeClass} object-contain drop-shadow select-none`}
        loading="lazy"
        onError={() => setHasError(true)}
      />
    </div>
  );
};
