"use client";
import { useStaticSearch } from "fumadocs-core/search/client";
import {
	SearchDialog,
	SearchDialogClose,
	SearchDialogContent,
	SearchDialogHeader,
	SearchDialogIcon,
	SearchDialogInput,
	SearchDialogList,
	SearchDialogOverlay,
	type SharedProps,
} from "fumadocs-ui/components/dialog/search";
import { basePath } from "@/lib/site";

/**
 * Cmd+K search over the index exported at /api/search, fetched once and searched in the browser.
 * `from` carries the base path: Fumadocs' default is the bare /api/search.
 */
export default function DefaultSearchDialog(props: SharedProps) {
	const search = useStaticSearch({ from: `${basePath}/api/search` });

	return (
		<SearchDialog {...search} {...props}>
			<SearchDialogOverlay />
			<SearchDialogContent>
				<SearchDialogHeader>
					<SearchDialogIcon />
					<SearchDialogInput />
					<SearchDialogClose />
				</SearchDialogHeader>
				<SearchDialogList />
			</SearchDialogContent>
		</SearchDialog>
	);
}
