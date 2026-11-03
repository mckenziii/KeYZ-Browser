# KeYZ mod store

Mods for KeYZ Browser: small `.uc.css` (style) and
`.uc.js` / `.uc.mjs` (script) files that change how the browser looks and works.
They're separate from Firefox add-ons.

## Getting mods

In KeYZ Browser, open **The Den › Mods › Mod store**. Browsing and installing need no
account. Every file is checked against the SHA-256 in `index.json` before it's installed.

## Publishing a mod

1. Put your mod in your profile's `chrome/mods` folder and try it out.
2. In **The Den › Mods › Publish a mod**, sign in with GitHub, fill in the name and
   version, and press **Publish**. KeYZ Browser forks this store, commits your mod to
   `mods/<id>/` and opens a pull request for you.
3. The store's checks run on the pull request:
   - **Style mods** (`.uc.css` only) go live automatically once the checks pass.
   - **Script mods** can do anything the browser can, so @mckenziii reviews the code
     first. They get the `needs-review` label until then.

To update your mod, publish it again with the same id and a higher version. Only the
original author (or the store owner) can update a mod.

### Rules the checks enforce

- One mod per pull request, inside `mods/<id>/` (`id`: lower-case letters, numbers, dashes).
- `mod.json` with `id`, `name`, `version` (`1.2.3`), `description`, `type` (`style` or
  `script`), `author` (your GitHub name) and `files` (1 to 5 files, 512 KB each at most).
- Style mods must be self-contained: no `url(http…)`, `@import` or `-moz-binding`.
  Use `data:` URLs for images.
- Allowed extra files: `README.md` and `preview.png` (500 KB at most).

## Reporting a mod

Something harmful or broken? [Open a report](../../issues/new?template=report-mod.yml).
The store owner can remove a mod by deleting its folder; the index updates by itself.

## How it works

- `index.json` is rebuilt by `.github/workflows/build-index.yml` (and right after an
  automatic merge) with each file's SHA-256 and the commit it came from.
- `.github/workflows/check-mod.yml` runs `tools/validate.ps1` on every pull request. It
  reads the pull request's files as data and never runs them.
