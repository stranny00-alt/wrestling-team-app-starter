# Wrestling Team App: Starter Kit

A ready-to-customize iPhone + iPad app for a high school wrestling team, plus the Google Apps Script that connects it to your team's Google Sheet. It's the same app Earlham Wrestling uses, with everything school-specific taken out.

Built by a coach with **Claude Code**. You can make it yours the same way: open this folder in Claude Code and tell it about your team.

> New to this? Read the walkthrough first: **[wrestling-team-app-guide](https://github.com/stranny00-alt/wrestling-team-app-guide)**.

## What it does

**Wrestlers** (sign in with their school Google account, see only their own data):
- Ironman points, practice attendance, open mats, Power/Speed sessions, Kids Club help
- Their current weight class (from their descent plan, or set by a coach)
- Log weight before/after practice, see practice loss, a chart against their descent plan, full history
- Their descent plan, week by week (unlocks after signing the handbook)
- Read and sign the team handbook

**Coaches** (iPhone and iPad, with a split view on iPad):
- Take attendance: practice, open mat, Power/Speed, youth practice/tournament, with Late and Excused
- Every wrestler's weigh-ins; weigh a wrestler in, fix or delete an entry (the sheet keeps a note of the old value)
- Set a wrestler's weight class or let it follow the plan
- Flags anyone more than 5 lbs over their plan weight; Team Overview; handbook sign-offs with email reminders

Light and dark mode. Lists sorted by last name. A website version of the portal is included too (`apps-script/Index.html`).

## What's in here

| Folder | What it is |
|---|---|
| `WrestlingTeam/` | The Xcode project (SwiftUI, iOS 17+, iPhone + iPad). Uses Google Sign-In for iOS. |
| `apps-script/Code.gs` | The Google Apps Script: website portal + the JSON API the app talks to. |
| `apps-script/Index.html` | The website portal page. |
| `apps-script/test/harness.js` | 72 automated checks of the script against fake sheet data (`node apps-script/test/harness.js`). |
| `SETUP.md` | Every setting you need to change, in order. |
| `CLAUDE.md` | Instructions for Claude Code, so it knows how this project fits together. |

## Try it right now (no setup)
Open `WrestlingTeam/WrestlingTeam.xcodeproj` in Xcode and run it on an iPhone simulator. Until you add your own settings it runs in **sample mode** with made-up wrestlers, and tap **Continue with Sample Data**. To see the coach side, add the launch argument `-SampleCoach YES` (Product → Scheme → Edit Scheme → Arguments).

## Make it yours
1. **Your sheet:** make a copy of the [blank Ironman Tracker template](https://docs.google.com/spreadsheets/d/1lxp2jwKBXsLiLAjSiXcn-f-m57zZiXmrFUF_78pF9Ws/copy) (and the [Weight Class Plans template](https://docs.google.com/spreadsheets/d/1Kin2CT8FNV5F2sYEvteUeH_J8yMWZz2kewNhZxP8fPA/copy)).
2. **Follow `SETUP.md`**, or open this folder in Claude Code and say something like:
   > Set this up for [your school] wrestling. Our school Google domain is [your domain], our colors are [colors], and I'm Coach [name] ([your school email]). Here's our logo. Walk me through Google sign-in and the App Store.
3. Publish under **your own** Apple Developer account ($99/year) and bundle ID.

## Privacy
This app handles minors' attendance and weights. Keep your sheet private, keep the school-domain checks on, and use made-up names for screenshots (sample mode does this for you). Wrestlers only ever receive their own data; that rule lives in the script, so don't loosen it.
