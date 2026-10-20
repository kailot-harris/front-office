// Published as a static export to GitHub Pages under /front-office/mlb/, not domain root -
// basePath/assetPrefix must match lib/basePath.ts's BASE_PATH exactly (same NODE_ENV==='production'
// gate) or framework-managed assets resolve correctly while hand-written asset paths (team logos,
// shot-chart JSON fetches) 404. trailingSlash matches GitHub Pages' directory-style URLs
// (.../players/ instead of .../players).
const isProd = process.env.NODE_ENV === 'production';
const basePath = isProd ? '/front-office/mlb' : '';

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  basePath,
  assetPrefix: basePath,
  trailingSlash: true,
  images: {
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
