import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  transpilePackages: ["@jobstack/db"],
};

export default nextConfig;
