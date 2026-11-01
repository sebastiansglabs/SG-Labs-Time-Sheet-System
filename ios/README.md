# Time Sheet for iPhone (native app)

The same Time Sheet app, rebuilt as a real iPhone app so the timer can live on the **lock screen** and in the
**Dynamic Island**, with **Pause/Resume** and **Stop** buttons in both.

- Close the app while the timer runs → it moves to the Dynamic Island and keeps counting.
- Press and hold the Dynamic Island → **Pause** and **Stop** buttons.
- Lock the phone → the timer shows on the lock screen with **Pause/Resume** and **Stop**.
- Stop from the lock screen → you get a notification; open the app to add photos and save it.

Built with a free Apple ID (no $99 needed). Free installs expire after 7 days. Re-run it from Xcode once
a week, or set up automatic refresh (step 9).

---

## 1. Install Xcode 26.3 (one time)

Your 2018 MacBook Pro tops out at macOS Sequoia, so it can't use the newest Xcode. **Xcode 26.3** is the right one.

1. Make sure macOS is updated: **System Settings → General → Software Update** (Sequoia 15.6 or later; not a beta).
2. Go to **https://developer.apple.com/download/all** and sign in with your normal Apple ID.
3. Search **Xcode 26.3**, download the `.xip` file (about 3 GB).
4. Double-click the `.xip` to unpack it (takes a while), then drag **Xcode** into **Applications**.
5. Open Xcode. If it asks which platforms to install, **iOS** is enough. Let it finish.

## 2. Get the code onto the Mac

1. Download: **https://github.com/sebastiansglabs/SG-Labs-Time-Sheet-System/archive/refs/heads/claude/clever-cerf-1z0297.zip**
2. Unzip it, open the folder, then open **`ios` → `TimeSheet.xcodeproj`** (double-click). Xcode opens the project.

## 3. Sign in and pick your "team" (one time)

1. Xcode menu → **Settings… → Accounts** → **+** → **Apple ID** → sign in.
2. In the left sidebar click the blue **TimeSheet** project icon at the top.
3. Under **TARGETS**, click **TimeSheet** → **Signing & Capabilities** tab → **Team**: pick **"Your Name (Personal Team)"**.
4. Do the same for the **TimeSheetWidgets** target.

> If Xcode says the **bundle identifier is not available**: click the blue **TimeSheet** project icon →
> **PROJECT: TimeSheet** → **Build Settings** → search `BUNDLE_ID_PREFIX` → change `com.sglabs` to something
> unique like `com.sglabs.yourname`. Both targets update together.

## 4. Get the iPhone ready (one time)

1. Plug the iPhone into the Mac with a cable. On the phone tap **Trust** and enter your passcode.
2. On the iPhone: **Settings → Privacy & Security → Developer Mode** → turn **On** → the phone restarts → confirm **Turn On**.
   (The Developer Mode switch only appears after the phone has been connected to Xcode once.)

## 5. Run it

1. At the top of Xcode, set the run destination to **your iPhone** (next to the ▶ button).
2. Press **▶ Run**. The first build takes a few minutes on this Mac.
3. The first time, the iPhone may say **"Untrusted Developer"**: on the phone go to
   **Settings → General → VPN & Device Management** → your Apple ID → **Trust**. Then press ▶ again.

## 6. Try the lock screen timer

1. In the app tap **+ New** to make a project, then **Start timer → Start**.
2. Swipe home: the timer sits in the Dynamic Island. Press and hold it for **Pause** / **Stop**.
3. Lock the phone: the timer and both buttons are on the lock screen.
4. When asked, allow notifications (used to remind you to add photos after a lock-screen Stop).

## 7. Bring over your hours from the web app

1. In the **web app**: **⋯ → Export**, save the file to **Files** (or AirDrop it to yourself).
2. In the **iPhone app**: **⋯ (top right) → Import backup** → pick that file → **Restore**.
   Projects, sessions and photos all come across.

## 8. Good to know

- **The 7-day limit (free Apple ID):** after 7 days the app won't open until you reinstall it. Your data stays.
  Plug in and press ▶ in Xcode again (step 5), or set up automatic refresh (step 9).
- **Long sessions:** iOS removes a lock-screen timer after about 8 hours. The timer itself keeps counting in the app,
  and opening the app puts it back on the lock screen.
- **Photos** can't be taken from the lock screen. After a lock-screen Stop, open the app to add them and save.

## 9. Automatic weekly refresh (optional, later)

With the Mac always on and both devices on your router, a free tool called **AltServer** can reinstall the app
over Wi-Fi before it expires. We'll set that up once the app is working. Steps will be added here.

## If something goes wrong

Send a screenshot of the red error in Xcode (the **Issue navigator**, the ⚠️ triangle icon in the left sidebar).
Most first-build problems are one-line fixes.

---

### Project layout

- `TimeSheet/`: the app (SwiftUI): screens, data (`Store.swift`), photos, backup import/export
- `Widgets/`: the lock screen and Dynamic Island design (`TimerLiveActivity.swift`)
- `Shared/`: used by both: the timer data the lock screen shows, and the Pause/Stop button actions
- Data is saved on the phone in the same format as the web app, so backups move between them.
