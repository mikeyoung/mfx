"use strict";

const SOUND_CACHE_NAME = "__CACHE_NAME__";
const SHELL_CACHE_NAME = "__SHELL_CACHE_NAME__";
const SOUND_CACHE_PREFIX = "mfx-sounds-v2-";
const SHELL_CACHE_PREFIX = "mfx-shell-";
const LEGACY_CACHE_PREFIX = "chaotic-sound-effects-";
const MAX_CONCURRENT_REQUESTS = 13;
const PREFETCH_HEADER = "X-MFX-Prefetch";
const SOUND_ROOT = new URL("snd/", self.registration.scope).href;
const SHELL_ASSETS = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./icon-192.png",
  "./icon-512.png"
].map((path) => new URL(path, self.registration.scope).href);

const networkWaiters = [];
let activeNetworkRequests = 0;

async function limitedNetworkFetch(request) {
  if (activeNetworkRequests >= MAX_CONCURRENT_REQUESTS) {
    await new Promise((resolve) => networkWaiters.push(resolve));
  }
  activeNetworkRequests += 1;
  try {
    return await fetch(request);
  } finally {
    activeNetworkRequests -= 1;
    const next = networkWaiters.shift();
    if (next) next();
  }
}

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(SHELL_CACHE_NAME);
    await Promise.all(SHELL_ASSETS.map(async (url) => {
      const response = await limitedNetworkFetch(new Request(url, { cache: "reload" }));
      if (!response.ok) throw new Error(`App shell request failed with ${response.status}.`);
      await cache.put(url, response);
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const cacheNames = await caches.keys();
    await Promise.all(cacheNames.map((name) => {
      const obsoleteSoundCache = (
        name.startsWith(SOUND_CACHE_PREFIX) || name.startsWith(LEGACY_CACHE_PREFIX)
      ) && name !== SOUND_CACHE_NAME;
      const obsoleteShellCache = name.startsWith(SHELL_CACHE_PREFIX)
        && name !== SHELL_CACHE_NAME;
      return obsoleteSoundCache || obsoleteShellCache
        ? caches.delete(name)
        : Promise.resolve(false);
    }));
    await self.clients.claim();
  })());
});

async function createRangeResponse(response, rangeHeader) {
  const match = /^bytes=(\d*)-(\d*)$/.exec(rangeHeader.trim());
  if (!match || (!match[1] && !match[2])) return response;

  const lengthHeader = response.headers.get("Content-Length");
  const size = lengthHeader === null ? Number.NaN : Number(lengthHeader);
  if (!Number.isSafeInteger(size)
      || size < 0
      || !response.body
      || response.headers.has("Content-Encoding")) {
    // A full streamed response is safer than buffering an unknown representation.
    return response;
  }

  let start;
  let end;

  if (match[1]) {
    start = Number(match[1]);
    end = match[2] ? Number(match[2]) : size - 1;
  } else {
    const suffixLength = Number(match[2]);
    start = Math.max(0, size - suffixLength);
    end = size - 1;
  }

  if (!Number.isSafeInteger(start)
      || !Number.isSafeInteger(end)
      || start < 0
      || end < start
      || start >= size) {
    try {
      await response.body.cancel();
    } catch {
      // The invalid response body is no longer needed.
    }
    return new Response(null, {
      status: 416,
      headers: { "Content-Range": `bytes */${size}` }
    });
  }

  end = Math.min(end, size - 1);
  const headers = new Headers(response.headers);
  headers.set("Accept-Ranges", "bytes");
  headers.set("Content-Range", `bytes ${start}-${end}/${size}`);
  headers.set("Content-Length", String((end - start) + 1));

  const reader = response.body.getReader();
  let position = 0;
  let finished = false;
  const body = new ReadableStream({
    async pull(controller) {
      if (finished) {
        controller.close();
        return;
      }

      try {
        while (true) {
          const result = await reader.read();
          if (result.done) {
            finished = true;
            controller.close();
            return;
          }

          const chunk = result.value;
          const chunkStart = position;
          const chunkEnd = chunkStart + chunk.byteLength;
          position = chunkEnd;
          if (chunkEnd <= start) continue;

          if (chunkStart > end) {
            finished = true;
            await reader.cancel();
            controller.close();
            return;
          }

          const sliceStart = Math.max(0, start - chunkStart);
          const sliceEnd = Math.min(chunk.byteLength, (end + 1) - chunkStart);
          if (sliceEnd > sliceStart) {
            controller.enqueue(chunk.subarray(sliceStart, sliceEnd));
          }

          if (chunkEnd > end) {
            finished = true;
            await reader.cancel();
            controller.close();
          }
          return;
        }
      } catch (error) {
        finished = true;
        controller.error(error);
        try {
          await reader.cancel(error);
        } catch {
          // The stream is already failed; there is nothing left to release.
        }
      }
    },
    async cancel(reason) {
      if (finished) return;
      finished = true;
      try {
        await reader.cancel(reason);
      } catch {
        // Cancellation is best-effort after the client stops reading.
      }
    }
  });

  return new Response(body, {
    status: 206,
    statusText: "Partial Content",
    headers
  });
}

async function handleSoundRequest(request) {
  // The page owns lazy-prefetch writes so it can wait until the complete body
  // is safely in Cache Storage before handing the URL to an audio track.
  if (request.headers.has(PREFETCH_HEADER)) {
    return limitedNetworkFetch(request);
  }

  const cache = await caches.open(SOUND_CACHE_NAME);
  const cached = await cache.match(request);
  if (cached) {
    const range = request.headers.get("Range");
    return range ? createRangeResponse(cached, range) : cached;
  }

  const response = await limitedNetworkFetch(request);
  if (response.ok && response.status === 200 && !request.headers.has("Range")) {
    try {
      await cache.put(request, response.clone());
    } catch {
      // Playback can continue even if the device refuses a cache write.
    }
  }
  return response;
}

async function handleShellRequest(request) {
  const cache = await caches.open(SHELL_CACHE_NAME);
  const cached = await cache.match(request);
  if (cached) return cached;

  try {
    const response = await limitedNetworkFetch(request);
    if (response.ok) {
      try {
        await cache.put(request, response.clone());
      } catch {
        // The network response remains usable when storage is unavailable.
      }
    }
    return response;
  } catch (error) {
    if (request.mode === "navigate") {
      const fallback = await cache.match(new URL("./", self.registration.scope).href);
      if (fallback) return fallback;
    }
    throw error;
  }
}

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  if (request.url.startsWith(SOUND_ROOT)) {
    event.respondWith(handleSoundRequest(request));
    return;
  }

  if (request.mode === "navigate" || SHELL_ASSETS.includes(request.url)) {
    event.respondWith(handleShellRequest(request));
  }
});
