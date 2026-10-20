// Published as a static export to GitHub Pages under /front-office/nfl/, not domain root -
// basePath/assetPrefix must match lib/basePath.ts's BASE_PATH exactly (same NODE_ENV==='production'
// gate) or framework-managed assets resolve correctly while hand-written asset paths (gallery
// animations, shot-chart JSON fetches) 404. trailingSlash matches GitHub Pages' directory-style
// URLs (.../players/ instead of .../players). images.unoptimized is required alongside
// output:'export' because next/image's default loader has no server to optimize against in a
// static export (GalleryClient.tsx uses next/image).
const isProd = process.env.NODE_ENV === 'production';
const basePath = isProd ? '/front-office/nfl' : '';

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  basePath,
  assetPrefix: basePath,
  trailingSlash: true,
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
