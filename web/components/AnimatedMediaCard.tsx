'use client';

import React from 'react';
import { BASE_PATH } from '@/lib/basePath';

export interface AnimatedMediaCardProps {
  /** Base filename without extension (e.g. 'gif_elo_rank_bump') or path relative to public/media */
  name: string;
  /** Accessible alt text describing the visualization's conclusion and content */
  alt: string;
  /** Optional title displayed above the graphic */
  title?: string;
  /** Optional caption or methodological context rendered below the graphic */
  caption?: string;
  /** Image width attribute (default: 1000) */
  width?: number;
  /** Image height attribute (default: 600) */
  height?: number;
  /** Additional outer container CSS class name */
  className?: string;
}

/**
 * AnimatedMediaCard component
 *
 * Implements accessible, reduced-motion friendly animated visualization presentation.
 * Features:
 * - Uses HTML5 `<picture>` element with `(prefers-reduced-motion: reduce)` media query.
 * - Reduced motion source targets the companion static PNG (final frame), avoiding unnecessary animation loops.
 * - Default `<img>` fallback loads the animated GIF.
 * - Supports clean caption and title labeling for screen readers and visual presentation.
 * - Handles base path resolution via BASE_PATH for sub-path hosting compatibility.
 */
export const AnimatedMediaCard: React.FC<AnimatedMediaCardProps> = ({
  name,
  alt,
  title,
  caption,
  width = 1000,
  height = 600,
  className = '',
}) => {
  // Strip any leading slashes or existing extensions from name
  const cleanName = name.replace(/^\/+/, '').replace(/\.(gif|png)$/i, '');
  const basePathPrefix = cleanName.startsWith('media/') ? `${BASE_PATH}/` : `${BASE_PATH}/media/`;
  const gifSrc = `${basePathPrefix}${cleanName}.gif`;
  const pngSrc = `${basePathPrefix}${cleanName}.png`;

  return (
    <figure className={`overflow-hidden rounded-xl border border-slate-800 bg-surface-raised/60 ${className}`}>
      {title && (
        <div className="border-b border-slate-800/80 px-4 py-3 bg-surface/80">
          <h4 className="text-sm font-bold text-white tracking-wide">{title}</h4>
        </div>
      )}
      <div className="relative overflow-hidden bg-slate-950/40">
        <picture>
          <source media="(prefers-reduced-motion: reduce)" srcSet={pngSrc} />
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={gifSrc}
            alt={alt}
            width={width}
            height={height}
            loading="lazy"
            className="block h-auto w-full object-contain"
          />
        </picture>
      </div>
      {caption && (
        <figcaption className="border-t border-slate-800/60 px-4 py-2.5 text-xs text-slate-400 bg-surface/40 leading-relaxed">
          {caption}
        </figcaption>
      )}
    </figure>
  );
};

export default AnimatedMediaCard;
