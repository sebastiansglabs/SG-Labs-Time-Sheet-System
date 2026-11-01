# Time Sheet

A work-hour tracker that installs on an iPhone as a home-screen web app (PWA), just like the Budget app.

When you do custom jobs for clients and charge by the hour, this app records exactly when you started and stopped,
how long you worked, what you worked on, and photos as proof of work. If a client asks where the hours came from,
pull it up on your phone. It can also be used by employees for simple time tracking.

## How it works

- **Start timer**: a full-screen timer with the current time at the top. Pick an existing project (or create one),
  add a description, and tap **Start**. You can **Pause** and **Resume**; breaks are not counted.
- **Stop**: you're asked if you want to add a photo (take one with the camera or pick from your library). Skip it or
  add as many as you like, then **Save to log**. Stopped by accident? Tap **Resume timer**.
- **Work log**: open a project, pick a month, and see each day. Every session shows start → stop time, total worked,
  photos, and the description. Tap a session to fix the times, edit the description, or add/remove photos.
  Forgot to start the timer? Use **+ Add** to log a session by hand.
- The timer keeps counting if you close the app or lock the phone. Reopening the app goes straight back to it.

The log always shows **exact** times. Billing rounds only the month's total **up** to the next full hour
(15h 3m bills as 16 h). The project page shows what that comes to at the project's hourly rate.

## Files

- `index.html` – layout and styles
- `app.js` – all app logic (hours live in the phone's local storage; photos in its IndexedDB)
- `sw.js` – service worker (offline support)
- `manifest.webmanifest`, `icon-*.png` – home-screen app name and icon
- `concept/` – PDF export concept (`receipt-concept.pdf`) and app screenshots. The PDF export button is not in
  the app yet; it gets wired up once the layout is approved.

The default hourly rate ($30) and the billing rounding are at the top of `app.js`.

## Run it on your PC

```
python -m http.server 8000
```

Then open http://localhost:8000.

## Put it on your iPhone (free, via GitHub Pages)

1. In this repo: **Settings → Pages → Build and deployment → Source: Deploy from a branch**, branch `main`,
   folder `/ (root)`. Save. (Pages on a private repo needs a paid GitHub plan; a public repo is free.)
2. After a minute the app is at `https://<your-username>.github.io/SG-Labs-Time-Sheet-System/`.
3. On the iPhone, open that link in **Safari**, tap **Share → Add to Home Screen**.

## Good to know

- Data is stored only on the phone. Use **⋯ → Export** now and then as a backup (photos are included).
- Photos are resized to 1600px so they don't fill up the phone.

## iPhone app (lock screen + Dynamic Island)

`ios/` holds a native iPhone version of the same app. The timer appears on the lock screen and in the
Dynamic Island, with Pause and Stop buttons. Setup steps: [ios/README.md](ios/README.md).

## Later

- PDF export for clients (see `concept/receipt-concept.pdf`).
- Team version: workers sign in and only see the projects they're assigned to. This needs a hosted
  database and logins; the data is already organized by project to make that move easier.
