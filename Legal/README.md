# Squeeshy legal pages

Live at **https://squeeshy-legal.pages.dev** — a Cloudflare Pages project called
`squeeshy-legal`, deliberately separate from `312itconsulting-site`.

- `/privacy` → App Store Connect "Privacy Policy URL"
- `/terms` → App Store Connect "Terms of Use (EULA)", or link it from your listing

They live here rather than only on the server because the privacy policy makes factual
claims about what the app does. When the app's data behaviour changes, this text has to
change in the same commit — the obvious case being optional iCloud syncing, which would
turn "nothing leaves your device" into something else.

## Deploying a change

```sh
npx wrangler pages deploy Legal --project-name squeeshy-legal --branch main
```

## Why not on 312itconsulting.com

That Pages project has **no git provider** — it is a direct-upload project, so
`wrangler pages deploy` replaces the entire site with whatever directory is passed. The
Astro source in `~/Desktop/312it-deploy` is months behind what is live, so rebuilding from
it would quietly revert the site. Serving these pages from their own project avoids that
entirely. To move them onto the main domain later, add a custom domain
(e.g. `legal.312itconsulting.com`) to the `squeeshy-legal` project rather than merging the
files into the site bundle.
