const GITHUB_OWNER = "davidkivuyo";
const GITHUB_REPO = "foodorder";
const CACHE_TTL_SECONDS = 60 * 60 * 24 * 30; // 30 days — safe since tags are immutable

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Expect paths like /v1.4.2/CampusBite-universal.apk
    const match = url.pathname.match(/^\/(v[\w.\-]+)\/([\w.\-]+\.(apk|sha256))$/);
    if (!match) {
      return new Response("Not found", { status: 404 });
    }

    const [, tag, filename] = match;
    const githubUrl = `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/download/${tag}/${filename}`;

    const cache = caches.default;
    const cacheKey = new Request(url.toString(), request);
    let response = await cache.match(cacheKey);

    if (!response) {
      const originResponse = await fetch(githubUrl, {
        cf: { cacheTtl: CACHE_TTL_SECONDS, cacheEverything: true },
      });

      if (!originResponse.ok) {
        return new Response("Upstream fetch failed", { status: originResponse.status });
      }

      response = new Response(originResponse.body, originResponse);
      response.headers.set("Cache-Control", `public, max-age=${CACHE_TTL_SECONDS}, immutable`);
      response.headers.set("Access-Control-Allow-Origin", "*");
      ctx.waitUntil(cache.put(cacheKey, response.clone()));
    }

    return response;
  },
};
