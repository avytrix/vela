import { createMDX } from "fumadocs-mdx/next";

/*
 * The site is served at https://avytrix.dev/opensource/gitlab-vela: avytrix.dev builds this
 * folder in its own CI and copies out/ under that path. NEXT_PUBLIC_SITE_URL is the origin only,
 * NEXT_PUBLIC_BASE_PATH the path prefix. Both default to production, so a plain `pnpm build`
 * gives the deployable site. Set NEXT_PUBLIC_BASE_PATH="" to serve from the root.
 */
const origin = (process.env.NEXT_PUBLIC_SITE_URL ?? "https://avytrix.dev").replace(/\/+$/, "");
const basePath = (process.env.NEXT_PUBLIC_BASE_PATH ?? "/opensource/gitlab-vela").replace(/\/+$/, "");

/** @type {import('next').NextConfig} */
const config = {
	reactStrictMode: true,
	// Static HTML export: GitHub Pages serves files, not a Node server.
	output: "export",
	// No trailing slash, like avytrix.dev: a page is exported as <route>.html and GitHub Pages
	// answers /<route> with it directly, so the canonical URL has no slash and no redirect.
	trailingSlash: false,
	basePath,
	// next/image optimization needs a server.
	images: { unoptimized: true },
	// The resolved values, so client code sees the same defaults as the server.
	env: {
		NEXT_PUBLIC_SITE_URL: origin,
		NEXT_PUBLIC_BASE_PATH: basePath,
	},
};

export default createMDX()(config);
