/**
 * WRESTLING TEAM PORTAL + APP API (starter kit)
 * Paste into your team's Ironman Tracker sheet: Extensions > Apps Script (replace Code.gs; add Index.html too).
 * Fill in the YOUR TEAM settings just below first.
 *
 * Website portal: Deploy > New deployment > Web app
 *   Execute as:        Me
 *   Who has access:    Anyone within your school's domain
 *
 * Wrestlers sign in with their school Google account and see ONLY their own Ironman stats.
 * Coaches listed on the "Portal Access" sheet see the whole team.
 *
 * iPhone app: the same script also has a JSON API (doPost, bottom of this file). It needs a SECOND
 * deployment of this same script: Web app, Execute as Me, Who has access "Anyone". The app sends the
 * wrestler's Google ID token; doPost checks it (signed by Google, your iOS client, your school domain) before
 * doing anything. Leave the website deployment above exactly as it is.
 */

// ── YOUR TEAM ───────────────────────────────────────────────────────────────────────────────
var SCHOOL_DOMAIN = 'yourschool.org';                 // only Google accounts @ this domain can sign in
var TEAM_NAME = 'Your Team Wrestling';                // shown in titles and the handbook statement
var HEAD_COACH = 'your coach';                        // used in messages like "Ask your coach to add it"
var DEFAULT_COACHES = ['coach@yourschool.org'];       // always treated as coaches (add more on Portal Access)
var LOGO_URL = '';                                    // optional: a public image URL for the portal header/favicon
// The iOS OAuth client ID(s) from Google Cloud, and the separate weight class plan sheet: see APP_CLIENT_IDS
// and WEIGHT_PLAN_SHEET_ID below.
// ─────────────────────────────────────────────────────────────────────────────────────────────
var DASHBOARD_SHEET = 'Dashboard';
var ACCESS_SHEET = 'Portal Access';
var SETTINGS_SHEET = 'Settings';
var CLASS_SHEET = 'Weight Classes';  // coach overrides of a wrestler's current weight class; created on first use
var POWER_SHEET = 'Power/Speed';   // attendance only, no points; created on first save
var DESCENT_SHEET = 'Descent Plans';

function doGet() {
  return HtmlService.createTemplateFromFile('Index').evaluate()
    .setTitle('Ironman Dashboard | ' + TEAM_NAME)
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
}

/** The signed-in website user (Google's own Apps Script sign-in). The app API passes a verified email instead. */
function activeEmail_() {
  return (Session.getActiveUser().getEmail() || '').toLowerCase().trim();
}

/** Called from the page. Everything is decided here on the server, never in the browser. */
function getPortalData() { return portalDataFor_(activeEmail_()); }

function portalDataFor_(email) {
  email = String(email || '').toLowerCase().trim();
  if (!email) {
    return { error: 'signin', message: 'Please sign in with your ' + SCHOOL_DOMAIN + ' school account.' };
  }
  if (email.split('@')[1] !== SCHOOL_DOMAIN) {
    return { error: 'domain', email: email, message: 'This portal is only for ' + SCHOOL_DOMAIN + ' accounts.' };
  }

  var ss = SpreadsheetApp.getActive();
  var rows = readDashboard_(ss);
  var team = readSnapshot_(ss);
  var settings = readSettings_(ss);
  var access = readAccess_(ss);
  var stamp = Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'MMM d, yyyy h:mm a');

  var descent = readDescent_(ss);

  if (access.coaches.indexOf(email) > -1) {
    return { role: 'coach', email: email, team: team, settings: settings, wrestlers: rows, updated: stamp,
      descents: descent.list, descentNotes: descent.notes, classOverrides: readClassOverrides_(ss) };
  }

  // A wrestler only ever gets back their OWN descent plan, matched to the email they signed in with.
  var myPlan = descent.byEmail[email] || null;
  var name = access.byEmail[email] || guessName_(email, rows) || (myPlan && myPlan.name);
  var me = name ? rows.filter(function (r) { return r.name.toLowerCase() === name.toLowerCase(); })[0] : null;
  if (!me && !myPlan) {
    return { error: 'notfound', email: email,
      message: 'You are signed in as ' + email + ', but that email is not linked to a wrestler yet. Ask ' + HEAD_COACH + ' to add it.' };
  }
  // The descent plan is only sent after the wrestler has signed off on this season's handbook.
  var signed = myPlan ? !!findHandbookRow_(handbookSheet_(), email) : false;
  return { role: 'wrestler', email: email, me: me || null, team: team, settings: settings, updated: stamp,
    descent: signed ? myPlan : null, descentLocked: !!myPlan && !signed, descentNotes: descent.notes,
    weightClass: (readClassOverrides_(ss)[email] || {}).weightClass || '' };
}

/* ---------- sheet readers ---------- */

function readDashboard_(ss) {
  var sh = ss.getSheetByName(DASHBOARD_SHEET);
  var v = sh.getDataRange().getDisplayValues();
  var h = -1;
  for (var i = 0; i < v.length; i++) { if (String(v[i][0]).trim() === 'Wrestler') { h = i; break; } }
  if (h < 0) throw new Error('Could not find the "Wrestler" header on the Dashboard sheet.');
  var head = v[h].map(function (x) { return String(x).trim(); });
  function col(label) { return head.indexOf(label); }
  var c = {
    present: col('Practices Present'), absent: col('Practices Absent'), pct: col('Practice %'),
    openmat: col('Open Mats'), kids: col('Kids Club Help'), youth: col('Youth Tournament'),
    penalty: col('Penalty'), total: col('Total Points'), status: col('Ironman Status')
  };
  var out = [];
  var power = powerCounts_(ss);
  for (var r = h + 1; r < v.length; r++) {
    var name = String(v[r][0]).trim();
    if (!name) continue;
    out.push({
      power: String(power.byName[name] || 0),
      name: name,
      present: v[r][c.present], absent: v[r][c.absent], pct: v[r][c.pct],
      openmat: v[r][c.openmat], kids: v[r][c.kids], youth: v[r][c.youth],
      penalty: v[r][c.penalty], total: v[r][c.total], status: v[r][c.status]
    });
  }
  return out;
}

/**
 * "Descent Plans" tab: one row per wrestler. Column A = school email, B = name, C-F = plan basics,
 * (column C, initial weight, and the Initial column are kept in the sheet but never shown),
 * then one column per step headed like "Week 4 · 11/02/2026" holding "142.00 (144, 150)".
 * Rows without an email in column A (below the wrestlers) are plan notes: label in A, value in B.
 */
function readDescent_(ss) {
  var out = { byEmail: {}, list: [], notes: {} };
  var sh = ss.getSheetByName(DESCENT_SHEET);
  if (!sh) return out;
  var v = sh.getDataRange().getDisplayValues();
  if (!v.length) return out;
  var head = v[0].map(function (x) { return String(x).trim(); });
  var steps = [];
  for (var c = 6; c < head.length; c++) {
    var m = head[c].match(/^(.*?)\s*[·\-|]\s*(\d{1,2}\/\d{1,2}\/\d{4})$/);
    if (m) steps.push({ col: c, label: m[1].trim(), date: m[2] });
  }
  var startDate = (steps.filter(function (s) { return /^initial/i.test(s.label); })[0] || {}).date;
  for (var r = 1; r < v.length; r++) {
    var a = String(v[r][0] || '').trim();
    if (!a) continue;
    if (a.indexOf('@') < 0) { if (r > 1 && v[r][1] !== '') out.notes[a] = String(v[r][1]).trim(); continue; }
    var plan = {
      email: a.toLowerCase(), name: String(v[r][1]).trim(),
      perWeek: v[r][3], minClass: v[r][4], minWeight: v[r][5], steps: []
    };
    steps.forEach(function (s) {
      // The plan starts the week after the assessment: skip the Initial column and any step on the assessment date.
      // Starting weight is never sent to the page.
      if (/^initial/i.test(s.label) || s.date === startDate) return;
      var cell = String(v[r][s.col] || '').trim();
      var mm = cell.match(/^([\d.]+)\s*(?:\(([^)]*)\))?/);
      if (!mm) return;
      plan.steps.push({ label: s.label, date: s.date, weight: parseFloat(mm[1]),
        classes: (mm[2] || '').split(',').map(function (x) { return x.trim(); }).filter(String) });
    });
    out.byEmail[plan.email] = plan;
    out.list.push(plan);
  }
  out.list.sort(function (x, y) { return x.name.localeCompare(y.name); });
  return out;
}

function readSnapshot_(ss) {
  var v = ss.getSheetByName(DASHBOARD_SHEET).getDataRange().getDisplayValues();
  var map = {};
  v.forEach(function (row) {
    for (var i = 0; i < row.length - 1; i++) {
      var k = String(row[i]).trim();
      if (['Wrestlers Tracked', 'Practice Sessions', 'Open Mat Sessions', 'Current Ironmen', 'Team Practice %'].indexOf(k) > -1) map[k] = row[i + 1];
    }
  });
  if (ss.getSheetByName(POWER_SHEET)) map['Power/Speed Sessions'] = String(powerCounts_(ss).sessions);
  return map;
}

function readSettings_(ss) {
  var sh = ss.getSheetByName(SETTINGS_SHEET);
  var map = {};
  if (!sh) return map;
  sh.getDataRange().getDisplayValues().forEach(function (r) { if (r[0]) map[String(r[0]).trim()] = r[1]; });
  return map;
}

function readAccess_(ss) {
  var sh = ss.getSheetByName(ACCESS_SHEET);
  var byEmail = {}, coaches = DEFAULT_COACHES.slice();
  if (sh) {
    sh.getDataRange().getDisplayValues().slice(1).forEach(function (r) {
      var name = String(r[0] || '').trim(), email = String(r[1] || '').toLowerCase().trim(), role = String(r[2] || '').toLowerCase().trim();
      if (!email) return;
      if (role === 'coach') { if (coaches.indexOf(email) < 0) coaches.push(email); }
      else if (name) byEmail[email] = name;
    });
  }
  return { byEmail: byEmail, coaches: coaches };
}

/** Fallback when an email isn't typed into Portal Access: match common school email patterns to a roster name. */
function guessName_(email, rows) {
  var local = email.split('@')[0].replace(/[^a-z]/g, '');
  var hits = rows.filter(function (r) {
    var parts = r.name.toLowerCase().replace(/[^a-z\s-]/g, '').split(/\s+/);
    var f = parts[0].replace(/-/g, ''), l = parts.slice(1).join('').replace(/-/g, '');
    return [f + l, f.charAt(0) + l, l + f, l + f.charAt(0), f + l.charAt(0)].indexOf(local) > -1 ||
           (local.indexOf(f) === 0 && local.indexOf(l) > -1);
  });
  return hits.length === 1 ? hits[0].name : null;
}

/* ---------- one-time setup ---------- */

/** Run once from the Apps Script editor: builds the "Portal Access" sheet from the Roster. */
function setupPortalAccess() {
  var ss = SpreadsheetApp.getActive();
  var sh = ss.getSheetByName(ACCESS_SHEET) || ss.insertSheet(ACCESS_SHEET);
  var existing = {};
  sh.getDataRange().getDisplayValues().slice(1).forEach(function (r) { if (r[0]) existing[String(r[0]).trim()] = r; });
  var names = readDashboard_(ss).map(function (r) { return r.name; });
  var out = [['Wrestler', 'School Email', 'Role']];
  names.forEach(function (n) { out.push(existing[n] ? [n, existing[n][1], existing[n][2] || 'wrestler'] : [n, '', 'wrestler']); });
  DEFAULT_COACHES.forEach(function (c) { out.push(['Coach', c, 'coach']); });
  sh.clear();
  sh.getRange(1, 1, out.length, 3).setValues(out);
  sh.getRange(1, 1, 1, 3).setFontWeight('bold').setBackground('#C8102E').setFontColor('#ffffff');
  sh.setFrozenRows(1);
  sh.autoResizeColumns(1, 3);
  sh.getRange(1, 5).setValue('Fill in each wrestler\'s school email. Leave blank to let the portal guess from the name. Add rows with Role = coach for other coaches.');
}

/**
 * Fills "School Email" on Portal Access from the Roster tab's Graduation year:
 * last name + grad year @ SCHOOL_DOMAIN  (e.g. Sam Smith, 2030 -> smith2030@yourschool.org)
 * Existing emails are overwritten for wrestlers; coach rows are left alone.
 */
function fillEmailsFromRoster() {
  var ss = SpreadsheetApp.getActive();
  var years = {};
  ss.getSheetByName('Roster').getDataRange().getDisplayValues().slice(1).forEach(function (r) {
    if (r[0]) years[String(r[0]).trim().toLowerCase()] = String(r[1] || '').replace(/[^0-9]/g, '');
  });
  var sh = ss.getSheetByName(ACCESS_SHEET);
  var v = sh.getDataRange().getDisplayValues();
  var seen = {}, report = [];
  for (var i = 1; i < v.length; i++) {
    var name = String(v[i][0]).trim(), role = String(v[i][2]).toLowerCase().trim();
    if (!name || role === 'coach') continue;
    var yr = years[name.toLowerCase()];
    if (!yr) { report.push('NO GRAD YEAR: ' + name); continue; }
    var last = name.split(/\s+/).slice(1).join('').toLowerCase().replace(/[^a-z]/g, '');
    var email = last + yr + '@' + SCHOOL_DOMAIN;
    if (seen[email]) report.push('DUPLICATE ' + email + ': ' + seen[email] + ' & ' + name);
    seen[email] = name;
    sh.getRange(i + 1, 2).setValue(email);
  }
  sh.getRange(1, 5).setValue('Emails auto-filled as lastname + grad year. Edit any that differ.');
  Logger.log(report.length ? report.join('\n') : 'All wrestler emails filled.');
  return report;
}

/* ---------- coach attendance (portal "Take Attendance" tab) ---------- */

var ATT_KINDS = {
  practice:  { sheet: 'Practice',  label: 'Practice' },
  openmat:   { sheet: 'Open Mat',  label: 'Open Mat' },
  kidshelp:  { sheet: 'Kids Club', label: 'Youth Practice (Kids Club Help)', type: 'Kids Club Help' },
  kidstourn: { sheet: 'Kids Club', label: 'Youth Tournament', type: 'Kids Club Tournament' },
  // Tracked only (no Ironman points). The tab is made the first time it's needed, laid out like Open Mat.
  power:   { sheet: POWER_SHEET, label: 'Power/Speed', create: true }
};

/** The tab an attendance kind writes to; Power/Speed is created on first use (Timestamp + Notes). */
function attSheet_(ss, cfg) {
  var sh = ss.getSheetByName(cfg.sheet);
  if (sh || !cfg.create) return sh;
  sh = ss.insertSheet(cfg.sheet);
  sh.getRange(1, 1, 1, 2).setValues([['Timestamp', 'Notes']]);
  sh.setFrozenRows(1);
  return sh;
}

/** Power/Speed: Present count per wrestler name + number of sessions. Empty if the tab doesn't exist yet. */
function powerCounts_(ss) {
  var out = { byName: {}, sessions: 0 };
  var sh = ss.getSheetByName(POWER_SHEET);
  if (!sh) return out;
  var v = sh.getDataRange().getValues();
  var head = v[0].map(function (x) { return String(x).trim(); });
  for (var r = 1; r < v.length; r++) {
    if (String(v[r][0]).trim() === '') continue;
    out.sessions++;
    for (var c = 0; c < head.length; c++) {
      var m = /^Attendance \[(.*)\]$/.exec(head[c]);
      if (m && String(v[r][c]).trim() === 'Present') out.byName[m[1]] = (out.byName[m[1]] || 0) + 1;
    }
  }
  return out;
}

/** App API version of requireCoach_: the email was already verified from the Google sign-in. */
function requireCoachEmail_(email) {
  email = String(email || '').toLowerCase().trim();
  if (readAccess_(SpreadsheetApp.getActive()).coaches.indexOf(email) < 0) throw new Error('Only coaches can see this.');
  return email;
}

function requireCoach_() {
  var email = activeEmail_();
  if (readAccess_(SpreadsheetApp.getActive()).coaches.indexOf(email) < 0) throw new Error('Only coaches can take attendance.');
  return email;
}

function dayKey_(v, tz) {
  if (v instanceof Date) return Utilities.formatDate(v, tz, 'yyyy-MM-dd');
  var d = new Date(v);
  return isNaN(d) ? '' : Utilities.formatDate(d, tz, 'yyyy-MM-dd');
}

/** Returns header map, the row for this date (or -1), and recent session dates. */
function findSession_(sh, kind, dateKey) {
  var cfg = ATT_KINDS[kind];
  var v = sh.getDataRange().getValues();
  var tz = sh.getParent().getSpreadsheetTimeZone();
  var head = v[0].map(function (x) { return String(x).trim(); });
  var row = -1, recent = [], seen = {};
  for (var i = v.length - 1; i >= 1; i--) {
    if (cfg.type && String(v[i][1]).trim() !== cfg.type) continue;
    var k = dayKey_(v[i][0], tz);
    if (!k) continue;
    if (k === dateKey && row < 0) row = i;
    if (!seen[k]) { seen[k] = 1; recent.push(k); }
  }
  recent.sort().reverse();
  return { values: v, head: head, row: row, recent: recent.slice(0, 12) };
}

function getAttendance(kind, dateKey) { return attendanceFor_(requireCoach_(), kind, dateKey); }

/** coachEmail must already be checked (requireCoach_ on the website, requireCoachEmail_ in the app API). */
function attendanceFor_(coachEmail, kind, dateKey) {
  if (!ATT_KINDS[kind]) throw new Error('Unknown attendance type.');
  var ss = SpreadsheetApp.getActive();
  var names = readDashboard_(ss).map(function (r) { return r.name; });
  var sh = ss.getSheetByName(ATT_KINDS[kind].sheet);
  // Just looking doesn't create the Power/Speed tab; the first save does.
  if (!sh) return { kind: kind, date: dateKey, exists: false, names: names, marks: {}, notes: '', recent: [] };
  var f = findSession_(sh, kind, dateKey);
  var marks = {}, notes = '';
  var notesCol = f.head.indexOf('Notes');
  if (f.row > -1) {
    names.forEach(function (n) {
      var c = f.head.indexOf('Attendance [' + n + ']');
      marks[n] = c > -1 ? String(f.values[f.row][c]).trim() : '';
    });
    if (notesCol > -1) notes = String(f.values[f.row][notesCol] || '');
  }
  return { kind: kind, date: dateKey, exists: f.row > -1, names: names, marks: marks, notes: notes, recent: f.recent };
}

function saveAttendance(kind, dateKey, marks, notes) { return saveAttendanceFor_(requireCoach_(), kind, dateKey, marks, notes); }

function saveAttendanceFor_(coachEmail, kind, dateKey, marks, notes) {
  marks = marks || {};
  var cfg = ATT_KINDS[kind];
  if (!cfg) throw new Error('Unknown attendance type.');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) throw new Error('Pick a date.');
  var lock = LockService.getScriptLock(); lock.waitLock(20000);
  try {
    var ss = SpreadsheetApp.getActive();
    var sh = attSheet_(ss, cfg);
    var names = readDashboard_(ss).map(function (r) { return r.name; });
    var f = findSession_(sh, kind, dateKey);
    var head = f.head;
    // make sure every wrestler has a column (inserted just before Notes)
    names.forEach(function (n) {
      var h = 'Attendance [' + n + ']';
      if (head.indexOf(h) > -1) return;
      var notesIdx = head.indexOf('Notes');
      if (notesIdx > -1) { sh.insertColumnBefore(notesIdx + 1); sh.getRange(1, notesIdx + 1).setValue(h); head.splice(notesIdx, 0, h); }
      else { sh.getRange(1, head.length + 1).setValue(h); head.push(h); }
    });
    var width = head.length;
    var rowNum = f.row > -1 ? f.row + 1 : sh.getLastRow() + 1;
    var cur = f.row > -1 ? sh.getRange(rowNum, 1, 1, width).getValues()[0] : head.map(function () { return ''; });
    if (f.row < 0) cur[0] = Utilities.parseDate(dateKey, ss.getSpreadsheetTimeZone(), 'yyyy-MM-dd');
    if (cfg.type) cur[1] = cfg.type;
    var present = 0;
    names.forEach(function (n) {
      var c = head.indexOf('Attendance [' + n + ']');
      var val = marks[n] === 'Present' ? 'Present' : 'Absent';
      if (val === 'Present') present++;
      cur[c] = val;
    });
    var nc = head.indexOf('Notes');
    if (nc > -1) cur[nc] = notes || '';
    sh.getRange(rowNum, 1, 1, width).setValues([cur]);
    if (f.row < 0) sh.getRange(rowNum, 1).setNumberFormat('m/d/yyyy');
    SpreadsheetApp.flush();
    return { ok: true, updated: f.row > -1, present: present, total: names.length, label: cfg.label, date: dateKey, by: coachEmail };
  } finally { lock.releaseLock(); }
}

/* ---------- weight class plans (wrestler form + coach list) ----------
   Answers go to a separate "Weight Class Plans" sheet (make one from the blank template; paste its ID below).
   One row per wrestler: submitting again updates their row instead of adding a new one. */

var WEIGHT_PLAN_SHEET_ID = 'PASTE_WEIGHT_PLAN_SHEET_ID';   // the long ID in that sheet's URL
var WEIGHT_CLASSES = ['106','113','120','126','132','138','144','150','157','165','175','190','215','285'];

function weightPlanSheet_() { return SpreadsheetApp.openById(WEIGHT_PLAN_SHEET_ID).getSheets()[0]; }

function currentWrestler_() { return wrestlerFor_(activeEmail_()); }

function wrestlerFor_(email) {
  email = String(email || '').toLowerCase().trim();
  if (!email || email.split('@')[1] !== SCHOOL_DOMAIN) throw new Error('Please sign in with your school account.');
  var ss = SpreadsheetApp.getActive();
  var rows = readDashboard_(ss);
  var name = readAccess_(ss).byEmail[email] || guessName_(email, rows);
  if (!name) throw new Error('Your email is not linked to a wrestler yet. Ask ' + HEAD_COACH + '.');
  var grad = '';
  var roster = ss.getSheetByName('Roster');
  if (roster) roster.getDataRange().getDisplayValues().forEach(function (r) {
    if (String(r[0]).trim().toLowerCase() === name.toLowerCase()) grad = r[1];
  });
  return { email: email, name: name, grad: grad };
}

function getWeightPlan() { return weightPlanFor_(activeEmail_()); }

function weightPlanFor_(email) {
  var me = wrestlerFor_(email);
  var v = weightPlanSheet_().getDataRange().getDisplayValues();
  var mine = null;
  for (var i = v.length - 1; i >= 1; i--) {
    if (String(v[i][2]).toLowerCase().trim() === me.email) { mine = { saved: v[i][0], before: v[i][4], after: v[i][5], current: v[i][6], notes: v[i][7] }; break; }
  }
  return { classes: WEIGHT_CLASSES, name: me.name, plan: mine };
}

function saveWeightPlan(before, after, current, notes) { return saveWeightPlanFor_(activeEmail_(), before, after, current, notes); }

function saveWeightPlanFor_(email, before, after, current, notes) {
  var me = wrestlerFor_(email);
  before = String(before || ''); after = String(after || '');
  if (WEIGHT_CLASSES.indexOf(before) < 0 || WEIGHT_CLASSES.indexOf(after) < 0) throw new Error('Pick a weight class for both before and after Christmas.');
  current = String(current || '').replace(/[^0-9.]/g, '').slice(0, 6);
  notes = String(notes || '').slice(0, 500);
  var lock = LockService.getScriptLock(); lock.waitLock(20000);
  try {
    var sh = weightPlanSheet_();
    var v = sh.getDataRange().getDisplayValues();
    var row = -1;
    for (var i = 1; i < v.length; i++) if (String(v[i][2]).toLowerCase().trim() === me.email) { row = i + 1; break; }
    if (row < 0) row = sh.getLastRow() + 1;
    sh.getRange(row, 1, 1, 8).setValues([[new Date(), me.name, me.email, me.grad, Number(before), Number(after), current ? Number(current) : '', notes]]);
    sh.getRange(row, 1).setNumberFormat('m/d/yyyy h:mm am/pm');
    SpreadsheetApp.flush();
    return { ok: true, before: before, after: after };
  } finally { lock.releaseLock(); }
}

function getWeightPlans() {
  requireCoach_();
  var v = weightPlanSheet_().getDataRange().getDisplayValues().slice(1).filter(function (r) { return r[1]; });
  var names = readDashboard_(SpreadsheetApp.getActive()).map(function (r) { return r.name; });
  var have = {};
  v.forEach(function (r) { have[String(r[1]).toLowerCase()] = 1; });
  return {
    plans: v.map(function (r) { return { saved: r[0], name: r[1], before: r[4], after: r[5], current: r[6], notes: r[7] }; }),
    missing: names.filter(function (n) { return !have[n.toLowerCase()]; }),
    url: 'https://docs.google.com/spreadsheets/d/' + WEIGHT_PLAN_SHEET_ID + '/edit'
  };
}

/* ---------- handbook sign-off ----------
   Wrestlers confirm they read the handbook. Signatures go to the "Handbook Sign-Off" tab of this spreadsheet. */

var HANDBOOK_SHEET = 'Handbook Sign-Off';
var HANDBOOK_URL = 'https://example.com/your-team-handbook.pdf';   // a link to your handbook PDF
var HANDBOOK_SEASON = '2026-27';

function handbookSheet_() {
  var ss = SpreadsheetApp.getActive();
  var sh = ss.getSheetByName(HANDBOOK_SHEET);
  if (!sh) {
    sh = ss.insertSheet(HANDBOOK_SHEET);
    sh.getRange(1, 1, 1, 6).setValues([['Signed', 'Wrestler', 'School Email', 'Typed Signature', 'Season', 'Statement']])
      .setFontWeight('bold').setBackground('#C8102E').setFontColor('#ffffff');
    sh.setFrozenRows(1);
  }
  return sh;
}

function findHandbookRow_(sh, email) {
  var v = sh.getDataRange().getDisplayValues();
  for (var i = v.length - 1; i >= 1; i--) {
    if (String(v[i][2]).toLowerCase().trim() === email && String(v[i][4]).trim() === HANDBOOK_SEASON) return { row: i + 1, signed: v[i][0], typed: v[i][3] };
  }
  return null;
}

function getHandbook() { return handbookFor_(activeEmail_()); }

function handbookFor_(email) {
  var me = wrestlerFor_(email);
  var f = findHandbookRow_(handbookSheet_(), me.email);
  return { url: HANDBOOK_URL, season: HANDBOOK_SEASON, name: me.name, signed: f ? f.signed : '', typed: f ? f.typed : '' };
}

function signHandbook(typed) { return signHandbookFor_(activeEmail_(), typed); }

function signHandbookFor_(email, typed) {
  var me = wrestlerFor_(email);
  typed = String(typed || '').trim().slice(0, 80);
  if (typed.length < 3) throw new Error('Type your full name to sign.');
  var lock = LockService.getScriptLock(); lock.waitLock(20000);
  try {
    var sh = handbookSheet_();
    var f = findHandbookRow_(sh, me.email);
    if (f) return { ok: true, signed: f.signed, already: true };
    var row = sh.getLastRow() + 1, now = new Date();
    sh.getRange(row, 1, 1, 6).setValues([[now, me.name, me.email, typed, HANDBOOK_SEASON,
      'I have read the ' + HANDBOOK_SEASON + ' ' + TEAM_NAME + ' Handbook and agree to follow it.']]);
    sh.getRange(row, 1).setNumberFormat('m/d/yyyy h:mm am/pm');
    SpreadsheetApp.flush();
    return { ok: true, signed: Utilities.formatDate(now, Session.getScriptTimeZone(), 'M/d/yyyy h:mm a') };
  } finally { lock.releaseLock(); }
}

function getHandbookList() { return handbookListFor_(requireCoach_()); }

function handbookListFor_(email) {
  requireCoachEmail_(email);
  var v = handbookSheet_().getDataRange().getDisplayValues().slice(1).filter(function (r) { return String(r[4]).trim() === HANDBOOK_SEASON; });
  var byName = {};
  v.forEach(function (r) { byName[String(r[1]).toLowerCase()] = r[0]; });
  var names = readDashboard_(SpreadsheetApp.getActive()).map(function (r) { return r.name; });
  return { season: HANDBOOK_SEASON, url: HANDBOOK_URL,
    signed: names.filter(function (n) { return byName[n.toLowerCase()]; }).map(function (n) { return { name: n, when: byName[n.toLowerCase()] }; }),
    missing: names.filter(function (n) { return !byName[n.toLowerCase()]; }) };
}

/* ---------- weigh-ins (iPhone app) ----------
   Wrestlers log their own weight from the app. Each entry is a new row on the "Weigh-Ins" tab of this
   spreadsheet (created the first time it's needed). Append-only: the app never edits or deletes rows.
   These are SELF-REPORTED weights, separate from official / certified weigh-ins.
   A wrestler only ever gets back their own rows. */

var WEIGHIN_SHEET = 'Weigh-Ins';
var WEIGHIN_SOURCE = 'app / self-reported';
var WEIGHIN_MIN = 70, WEIGHIN_MAX = 350;   // anything outside this is a typo
var WEIGHIN_DAILY_LIMIT = 10;              // per wrestler per 24 hours, to stop accidental floods
// Column F "When": wrestlers weigh before and after practice. Older rows (before this column existed) are blank.
var WEIGHIN_WHEN = { before: 'Before practice', after: 'After practice', other: 'Other' };
// Column G "Edited": filled when a coach fixes an entry (when, who, and the old value).
var WEIGHIN_HEADERS = ['Timestamp', 'School Email', 'Wrestler', 'Weight', 'Source', 'When', 'Edited'];
var WEIGHIN_COACH_SOURCE = 'coach';   // Source for weights a coach punched in: "coach / <coach email>"

/** "Before practice" -> "before", etc. Blank or unknown -> "". */
function whenKey_(label) {
  label = String(label || '').trim().toLowerCase();
  for (var k in WEIGHIN_WHEN) if (WEIGHIN_WHEN[k].toLowerCase() === label || k === label) return k;
  return '';
}

function weighInSheet_() {
  var ss = SpreadsheetApp.getActive();
  var sh = ss.getSheetByName(WEIGHIN_SHEET);
  if (!sh) {
    sh = ss.insertSheet(WEIGHIN_SHEET);
    sh.setFrozenRows(1);
  }
  // Create the header row, or add the newer "When" / "Edited" columns to an older tab. Existing rows are untouched.
  var head = sh.getRange(1, 1, 1, WEIGHIN_HEADERS.length).getValues()[0];
  if (String(head[WEIGHIN_HEADERS.length - 1]).trim() !== 'Edited' || String(head[0]).trim() !== 'Timestamp') {
    sh.getRange(1, 1, 1, WEIGHIN_HEADERS.length).setValues([WEIGHIN_HEADERS])
      .setFontWeight('bold').setBackground('#C8102E').setFontColor('#ffffff');
  }
  return sh;
}

/** This wrestler's weigh-ins, newest first. */
function weighInsFor_(email, limit) {
  var me = wrestlerFor_(email);
  var sh = weighInSheet_();
  var out = [];
  if (sh.getLastRow() > 1) {
    var v = sh.getRange(2, 1, sh.getLastRow() - 1, 7).getValues();
    for (var i = v.length - 1; i >= 0; i--) {
      if (String(v[i][1]).toLowerCase().trim() !== me.email) continue;
      var at = v[i][0] instanceof Date ? v[i][0] : new Date(v[i][0]);
      var w = Number(v[i][3]);
      if (isNaN(at) || !w) continue;
      out.push(weighInJson_(at, w, v[i]));
      if (out.length >= (limit || 120)) break;
    }
  }
  return { name: me.name, weighIns: out };
}

/** One weigh-in row as JSON for the app. `row` is the sheet row (Timestamp ... Edited). */
function weighInJson_(at, w, row) {
  return { at: at.toISOString(), weight: w, source: String(row[4] || ''), when: whenKey_(row[5]), edited: String(row[6] || '') };
}

/** Rounds to 0.1 lb and checks the range; throws with `who` ("your" / "their") in the message. */
function cleanWeight_(weight, who) {
  var w = Math.round(Number(String(weight == null ? '' : weight).replace(/[^0-9.]/g, '')) * 10) / 10;
  if (!w || w < WEIGHIN_MIN || w > WEIGHIN_MAX) throw new Error('Enter ' + who + ' weight in pounds (between ' + WEIGHIN_MIN + ' and ' + WEIGHIN_MAX + ').');
  return w;
}

/** Appends one weigh-in row. Caller holds the script lock. */
function appendWeighIn_(email, name, w, whenK, source) {
  var dayAgo = Date.now() - 864e5;
  var recent = weighInsFor_(email, WEIGHIN_DAILY_LIMIT).weighIns.filter(function (x) { return new Date(x.at).getTime() > dayAgo; });
  if (recent.length >= WEIGHIN_DAILY_LIMIT) throw new Error('That\'s ' + WEIGHIN_DAILY_LIMIT + ' weigh-ins in the last day. Try again tomorrow, or tell ' + HEAD_COACH + ' if one is wrong.');
  var sh = weighInSheet_();
  var row = sh.getLastRow() + 1, now = new Date();
  sh.getRange(row, 1, 1, 6).setValues([[now, email, name, w, source, WEIGHIN_WHEN[whenK]]]);
  sh.getRange(row, 1).setNumberFormat('m/d/yyyy h:mm am/pm');
  sh.getRange(row, 4).setNumberFormat('0.0');
  SpreadsheetApp.flush();
  return { ok: true, weighIn: { at: now.toISOString(), weight: w, source: source, when: whenK, edited: '' } };
}

function logWeighInFor_(email, weight, when) {
  var me = wrestlerFor_(email);
  var w = cleanWeight_(weight, 'your');
  var lock = LockService.getScriptLock(); lock.waitLock(20000);
  try { return appendWeighIn_(me.email, me.name, w, whenKey_(when) || 'other', WEIGHIN_SOURCE); }
  finally { lock.releaseLock(); }
}

/* ---------- weight classes ----------
   A wrestler's current weight class comes from their descent plan (this week's lowest eligible class) unless a coach
   sets one. Overrides live on the "Weight Classes" tab: one row per wrestler, removed when set back to the plan. */

function classSheet_() {
  var ss = SpreadsheetApp.getActive();
  var sh = ss.getSheetByName(CLASS_SHEET);
  if (!sh) {
    sh = ss.insertSheet(CLASS_SHEET);
    sh.getRange(1, 1, 1, 5).setValues([['School Email', 'Wrestler', 'Weight Class', 'Set By', 'Updated']])
      .setFontWeight('bold').setBackground('#C8102E').setFontColor('#ffffff');
    sh.setFrozenRows(1);
  }
  return sh;
}

/** { email: { weightClass, by, updated } } from the Weight Classes tab (empty if the tab doesn't exist yet). */
function readClassOverrides_(ss) {
  var out = {};
  var sh = ss.getSheetByName(CLASS_SHEET);
  if (!sh || sh.getLastRow() < 2) return out;
  sh.getRange(2, 1, sh.getLastRow() - 1, 5).getDisplayValues().forEach(function (r) {
    var em = String(r[0] || '').toLowerCase().trim(), c = String(r[2] || '').trim();
    if (em && c) out[em] = { weightClass: c, by: String(r[3] || ''), updated: String(r[4] || '') };
  });
  return out;
}

/** Coaches: set a wrestler's weight class, or pass '' to go back to the one from their descent plan. */
function setWeightClassFor_(coachEmail, wrestlerEmail, weightClass) {
  requireCoachEmail_(coachEmail);
  wrestlerEmail = String(wrestlerEmail || '').toLowerCase().trim();
  var name = wrestlerNameFor_(wrestlerEmail);
  var cls = String(weightClass == null ? '' : weightClass).trim();
  if (cls && WEIGHT_CLASSES.indexOf(cls) < 0) throw new Error('Pick one of the weight classes.');
  var lock = LockService.getScriptLock(); lock.waitLock(20000);
  try {
    var sh = classSheet_();
    var row = -1;
    if (sh.getLastRow() > 1) {
      var v = sh.getRange(2, 1, sh.getLastRow() - 1, 1).getValues();
      for (var i = 0; i < v.length; i++) if (String(v[i][0]).toLowerCase().trim() === wrestlerEmail) { row = i + 2; break; }
    }
    if (!cls) { if (row > 0) sh.deleteRow(row); SpreadsheetApp.flush(); return { ok: true, weightClass: '' }; }
    var stamp = Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'M/d/yyyy h:mm a');
    var vals = [[wrestlerEmail, name, cls, coachEmail, stamp]];
    if (row > 0) sh.getRange(row, 1, 1, 5).setValues(vals); else sh.getRange(sh.getLastRow() + 1, 1, 1, 5).setValues(vals);
    SpreadsheetApp.flush();
    return { ok: true, weightClass: cls, by: coachEmail, updated: stamp };
  } finally { lock.releaseLock(); }
}

/* ---------- coach weigh-ins: punch in a wrestler's weight, fix or delete an entry ---------- */

/** Wrestler name for a school email on Portal Access, or throws. */
function wrestlerNameFor_(email) {
  email = String(email || '').toLowerCase().trim();
  var name = readAccess_(SpreadsheetApp.getActive()).byEmail[email];
  if (!name) throw new Error('That wrestler has no school email on Portal Access yet.');
  return name;
}

function coachLogWeighInFor_(coachEmail, wrestlerEmail, weight, when) {
  requireCoachEmail_(coachEmail);
  wrestlerEmail = String(wrestlerEmail || '').toLowerCase().trim();
  var name = wrestlerNameFor_(wrestlerEmail);
  var w = cleanWeight_(weight, 'their');
  var lock = LockService.getScriptLock(); lock.waitLock(20000);
  try { return appendWeighIn_(wrestlerEmail, name, w, whenKey_(when) || 'other', WEIGHIN_COACH_SOURCE + ' / ' + coachEmail); }
  finally { lock.releaseLock(); }
}

/** Sheet row number (1-based) of a wrestler's weigh-in with this timestamp (ISO from the app), or throws. */
function findWeighInRow_(sh, email, at) {
  var t = new Date(at).getTime();
  if (isNaN(t)) throw new Error('Pick a weigh-in to change.');
  // Exact match on the timestamp the app got from this same sheet (never a "close enough" row).
  if (sh.getLastRow() > 1) {
    var v = sh.getRange(2, 1, sh.getLastRow() - 1, 2).getValues();
    for (var i = v.length - 1; i >= 0; i--) {
      if (String(v[i][1]).toLowerCase().trim() !== email) continue;
      var d = v[i][0] instanceof Date ? v[i][0] : new Date(v[i][0]);
      if (d.getTime() === t) return i + 2;
    }
  }
  throw new Error('That weigh-in is no longer on the sheet. Pull to refresh.');
}

function editWeighInFor_(coachEmail, wrestlerEmail, at, weight, when) {
  requireCoachEmail_(coachEmail);
  wrestlerEmail = String(wrestlerEmail || '').toLowerCase().trim();
  var w = cleanWeight_(weight, 'their');
  var lock = LockService.getScriptLock(); lock.waitLock(20000);
  try {
    var sh = weighInSheet_();
    var row = findWeighInRow_(sh, wrestlerEmail, at);
    var cur = sh.getRange(row, 1, 1, 7).getValues()[0];
    var whenK = when == null || when === '' ? whenKey_(cur[5]) : (whenKey_(when) || 'other');
    var oldW = Number(cur[3]), oldWhen = String(cur[5] || '');
    var newWhen = whenK ? WEIGHIN_WHEN[whenK] : oldWhen;
    if (oldW === w && oldWhen === newWhen) {
      var d0 = cur[0] instanceof Date ? cur[0] : new Date(cur[0]);
      return { ok: true, changed: false, weighIn: weighInJson_(d0, w, cur) };
    }
    var stamp = Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'M/d/yyyy h:mm a');
    var note = stamp + ' by ' + coachEmail + ': was ' + oldW.toFixed(1) + (oldWhen && oldWhen !== newWhen ? ' (' + oldWhen + ')' : '');
    var edited = String(cur[6] || '') ? String(cur[6]) + '; ' + note : note;
    sh.getRange(row, 4).setValue(w).setNumberFormat('0.0');
    sh.getRange(row, 6, 1, 2).setValues([[newWhen, edited]]);
    SpreadsheetApp.flush();
    cur[3] = w; cur[5] = newWhen; cur[6] = edited;
    var d = cur[0] instanceof Date ? cur[0] : new Date(cur[0]);
    return { ok: true, changed: true, weighIn: weighInJson_(d, w, cur) };
  } finally { lock.releaseLock(); }
}

function deleteWeighInFor_(coachEmail, wrestlerEmail, at) {
  requireCoachEmail_(coachEmail);
  wrestlerEmail = String(wrestlerEmail || '').toLowerCase().trim();
  var lock = LockService.getScriptLock(); lock.waitLock(20000);
  try {
    var sh = weighInSheet_();
    sh.deleteRow(findWeighInRow_(sh, wrestlerEmail, at));
    SpreadsheetApp.flush();
    return { ok: true };
  } finally { lock.releaseLock(); }
}

/** Coaches only: every wrestler's weigh-ins (newest first, up to `limit` each), plus roster wrestlers with none yet. */
function teamWeighInsFor_(email, limit) {
  requireCoachEmail_(email);
  limit = Math.min(Math.max(Number(limit) || 60, 1), 200);
  var ss = SpreadsheetApp.getActive();
  var access = readAccess_(ss);
  var byEmail = {};
  var sh = weighInSheet_();
  if (sh.getLastRow() > 1) {
    var v = sh.getRange(2, 1, sh.getLastRow() - 1, 7).getValues();
    for (var i = v.length - 1; i >= 0; i--) {
      var em = String(v[i][1]).toLowerCase().trim();
      var at = v[i][0] instanceof Date ? v[i][0] : new Date(v[i][0]);
      var w = Number(v[i][3]);
      if (!em || isNaN(at) || !w) continue;
      var g = byEmail[em] || (byEmail[em] = { email: em, name: access.byEmail[em] || String(v[i][2] || em), weighIns: [] });
      if (g.weighIns.length < limit) g.weighIns.push(weighInJson_(at, w, v[i]));
    }
  }
  // Roster wrestlers who haven't logged anything still show up (with an empty list).
  var emailByName = {};
  Object.keys(access.byEmail).forEach(function (em) { emailByName[access.byEmail[em].toLowerCase()] = em; });
  readDashboard_(ss).forEach(function (r) {
    var em = emailByName[r.name.toLowerCase()];
    if (em && !byEmail[em]) byEmail[em] = { email: em, name: r.name, weighIns: [] };
    if (!em && !Object.keys(byEmail).some(function (k) { return byEmail[k].name.toLowerCase() === r.name.toLowerCase(); }))
      byEmail['name:' + r.name] = { email: '', name: r.name, weighIns: [] };
  });
  var list = Object.keys(byEmail).map(function (k) { return byEmail[k]; });
  list.sort(function (a, b) { return a.name.localeCompare(b.name); });
  return { wrestlers: list };
}

/* ---------- iPhone app JSON API ----------
   POST body (JSON): { "idToken": "<Google ID token>", "action": "...", ...arguments }
   Every reply is JSON: { ok: true, data: ... } or { ok: false, error: "code", message: "..." }.
   Actions: ping (no sign-in needed), home, portal, weighIns, logWeighIn, weightPlan, saveWeightPlan, handbook, signHandbook,
   and for coaches only: teamWeighIns, handbookList.

   Security: this deployment is open to "Anyone", so the ID token is the only gate. It must be signed by Google
   (checked by Google's tokeninfo endpoint), issued to our iOS app (aud), unexpired, and for a verified
   account on your school domain (hd). Then the same per-email functions the website uses decide what that email can see. */

// Paste the iOS OAuth client ID here once you create it in Google Cloud (ends in .apps.googleusercontent.com).
var APP_CLIENT_IDS = ['PASTE_IOS_CLIENT_ID.apps.googleusercontent.com'];

function doPost(e) {
  var req;
  try { req = JSON.parse((e && e.postData && e.postData.contents) || '{}'); }
  catch (err) { return json_({ ok: false, error: 'badrequest', message: 'Request was not valid JSON.' }); }
  var action = String(req.action || '');
  if (action === 'ping') return json_({ ok: true, data: { pong: true, time: new Date().toISOString() } });

  var email;
  try { email = verifyIdToken_(req.idToken); }
  catch (err) { return json_({ ok: false, error: 'auth', message: err.message }); }

  try {
    var data;
    switch (action) {
      case 'home':
        data = portalDataFor_(email);
        if (!data.error && data.role === 'wrestler') data.weighIns = weighInsFor_(email, 60).weighIns;
        break;
      case 'portal':         data = portalDataFor_(email); break;
      case 'weighIns':       data = weighInsFor_(email, Number(req.limit) || 120); break;
      case 'logWeighIn':     data = logWeighInFor_(email, req.weight, req.when); break;
      case 'weightPlan':     data = weightPlanFor_(email); break;
      case 'saveWeightPlan': data = saveWeightPlanFor_(email, req.before, req.after, req.current, req.notes); break;
      case 'handbook':       data = handbookFor_(email); break;
      case 'signHandbook':   data = signHandbookFor_(email, req.typed); break;
      case 'teamWeighIns':   data = teamWeighInsFor_(email, req.limit); break;
      case 'handbookList':   data = handbookListFor_(email); break;
      case 'attendance':     data = attendanceFor_(requireCoachEmail_(email), req.kind, String(req.date || '')); break;
      case 'coachLogWeighIn': data = coachLogWeighInFor_(email, req.wrestlerEmail, req.weight, req.when); break;
      case 'editWeighIn':    data = editWeighInFor_(email, req.wrestlerEmail, req.at, req.weight, req.when); break;
      case 'setWeightClass': data = setWeightClassFor_(email, req.wrestlerEmail, req.weightClass); break;
      case 'deleteWeighIn':  data = deleteWeighInFor_(email, req.wrestlerEmail, req.at); break;
      case 'saveAttendance': data = saveAttendanceFor_(requireCoachEmail_(email), req.kind, String(req.date || ''), req.marks, req.notes); break;
      default: return json_({ ok: false, error: 'badrequest', message: 'Unknown action "' + action + '".' });
    }
    if (data && data.error) return json_({ ok: false, error: data.error, message: data.message || data.error });
    return json_({ ok: true, data: data });
  } catch (err) {
    return json_({ ok: false, error: 'failed', message: err.message || String(err) });
  }
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

/** Returns the verified, lower-case school email for a Google ID token, or throws. */
function verifyIdToken_(token) {
  token = String(token || '');
  if (!token || token.split('.').length !== 3) throw new Error('Please sign in again.');
  var cache = CacheService.getScriptCache();
  var key = 'idt_' + Utilities.base64EncodeWebSafe(Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, token));
  var hit = cache.get(key);
  if (hit) return hit;

  var res = UrlFetchApp.fetch('https://oauth2.googleapis.com/tokeninfo?id_token=' + encodeURIComponent(token), { muteHttpExceptions: true });
  if (res.getResponseCode() !== 200) throw new Error('Your sign-in expired. Please sign in again.');
  var c = JSON.parse(res.getContentText());
  var now = Math.floor(Date.now() / 1000);
  if (['accounts.google.com', 'https://accounts.google.com'].indexOf(c.iss) < 0) throw new Error('Sign-in was not from Google.');
  if (APP_CLIENT_IDS.indexOf(c.aud) < 0) throw new Error('Sign-in was not from the ' + TEAM_NAME + ' app.');
  if (!(Number(c.exp) > now)) throw new Error('Your sign-in expired. Please sign in again.');
  if (String(c.email_verified) !== 'true') throw new Error('Your Google email is not verified.');
  var email = String(c.email || '').toLowerCase().trim();
  if (c.hd !== SCHOOL_DOMAIN || email.split('@')[1] !== SCHOOL_DOMAIN) throw new Error('Please sign in with your ' + SCHOOL_DOMAIN + ' school account.');

  var ttl = Math.min(Number(c.exp) - now, 600);
  if (ttl > 30) cache.put(key, email, ttl);
  return email;
}
