import { ArrowRight, BookOpen, Briefcase, EyeOff, Heart, ShieldCheck, TriangleAlert } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";
import { GithubMark } from "@/components/github-mark";
import { createMetadata, siteConfig } from "@/lib/site";

export const metadata: Metadata = createMetadata({ description: siteConfig.description, path: "/" });

/*
 * Every claim here is in README.md or docs/compat/README.md. When those change, change this too:
 * the docs pages rebuild from the Markdown, this page does not.
 */

const levels = [
	["View", "see that the path exists in file lists"],
	["Read", "open the file and see its contents"],
	["Write", "create, change, rename or delete it"],
];

const tested = [
	["Tier A, server hook", "23 of 23 live cases on GitLab CE 15.11 to 19.5"],
	["Tier B, overlay", "68 of 68 on 16.11 to 19.5, and 69 of 69 on 15.11"],
	["In-place upgrade", "19.0.2 to 19.0.11 in Docker, overlay 68 of 68 after the upgrade"],
	["Not tested", "source installs, Helm, Gitaly Cluster (Praefect)"],
];

function Section({ title, children }: { title: string; children: ReactNode }) {
	return (
		<section className="border-fd-border border-t py-12">
			<h2 className="text-2xl font-semibold tracking-tight">{title}</h2>
			<div className="text-fd-foreground/90 mt-4 leading-relaxed">{children}</div>
		</section>
	);
}

const button =
	"inline-flex items-center gap-2 rounded-lg px-5 py-2.5 text-sm font-medium transition-colors";

export default function HomePage() {
	return (
		<main className="mx-auto w-full max-w-5xl px-4 py-16 sm:px-6">
			<div className="mb-12 max-w-3xl">
				<p className="text-fd-primary font-mono text-sm">Open source, MIT</p>
				<h1 className="mt-3 text-4xl font-bold tracking-tight text-balance sm:text-5xl">
					Folder and file permissions for self-hosted GitLab CE
				</h1>
				<p className="text-fd-muted-foreground mt-5 text-lg leading-relaxed">
					{siteConfig.name} lets you decide which users and groups can view, read or write each path in a
					project, without paying for a higher GitLab tier. Turning it on changes nothing until you add a rule,
					and it can only take access away, never give more than GitLab already allows.
				</p>
				<div className="mt-8 flex flex-wrap gap-3">
					<Link href="/docs/install" className={`${button} bg-fd-primary text-fd-primary-foreground hover:opacity-90`}>
						Get started <ArrowRight className="size-4" />
					</Link>
					<Link href="/docs" className={`${button} border-fd-border hover:bg-fd-accent border`}>
						<BookOpen className="size-4" /> Read the docs
					</Link>
					<a href={siteConfig.github} className={`${button} border-fd-border hover:bg-fd-accent border`}>
						<GithubMark className="size-4" /> {siteConfig.name} on GitHub
					</a>
				</div>
			</div>

			<Section title="Three levels on any file or folder">
				<p>You give each user or group up to three levels. Each level includes the one before it.</p>
				<ul className="mt-4 grid gap-3 sm:grid-cols-3">
					{levels.map(([name, what]) => (
						<li key={name} className="bg-fd-card border-fd-border rounded-xl border p-4">
							<p className="font-semibold">{name}</p>
							<p className="text-fd-muted-foreground mt-1 text-sm">{what}</p>
						</li>
					))}
				</ul>
				<p className="mt-4">
					A folder rule covers everything inside it, a rule on a single file beats the folder around it, and an
					explicit deny always wins. Instance admins and project Owners are never locked out.
				</p>
			</Section>

			<Section title="Two tiers, so it works on any GitLab CE">
				<div className="grid gap-4 sm:grid-cols-2">
					<div className="bg-fd-card border-fd-border rounded-xl border p-5">
						<ShieldCheck className="text-fd-primary size-5" aria-hidden="true" />
						<h3 className="mt-3 font-semibold">Tier A, server hook</h3>
						<p className="text-fd-muted-foreground mt-2 text-sm leading-relaxed">
							Enforces writes on any CE version and install method (Linux package, Docker, source, Helm), using
							only the global pre-receive server hooks GitLab documents. It lives outside GitLab&apos;s files, so
							it survives upgrades.
						</p>
					</div>
					<div className="bg-fd-card border-fd-border rounded-xl border p-5">
						<EyeOff className="text-fd-primary size-5" aria-hidden="true" />
						<h3 className="mt-3 font-semibold">Tier B, overlay</h3>
						<p className="text-fd-muted-foreground mt-2 text-sm leading-relaxed">
							Everything in Tier A, plus hiding paths in the web UI, API, search and diffs, and a settings page
							under Project Settings. It relies on GitLab internals, so it refuses to boot if GitLab changed
							something it needs.
						</p>
					</div>
				</div>
				<p className="mt-4">
					<Link href="/docs/portability" className="text-fd-primary font-medium underline-offset-4 hover:underline">
						Why there are two tiers
					</Link>
				</p>
			</Section>

			<Section title="The one limit you must know about">
				<div className="flex gap-3 rounded-xl border border-amber-500/40 bg-amber-500/10 p-5">
					<TriangleAlert className="mt-0.5 size-5 shrink-0 text-amber-600 dark:text-amber-400" aria-hidden="true" />
					<div>
						<p className="font-semibold">{siteConfig.name} does not stop git clone or git fetch.</p>
						<p className="mt-2">
							Write rules are enforced: a push that touches a path the person may not change is rejected. View
							and Read rules only hide things inside GitLab. Anyone who can clone the repository has every file
							and the full history. Commit history, source downloads, compare pages and project export are not
							filtered either. To keep a folder secret, put it in its own project.
						</p>
						<p className="mt-3">
							<Link href="/docs/split-secrets" className="text-fd-primary font-medium underline-offset-4 hover:underline">
								Keeping a folder out of everyone&apos;s clone
							</Link>
						</p>
					</div>
				</div>
			</Section>

			<Section title="Tested versions">
				<p>
					Every result below is a live run of the end-to-end suite against a real GitLab CE container. Only
					versions with green results are listed as tested.
				</p>
				<dl className="mt-4 grid gap-3 sm:grid-cols-2">
					{tested.map(([what, result]) => (
						<div key={what} className="bg-fd-card border-fd-border rounded-xl border p-4">
							<dt className="font-semibold">{what}</dt>
							<dd className="text-fd-muted-foreground mt-1 text-sm">{result}</dd>
						</div>
					))}
				</dl>
				<p className="mt-4">
					<Link href="/docs/compat" className="text-fd-primary font-medium underline-offset-4 hover:underline">
						All compatibility results
					</Link>
				</p>
			</Section>

			<Section title="Support the work">
				<div className="grid gap-4 sm:grid-cols-2">
					<div className="bg-fd-card border-fd-border rounded-xl border p-5">
						<Heart className="text-fd-primary size-5" aria-hidden="true" />
						<h3 className="mt-3 font-semibold">Sponsor {siteConfig.name}</h3>
						<p className="text-fd-muted-foreground mt-2 text-sm leading-relaxed">
							{siteConfig.name} is free under MIT. Sponsoring pays for testing on more GitLab versions, bug fixes
							and the next release. Even $1 a month helps.
						</p>
						<a href={siteConfig.sponsor} className={`${button} bg-fd-primary text-fd-primary-foreground mt-4 hover:opacity-90`}>
							Sponsor on GitHub
						</a>
					</div>
					<div className="bg-fd-card border-fd-border rounded-xl border p-5">
						<Briefcase className="text-fd-primary size-5" aria-hidden="true" />
						<h3 className="mt-3 font-semibold">Work with Avytrix</h3>
						<p className="text-fd-muted-foreground mt-2 text-sm leading-relaxed">
							{siteConfig.name} is built and maintained by {siteConfig.organization.name}. We also build custom
							software, set up GitLab and CI, and maintain the open source we publish.
						</p>
						<a href={siteConfig.organization.contact} className={`${button} border-fd-border hover:bg-fd-accent mt-4 border`}>
							Tell us about your project
						</a>
					</div>
				</div>
			</Section>

			<footer className="border-fd-border text-fd-muted-foreground border-t pt-8 text-sm">
				<p>
					{siteConfig.name} is MIT licensed and built by{" "}
					<a href={siteConfig.organization.url} className="underline underline-offset-4">
						{siteConfig.organization.name}
					</a>
					. It is an independent project. It is not made by, endorsed by or affiliated with GitLab Inc. GitLab is a
					trademark of GitLab Inc.
				</p>
			</footer>
		</main>
	);
}
