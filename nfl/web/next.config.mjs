/** @type {import('next').NextConfig} */
const nextConfig = {
  images: {
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
