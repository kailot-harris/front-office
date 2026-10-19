'use client';

import React from 'react';

interface FootballIconProps {
  className?: string;
  size?: number;
}

export const FootballIcon: React.FC<FootballIconProps> = ({ className = 'w-6 h-6', size = 24 }) => {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
    >
      <path
        d="M21.5 2.5C14.5 1.5 4 6 2.5 12C1 18 6 22.5 12 21.5C18 20 22.5 9.5 21.5 2.5Z"
        fill="url(#football-gradient)"
        stroke="#10b981"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {/* Central Laces */}
      <line
        x1="7"
        y1="17"
        x2="17"
        y2="7"
        stroke="#ffffff"
        strokeWidth="1.5"
        strokeLinecap="round"
      />
      <line
        x1="9"
        y1="13"
        x2="11"
        y2="15"
        stroke="#ffffff"
        strokeWidth="1.2"
        strokeLinecap="round"
      />
      <line
        x1="11"
        y1="11"
        x2="13"
        y2="13"
        stroke="#ffffff"
        strokeWidth="1.2"
        strokeLinecap="round"
      />
      <line
        x1="13"
        y1="9"
        x2="15"
        y2="11"
        stroke="#ffffff"
        strokeWidth="1.2"
        strokeLinecap="round"
      />
      <defs>
        <linearGradient id="football-gradient" x1="2.5" y1="21.5" x2="21.5" y2="2.5" gradientUnits="userSpaceOnUse">
          <stop stopColor="#064e3b" />
          <stop offset="0.5" stopColor="#047857" />
          <stop offset="1" stopColor="#10b981" />
        </linearGradient>
      </defs>
    </svg>
  );
};
