import { DocsLayout } from "fumadocs-ui/layouts/notebook";
import type { ReactNode } from "react";
import { baseOptions } from "@/lib/layout.shared";
import { source } from "@/lib/source";

/**
 * The notebook layout with a full-width top bar, like the sibling Avytrix docs. `{...options}`
 * spreads first: it carries its own `nav`, which would otherwise overwrite `mode: "top"`.
 */
export default function Layout({ children }: { children: ReactNode }) {
	const options = baseOptions();
	return (
		<DocsLayout {...options} tree={source.getPageTree()} nav={{ ...options.nav, mode: "top" }} sidebar={{ collapsible: true }}>
			{children}
		</DocsLayout>
	);
}
