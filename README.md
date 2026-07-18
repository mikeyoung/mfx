# Mellotron Sound Effects

A minimal, endless browser sound-collage instrument built from 1,260 Mellotron sound-effects samples.

**Live site:** [mikeyoung.org/mfx](https://mikeyoung.org/mfx/)

## Playback

Press **GO!** to start four independent tracks. Press **STOP** to release every active audio resource and reset the session.

Each new sound independently receives randomized processing:

- 50% chance of reverse playback
- 50% chance of an echoing feedback delay
- 50% chance of a playback-rate shift between 0.5x and 2x
- random stereo position, with optional animated panning
- optional moderate oscillator-based pitch modulation
- 25% per-track gain followed by a shared peak limiter

A track does not select its next sound until the current sound and any delay trail have finished.

## Performance design

- Playback is capped at four tracks.
- Forward sounds without oscillator pitch use the browser's native media pipeline.
- Reverse and pitch-modulated sounds use short-lived decoded Web Audio buffers.
- Sources, buffers, timers, listeners, automation, and audio nodes are explicitly released after every sound.
- Cache warming is sequential so only one background download is active at a time.
- Audio is stored on disk with Cache Storage rather than retained in JavaScript memory.
- A versioned completion marker prevents rescanning a fully populated cache.

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

The build writes `index.html` and `sw.js`. Commit those generated files together with sound-file changes.

## Deploy

`deploy_mellotron.sh` uploads `index.html`, `sw.js`, and `snd/` to the isolated `/mfx` FTPS directory, retries failures, and verifies the public HTTPS endpoints.

```bash
bash "M:/backup/webdev/chaotic sound effects/deploy_mellotron.sh"
```

The deployment script is non-destructive: it neither lists nor deletes remote files. Authentication is handled directly by curl through a local `.netrc` file; credentials are not stored in this repository.

## Project layout

```text
index.html             Generated static application
sw.js                  Generated cache service worker
snd/                   Audio library
src/                   Source templates
build.ps1              Manifest and cache-version generator
deploy_mellotron.sh    Guarded FTPS deployment
```

## License

[MIT](LICENSE)
