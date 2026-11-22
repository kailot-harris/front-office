import { BASE_PATH } from '@/lib/basePath';

/**
 * A page that only forwards visitors to a page's new address (#211).
 *
 * The site is a static export on GitHub Pages, so there are no server
 * redirects. Each old address keeps a tiny page that forwards in three ways:
 * an inline script (instant, keeps the query string and #hash), a meta
 * refresh (works with scripts off), and a plain link as a last resort.
 * Pair it with `redirectMetadata()` so search engines drop the old address.
 */
export function redirectMetadata(label: string) {
  return {
    title: `${label} has moved`,
    robots: { index: false, follow: true },
  };
}

export function RedirectStub({ to, label }: { to: string; label: string }) {
  const target = `${BASE_PATH}${to}`;
  const script = `location.replace(${JSON.stringify(target)}+location.search+location.hash);`;
  return (
    <div className="max-w-xl mx-auto px-4 py-16 text-center" data-testid="redirect-stub">
      <meta httpEquiv="refresh" content={`0; url=${target}`} />
      <script dangerouslySetInnerHTML={{ __html: script }} />
      <p className="text-slate-300">
        {label} has moved to <a className="underline text-orange-400" href={target}>a new address</a>.
      </p>
    </div>
  );
}
