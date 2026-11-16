/**
 * Renders schema.org JSON-LD. The input is our own static objects, and `<` is escaped so no
 * string in them can close the script element.
 */
export function JsonLd({ data }: { data: object }) {
	const json = JSON.stringify(data).replace(/</g, "\\u003c");
	return <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: json }} />;
}
