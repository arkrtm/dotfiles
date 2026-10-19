/**
 * format-json-yaml — format JSON and YAML right after a successful write/edit.
 *
 * Python is already auto-formatted by pi-lens (ruff); this fills the gap for
 * JSON (jq) and YAML (yamlfix). Both are PATH prerequisites; a missing one is
 * reported once and the file is left untouched. A failed or partial format is
 * never written back.
 */
import { spawnSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function formatJsonYaml(pi: ExtensionAPI) {
	// toolCallId -> path, captured at call time and formatted once it succeeds.
	const pending = new Map<string, string>();
	const warned = new Set<string>();

	pi.on("tool_call", async (event) => {
		if (event.toolName === "write" || event.toolName === "edit") {
			pending.set(event.toolCallId, event.input.path as string);
		}
		return undefined;
	});

	pi.on("tool_execution_end", async (event, ctx) => {
		const path = pending.get(event.toolCallId);
		if (path === undefined) return;
		pending.delete(event.toolCallId);
		if (event.isError) return;

		const warnOnce = (tool: string) => {
			if (warned.has(tool)) return;
			warned.add(tool);
			ctx.ui.notify(`${tool} not found — left ${path} unformatted`, "warning");
		};
		const lower = path.toLowerCase();

		if (lower.endsWith(".json")) {
			// jq prints to stdout; write back only on a clean, non-empty result.
			const res = spawnSync("jq", [".", path], { encoding: "utf8", timeout: 5000 });
			if (res.error) {
				if ((res.error as NodeJS.ErrnoException).code === "ENOENT") warnOnce("jq");
				return;
			}
			if (res.status === 0 && res.stdout) {
				try {
					writeFileSync(path, res.stdout);
				} catch {
					/* leave the file as the agent wrote it */
				}
			}
		} else if (lower.endsWith(".yaml") || lower.endsWith(".yml")) {
			// yamlfix edits in place; a parse failure exits non-zero without clobbering.
			// Gentle settings (normalize spacing only): keep the original sequence
			// style, no "---" header, and preserve quotes.
			const res = spawnSync("yamlfix", [path], {
				encoding: "utf8",
				timeout: 5000,
				env: {
					...process.env,
					YAMLFIX_SEQUENCE_STYLE: "keep_style",
					YAMLFIX_EXPLICIT_START: "false",
					YAMLFIX_PRESERVE_QUOTES: "true",
				},
			});
			if (res.error && (res.error as NodeJS.ErrnoException).code === "ENOENT") {
				warnOnce("yamlfix");
			}
		}
	});
}
