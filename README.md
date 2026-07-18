# Mellotron Sound Effects

A minimal, endless browser sound-collage instrument built from 1,260 Mellotron sound-effects samples.

**Live site:** [mikeyoung.org/mfx](https://mikeyoung.org/mfx/)

## Versioning

The current release is **9.2**, with `9` as the major version and `2` as the minor version. `VERSION` is the single source of truth and is injected into the generated page during the build.

Every code commit must increment the minor version by one before rebuilding and committing. For example, the commit following 9.2 must be 9.3.

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

Each track keeps exactly two future sounds loading while the current sound plays. Playback advances only after the current sound and any delay trail have finished.

## Performance design

- Playback is capped at four tracks.
- Each track lazily loads two sounds ahead; the full library is never preloaded.
- Failed loads are skipped immediately and replaced until a usable sound is found.
- Network work is capped at 13 concurrent requests in both the page and service worker.
- Forward sounds without oscillator pitch use the browser's native media pipeline.
- Reverse and pitch-modulated sounds use short-lived decoded Web Audio buffers.
- Sources, buffers, timers, listeners, automation, and audio nodes are explicitly released after every sound.
- Successfully lazy-loaded audio is stored on disk with Cache Storage rather than retained in JavaScript memory.
- A one-frame silent Web Audio loop and Screen Wake Lock provide best-effort continuous operation while playback is active. Browsers and operating systems may still suspend background pages.
- Media-session buttons are explicitly ignored.

## PWA

The app includes a manifest, offline app shell, install icons, and a service worker. Use the browser's install command to run it as a standalone PWA. Audio still requires the initial **GO!** interaction.

## Run locally

The page must be served over HTTP so Web Audio, fetch, and the service worker can operate correctly.

```bash
python -m http.server 8080
```

Then open <http://localhost:8080/>. Browsers require the initial **GO!** interaction before audio can start.

## Rebuild after changing `snd/`

The sound manifest and cache version are generated from the files in `snd/`:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

The build writes `index.html` and `sw.js`, including versioned sound and app-shell cache names. Commit those generated files together with source or sound-file changes.

## Deploy

`deploy_mellotron.sh` uploads the generated page, worker, PWA manifest, icons, and `snd/` to the isolated `/mfx` FTPS directory, retries failures, and verifies the public HTTPS endpoints.

```bash
bash "M:/backup/webdev/chaotic sound effects/deploy_mellotron.sh"
```

The deployment script is non-destructive: it neither lists nor deletes remote files. Authentication is handled directly by curl through a local `.netrc` file; credentials are not stored in this repository.

## Project layout

```text
index.html             Generated static application
sw.js                  Generated cache service worker
manifest.webmanifest   PWA metadata
icon-192.png           PWA and touch icon
icon-512.png           Large and maskable PWA icon
snd/                   Audio library
src/                   Source templates
build.ps1              Manifest and cache-version generator
VERSION                Current major.minor application version
deploy_mellotron.sh    Guarded FTPS deployment
```

## License

[MIT](LICENSE)
