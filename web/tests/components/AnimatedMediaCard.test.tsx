import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { AnimatedMediaCard } from '@/components/AnimatedMediaCard';

describe('AnimatedMediaCard', () => {
  it('renders a picture element with prefers-reduced-motion media source pointing to png and img fallback pointing to gif', () => {
    const { container } = render(
      <AnimatedMediaCard
        name="gif_elo_rank_bump"
        title="Elo Rank Bump"
        alt="Animated bump chart of Elo rating movements"
        caption="Daily rank trajectories."
      />
    );

    const figure = container.querySelector('figure');
    expect(figure).toBeInTheDocument();

    const titleEl = screen.getByText('Elo Rank Bump');
    expect(titleEl).toBeInTheDocument();

    const captionEl = screen.getByText('Daily rank trajectories.');
    expect(captionEl).toBeInTheDocument();

    const picture = container.querySelector('picture');
    expect(picture).toBeInTheDocument();

    const source = picture?.querySelector('source');
    expect(source).toBeInTheDocument();
    expect(source?.getAttribute('media')).toBe('(prefers-reduced-motion: reduce)');
    expect(source?.getAttribute('srcset')).toContain('/media/gif_elo_rank_bump.png');

    const img = screen.getByRole('img');
    expect(img).toBeInTheDocument();
    expect(img.getAttribute('src')).toContain('/media/gif_elo_rank_bump.gif');
    expect(img.getAttribute('alt')).toBe('Animated bump chart of Elo rating movements');
  });

  it('handles name containing media/ prefix and file extension gracefully', () => {
    const { container } = render(
      <AnimatedMediaCard
        name="media/gif_net_rating_quadrant.gif"
        alt="Net rating quadrant scatter"
      />
    );

    const source = container.querySelector('source');
    expect(source?.getAttribute('srcset')).toContain('/media/gif_net_rating_quadrant.png');

    const img = screen.getByRole('img');
    expect(img.getAttribute('src')).toContain('/media/gif_net_rating_quadrant.gif');
    expect(img.getAttribute('alt')).toBe('Net rating quadrant scatter');
  });
});
