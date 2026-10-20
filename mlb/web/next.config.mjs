const sportSlug = 'mlb';
const repoBase = process.env.PAGES_BASE_PATH ?? '';
const basePath = `${repoBase}/${sportSlug}`;

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  // Re-exposed so lib/basePath.ts's `process.env.PAGES_BASE_PATH` is inlined into the client
  // bundle at build time. Without this, Next only replaces NODE_ENV and NEXT_PUBLIC_* vars in
  // client code, so BASE_PATH silently fell back to '' in the browser and every hand-written
  // asset path resolved to /mlb/... instead of /front-office/mlb/... and 404'd.
  env: { PAGES_BASE_PATH: repoBase },
  trailingSlash: true,
  basePath,
  images: {
    unoptimized: true,
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'a.espncdn.com',
        pathname: '/i/teamlogos/**',
      },
      {
        protocol: 'https',
        hostname: 'www.mlbstatic.com',
        pathname: '/team-logos/**',
      },
    ],
  },
};

export default nextConfig;
