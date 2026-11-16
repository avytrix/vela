import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";
import { BookOpen, Globe, Heart, House } from "lucide-react";
import { GithubMark } from "@/components/github-mark";
import { asset, siteConfig } from "@/lib/site";

/** The header shared by the home page and the docs: logo and name, Avytrix home, Docs, GitHub, Sponsor, open source. */
export function baseOptions(): BaseLayoutProps {
	return {
		nav: {
			title: (
				<span className="inline-flex items-center gap-2 font-semibold">
					{/* A 24px mark needs no optimizer; plain <img> needs the base path by hand. */}
					<img
						src={asset(siteConfig.logo)}
						alt={`${siteConfig.organization.name} logo`}
						width={24}
						height={24}
						className="size-6"
					/>
					{siteConfig.name}
				</span>
			),
			url: "/",
			transparentMode: "none",
		},
		links: [
			// The way back to the company site, first so it is easy to find
			{
				icon: <House />,
				text: "Avytrix home",
				url: siteConfig.organization.url,
			},
			{
				icon: <BookOpen className="text-fd-primary" />,
				text: <span className="font-semibold text-fd-primary">Docs</span>,
				url: "/docs",
				active: "nested-url",
			},
			{
				type: "icon",
				label: "GitHub",
				icon: <GithubMark />,
				text: "GitHub",
				url: siteConfig.github,
				external: true,
			},
			{
				type: "icon",
				label: "Sponsor",
				icon: <Heart className="text-fd-primary" />,
				text: "Sponsor",
				url: siteConfig.sponsor,
				external: true,
			},
			{
				type: "icon",
				label: "All open source projects",
				icon: <Globe className="text-fd-primary" />,
				text: "All open source projects",
				url: siteConfig.organization.opensource,
				external: true,
			},
		],
	};
}
