import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  cacheComponents: true,
  partialPrefetching: true,
  // Old Now addresses forward to the single Now page. Done here rather than with
  // redirect() in a page, so the redirect never runs during rendering.
  async redirects() {
    return [
      { source: "/now/filmmaking", destination: "/now", permanent: false },
      { source: "/now/acting", destination: "/now", permanent: false },
    ];
  },
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
