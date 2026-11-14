# Setup checklist

Do these in order. Anything marked **PASTE_** or **yourschool.org** is a placeholder.

## 1. Your Google Sheet
- [ ] Make a copy of the blank [Ironman Tracker template](https://docs.google.com/spreadsheets/d/1lxp2jwKBXsLiLAjSiXcn-f-m57zZiXmrFUF_78pF9Ws/copy). Read its **START HERE** tab.
- [ ] Settings tab: set **School email domain**. Fill in **Roster** and **Portal Access** (add yourself with Role = coach).
- [ ] Optional: copy the [Weight Class Plans template](https://docs.google.com/spreadsheets/d/1Kin2CT8FNV5F2sYEvteUeH_J8yMWZz2kewNhZxP8fPA/copy) and note its ID (the long part of its URL).

## 2. The Apps Script
- [ ] In your sheet: **Extensions → Apps Script**. Replace `Code.gs` with `apps-script/Code.gs`; add an HTML file named `Index` with `apps-script/Index.html`.
- [ ] At the top of `Code.gs`, fill in **YOUR TEAM**: `SCHOOL_DOMAIN`, `TEAM_NAME`, `HEAD_COACH`, `DEFAULT_COACHES`, optional `LOGO_URL`.
- [ ] Further down: `WEIGHT_PLAN_SHEET_ID`, `HANDBOOK_URL`, `HANDBOOK_SEASON`.
- [ ] Website portal (optional): **Deploy → New deployment → Web app**, Execute as **Me**, access **Anyone within your domain**.
- [ ] (Later, after step 3) Paste your iOS client ID into `APP_CLIENT_IDS`.
- [ ] App API: **Deploy → New deployment → Web app**, Execute as **Me**, access **Anyone**. Copy the **deployment ID**. The first deploy asks you to authorize "connect to an external service"; that's the sign-in check.
- [ ] Every time you change the script later: **Deploy → Manage deployments → Edit → New version**. The app only sees deployed versions.

## 3. Google sign-in (Google Cloud Console, signed in with your SCHOOL account)
- [ ] Create a project.
- [ ] **Google Auth Platform:** app name, audience **Internal** (only your school's accounts), support email.
- [ ] **Clients → Create client → iOS**, bundle ID = the one you'll use (e.g. `com.yourschool.wrestling`). Copy the **client ID**.
- [ ] Test sign-in with a real student account early. If your district blocks under-18 accounts from unapproved apps, IT can trust this client ID in the Google Admin console (App access control).

## 4. The app (Xcode)
- [ ] `WrestlingTeam/Config.xcconfig`: `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_REVERSED_CLIENT_ID` (the same ID reversed: `com.googleusercontent.apps.<id>`), `APPS_SCRIPT_DEPLOYMENT_ID`.
- [ ] `WrestlingTeam/WrestlingTeam/AppConfig.swift`: `schoolDomain`, `teamName`, `handbookCoach`.
- [ ] `Theme.swift`: team colors (`red`, `gold`).
- [ ] Assets: replace `TeamLogo` (transparent PNG, ~600 px) and `AppIcon` (1024×1024, **no transparency**).
- [ ] Project settings: your **Team** (Signing & Capabilities), **bundle ID** (must match the Google iOS client), display name.
- [ ] `WrestlingTeam.entitlements`: the keychain group must use your bundle ID. Google Sign-In needs it, and the app must be **signed** to sign in.
- [ ] `ExportOptions.plist`: your Apple team ID (for uploading builds from the command line).

## 5. Test
- [ ] Sign in as a wrestler and as a coach on a simulator and on your own iPhone/iPad (Developer Mode on).
- [ ] Log a weigh-in, take attendance, sign the handbook. Check the rows land on your sheet. The script creates the **Weigh-Ins**, **Power/Speed** and **Weight Classes** tabs itself.

## 6. App Store
- [ ] App Store Connect: new app, name, description, category (Sports/Education), age rating, price Free, availability.
- [ ] Privacy policy URL (a page on your team site) and App Privacy: Name, Email, Fitness, Other User Content; all for App Functionality, linked to the user, no tracking.
- [ ] Screenshots from the simulator in sample mode (iPhone 6.9" and iPad 13").
- [ ] App Review: a **test wrestler** school account on your roster, plus notes: one school team, school Google accounts only (Sign in with Apple isn't required: guideline 4.8 exception for existing school accounts).
- [ ] Submit, then request **unlisted** distribution so only people with the link can find it.
