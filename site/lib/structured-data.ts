import { absoluteUrl, siteConfig } from "./site";

/*
 * Schema.org for this site. Each page carries exactly one @graph, and every node it names is in
 * that graph. Only facts stated in the repository: the name, the MIT license, Ruby, the GitHub
 * repository, and Avytrix Technologies as author and publisher. No ratings, no sameAs, no
 * version number (vela has no release yet).
 */
const root = siteConfig.url;
const home = absoluteUrl("/");
const orgRef = { "@id": `${root}#organization` };
const softwareRef = { "@id": `${root}#software` };
const websiteRef = { "@id": `${root}#website` };

const shared = [
	{
		"@type": "Organization",
		...orgRef,
		name: siteConfig.organization.name,
		url: siteConfig.organization.url,
		logo: { "@type": "ImageObject", url: `${root}${siteConfig.logo}` },
	},
	{
		"@type": "WebSite",
		...websiteRef,
		url: home,
		name: siteConfig.name,
		description: siteConfig.description,
		publisher: orgRef,
		inLanguage: "en-US",
	},
	{
		"@type": "SoftwareSourceCode",
		...softwareRef,
		name: siteConfig.name,
		description: siteConfig.description,
		codeRepository: siteConfig.github,
		programmingLanguage: "Ruby",
		license: "https://opensource.org/licenses/MIT",
		url: home,
		author: orgRef,
		publisher: orgRef,
	},
];

export function homeLd() {
	return {
		"@context": "https://schema.org",
		"@graph": [
			...shared,
			{
				"@type": "WebPage",
				"@id": `${home}#webpage`,
				url: home,
				name: siteConfig.homeTitle,
				description: siteConfig.description,
				isPartOf: websiteRef,
				about: softwareRef,
				publisher: orgRef,
				inLanguage: "en-US",
			},
		],
	};
}

export function docPageLd({ title, description, url }: { title: string; description?: string; url: string }) {
	const pageUrl = absoluteUrl(url);
	const trail = [
		{ name: siteConfig.name, url: "/" },
		...(url === "/docs" ? [] : [{ name: "Docs", url: "/docs" }]),
		{ name: title, url },
	];
	return {
		"@context": "https://schema.org",
		"@graph": [
			...shared,
			{
				"@type": "TechArticle",
				"@id": `${pageUrl}#webpage`,
				url: pageUrl,
				headline: title,
				name: title,
				description,
				isPartOf: websiteRef,
				about: softwareRef,
				publisher: orgRef,
				author: orgRef,
				inLanguage: "en-US",
				breadcrumb: { "@id": `${pageUrl}#breadcrumb` },
			},
			{
				"@type": "BreadcrumbList",
				"@id": `${pageUrl}#breadcrumb`,
				itemListElement: trail.map((item, i) => ({
					"@type": "ListItem",
					position: i + 1,
					name: item.name,
					item: absoluteUrl(item.url),
				})),
			},
		],
	};
}
