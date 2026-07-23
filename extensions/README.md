# Browser extension packages

This directory builds submission packages for the Chrome Web Store and Firefox Add-ons (AMO) from the same generated application used by the PWA.

The complete 45 MiB `sounds.pack` library is bundled inside each extension. The extension does not download code or audio at runtime, request host access, collect data, or require a network connection after installation. On first launch, the existing streaming loader places the packaged sound file in browser-managed persistent storage so individual clips can be sliced without retaining decoded copies of the library in memory.

Every package includes `LICENSE` for the MIT-licensed software and `MEDIA-NOTICE.md` explaining that the audio, images, icons, and other media are excluded from the MIT License and require separate authorization. Do not publicly submit or distribute a package until that authorization covers the intended stores, territories, and offline bundling behavior.

## Build

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\extensions\build-extensions.ps1 -RebuildApp
```

Use `-RebuildApp` after changing `src/index.template.html`, `snd/`, icons, or `VERSION`. Omit it when `index.html` and `sounds.pack` are already current.

Generated unpacked directories and upload-ready ZIP files are written beneath `extensions/dist/` and `extensions/artifacts/`. Both paths are ignored by Git.

## Test locally

Chrome or Chromium:

1. Open `chrome://extensions`.
2. Enable Developer mode.
3. Select **Load unpacked**.
4. Select `extensions/dist/chrome`.
5. Click the Chaotic Sound Effects toolbar icon. The application must open in a full tab.

Firefox desktop:

1. Open `about:debugging#/runtime/this-firefox`.
2. Select **Load Temporary Add-on**.
3. Select `extensions/dist/firefox/manifest.json`.
4. Click the Chaotic Sound Effects toolbar icon. The application must open in a full tab.

For AMO linting, install Mozilla's `web-ext` separately, then run:

```powershell
web-ext lint --source-dir .\extensions\dist\firefox
```

The Firefox ZIP must be signed by AMO before it can be installed in a regular Firefox profile. The Chrome ZIP is uploaded through the Chrome Web Store Developer Dashboard.

## Submission material

Copy the prepared descriptions, privacy answers, permission explanation, media-rights disclosure, and reviewer notes from `store-listing.md`. Add current screenshots made from the unpacked production build before submitting. Complete the authorization placeholders only after a written agreement is in effect.
