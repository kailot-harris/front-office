import { describe, it, expect } from 'vitest';
import { render, screen, fireEvent, within } from '@testing-library/react';


import { Sidebar } from '@/components/Sidebar';

describe('Sidebar Front Office home link (#220)', () => {
  it('is the first link in the desktop sidebar, pointing to /front-office/', () => {
    const { container } = render(<Sidebar />);
    const first = container.querySelector('aside a');
    expect(first?.textContent).toContain('Front Office home');
    expect(first?.getAttribute('href')).toBe('/front-office/');
    expect(first?.hasAttribute('aria-current')).toBe(false);
    expect(first?.className).not.toMatch(/bg-accent-600/);
  });
  it('is the first link in the phone drawer', () => {
    render(<Sidebar />);
    fireEvent.click(screen.getByLabelText(/toggle navigation menu/i));
    const drawer = screen.getByRole('dialog');
    const first = within(drawer).getAllByRole('link')[0];
    expect(first.textContent).toContain('Front Office home');
    expect(first.getAttribute('href')).toBe('/front-office/');
    expect(first.hasAttribute('aria-current')).toBe(false);
  });
  it('orders nav groups with Front Office first and open when seasonState is offseason', () => {
    const { container } = render(<Sidebar seasonState="offseason" />);
    const labels = Array.from(container.querySelectorAll('aside a')).filter((a) => !a.closest('nav[aria-label="Switch sport"]')).map((a) => a.getAttribute('href'));
    expect(labels[1]).toBe('/cap-sheet');
    expect(labels[2]).toBe('/coaches');
    expect(labels[3]).toBe('/offseason');
    expect(labels[4]).toBe('/');
  });
});
