const GITHUB_OWNER = "davidkivuyo";
const GITHUB_REPO = "foodorder";

const LATEST_META_TTL = 300;
const ASSET_TTL = 60 * 60 * 24 * 30;
const GITHUB_API = "https://api.github.com";
const ALLOWED_HOST = "dl.larason.space";

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method !== "GET") {
      return new Response("Method not allowed", { status: 405 });
    }

    try {
      if (url.pathname === "/latest") {
        return await serveMetadata(null, ctx, env);
      }

      const releaseMatch = url.pathname.match(/^\/release\/(v[\w.\-]+)$/);
      if (releaseMatch) {
        return await serveMetadata(releaseMatch[1], ctx, env);
      }

      const assetMatch = url.pathname.match(
        /^\/(v[\w.\-]+)\/([\w.\-]+\.(apk|sha256))$/
      );
      if (assetMatch) {
        const [, tag, filename] = assetMatch;
        return await serveAsset(tag, filename, request, ctx);
      }

      return new Response("Not found", { status: 404 });
    } catch (err) {
      return new Response(
        JSON.stringify({ error: "Service temporarily unavailable" }),
        { status: 502, headers: { "content-type": "application/json" } }
      );
    }
  },
};

// -- metadata --------------------------------------------------------------

async function serveMetadata(explicitTag, ctx, env) {
  const cacheKeyUrl = explicitTag
    ? `https://dl.larason.space/release/${explicitTag}`
    : `https://dl.larason.space/latest`;
  const cache = caches.default;
  const cacheKey = new Request(cacheKeyUrl);

  const cached = await cache.match(cacheKey);
  if (cached) return cached;

  const tag = explicitTag ?? (await resolveLatestTag());
  if (!tag) {
    return jsonResponse({ error: "Could not resolve release" }, 502);
  }

  const releaseJsonUrl = `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/download/${tag}/release.json`;
  const originResponse = await fetch(releaseJsonUrl, {
    headers: { "User-Agent": "larason-release-proxy" },
  });

  if (!originResponse.ok) {
    return jsonResponse({ error: "Release metadata unavailable" }, 502);
  }

  const raw = await originResponse.json();
  const rewritten = rewriteGithubUrls(raw, tag);

  // Fail closed: if anything other than an approved dl.larason.space URL
  // survived rewriting, refuse to serve it rather than leaking internals
  // or forwarding an unexpected/malformed link to the client.
  const leak = findDisallowedUrl(rewritten);
  if (leak) {
    return jsonResponse(
      { error: "Release metadata failed validation" },
      502
    );
  }

  const ttl = explicitTag ? ASSET_TTL : LATEST_META_TTL;
  const response = jsonResponse(rewritten, 200, ttl);

  ctx.waitUntil(cache.put(cacheKey, response.clone()));
  return response;
}

async function resolveLatestTag() {
  const res = await fetch(
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

function rewriteGithubUrls(obj, tag) {
  if (typeof obj === "string") {
    const match = obj.match(
      /^https:\/\/github\.com\/[^/]+\/[^/]+\/releases\/download\/[^/]+\/([\w.\-]+)$/
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
  if (typeof obj === "string") {
    if (!looksLikeAbsoluteUrl(obj)) return null;
    try {
      const parsed = new URL(obj);
      if (parsed.protocol !== "https:" || parsed.host !== ALLOWED_HOST) {
        return obj;
      }
    } catch {
      // Not a parseable URL at all — not a leak, just a plain string field
      return null;
    }
    return null;
  }
  if (Array.isArray(obj)) {
    for (const item of obj) {
      const bad = findDisallowedUrl(item);
      if (bad) return bad;
    }
    return null;
  }
  if (obj && typeof obj === "object") {
    for (const value of Object.values(obj)) {
      const bad = findDisallowedUrl(value);
      if (bad) return bad;
    }
    return null;
  }
  return null;
}

function looksLikeAbsoluteUrl(str) {
  return /^https?:\/\//i.test(str);
}

function jsonResponse(body, status = 200, cacheTtl = null) {
  const headers = { "content-type": "application/json" };
  if (cacheTtl) headers["Cache-Control"] = `public, max-age=${cacheTtl}`;
  headers["Access-Control-Allow-Origin"] = "*";
  return new Response(JSON.stringify(body), { status, headers });
}

// -- asset proxy -------------------------------------------------------------

async function serveAsset(tag, filename, request, ctx) {
  const githubUrl = `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/download/${tag}/${filename}`;

  const cache = caches.default;
  const cacheKey = new Request(request.url, request);
  const cached = await cache.match(cacheKey);
  if (cached) return cached;

  const originResponse = await fetch(githubUrl, {
    cf: { cacheTtl: ASSET_TTL, cacheEverything: true },
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
