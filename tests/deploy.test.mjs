import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFile, spawnSync } from "node:child_process";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readlinkSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { basename, join, resolve, sep } from "node:path";
import test from "node:test";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const releaseScript = resolve("deploy/release.sh");
const articlePath = "articles/evidence-driven-ai-infra.html";

const makeSandbox = () => mkdtempSync(join(tmpdir(), "zwz-blog-deploy-"));

const writePayload = (directory, sha, marker = sha.slice(0, 8)) => {
  mkdirSync(join(directory, "articles"), { recursive: true });
  mkdirSync(join(directory, "assets"), { recursive: true });
  writeFileSync(join(directory, "index.html"), `<h1>${marker}</h1>\n`);
  writeFileSync(join(directory, articlePath), `<article>${marker}</article>\n`);
  writeFileSync(join(directory, "assets/styles.css"), `/* ${marker} */\n`);
  writeFileSync(
    join(directory, "deploy-meta.json"),
    `${JSON.stringify({ sha, run_id: "test", deployed_at: "2026-09-16T00:00:00Z" }, null, 2)}\n`,
  );
};

const makeArchive = (sandbox, sha, marker, mutatePayload = () => {}) => {
  const payload = join(sandbox, `payload-${sha}`);
  const archive = join(sandbox, `release-${sha}.tar.gz`);
  const checksum = `${archive}.sha256`;
  writePayload(payload, sha, marker);
  mutatePayload(payload);
  const tar = spawnSync("tar", ["-czf", archive, "-C", payload, "."], { encoding: "utf8" });
  assert.equal(tar.status, 0, tar.stderr);
  const digest = createHash("sha256").update(readFileSync(archive)).digest("hex");
  writeFileSync(checksum, `${digest}  ${basename(archive)}\n`);
  return { archive, checksum };
};

const runRelease = async (args, env) => {
  try {
    const result = await execFileAsync("bash", [releaseScript, ...args], {
      env: { ...process.env, ...env },
    });
    return { status: 0, ...result };
  } catch (error) {
    return {
      status: error.code,
      stdout: error.stdout ?? "",
      stderr: error.stderr ?? "",
    };
  }
};

const startSiteServer = async (webRoot, hostHeader) => {
  let rejectedSha = null;
  const server = createServer((request, response) => {
    try {
      if (request.headers.host !== hostHeader) {
        response.writeHead(400).end("wrong host");
        return;
      }

      const current = realpathSync(join(webRoot, "current"));
      const metadata = JSON.parse(readFileSync(join(current, "deploy-meta.json"), "utf8"));
      if (metadata.sha === rejectedSha) {
        response.writeHead(503).end("rejected release");
        return;
      }

      const pathname = new URL(request.url, "http://localhost").pathname;
      const relative = pathname === "/" ? "index.html" : pathname.slice(1);
      const file = resolve(current, relative);
      if (!file.startsWith(`${current}${sep}`)) {
        response.writeHead(400).end("invalid path");
        return;
      }
      const body = readFileSync(file);
      response.writeHead(200).end(body);
    } catch {
      response.writeHead(404).end("not found");
    }
  });

  await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
  const { port } = server.address();
  return {
    url: `http://127.0.0.1:${port}`,
    reject(sha) {
      rejectedSha = sha;
    },
    close: () => new Promise((resolveClose) => server.close(resolveClose)),
  };
};

test("deploy rejects a non-40-character SHA before changing the web root", async (t) => {
  const sandbox = makeSandbox();
  t.after(() => rmSync(sandbox, { recursive: true, force: true }));
  const webRoot = join(sandbox, "web");
  const result = await runRelease(["deploy", "abc", "missing.tar.gz", "missing.sha256"], {
    WEB_ROOT: webRoot,
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /exactly 40 lowercase hexadecimal/);
  assert.equal(existsSync(webRoot), false);
});

test("deploy rejects a bad archive checksum and leaves no incoming directory", async (t) => {
  const sandbox = makeSandbox();
  t.after(() => rmSync(sandbox, { recursive: true, force: true }));
  const sha = "1".repeat(40);
  const webRoot = join(sandbox, "web");
  const { archive, checksum } = makeArchive(sandbox, sha, "bad-checksum");
  writeFileSync(checksum, `${"0".repeat(64)}  ${basename(archive)}\n`);

  const result = await runRelease(["deploy", sha, archive, checksum], { WEB_ROOT: webRoot });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /checksum mismatch/);
  assert.equal(existsSync(join(webRoot, `.incoming-${sha}`)), false);
  assert.equal(existsSync(join(webRoot, "current")), false);
});

test("deploy validates required files and the embedded release SHA before activation", async (t) => {
  const sandbox = makeSandbox();
  t.after(() => rmSync(sandbox, { recursive: true, force: true }));
  const webRoot = join(sandbox, "web");
  const missingFileSha = "5".repeat(40);
  const missingFile = makeArchive(sandbox, missingFileSha, "missing-css", (payload) => {
    rmSync(join(payload, "assets", "styles.css"));
  });

  const missingResult = await runRelease(
    ["deploy", missingFileSha, missingFile.archive, missingFile.checksum],
    { WEB_ROOT: webRoot },
  );
  assert.notEqual(missingResult.status, 0);
  assert.match(missingResult.stderr, /missing required regular file: assets\/styles\.css/);
  assert.equal(existsSync(join(webRoot, `.incoming-${missingFileSha}`)), false);

  const embeddedSha = "6".repeat(40);
  const requestedSha = "7".repeat(40);
  const mismatch = makeArchive(sandbox, embeddedSha, "wrong-metadata");
  const mismatchResult = await runRelease(
    ["deploy", requestedSha, mismatch.archive, mismatch.checksum],
    { WEB_ROOT: webRoot },
  );
  assert.notEqual(mismatchResult.status, 0);
  assert.match(mismatchResult.stderr, /deploy-meta\.json SHA does not match/);
  assert.equal(existsSync(join(webRoot, `.incoming-${requestedSha}`)), false);
  assert.equal(existsSync(join(webRoot, "current")), false);
});

test("deploy rejects symbolic links in an otherwise valid archive", async (t) => {
  const sandbox = makeSandbox();
  t.after(() => rmSync(sandbox, { recursive: true, force: true }));
  const sha = "8".repeat(40);
  const webRoot = join(sandbox, "web");
  const unsafe = makeArchive(sandbox, sha, "unsafe-link", (payload) => {
    symlinkSync("index.html", join(payload, "alias.html"));
  });

  const result = await runRelease(["deploy", sha, unsafe.archive, unsafe.checksum], {
    WEB_ROOT: webRoot,
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /only regular files and directories/);
  assert.equal(existsSync(join(webRoot, "current")), false);
});

test("deploy switches atomically, restores on failed health checks, and supports rollback", async (t) => {
  const sandbox = makeSandbox();
  const webRoot = join(sandbox, "web");
  const hostHeader = "zwz-blog.test";
  mkdirSync(webRoot, { recursive: true });
  const site = await startSiteServer(webRoot, hostHeader);
  t.after(async () => {
    await site.close();
    rmSync(sandbox, { recursive: true, force: true });
  });

  const env = {
    WEB_ROOT: webRoot,
    HOST_HEADER: hostHeader,
    HEALTHCHECK_URL: site.url,
  };
  const sha1 = "1".repeat(40);
  const sha2 = "2".repeat(40);
  const sha3 = "3".repeat(40);

  const first = makeArchive(sandbox, sha1, "first");
  const firstResult = await runRelease(["deploy", sha1, first.archive, first.checksum], env);
  assert.equal(firstResult.status, 0, firstResult.stderr);
  assert.match(firstResult.stdout, /PREVIOUS_RELEASE_SHA=none/);
  assert.match(firstResult.stdout, new RegExp(`DEPLOYED_SHA=${sha1}`));
  assert.equal(lstatSync(join(webRoot, "current")).isSymbolicLink(), true);
  assert.equal(readlinkSync(join(webRoot, "current")), join(webRoot, "releases", sha1));
  assert.equal(existsSync(join(webRoot, `.incoming-${sha1}`)), false);

  const second = makeArchive(sandbox, sha2, "second");
  const secondResult = await runRelease(["deploy", sha2, second.archive, second.checksum], env);
  assert.equal(secondResult.status, 0, secondResult.stderr);
  assert.match(secondResult.stdout, new RegExp(`PREVIOUS_RELEASE_SHA=${sha1}`));
  assert.equal(readlinkSync(join(webRoot, "current")), join(webRoot, "releases", sha2));
  assert.match(readFileSync(join(webRoot, "current", "index.html"), "utf8"), /second/);

  const third = makeArchive(sandbox, sha3, "must-rollback");
  site.reject(sha3);
  const failed = await runRelease(["deploy", sha3, third.archive, third.checksum], env);
  assert.notEqual(failed.status, 0);
  assert.match(failed.stderr, /previous release restored/);
  assert.equal(readlinkSync(join(webRoot, "current")), join(webRoot, "releases", sha2));
  assert.match(readFileSync(join(webRoot, "current", "index.html"), "utf8"), /second/);
  assert.equal(existsSync(join(webRoot, `.incoming-${sha3}`)), false);

  site.reject(null);
  const rollback = await runRelease(["rollback", sha1], env);
  assert.equal(rollback.status, 0, rollback.stderr);
  assert.match(rollback.stdout, new RegExp(`PREVIOUS_RELEASE_SHA=${sha2}`));
  assert.match(rollback.stdout, new RegExp(`DEPLOYED_SHA=${sha1}`));
  assert.equal(readlinkSync(join(webRoot, "current")), join(webRoot, "releases", sha1));

  site.reject(sha2);
  const failedRollback = await runRelease(["rollback", sha2], env);
  assert.notEqual(failedRollback.status, 0);
  assert.match(failedRollback.stderr, /previous release restored/);
  assert.equal(readlinkSync(join(webRoot, "current")), join(webRoot, "releases", sha1));

  const missing = await runRelease(["rollback", "4".repeat(40)], env);
  assert.notEqual(missing.status, 0);
  assert.match(missing.stderr, /release directory is missing/);
  assert.equal(readlinkSync(join(webRoot, "current")), join(webRoot, "releases", sha1));
});
