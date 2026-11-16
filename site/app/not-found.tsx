import { HomeLayout } from "fumadocs-ui/layouts/home";
import Link from "next/link";
import { baseOptions } from "@/lib/layout.shared";

export const metadata = {
	title: "Page not found",
	robots: { index: false, follow: true },
};

export default function NotFound() {
	return (
		<HomeLayout {...baseOptions()}>
			<main className="flex flex-1 flex-col items-center justify-center px-4 py-24 text-center">
				<p className="text-fd-muted-foreground font-mono text-sm">404</p>
				<h1 className="mt-3 text-3xl font-bold tracking-tight">That page is not here</h1>
				<p className="text-fd-muted-foreground mt-3 max-w-md">
					It may have moved. Press Cmd+K (Ctrl+K on Windows and Linux) to search, or start from the docs.
				</p>
				<Link href="/docs" className="bg-fd-primary text-fd-primary-foreground mt-8 rounded-lg px-5 py-2.5 text-sm font-medium">
					Go to the docs
				</Link>
			</main>
		</HomeLayout>
	);
}
