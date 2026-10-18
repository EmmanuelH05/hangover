#!/usr/bin/env bun
// Writes Sources/OpenIslandApp/Resources/WhatsNew.json from
// design/update-flow/WHATS-NEW.md (D82). The Markdown file is where the
// What's new words are written; the JSON is what the app reads. Run after
// every edit of the Markdown: `bun scripts/whats-new.ts`. The test
// WhatsNewTests checks the two agree.
//
// The Markdown shape: a "## 1.0.14" heading per version, then numbered
// items "1. **Title**" with the sub line indented under each. An indented
// "symbol: name" line names the SF Symbol on the item's plate.

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "..");
const source = join(root, "design/update-flow/WHATS-NEW.md");
const target = join(root, "Sources/OpenIslandApp/Resources/WhatsNew.json");

type Item = { title: string; detail?: string; symbol?: string };
type Release = { version: string; items: Item[] };

export function parse(markdown: string): Release[] {
  const releases: Release[] = [];
  let release: Release | null = null;
  let item: Item | null = null;
  for (const raw of markdown.split("\n")) {
    const heading = raw.match(/^##\s+(\d+(?:\.\d+)*)\s*$/);
    if (heading) {
      release = { version: heading[1], items: [] };
      releases.push(release);
      item = null;
      continue;
    }
    if (!release) continue;
    const numbered = raw.match(/^\d+\.\s+\*\*(.+?)\*\*\s*$/);
    if (numbered) {
      item = { title: numbered[1].trim() };
      release.items.push(item);
      continue;
    }
    const indented = raw.match(/^\s+(\S.*)$/);
    if (indented && item) {
      const line = indented[1].trim();
      const symbol = line.match(/^symbol:\s*(\S+)$/);
      if (symbol) item.symbol = symbol[1];
      else if (!item.detail) item.detail = line;
      continue;
    }
    if (raw.trim() === "") item = null;
    else if (!raw.startsWith(" ")) item = null;
  }
  return releases.filter((r) => r.items.length > 0).sort(byVersionDescending);
}

function byVersionDescending(a: Release, b: Release): number {
  const left = a.version.split(".").map(Number);
  const right = b.version.split(".").map(Number);
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    const x = left[i] ?? 0;
    const y = right[i] ?? 0;
    if (x !== y) return y - x;
  }
  return 0;
}

if (import.meta.main) {
  const releases = parse(readFileSync(source, "utf8"));
  const json = JSON.stringify({ releases }, null, 2) + "\n";
  writeFileSync(target, json);
  const count = releases.reduce((n, r) => n + r.items.length, 0);
  console.log(`WhatsNew.json: ${releases.length} version(s), ${count} item(s)`);
}
