# Mellotron Sound Effects

A minimal, endless browser sound-collage instrument built from 1,260 Mellotron sound-effects samples.

**Live site:** [mikeyoung.org/mfx](https://mikeyoung.org/mfx/)

## Versioning

The current release is **9.8**, with `9` as the major version and `8` as the minor version. `VERSION` is the single source of truth and is injected into the generated page during the build.

Every code commit must increment the minor version by one before rebuilding and committing. For example, the commit following 9.8 must be 9.9.

## Playback

Press **GO!** to start four independent tracks. Press **STOP** to release every active audio resource and reset the session.

Each new sound independently receives randomized processing:

- never repeats any of the previous 12 sound selections
- 50% chance of reverse playback
- 50% chance of an echoing feedback delay
- 50% chance of a playback-rate shift between 0.5x and 2x
- random stereo position, with optional animated panning
- optional moderate oscillator-based pitch modulation
- 25% per-track gain followed by a shared peak limiter

On page load, a text-free full-screen loader shows the sound-pack transfer as a hard-edged, full-height white bar growing across a black background. The controls appear only after both the complete sound library and the PWA app shell have been durably stored for offline use. Playback advances only after the current sound and any delay trail have finished.

## Performance design

- Playback is capped at four tracks.
- The 1,260 original MP3 byte streams are concatenated without recompression into one approximately 45 MiB `sounds.pack` file.
- The generated page embeds a compact filename, byte-offset, and byte-length map. Each selected clip is recovered locally with `File.slice()`.
- The pack is streamed into the browser's Origin Private File System when available, with Cache Storage as the feature-detected fallback.
- The complete sound library therefore requires one network request on first use and no per-clip network requests afterward.
- A failed or interrupted pack transfer is removed and retried up to three times; incomplete packs are never accepted as ready.
- The content-derived pack name remains unchanged across code releases, preventing code-version updates from downloading the sounds again.
- Forward sounds without oscillator pitch use the browser's native media pipeline.
- Reverse and pitch-modulated sounds use short-lived decoded Web Audio buffers.
- Sources, buffers, timers, listeners, automation, and audio nodes are explicitly released after every sound.
- Only a small compressed slice and any active decoded clip are retained for playback; the complete pack remains disk-backed where OPFS is available.
- A one-frame silent Web Audio loop and Screen Wake Lock provide best-effort continuous operation while playback is active. Browsers and operating systems may still suspend background pages.
- Media-session buttons are explicitly ignored.

## PWA

The app includes a manifest, offline app shell, install icons, and a service worker. The site-local `web.config` registers the generated `.pack` file as static binary content on IIS. Use the browser's install command to run it as a standalone PWA. Audio still requires the initial **GO!** interaction.

The loading takeover is dismissed only after the current app shell and complete content-versioned sound pack are verified in persistent browser storage. A subsequent launch can therefore initialize successfully with no network available. The app requests persistent storage on supporting browsers, although the browser or operating system retains final authority over storage eviction.

App-shell updates use the service worker's atomic install/activate lifecycle: the previous offline shell remains intact until the replacement is complete. Navigations use the network first with an offline cache fallback. Sound-pack cache keys are derived from audio content rather than the application version, so a code-only update does not redownload the library.

## Run locally

The page must be served over HTTP so Web Audio, fetch, and the service worker can operate correctly.

```bash
python -m http.server 8080
```

Then open <http://localhost:8080/>. Browsers require the initial **GO!** interaction before audio can start.

## Rebuild after changing `snd/`

The indexed sound pack, manifest, and content-derived cache version are generated from the files in `snd/`:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

The build writes the ignored deployment artifact `sounds.pack` plus `index.html` and `sw.js`. Commit the generated page and worker together with source or sound-file changes; rebuild the pack before deployment.

## Deploy

`deploy_mellotron.sh` uploads the generated page, worker, PWA manifest, icons, IIS MIME configuration, and single `sounds.pack` file to the isolated `/mfx` FTPS directory, retries failures, and verifies the public HTTPS endpoints. Individual files under `snd/` are no longer uploaded.

```bash
bash "M:/backup/webdev/chaotic sound effects/deploy_mellotron.sh"
```

The deployment script is non-destructive: it neither lists nor deletes remote files. Authentication is handled directly by curl through a local `.netrc` file; credentials are not stored in this repository.

Successful deployments record SHA-256 hashes in the ignored `.deploy-state/` directory. Later deployments upload only files whose contents changed. A fresh clone without deployment state performs one complete upload before incremental deployment begins.

Run `deploy_mellotron.sh --plan` to calculate the incremental upload count without accessing FTP or changing deployment state.

## Project layout

```text
index.html             Generated static application
sw.js                  Generated cache service worker
manifest.webmanifest   PWA metadata
icon-192.png           PWA and touch icon
icon-512.png           Large and maskable PWA icon
web.config             Site-local IIS MIME mapping for the sound pack
snd/                   Audio library
sounds.pack            Ignored, generated indexed audio pack
src/                   Source templates
build.ps1              Pack, manifest, and cache-version generator
VERSION                Current major.minor application version
deploy_mellotron.sh    Guarded FTPS deployment
```

## License

[MIT](LICENSE)
