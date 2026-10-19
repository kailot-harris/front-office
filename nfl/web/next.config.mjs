const sportSlug = 'nfl';
const repoBase = process.env.PAGES_BASE_PATH ?? '';
const basePath = `${repoBase}/${sportSlug}`;

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  basePath,
  images: {
    unoptimized: true,
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'a.espncdn.com',
        pathname: '/**',
      },
      {
        protocol: 'https',
        hostname: 'static.www.nfl.com',
        pathname: '/**',
      },
      {
        protocol: 'https',
        hostname: 'static.nfl.com',
        pathname: '/**',
      },
    ],
  },
};

export default nextConfig;
