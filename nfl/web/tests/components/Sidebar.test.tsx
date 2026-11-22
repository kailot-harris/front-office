import { describe, expect, it } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { Sidebar } from '../../components/Sidebar';

const HOME = 'Front Office home';

describe('Sidebar Front Office home link (#220)', () => {
  it('is the first link, above the sport name, pointing at /front-office/', () => {
    const { container } = render(<Sidebar />);
    const aside = container.querySelector('aside') as HTMLElement;
    const first = aside.querySelector('a') as HTMLAnchorElement;
    expect(first).toHaveTextContent(HOME);
    expect(first.getAttribute('href')).toBe('/front-office/');
    expect(first).not.toHaveAttribute('aria-current');
    const brand = Array.from(aside.querySelectorAll('span')).find((s) => s.textContent === 'NFL') as HTMLElement;
    expect(first.compareDocumentPosition(brand) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('also appears in the phone drawer', () => {
    render(<Sidebar />);
    expect(screen.getAllByText(HOME)).toHaveLength(1);
    fireEvent.click(screen.getByLabelText('Toggle navigation menu'));
    const links = screen.getAllByText(HOME).map((el) => el.closest('a') as HTMLAnchorElement);
    expect(links).toHaveLength(2);
    for (const a of links) {
      expect(a.getAttribute('href')).toBe('/front-office/');
      expect(a).not.toHaveAttribute('aria-current');
    }
  });

  it('orders nav items with the season state', () => {
    const { container } = render(<Sidebar seasonState="offseason" />);
    const navLabels = Array.from(container.querySelectorAll('aside a span.font-semibold')).map((s) => s.textContent);
    expect(navLabels[0]).toBe('Season Standings');
    expect(navLabels).toContain('Visual Gallery');
  });
});
