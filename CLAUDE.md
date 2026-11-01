# SG Labs Time Sheet: notes for Claude

Read this first. It carries the project's context between sessions.

## Who / how to work
- Owner: runs SG Labs and bills clients by the hour; lives in a dorm.
- Act as a business partner/advisor: friendly, plain language, explain trade-offs, give a recommendation.
  Research (docs/web) before answering anything factual. Not a professional developer, so give exact click-by-click steps.
- Default currency USD. Their rate is $30/hr.

## What the app is
A work-hour tracker: tap Start, pick/create a project, add a description; Pause/Resume (breaks not counted);
Stop → optional proof-of-work photos → saved to a per-project log grouped by month and day. Each entry box shows
start → stop (top left), total worked (bottom left), photos (right half), and the description (bottom).
The log always shows EXACT times. Only billing rounds: the month's total rounds UP to the next full hour.

## Two versions in this repo
1. **Web app (live)**: `index.html`, `app.js`, `sw.js`, `manifest.webmanifest`. Vanilla JS home-screen web app,
   same style as their budgeting app (github.com/sebastiansglabs/budgeting-app). Data stays on the phone
   (localStorage + IndexedDB for photos). Served by GitHub Pages from `main`:
   https://sebastiansglabs.github.io/SG-Labs-Time-Sheet-System/. **Merging to `main` publishes it.**
   Bump `CACHE` in `sw.js` when shipping changes.
2. **Native iPhone app**: `ios/` (SwiftUI, iOS 17+, Xcode project with synchronized folders). Exists for the
   lock screen + Dynamic Island timer (Live Activity) with Pause/Resume and Stop buttons (LiveActivityIntent,
   `#if !WIDGET_EXTENSION` guards the app-only code). Uses the same JSON format as the web app and imports its
   backup. Setup steps for the owner: `ios/README.md`.

## Owner's hardware
- MacBook Pro 13" 2018 (Intel i5, 8 GB). Max macOS is Sequoia → **max Xcode is 26.3** (26.4+ needs Tahoe,
  27 needs Apple silicon). Plenty of disk. Can stay on 24/7 in their dorm on their own router.
- iPhone 15 Pro Max (has Dynamic Island).
- Signing: **free Apple ID (Personal Team), no $99 program for now**. Free installs expire every 7 days.
  App Groups don't work on free teams, so the design avoids them. Plan: AltServer on the Mac for weekly
  auto-refresh over Wi-Fi (not set up yet).

## Status (Nov 2026)
- Web app: done and live. Running timer shows only the timer + Pause/Stop. "Discard this session" after Stop.
- iOS app: code written but **never compiled yet** (written from a Linux cloud session). Next: first build in
  Xcode 26.3 on the Mac, fix compile errors, install on the iPhone, test the Live Activity buttons.
  Merge `ios/` into `main` only after it builds.
- PDF export for clients: concept only (`concept/receipt-concept.pdf`), no export button yet. Open questions for
  the owner: (1) round the monthly total (current) or each session? (2) header name/contact details,
  (3) keep the separate photo page or thumbnails only?

## Later
- AltServer weekly auto-refresh setup (add steps to `ios/README.md` §9).
- Team version: workers log in and only see projects they're assigned to (needs hosted DB + auth, and the
  $99 Apple program for TestFlight distribution).

## Conventions
- Work on a branch, open a PR, merge to `main` to publish (the owner has OK'd merging for releases).
- Don't put personal contact details (email/phone) in committed files.
