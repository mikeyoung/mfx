"use strict";

const APP_VERSION = "9.11";
const SOUND_CACHE_NAME = "mfx-sound-pack-v1-c50b03359543";
const SHELL_CACHE_NAME = "mfx-shell-4e96986b4f06";
const SOUND_CACHE_PREFIX = "mfx-sound-pack-v1-";
const SHELL_CACHE_PREFIX = "mfx-shell-";
const LEGACY_SOUND_CACHE_PREFIXES = ["mfx-sounds-v2-", "chaotic-sound-effects-"];
const MAX_CONCURRENT_REQUESTS = 13;
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
        name.startsWith(SOUND_CACHE_PREFIX)
        || LEGACY_SOUND_CACHE_PREFIXES.some((prefix) => name.startsWith(prefix))
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

async function handleShellRequest(request, cacheKey = request.url) {
  const cache = await caches.open(SHELL_CACHE_NAME);

  if (request.mode === "navigate") {
    try {
      const response = await limitedNetworkFetch(new Request(request, { cache: "no-cache" }));
      if (response.ok) {
        try {
          await cache.put(new URL("./", self.registration.scope).href, response.clone());
        } catch {
          // The fresh navigation remains usable when storage is unavailable.
        }
      }
      return response;
    } catch {
      // Fall through to the offline shell below.
    }

    const fallback = await cache.match(new URL("./", self.registration.scope).href);
    if (fallback) return fallback;
    return limitedNetworkFetch(request);
  }

  const requestUrl = new URL(request.url);
  const requestedVersion = requestUrl.searchParams.get("v");
  if (requestedVersion && requestedVersion !== APP_VERSION) {
    // A newer page may briefly be controlled by the previous worker. Never let
    // that worker answer versioned asset requests from its stale shell cache.
    return limitedNetworkFetch(request);
  }

  const cached = await cache.match(cacheKey);
  if (cached) return cached;

  try {
    const response = await limitedNetworkFetch(request);
    if (response.ok) {
      try {
        await cache.put(cacheKey, response.clone());
      } catch {
        // The network response remains usable when storage is unavailable.
      }
    }
    return response;
  } catch (error) {
    throw error;
  }
}

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const shellUrl = new URL(request.url);
  shellUrl.searchParams.delete("v");
  if (request.mode === "navigate" || SHELL_ASSETS.includes(shellUrl.href)) {
    event.respondWith(handleShellRequest(request, shellUrl.href));
  }
});
