import type { Metadata } from "next";

/*
 * Origin and base path come from next.config.mjs, which resolves the defaults and passes them
 * through `env`, so these are the same values on the server and in the browser.
 */
const origin = (process.env.NEXT_PUBLIC_SITE_URL ?? "https://avytrix.dev").replace(/\/+$/, "");
export const basePath = (process.env.NEXT_PUBLIC_BASE_PATH ?? "/opensource/gitlab-vela").replace(/\/+$/, "");

export const siteConfig = {
	name: "vela",
	/** origin + basePath: the root every absolute URL starts from. */
	url: `${origin}${basePath}`,
	/** The home page <title>: at most 60 characters, ending with the suffix every page uses. */
	homeTitle: "Folder and file permissions for GitLab CE | vela",
	description:
		"vela adds folder and file permissions (view, read and write) to self-hosted GitLab CE. Open source and MIT licensed, tested live on GitLab CE 15.11 to 19.5.",
	github: "https://github.com/avytrix/vela",
	sponsor: "https://github.com/sponsors/avytrix",
	license: "MIT",
	logo: "/avytrix-icon.png",
	organization: {
		name: "Avytrix Technologies",
		url: "https://avytrix.dev",
		opensource: "https://avytrix.dev/opensource",
		contact: "https://avytrix.dev/contact",
	},
};

/** A file in public/, with the base path: plain <img> tags do not get it from Next. */
export function asset(path: string): string {
	return `${basePath}${path}`;
}

/** The one URL form for a page: origin + basePath + path, no trailing slash. */
export function absoluteUrl(path = "/"): string {
	const clean = (path.split("#")[0] ?? "/").replace(/\/+$/, "");
	return `${siteConfig.url}${clean}`;
}

export const indexRobots = {
	index: true,
	follow: true,
	"max-snippet": -1,
	"max-image-preview": "large",
	"max-video-preview": -1,
} as const;

/** Per-page metadata with a self canonical. `path` is the route without the base path. */
export function createMetadata(params: {
	title?: string;
	description: string;
	path: string;
	ogType?: "website" | "article";
}): Metadata {
	const url = absoluteUrl(params.path);
	const heading = params.title ? `${params.title} | ${siteConfig.name}` : siteConfig.homeTitle;
	return {
		title: params.title ?? { absolute: siteConfig.homeTitle },
		description: params.description,
		alternates: { canonical: url },
		robots: indexRobots,
		openGraph: {
			type: params.ogType ?? "website",
			url,
			siteName: siteConfig.name,
			title: heading,
			description: params.description,
			locale: "en_US",
		},
		twitter: { card: "summary", title: heading, description: params.description },
	};
}
