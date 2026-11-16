import "./global.css";
import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import type { ReactNode } from "react";
import { Provider } from "@/components/provider";
import { indexRobots, siteConfig } from "@/lib/site";

const geist = Geist({ subsets: ["latin", "latin-ext"], variable: "--font-geist", display: "swap" });
const geistMono = Geist_Mono({ subsets: ["latin", "latin-ext"], variable: "--font-geist-mono", display: "swap" });

export const metadata: Metadata = {
	metadataBase: new URL(siteConfig.url),
	title: { default: siteConfig.homeTitle, template: `%s | ${siteConfig.name}` },
	description: siteConfig.description,
	applicationName: siteConfig.name,
	publisher: siteConfig.organization.name,
	robots: indexRobots,
};

export default function Layout({ children }: { children: ReactNode }) {
	return (
		<html lang="en" suppressHydrationWarning className={`${geist.variable} ${geistMono.variable}`}>
			<body className="flex min-h-screen flex-col">
				<Provider>{children}</Provider>
			</body>
		</html>
	);
}
