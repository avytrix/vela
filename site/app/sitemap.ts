import type { MetadataRoute } from "next";
import { absoluteUrl } from "@/lib/site";
import { source } from "@/lib/source";

export const dynamic = "force-static";
export const revalidate = false;

/** The home page and every docs page, each at its canonical URL. No lastmod: a build date says nothing. */
export default function sitemap(): MetadataRoute.Sitemap {
	return [{ url: absoluteUrl("/") }, ...source.getPages().map((page) => ({ url: absoluteUrl(page.url) }))];
}
