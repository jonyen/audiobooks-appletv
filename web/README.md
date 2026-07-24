# Audiobooks Web

React + Vite web port of AudiobooksTV: browse LibriVox, read along with
Project Gutenberg text, synced progress via Sign in with Apple + Firestore.

## Local development

```bash
npm install
npm test               # Vitest unit tests
npm run preview:full   # build + wrangler pages dev (serves /api/* functions)
```

`npm run dev` serves the SPA only (no /api proxy); use `preview:full` when
you need the LibriVox/Gutenberg proxy.

## One-time setup

1. **Firebase project** (Spark tier, its own project — NOT shared with
   bible-appletv): create at console.firebase.google.com, add a Web app,
   copy the config values into `.env.local` (see `.env.example`).
2. **Firestore**: create the database. Add a `firebase.json` next to
   `firestore.rules` so the CLI can find it:

   ```json
   { "firestore": { "rules": "firestore.rules" } }
   ```

   then deploy: `npx firebase-tools deploy --only firestore:rules`.
3. **Sign in with Apple** (requires an Apple Developer account):
   - developer.apple.com → Identifiers → create a **Services ID**
     (e.g. `com.example.audiobooks.web`), enable "Sign in with Apple",
     configure the web domain and the Firebase return URL
     (`https://<project>.firebaseapp.com/__/auth/handler`).
   - Create a **Sign in with Apple key**, note the Key ID and Team ID.
   - Firebase console → Authentication → Sign-in method → Apple: enable,
     fill in Services ID, Team ID, Key ID, and the key file contents.
4. **Cloudflare Pages**: create a Pages project from this repo
   (root directory `web`, build command `npm run build`, output `dist`) or
   deploy manually with `npx wrangler pages deploy dist`. Set the four
   `VITE_FIREBASE_*` environment variables in the Pages project settings.
5. Add the Pages domain (`*.pages.dev` and any custom domain) to Firebase
   Authentication → Settings → Authorized domains, and to the Apple
   Services ID's web domains.

## Architecture notes

- `/api/librivox` and `/api/gutenberg/:id` are Pages Functions proxying the
  two upstreams that lack CORS headers; both cache at the edge. Audio
  streams directly from archive.org (CORS + Range supported).
- Progress and preamble offsets live in Firestore
  (`users/{uid}/state/progress`, `users/{uid}/state/preambles`) and merge
  with the tvOS app's writes — see the design spec in
  `../docs/superpowers/specs/2026-07-23-web-port-synced-progress-design.md`.
