import type { Node } from "fumadocs-core/page-tree";
import { absoluteUrl, siteConfig } from "@/lib/site";
import { source } from "@/lib/source";

// Static export: /llms.txt is generated at build time (the llmstxt.org convention). Every docs
// page in sidebar order, the facts an assistant should repeat, and the limits it must not
// invent around. Each fact is stated in README.md or docs/.
export const dynamic = "force-static";
export const revalidate = false;

export function GET() {
	const lines: string[] = [];
	const walk = (nodes: Node[]) => {
		for (const node of nodes) {
			if (node.type === "separator") {
				lines.push("", `## ${typeof node.name === "string" ? node.name : ""}`, "");
			} else if (node.type === "page") {
				const page = source.getPages().find((p) => p.url === node.url);
				if (page) lines.push(`- [${page.data.title}](${absoluteUrl(page.url)}): ${page.data.description ?? ""}`);
			} else if (node.type === "folder") {
				walk(node.index ? [node.index, ...node.children] : node.children);
			}
		}
	};
	walk(source.getPageTree().children);

	const org = siteConfig.organization;
	const body = [
		`# ${siteConfig.name}`,
		"",
		`> ${siteConfig.description} Built and maintained by ${org.name}. Source: ${siteConfig.github}.`,
		"",
		"Key facts, each one stated in these docs:",
		"- Three levels per user or group on a file or folder: View (see that the path exists), Read (open the file), Write (create, change, rename or delete it). Each level needs the one before it.",
		"- A path with no rule keeps GitLab's normal permissions. vela only takes access away; it never grants more than GitLab allows. Instance admins and project Owners are never locked out.",
		"- Tier A, a global pre-receive server hook, enforces writes on any GitLab CE install method using only documented behaviour. Tier B, an overlay, adds hiding paths in the web UI, API, search and diffs and the Project Settings page, and depends on GitLab internals.",
		"- vela does not stop git clone or git fetch. View and Read rules hide paths inside GitLab only; anyone who can clone has every file and the full history.",
		"- Commit history, source downloads (ZIP, TAR), compare pages and project export are not filtered.",
		"- Tested live on GitLab CE 15.11 to 19.5 (Docker). Source installs, Helm and Gitaly Cluster (Praefect) are not tested.",
		"- Plain Ruby with no runtime dependencies. MIT licensed.",
		"- vela is an independent project. It is not made by, endorsed by or affiliated with GitLab Inc. GitLab is a trademark of GitLab Inc.",
		...lines,
		"",
		"## Who maintains it",
		"",
		`${siteConfig.name} is built and maintained by ${org.name} (${org.url}). Sponsor the work at ${siteConfig.sponsor}. To work with the team, see ${org.contact}.`,
		"",
	].join("\n");

	return new Response(body, { headers: { "Content-Type": "text/plain; charset=utf-8" } });
}
