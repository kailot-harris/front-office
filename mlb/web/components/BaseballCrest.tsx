'use client';

import React from 'react';

interface BaseballCrestProps {
  className?: string;
  size?: number;
}

export const BaseballCrest: React.FC<BaseballCrestProps> = ({
  className = 'w-7 h-7',
  size = 28,
}) => {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 64 64"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
    >
      {/* Outer Diamond Field Frame */}
      <path
        d="M32 4L60 32L32 60L4 32L32 4Z"
        fill="#0F172A"
        stroke="#38BDF8"
        strokeWidth="2.5"
      />
      {/* Core Baseball Sphere */}
      <circle cx="32" cy="32" r="18" fill="#F8FAFC" stroke="#94A3B8" strokeWidth="1.5" />
      {/* Left Crimson Seam */}
      <path
        d="M21 18C26 24 26 40 21 46"
        stroke="#E11D48"
        strokeWidth="2.2"
        strokeLinecap="round"
        strokeDasharray="2.5 2.5"
      />
      {/* Right Crimson Seam */}
      <path
        d="M43 18C38 24 38 40 43 46"
        stroke="#E11D48"
        strokeWidth="2.2"
        strokeLinecap="round"
        strokeDasharray="2.5 2.5"
      />
      {/* Basepath Corner Nodes */}
      <rect x="30" y="6" width="4" height="4" fill="#F59E0B" />
      <rect x="54" y="30" width="4" height="4" fill="#F59E0B" />
      <rect x="30" y="54" width="4" height="4" fill="#F59E0B" />
      <rect x="6" y="30" width="4" height="4" fill="#F59E0B" />
    </svg>
  );
};
