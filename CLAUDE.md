# Wrestling Team App starter kit: notes for Claude Code

The coach you're helping is usually not a programmer. Explain in plain words, do the edits yourself, and confirm before
anything outward-facing (deploying the script, uploading builds, submitting to the App Store, sharing files).

## How it fits together
- **Google Sheet** (from the blank Ironman Tracker template) is the source of truth. Coaches keep editing it. Tabs:
  Dashboard (formulas; header row starts with "Wrestler"), Roster, Portal Access (Wrestler, School Email, Role),
  Practice / Open Mat / Kids Club (wide: Timestamp [+ Event Type] + "Attendance [Name]" columns + Notes), Settings,
  Handbook Sign-Off, Descent Plans. The script creates Weigh-Ins, Power/Speed and Weight Classes on first use.
- **apps-script/Code.gs**: bound to the sheet. `doGet` serves the website portal (`Index.html`, `google.script.run`).
  `doPost` is the app's JSON API: `{idToken, action, ...}` → `{ok, data}` / `{ok:false, error, message}`. Every call
  verifies the Google ID token (tokeninfo; iss, `aud` ∈ `APP_CLIENT_IDS`, exp, email_verified, `hd` = `SCHOOL_DOMAIN`),
  then the same per-email functions decide what that email can see. Wrestlers only ever get their own data; coach-only
  actions go through `requireCoachEmail_`. Two deployments: website ("Anyone within domain") and app API ("Anyone").
- **WrestlingTeam/** (SwiftUI, iOS 17+, iPhone + iPad, Swift 5 mode, GoogleSignIn-iOS via SPM). Hand-written
  `project.pbxproj` with a synchronized folder: new files in `WrestlingTeam/WrestlingTeam/` are picked up automatically.
  Settings flow `Config.xcconfig` → `Info.plist` (GIDClientID, URL scheme, APIDeploymentID). `AppConfig.swift` holds
  team name / school domain. `LiveAPI` posts to `https://script.google.com/macros/s/<deployment id>/exec`.
- **Sample mode** is automatic while `Config.xcconfig` has PASTE_ placeholders (or with launch arg `-SampleData YES`):
  `SampleAPI` has made-up wrestlers and never touches a sheet. Debug-only launch args for screenshots:
  `-AutoSampleSignIn YES`, `-SampleSigned YES`, `-SampleCoach YES`, `-StartTab home|weight|plan|handbook`,
  `-CoachTab team|attendance|weighins|descent|handbook`, `-OpenWrestler "Alex Carter"`, `-ScreenshotSignIn YES`.

## Customizing for a new team (see SETUP.md for the full checklist)
- Script: the YOUR TEAM block at the top of Code.gs, plus `WEIGHT_PLAN_SHEET_ID`, `HANDBOOK_URL`, `HANDBOOK_SEASON`,
  `APP_CLIENT_IDS`.
- App: `AppConfig.swift`, `Theme.swift` colors, `TeamLogo` + `AppIcon` assets (icon 1024×1024, no alpha),
  bundle ID + team in the project, keychain group in `WrestlingTeam.entitlements`, `Config.xcconfig` IDs.
- Keep the sheet's tab and header names; the Dashboard formulas and the script look them up by name.

## Commands
- Script tests: `node apps-script/test/harness.js` (fake sheets/Google services; run after every Code.gs change).
- Simulator build: `xcodebuild -scheme WrestlingTeam -destination 'id=<sim>' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build`
- Google Sign-In needs keychain access, so a sign-in test must be a **signed** build (unsigned builds fail after sign-in).
- Device install: build with `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`, then
  `xcrun devicectl device install app --device <udid> <path>.app` (device needs Developer Mode).
- Testing the live API with curl: `curl -sL -d '{"action":"ping"}' <exec url>` (use `-d`, not `-X POST`).
- Script changes only reach the app after **Deploy → Manage deployments → Edit → New version**.

## Rules
- These are minors' weights and attendance: keep sheets private, never weaken the per-email checks in the script,
  use sample data for screenshots.
- Weigh-ins: wrestlers append only; coaches may log, fix (old value noted in the Edited column) or delete.
- Descent plan weights are a **limit / guide**, not a goal; the app doesn't warn wrestlers about the plan when they
  log weights, but coaches see anyone more than 5 lbs over.
