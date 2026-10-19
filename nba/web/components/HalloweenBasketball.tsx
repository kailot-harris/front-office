'use client';

import React from 'react';

interface HalloweenBasketballProps {
  className?: string;
  size?: number;
}

export const HalloweenBasketball: React.FC<HalloweenBasketballProps> = ({
  className = 'w-6 h-6',
  size = 24,
}) => {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 32 32"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={`inline-block flex-shrink-0 drop-shadow-md ${className}`}
    >
      <title>October Halloween Basketball</title>
      <defs>
        {/* Pumpkin / Basketball base gradient */}
        <radialGradient id="spookyBallGrad" cx="35%" cy="35%" r="65%">
          <stop offset="0%" stopColor="#fb923c" />
          <stop offset="55%" stopColor="#ea580c" />
          <stop offset="90%" stopColor="#c2410c" />
          <stop offset="100%" stopColor="#7c2d12" />
        </radialGradient>

        {/* Carved Jack-o'-lantern Glowing Eye/Mouth Gradient */}
        <radialGradient id="jackGlow" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor="#ffffff" />
          <stop offset="40%" stopColor="#fef08a" />
          <stop offset="85%" stopColor="#f59e0b" />
          <stop offset="100%" stopColor="#b45309" />
        </radialGradient>

        {/* Subtle drop glow filter */}
        <filter id="emberGlow" x="-20%" y="-20%" width="140%" height="140%">
          <feGaussianBlur stdDeviation="0.8" result="blur" />
          <feComposite in="SourceGraphic" in2="blur" operator="over" />
        </filter>
      </defs>

      {/* Pumpkin Stem at the top */}
      <path
        d="M15 2C15.5 0.8 17 0.5 18 1C17.5 2.2 17.2 3.5 17 4.5C16.2 4.2 15.5 4.1 15 4.2L15 2Z"
        fill="#166534"
        stroke="#14532d"
        strokeWidth="0.5"
      />

      {/* Main Basketball Sphere */}
      <circle cx="16" cy="17" r="14" fill="url(#spookyBallGrad)" stroke="#431407" strokeWidth="1" />

      {/* Basketball Seams (Black / Dark Burnt Umber) */}
      {/* Horizontal Seam */}
      <path
        d="M2.5 17C7 16.5 25 16.5 29.5 17"
        stroke="#431407"
        strokeWidth="1.2"
        strokeLinecap="round"
        opacity="0.85"
      />
      {/* Vertical Seam */}
      <path
        d="M16 3.2C16 8 16 26 16 30.8"
        stroke="#431407"
        strokeWidth="1.2"
        strokeLinecap="round"
        opacity="0.85"
      />
      {/* Left Arc Seam */}
      <path
        d="M7 6C11 11 11 23 7 28"
        stroke="#431407"
        strokeWidth="1.1"
        strokeLinecap="round"
        opacity="0.8"
      />
      {/* Right Arc Seam */}
      <path
        d="M25 6C21 11 21 23 25 28"
        stroke="#431407"
        strokeWidth="1.1"
        strokeLinecap="round"
        opacity="0.8"
      />

      {/* Jack-o'-Lantern Carved Eyes (Glowing Triangles) */}
      {/* Left Eye */}
      <polygon
        points="10,12.5 13.5,14 11.5,15.5"
        fill="url(#jackGlow)"
        filter="url(#emberGlow)"
        stroke="#78350f"
        strokeWidth="0.4"
      />
      {/* Right Eye */}
      <polygon
        points="22,12.5 18.5,14 20.5,15.5"
        fill="url(#jackGlow)"
        filter="url(#emberGlow)"
        stroke="#78350f"
        strokeWidth="0.4"
      />

      {/* Nose (small inverted triangle) */}
      <polygon
        points="16,15.5 15,17 17,17"
        fill="url(#jackGlow)"
        filter="url(#emberGlow)"
      />

      {/* Carved Spooky Tooth Grin */}
      <path
        d="M9 20C10.5 22.5 13 24 16 24C19 24 21.5 22.5 23 20C21.5 21 20 20.5 19.5 21.5C19 22.5 17.5 21 16 22C14.5 21 13 22.5 12.5 21.5C12 20.5 10.5 21 9 20Z"
        fill="url(#jackGlow)"
        filter="url(#emberGlow)"
        stroke="#78350f"
        strokeWidth="0.5"
      />

      {/* Subtle October Night Sparkle */}
      <circle cx="23" cy="8" r="0.8" fill="#fef08a" opacity="0.9" />
    </svg>
  );
};
