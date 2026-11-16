import { DocsBody, DocsDescription, DocsPage, DocsTitle } from "fumadocs-ui/layouts/notebook/page";
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { JsonLd } from "@/components/json-ld";
import { getMDXComponents } from "@/components/mdx";
import { createMetadata, siteConfig } from "@/lib/site";
import { source } from "@/lib/source";
import { docPageLd } from "@/lib/structured-data";

export default async function Page(props: { params: Promise<{ slug?: string[] }> }) {
	const params = await props.params;
	const page = source.getPage(params.slug);
	if (!page) notFound();
	const MDX = page.data.body;

	return (
		<DocsPage toc={page.data.toc} full={page.data.full}>
			<JsonLd data={docPageLd({ title: page.data.title, description: page.data.description, url: page.url })} />
			<DocsTitle>{page.data.title}</DocsTitle>
			<DocsDescription className="doc-lede mb-0">{page.data.description}</DocsDescription>
			<DocsBody>
				<MDX components={getMDXComponents()} />
				<p className="text-fd-muted-foreground mt-12 border-t pt-6 text-sm">
					This page is built from{" "}
					<a href={`${siteConfig.github}/blob/main/${page.data.repoPath}`}>{page.data.repoPath} on GitHub</a>.
				</p>
			</DocsBody>
		</DocsPage>
	);
}

export function generateStaticParams() {
	return source.generateParams();
}

export async function generateMetadata(props: { params: Promise<{ slug?: string[] }> }): Promise<Metadata> {
	const params = await props.params;
	const page = source.getPage(params.slug);
	if (!page) notFound();
	return createMetadata({
		title: page.data.title,
		description: page.data.description ?? "",
		path: page.url,
		ogType: "article",
	});
}
