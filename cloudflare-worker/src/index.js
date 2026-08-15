const GITHUB_OWNER = "larason";
const GITHUB_REPO = "foodorder";

const LATEST_META_TTL = 300;
const ASSET_TTL = 60 * 60 * 24 * 30;
const GITHUB_API = "https://api.github.com";
const ALLOWED_HOST = "dl.larason.space";

// Header used to record when a response was stored in the Cache API.
// The Cache API does not auto-expire entries, so TTLs are enforced
// explicitly by comparing this timestamp against the configured TTL.
const STORED_AT_HEADER = "x-proxy-cached-at";

// Timeout (ms) applied to the connection + response-headers phase of GitHub
// fetches for metadata (GitHub API + release.json). The timer is cancelled as
// soon as headers arrive, so streamed bodies are never truncated mid-download.
const GITHUB_TIMEOUT_MS = 10000;

// Timeout (ms) for asset proxying (APK/sha256 downloads). Headers can be slow
// to arrive under elevated GitHub TTFB, so give these a more generous budget
// than the short metadata timeout above.
const ASSET_TIMEOUT_MS = 60000;

// After a failed refresh of /latest, keep serving the last good cached copy
// for this many seconds without re-hitting GitHub, so an outage does not
// stampede the rate-limited GitHub API on every request.
const STALE_GRACE_TTL = 300;

// Fetch from GitHub with a timeout that covers connecting and receiving the
// response headers. The abort timer is cleared once the response arrives, so
// the body can stream to completion (important for large APK downloads).
// Callers may override the default timeout via { timeoutMs }.
async function fetchFromGithub(url, options = {}) {
  const { timeoutMs = GITHUB_TIMEOUT_MS, ...rest } = options;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      ...rest,
      signal: controller.signal,
    });
    clearTimeout(timer);
    return response;
  } catch (err) {
    clearTimeout(timer);
    throw err;
  }
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method !== "GET") {
      return new Response("Method not allowed", { status: 405 });
    }

    try {
      if (url.pathname === "/latest") {
        return await serveLatest(ctx);
      }

      const releaseMatch = url.pathname.match(/^\/release\/(v[\w.-]+)$/);
      if (releaseMatch) {
        return await serveRelease(releaseMatch[1], ctx);
      }

      const assetMatch = url.pathname.match(
        /^\/(v[\w.-]+)\/([\w.-]+\.(apk|sha256))$/
      );
      if (assetMatch) {
        const [, tag, filename] = assetMatch;
        return await serveAsset(tag, filename, request, ctx);
      }

      return new Response("Not found", { status: 404 });
    } catch (err) {
      console.error("Request handler error:", err);
      return new Response(
        JSON.stringify({ error: "Service temporarily unavailable" }),
        { status: 502, headers: { "content-type": "application/json" } }
      );
    }
  },
};

// -- metadata --------------------------------------------------------------

// Epoch seconds of the most recent failed refresh of /latest. Module-level
// state is per-isolate, which still collapses the common stampede case.
let lastLatestRefreshFailureAt = 0;

// GET /latest
//
// Serves the metadata for the current default release with a 5-minute edge
// TTL. A cached copy that has expired is refreshed from GitHub; if GitHub is
// unreachable the last good cached copy is served with `stale: true` instead
// of erroring out. After a refresh failure, subsequent requests keep serving
// the stale copy for STALE_GRACE_TTL seconds without re-hitting GitHub, so
// an outage does not stampede the rate-limited GitHub API on every request.
async function serveLatest(ctx) {
  const cacheKey = new Request("https://dl.larason.space/latest");
  const cache = caches.default;

  const cached = await cache.match(cacheKey);
  const now = Date.now() / 1000;

  if (cached && ageSeconds(cached) < LATEST_META_TTL) {
    return cached;
  }

  // Outage grace window: a refresh failed recently — keep serving the last
  // good copy until the window lapses instead of re-hitting GitHub.
  if (cached && now - lastLatestRefreshFailureAt < STALE_GRACE_TTL) {
    return staleResponse(cached);
  }

  try {
    const tag = await resolveLatestTag();
    if (!tag) throw new Error("Could not resolve latest release");
    // Refresh succeeded — clear the failure marker.
    lastLatestRefreshFailureAt = 0;
    return await buildMetadataResponse(tag, cache, cacheKey, ctx, {
      ttl: LATEST_META_TTL,
    });
  } catch (err) {
    console.error("serveLatest error:", err);
    lastLatestRefreshFailureAt = Date.now() / 1000;
    if (cached) {
      return staleResponse(cached);
    }
    return jsonResponse({ error: "Release metadata unavailable" }, 502);
  }
}

// GET /release/{tag}
//
// Serves metadata for a specific immutable release. Once cached it is never
// refreshed from GitHub.
async function serveRelease(tag, ctx) {
  const cacheKey = new Request(`https://dl.larason.space/release/${tag}`);
  const cache = caches.default;

  const cached = await cache.match(cacheKey);
  if (cached) return cached;

  try {
    return await buildMetadataResponse(tag, cache, cacheKey, ctx, {
      ttl: ASSET_TTL,
      immutable: true,
    });
  } catch (err) {
    console.error("serveRelease error:", err);
    return jsonResponse({ error: "Release metadata unavailable" }, 502);
  }
}

// Fetch a release's release.json from GitHub, rewrite every URL to point at
// the proxy host, validate that nothing unexpected leaked through, then cache
// the result at the edge.
async function buildMetadataResponse(tag, cache, cacheKey, ctx, { ttl, immutable = false }) {
  const releaseJsonUrl = `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/download/${tag}/release.json`;
  const originResponse = await fetchFromGithub(releaseJsonUrl, {
    headers: { "User-Agent": "larason-release-proxy" },
  });

  if (!originResponse.ok) {
    throw new Error(`Origin returned ${originResponse.status}`);
  }

  const raw = await originResponse.json();
  const rewritten = rewriteGithubUrls(raw, tag);

  // Fail closed: if anything other than an approved dl.larason.space URL
  // survived rewriting, refuse to serve it rather than leaking internals
  // or forwarding an unexpected/malformed link to the client.
  const leak = findDisallowedUrl(rewritten);
  if (leak) {
    throw new Error("Release metadata failed validation");
  }

  const response = jsonResponse(rewritten, 200, ttl, {
    "Cache-Control": `public, max-age=${ttl}${immutable ? ", immutable" : ""}`,
  });

  // Cache the response with a stored-at timestamp so TTLs can be enforced.
  const cachedClone = response.clone();
  const ts = String(Math.floor(Date.now() / 1000));
  const headers = new Headers(cachedClone.headers);
  headers.set(STORED_AT_HEADER, ts);
  ctx.waitUntil(
    cache.put(
      cacheKey,
      new Response(cachedClone.body, {
        status: cachedClone.status,
        statusText: cachedClone.statusText,
        headers,
      })
    )
  );

  return response;
}

async function resolveLatestTag() {
  const res = await fetchFromGithub(
    `${GITHUB_API}/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest`,
    {
      headers: {
        "User-Agent": "larason-release-proxy",
        Accept: "application/vnd.github+json",
      },
    }
  );
  if (!res.ok) return null;
  const data = await res.json();
  return data.tag_name ?? null;
}

// Age (seconds) of a cached response based on the stored-at timestamp.
function ageSeconds(cached) {
  const raw = cached.headers.get(STORED_AT_HEADER);
  if (!raw) return Infinity;
  const storedAt = Number(raw);
  if (!Number.isFinite(storedAt)) return Infinity;
  return (Date.now() / 1000) - storedAt;
}

// Return a stale cached copy with `stale: true` added, without mutating the
// stored entry. Marked no-store so it is never re-cached.
function staleResponse(cached) {
  return cached
    .clone()
    .text()
    .then((text) => {
      let body = {};
      try {
        body = JSON.parse(text);
      } catch {
        // Non-JSON cached body is discarded — the response contains only the
        // stale marker. Clients cannot consume raw text, so there is nothing
        // to preserve.
      }
      return jsonResponse({ ...body, stale: true }, 200, null, {
        "Cache-Control": "no-store",
      });
    });
}

function rewriteGithubUrls(obj, tag) {
  if (typeof obj === "string") {
    const match = obj.match(
      /^https:\/\/github\.com\/[^/]+\/[^/]+\/releases\/download\/[^/]+\/([\w.-]+)$/
    );
    if (match) {
      return `https://${ALLOWED_HOST}/${tag}/${match[1]}`;
    }
    return obj;
  }
  if (Array.isArray(obj)) {
    return obj.map((item) => rewriteGithubUrls(item, tag));
  }
  if (obj && typeof obj === "object") {
    const out = {};
    for (const [key, value] of Object.entries(obj)) {
      out[key] = rewriteGithubUrls(value, tag);
    }
    return out;
  }
  return obj;
}

// Walk the fully-rewritten object and return the first value that looks
// like a URL but is NOT an https://dl.larason.space/... URL. Any string
// that parses as an absolute URL is treated as security-relevant — this
// is deliberately strict rather than trying to guess which fields are
// "download-like".
function findDisallowedUrl(obj) {
  if (typeof obj === "string") return findDisallowedUrlInString(obj);
  if (Array.isArray(obj)) return findDisallowedUrlInIterable(obj);
  if (obj && typeof obj === "object") {
    return findDisallowedUrlInIterable(Object.values(obj));
  }
  return null;
}

function findDisallowedUrlInString(str) {
  if (!looksLikeAbsoluteUrl(str)) return null;
  try {
    const parsed = new URL(str);
    if (parsed.protocol !== "https:" || parsed.host !== ALLOWED_HOST) {
      return str;
    }
  } catch {
    // Not a parseable URL at all — not a leak, just a plain string field
    return null;
  }
  return null;
}

function findDisallowedUrlInIterable(items) {
  for (const item of items) {
    const bad = findDisallowedUrl(item);
    if (bad) return bad;
  }
  return null;
}

function looksLikeAbsoluteUrl(str) {
  return /^https?:\/\//i.test(str);
}

function jsonResponse(body, status = 200, cacheTtl = null, extraHeaders = {}) {
  const headers = { "content-type": "application/json" };
  if (cacheTtl) headers["Cache-Control"] = `public, max-age=${cacheTtl}`;
  headers["Access-Control-Allow-Origin"] = "*";
  Object.assign(headers, extraHeaders);
  return new Response(JSON.stringify(body), { status, headers });
}

// -- asset proxy -------------------------------------------------------------

// GET /{tag}/{filename}
//
// Proxies the actual APK / checksum bytes from GitHub. Tags are immutable so
// the bytes are cached with a long-lived immutable TTL. Range requests are
// forwarded to the origin so interrupted downloads can resume from the last
// received byte.
async function serveAsset(tag, filename, request, ctx) {
  const githubUrl = `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/download/${tag}/${filename}`;

  const range = request.headers.get("range");

  // Range requests bypass the Cache API (a 206 partial response must never
  // shadow the full cached representation). Cloudflare's HTTP cache handles
  // range slices at the edge via cacheEverything below.
  if (range) {
    return proxyRangeAsset(githubUrl, request, range);
  }

  const cache = caches.default;
  const cacheKey = new Request(request.url, request);
  const cached = await cache.match(cacheKey);
  if (cached) return cached;

  const originResponse = await fetchFromGithub(githubUrl, {
    cf: { cacheTtl: ASSET_TTL, cacheEverything: true },
    timeoutMs: ASSET_TIMEOUT_MS,
  });

  if (!originResponse.ok) {
    return jsonResponse({ error: "Asset not found" }, originResponse.status);
  }

  const response = new Response(originResponse.body, originResponse);
  response.headers.set(
    "Cache-Control",
    `public, max-age=${ASSET_TTL}, immutable`
  );
  response.headers.set("Access-Control-Allow-Origin", "*");
  response.headers.delete("x-github-request-id");
  response.headers.delete("via");

  ctx.waitUntil(cache.put(cacheKey, response.clone()));
  return response;
}

async function proxyRangeAsset(githubUrl, request, range) {
  const originResponse = await fetchFromGithub(githubUrl, {
    headers: { Range: range, "User-Agent": "larason-release-proxy" },
    cf: { cacheTtl: ASSET_TTL, cacheEverything: true },
    timeoutMs: ASSET_TIMEOUT_MS,
  });

  if (
    originResponse.status !== 206 ||
    !originResponse.headers.get("Content-Range")
  ) {
    // Do not reuse originResponse.status: a 200 full-body reply to a Range
    // request would otherwise surface as a JSON body with status 200, which
    // clients treat as a valid download start. Report a server error instead.
    return jsonResponse({ error: "Asset not found" }, 502);
  }

  const response = new Response(originResponse.body, originResponse);
  response.headers.set(
    "Cache-Control",
    `public, max-age=${ASSET_TTL}, immutable`
  );
  response.headers.set("Access-Control-Allow-Origin", "*");
  response.headers.delete("x-github-request-id");
  response.headers.delete("via");
  return response;
}
