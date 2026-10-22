import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { CoachImpactProfile } from '@/components/CoachImpactProfile';
import { loadAllDatasets } from '../helpers/datasets';

const { coaches } = loadAllDatasets();

/**
 * Issue #14: the old "Talent-to-Wins Bridge" drew four tactical rows as waterfall
 * steps under a headline gap they were never calibrated against, so the visual
 * asserted `baseline + sum(deltas) = final` when that held for no coach.
 *
 * These tests lock in the replacement contract: the gap is described as a model
 * residual between two projection variants, and the tactical rows are explicitly
 * NOT a decomposition of it.
 */
describe('CoachImpactProfile', () => {
  it('frames the headline as a projection gap between two model variants', () => {
    const coach = coaches[0];
    render(<CoachImpactProfile coach={coach} />);

    expect(
      screen.getByText(`Coaching Impact Profile: ${coach.headCoach.name}`),
    ).toBeInTheDocument();
    expect(screen.getByText(/Projection gap/)).toBeInTheDocument();
    expect(
      screen.getByText(`${coach.metrics.talentExpectedWins} W`),
    ).toBeInTheDocument();
    expect(
      screen.getByText(`${coach.metrics.actualProjectedWins} W`),
    ).toBeInTheDocument();
  });

  it('states that the tactical indicators do not sum to the gap', () => {
    const coach = coaches[0];
    render(<CoachImpactProfile coach={coach} />);

    expect(
      screen.getByText(/do not sum to the projection gap/i),
    ).toBeInTheDocument();
    expect(screen.getByText(/not a decomposition/i)).toBeInTheDocument();
    expect(screen.getByText(/no tactical sub-metric is added/i)).toBeInTheDocument();
  });

  it('never restores the old waterfall bridge copy', () => {
    const coach = coaches[0];
    render(<CoachImpactProfile coach={coach} />);

    expect(screen.queryByText(/Talent-to-Wins/i)).toBeNull();
    expect(screen.queryByText(/Wins Added/i)).toBeNull();
    expect(screen.queryByText(/Wins Lost/i)).toBeNull();
    expect(screen.queryByText(/Decomposing roster baseline/i)).toBeNull();
  });

  it('surfaces per-field provenance, including synthetic bands', () => {
    const coach = coaches[0];
    render(<CoachImpactProfile coach={coach} />);

    expect(screen.getAllByText('Observed PBP').length).toBeGreaterThan(0);
    expect(screen.getAllByText('Synthetic band').length).toBeGreaterThan(0);
  });

  it('reports the ATO and challenge values from the dataset verbatim', () => {
    const coach = coaches[0];
    const { metrics } = coach;
    render(<CoachImpactProfile coach={coach} />);

    expect(
      screen.getByText(
        `${metrics.atoOffensivePpp.toFixed(3)} for / ${metrics.atoDefensivePppAllowed.toFixed(3)} allowed`,
      ),
    ).toBeInTheDocument();
    expect(
      screen.getByText(
        new RegExp(`${(metrics.challengeSuccessRate * 100).toFixed(1)}% success`),
      ),
    ).toBeInTheDocument();
  });
});
