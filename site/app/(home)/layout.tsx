import { HomeLayout } from "fumadocs-ui/layouts/home";
import type { ReactNode } from "react";
import { JsonLd } from "@/components/json-ld";
import { baseOptions } from "@/lib/layout.shared";
import { homeLd } from "@/lib/structured-data";

export default function Layout({ children }: { children: ReactNode }) {
	return (
		<HomeLayout {...baseOptions()}>
			<JsonLd data={homeLd()} />
			{children}
		</HomeLayout>
	);
}
