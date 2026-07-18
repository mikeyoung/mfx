"use strict";

const CACHE_NAME = "__CACHE_NAME__";
const CACHE_PREFIX = "chaotic-sound-effects-";
const MAX_RETRY_PASSES = 3;
const COMPLETION_MARKER_URL = new URL(".cache-complete", self.registration.scope).href;

self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const cacheNames = await caches.keys();
    await Promise.all(
      cacheNames
        .filter((name) => name.startsWith(CACHE_PREFIX) && name !== CACHE_NAME)
        .map((name) => caches.delete(name))
    );
    await self.clients.claim();
  })());
});

async function notifyClients(message) {
  const clients = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
  for (const client of clients) client.postMessage(message);
}

async function cacheSounds(urls) {
  const cache = await caches.open(CACHE_NAME);
  const completionMarker = new Request(COMPLETION_MARKER_URL);
  if (await cache.match(completionMarker)) {
    await notifyClients({
      type: "CACHE_COMPLETE",
      cacheName: CACHE_NAME,
      total: urls.length,
      errors: 0
    });
    return;
  }

  let failedIndexes = [];

  for (let index = 0; index < urls.length; index += 1) {
    const request = new Request(urls[index], { cache: "reload" });

    try {
      if (!(await cache.match(request))) {
        // cache.add() lets the browser stream the response directly to its on-disk
        // cache. Sequential work caps background download memory at one file.
        await cache.add(request);
      }
    } catch {
      failedIndexes.push(index);
    }

    const completed = index + 1;
    if (completed % 25 === 0 || completed === urls.length) {
      await notifyClients({
        type: "CACHE_PROGRESS",
        cacheName: CACHE_NAME,
        completed,
        total: urls.length,
        errors: failedIndexes.length
      });
    }
  }

  for (
    let attempt = 1;
    attempt <= MAX_RETRY_PASSES && failedIndexes.length;
    attempt += 1
  ) {
    const retryingIndexes = failedIndexes;
    failedIndexes = [];

    await notifyClients({
      type: "CACHE_RETRY_START",
      cacheName: CACHE_NAME,
      attempt,
      maxAttempts: MAX_RETRY_PASSES,
      total: retryingIndexes.length
    });

    for (let index = 0; index < retryingIndexes.length; index += 1) {
      const soundIndex = retryingIndexes[index];
      const request = new Request(urls[soundIndex], { cache: "reload" });

      try {
        if (!(await cache.match(request))) {
          await cache.add(request);
        }
      } catch {
        failedIndexes.push(soundIndex);
      }

      const completed = index + 1;
      if (completed % 25 === 0 || completed === retryingIndexes.length) {
        await notifyClients({
          type: "CACHE_RETRY_PROGRESS",
          cacheName: CACHE_NAME,
          attempt,
          maxAttempts: MAX_RETRY_PASSES,
          completed,
          total: retryingIndexes.length,
          errors: failedIndexes.length
        });
      }
    }
  }

  if (!failedIndexes.length) {
    await cache.put(completionMarker, new Response("complete", {
      headers: { "Content-Type": "text/plain" }
    }));
  }

  await notifyClients({
    type: "CACHE_COMPLETE",
    cacheName: CACHE_NAME,
    total: urls.length,
    errors: failedIndexes.length
  });
}

let warming = null;

self.addEventListener("message", (event) => {
  const message = event.data;
  if (!message || message.type !== "CACHE_SOUNDS" || message.cacheName !== CACHE_NAME) return;
  if (!Array.isArray(message.urls) || warming) return;

  warming = cacheSounds(message.urls).finally(() => {
    warming = null;
  });
  event.waitUntil(warming);
});

async function createRangeResponse(response, rangeHeader) {
  const match = /^bytes=(\d*)-(\d*)$/.exec(rangeHeader.trim());
  if (!match || (!match[1] && !match[2])) return response;

  const body = await response.arrayBuffer();
  const size = body.byteLength;
  let start;
  let end;

  if (match[1]) {
    start = Number(match[1]);
    end = match[2] ? Number(match[2]) : size - 1;
  } else if (match[2]) {
    const suffixLength = Number(match[2]);
    start = Math.max(0, size - suffixLength);
    end = size - 1;
  }

  if (!Number.isSafeInteger(start)
      || !Number.isSafeInteger(end)
      || start < 0
      || end < start
      || start >= size) {
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

  return new Response(body.slice(start, end + 1), {
    status: 206,
    statusText: "Partial Content",
    headers
  });
}

self.addEventListener("fetch", (event) => {
  const soundRoot = new URL("snd/", self.registration.scope).href;
  if (event.request.method !== "GET" || !event.request.url.startsWith(soundRoot)) return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const cached = await cache.match(event.request);
    if (!cached) return fetch(event.request);
    const range = event.request.headers.get("Range");
    return range ? createRangeResponse(cached, range) : cached;
  })());
});
