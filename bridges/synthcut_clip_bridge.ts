#!/usr/bin/env -S npx tsx
import { createInterface } from "node:readline";
import { pathToFileURL } from "node:url";
import { join, resolve } from "node:path";

const synthCutRoot = resolve(
  process.env.CLIP_RESOLVED_SYNTHCUT_ROOT ?? join(process.cwd(), "external", "SynthCut"),
);

const clipModulePath = join(synthCutRoot, "packages", "core", "src", "media", "clip.ts");
const clip = await import(pathToFileURL(clipModulePath).href);

type Request = {
  id?: string | number;
  op: "ensure" | "embed_image" | "embed_text";
  path?: string;
  time?: number;
  query?: string;
};

function respond(payload: unknown) {
  process.stdout.write(JSON.stringify(payload) + "\n");
}

async function handle(req: Request) {
  const id = req.id ?? null;
  try {
    if (req.op === "ensure") {
      respond({ id, ok: true, available: await clip.ensureClip() });
      return;
    }
    if (req.op === "embed_image") {
      if (!req.path) throw new Error("embed_image requires path");
      const embedding = await clip.embedImage(req.path, Number(req.time ?? 0));
      respond({ id, ok: true, embedding });
      return;
    }
    if (req.op === "embed_text") {
      if (!req.query) throw new Error("embed_text requires query");
      const embedding = await clip.embedText(req.query);
      respond({ id, ok: true, embedding });
      return;
    }
    throw new Error(`unknown op: ${(req as { op?: string }).op}`);
  } catch (error) {
    respond({
      id,
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });
for await (const line of rl) {
  const trimmed = line.trim();
  if (!trimmed) continue;
  try {
    await handle(JSON.parse(trimmed) as Request);
  } catch (error) {
    respond({
      id: null,
      ok: false,
      error: `invalid request: ${error instanceof Error ? error.message : String(error)}`,
    });
  }
}
