# Chaotic Sound Effects store submission

## Shared listing content

Name: **Chaotic Sound Effects**

Short summary:

> Create an endless five-track stereo collage from a library of 1,260 sound effects.

Full description:

> Chaotic Sound Effects creates a continuously changing sound collage from a library of 1,260 effects. Five simultaneous tracks independently randomize direction, playback rate, pitch movement, stereo position, panning motion, and echo trails. The previous 12 selections are excluded to keep the sequence varied.
>
> Playback starts only after you press GO! and stops when you press STOP. The complete sound library is included with the extension and remains available offline. No account, subscription, analytics, advertising, or network access is required.

Homepage: `https://mikeyoung.org/csfx/`

Support URL: `https://github.com/mikeyoung/mfx/issues`

Software license: MIT

Media license: Excluded from the MIT License and distributed only under separate authorization from the applicable rights holder. Do not describe the entire extension package as MIT licensed.

Suggested category: choose the current store category closest to **Music and Audio**.

## Chrome Web Store

Single purpose:

> Generate an endless randomized stereo sound-effects collage in a dedicated extension tab.

Permission justification:

> The extension requests no API permissions and no host permissions. Its toolbar action uses the browser's standard action and tab-creation APIs to open the packaged application in a full tab. Opening a tab does not require the `tabs` permission.

Remote code:

> No. All HTML, CSS, JavaScript, icons, the sound index, and the 45 MiB audio pack are included in the submitted ZIP. The extension does not download or execute remote code.

Data-use declaration:

> The extension does not collect, transmit, sell, or use user data. It has no analytics, accounts, advertisements, cookies, or telemetry. Browser-managed local storage contains only the application version and a local copy of the static bundled audio pack.

Media-rights disclosure for the listing — use only after authorization is effective:

> The application software is MIT licensed. Bundled audio recordings, images, icons, and other media are not covered by the MIT License and are used under separate authorization from their applicable rights holders.

Do not publish that statement until it is true under an executed agreement.

Store assets to supply in the dashboard:

- At least one current 1280 x 800 px application screenshot; Chrome also accepts 640 x 400 px.
- The packaged 128 px icon as the store icon.
- A 440 x 280 px small promotional image.
- An optional 1400 x 560 px marquee promotional image for featured-placement eligibility.

## Firefox Add-ons (AMO)

Firefox extension ID: `chaotic-sound-effects@mikeyoung.org`

Supported Firefox versions:

- Firefox desktop 140 or later.
- Firefox for Android 142 or later.

Data collection declaration:

> None. `browser_specific_settings.gecko.data_collection_permissions.required` is set to `none`. All application and audio resources are packaged locally, and no user data is collected or transmitted.

Notes for reviewers:

> This is a Manifest V3 audio application with no requested permissions and no remotely hosted code. Clicking the toolbar action opens the packaged `index.html` in a full tab so audio is not tied to a short-lived popup. Audio never autoplays; the user must press GO!.
>
> `sounds.pack` is a static concatenation of 1,260 MP3 files, not executable content. The byte-range index is embedded as data near the top of `app.js`. At first launch the packaged file is streamed into browser-managed origin-private storage (with Cache Storage fallback), verified by exact byte length, and exposed as short-lived slices during playback. Decoded buffers, object URLs, Web Audio nodes, timers, and listeners are explicitly released.
>
> The submitted JavaScript is readable and is not minified or obfuscated. `extensions/build-extensions.ps1` extracts the generated inline application script and stylesheet into CSP-compatible local files, substitutes the repository `VERSION`, copies the static sound pack and icons, and creates the ZIP. Software source is available at https://github.com/mikeyoung/mfx under the MIT License. `MEDIA-NOTICE.md` expressly excludes the packaged media from that license.

Media authorization note for reviewers — complete only after authorization is effective:

> The bundled audio recordings are distributed under separate written authorization from **[RIGHTS-HOLDER LEGAL NAME]**, effective **[DATE]**, reference **[AGREEMENT OR CONTACT REFERENCE]**. The authorization covers downloadable Chrome and Firefox extension packages, offline local storage, the hosted PWA, worldwide distribution, and the playback transformations performed by the application. Documentation can be supplied privately to the reviewer on request.

Do not submit that statement with placeholders or before every assertion is supported by the executed authorization. If the agreement uses narrower language, replace the statement with its exact permitted scope.

Privacy policy field:

> No privacy policy is required for the current package because it collects and transmits no data. If the dashboard still requires a URL, publish the repository's `PRIVACY.md` on the project website and use that public URL.

Firefox listing images:

> Use current 1280 x 800 px screenshots where possible. Firefox recommends that maximum display size; other screenshots should retain a 1.6:1 aspect ratio.

## Release checklist

1. Obtain executed written authorization covering the actual media, downloadable browser-extension packages, the hosted PWA, offline caching, all playback transformations, intended territories, and commercial or noncommercial distribution as applicable.
2. Retain the authorization privately and record the rights-holder legal name, effective date, and reference for reviewers.
3. Add any attribution, trademark statement, usage restriction, or other wording required by that authorization to `MEDIA-NOTICE.md`, the package, and the store listings.
4. Ensure the store's license selection does not represent the entire media-containing package as MIT licensed; use the split software/media explanation above wherever the dashboard permits.
5. Remove every bracketed placeholder and verify every reviewer statement against the executed authorization.
6. Increment the repository minor version and rebuild before every submitted update.
7. Run `extensions/build-extensions.ps1 -RebuildApp`.
8. Load both unpacked packages and verify first launch, GO, STOP, repeated GO/STOP, reload, and offline restart.
9. Run `web-ext lint` on `extensions/dist/firefox`.
10. Confirm both ZIPs have `LICENSE` and `MEDIA-NOTICE.md` at the archive root, have `manifest.json` at the archive root, and contain no secrets, deploy state, source MP3 directory, or remote scripts.
11. Capture current screenshots from the exact unpacked build being submitted.
12. Upload the browser-specific ZIP and paste the matching listing/reviewer content above.
