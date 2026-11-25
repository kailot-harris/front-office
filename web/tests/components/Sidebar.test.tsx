import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { Sidebar } from '../../components/Sidebar';

const { mockPathname } = vi.hoisted(() => ({
  mockPathname: vi.fn(() => '/'),
}));

vi.mock('next/navigation', () => ({
  usePathname: () => mockPathname(),
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn(), back: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));

const HOME = 'Front Office home';
const GROUP_LABELS = ['Season & Games', 'Player', 'Front Office', 'Visualizations', 'Models'];

describe('Sidebar Front Office home link (#220)', () => {
  beforeEach(() => {
    mockPathname.mockReturnValue('/');
    window.localStorage.clear();
  });

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
});

describe('Sidebar collapsible groups (#230)', () => {
  beforeEach(() => {
    mockPathname.mockReturnValue('/');
    window.localStorage.clear();
  });

  it('renders all 5 group headings as <button type="button" aria-expanded> in desktop and mobile', () => {
    const { container } = render(<Sidebar />);
    const aside = container.querySelector('aside') as HTMLElement;
    const desktopButtons = GROUP_LABELS.map((label) => {
      const btn = Array.from(aside.querySelectorAll('button')).find((b) => b.textContent?.includes(label));
      expect(btn).toBeTruthy();
      expect(btn?.getAttribute('type')).toBe('button');
      expect(btn).toHaveAttribute('aria-expanded');
      return btn!;
    });
    expect(desktopButtons[0]).toHaveAttribute('aria-expanded', 'true');
    expect(desktopButtons[1]).toHaveAttribute('aria-expanded', 'false');

    fireEvent.click(screen.getByLabelText('Toggle navigation menu'));
    for (const label of GROUP_LABELS) {
      expect(screen.getAllByRole('button', { name: label })).toHaveLength(2);
    }
  });

  it('promotes Front Office to top and defaultOpen in offseason', () => {
    const { container } = render(<Sidebar seasonState="offseason" />);
    const aside = container.querySelector('aside') as HTMLElement;
    const groupHeadings = Array.from(aside.querySelectorAll('nav button')).map((b) => b.textContent?.trim());
    expect(groupHeadings).toEqual(['Front Office', 'Season & Games', 'Player', 'Visualizations', 'Models']);

    const frontOfficeBtn = aside.querySelector('nav button') as HTMLButtonElement;
    expect(frontOfficeBtn).toHaveAttribute('aria-expanded', 'true');
    expect(aside).toHaveTextContent('Payroll & Cap');
    expect(aside).toHaveTextContent('Coaching Staffs');
  });

  it('keeps the active group always open and marks the active link with aria-current="page"', () => {
    mockPathname.mockReturnValue('/players/');
    const { container } = render(<Sidebar />);
    const aside = container.querySelector('aside') as HTMLElement;
    const playerBtn = Array.from(aside.querySelectorAll('nav button')).find((b) =>
      b.textContent?.includes('Player'),
    ) as HTMLButtonElement;
    expect(playerBtn).toHaveAttribute('aria-expanded', 'true');

    // Clicking the active group heading keeps it open
    fireEvent.click(playerBtn);
    expect(playerBtn).toHaveAttribute('aria-expanded', 'true');

    const activeLink = aside.querySelector('a[href="/players"]') as HTMLAnchorElement;
    expect(activeLink).toHaveAttribute('aria-current', 'page');
  });

  it('persists manually opened groups in localStorage across mounts', () => {
    const { container, unmount } = render(<Sidebar />);
    const aside = container.querySelector('aside') as HTMLElement;
    const modelsBtn = Array.from(aside.querySelectorAll('nav button')).find((b) =>
      b.textContent?.includes('Models'),
    ) as HTMLButtonElement;

    expect(modelsBtn).toHaveAttribute('aria-expanded', 'false');
    fireEvent.click(modelsBtn);
    expect(modelsBtn).toHaveAttribute('aria-expanded', 'true');
    expect(aside).toHaveTextContent('Diagnostics');

    unmount();

    const remounted = render(<Sidebar />);
    const aside2 = remounted.container.querySelector('aside') as HTMLElement;
    const modelsBtn2 = Array.from(aside2.querySelectorAll('nav button')).find((b) =>
      b.textContent?.includes('Models'),
    ) as HTMLButtonElement;
    expect(modelsBtn2).toHaveAttribute('aria-expanded', 'true');
    expect(aside2).toHaveTextContent('Diagnostics');
  });

  it('handles unavailable localStorage gracefully', () => {
    const getSpy = vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('SecurityError');
    });
    const setSpy = vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('SecurityError');
    });

    const { container } = render(<Sidebar />);
    const aside = container.querySelector('aside') as HTMLElement;
    const modelsBtn = Array.from(aside.querySelectorAll('nav button')).find((b) =>
      b.textContent?.includes('Models'),
    ) as HTMLButtonElement;

    fireEvent.click(modelsBtn);
    expect(modelsBtn).toHaveAttribute('aria-expanded', 'true');

    getSpy.mockRestore();
    setSpy.mockRestore();
  });
});
