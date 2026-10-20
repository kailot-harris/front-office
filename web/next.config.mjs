const sportSlug = 'mlb';
const repoBase = process.env.PAGES_BASE_PATH ?? '';
const basePath = `${repoBase}/${sportSlug}`;

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
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
