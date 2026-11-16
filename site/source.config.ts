import { defineConfig, defineDocs, frontmatterSchema } from "fumadocs-mdx/config";

// content/docs is generated from ../README.md and ../docs by scripts/sync-docs.mjs.
export const docs = defineDocs({
	dir: "content/docs",
	docs: {
		// repoPath: the Markdown file in the repository the page is built from.
		schema: frontmatterSchema.extend({ repoPath: frontmatterSchema.shape.title }),
		postprocess: { includeProcessedMarkdown: true },
	},
});

export default defineConfig({
	mdxOptions: {
		rehypeCodeOptions: {
			themes: { light: "github-light", dark: "github-dark" },
			langs: ["bash", "sh", "json", "ruby", "yaml", "sql"],
		},
	},
});
