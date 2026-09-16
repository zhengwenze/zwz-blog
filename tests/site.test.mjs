import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import test from "node:test";

const root = resolve("dist");
const pages = [
  join(root, "index.html"),
  join(root, "articles", "evidence-driven-ai-infra.html"),
];

const read = (path) => readFileSync(path, "utf8");

test("public entrypoints exist", () => {
  for (const page of pages) assert.equal(existsSync(page), true, page);
  assert.equal(existsSync(join(root, "assets", "styles.css")), true);
});

test("every page has required metadata and landmarks", () => {
  for (const page of pages) {
    const html = read(page);
    assert.match(html, /<html lang="zh-CN">/);
    assert.match(html, /<meta name="description" content="[^"]+">/);
    assert.match(html, /<meta name="viewport"/);
    assert.match(html, /<title>[^<]+<\/title>/);
    assert.match(html, /<main[^>]*>/);
    assert.match(html, /class="skip-link"/);
    assert.doesNotMatch(html, /TODO|PLACEHOLDER|lorem ipsum/i);
  }
});

test("local href and stylesheet references resolve", () => {
  for (const page of pages) {
    const html = read(page);
    const refs = [...html.matchAll(/(?:href|src)="([^"]+)"/g)].map((match) => match[1]);

    for (const ref of refs) {
      if (/^(?:https?:|mailto:|#|data:)/.test(ref)) continue;
      const fileRef = ref.split("#", 1)[0];
      const target = fileRef.startsWith("/") ? join(root, fileRef) : join(dirname(page), fileRef);
      assert.equal(existsSync(target), true, `${page} -> ${ref}`);
    }
  }
});

test("home page links to the published article", () => {
  const home = read(join(root, "index.html"));
  assert.match(home, /\/articles\/evidence-driven-ai-infra\.html/);
  assert.match(home, /郑文泽/);
});
