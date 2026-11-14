// Runs Code.gs against fake Google services and fake sheet data. Usage: node test/harness.js
const fs = require('fs'), path = require('path'), crypto = require('crypto'), vm = require('vm');

function makeSheet(name, rows) {
  const s = { name, rows: rows.map(r => r.slice()) };
  const width = () => Math.max(1, ...s.rows.map(r => r.length));
  const disp = v => v instanceof Date ? (v.getMonth()+1)+'/'+v.getDate()+'/'+v.getFullYear() : String(v ?? '');
  const range = (r, c, nr, nc) => ({
    getValues: () => Array.from({length: nr}, (_, i) => Array.from({length: nc}, (_, j) => (s.rows[r-1+i]||[])[c-1+j] ?? '')),
    getDisplayValues() { return this.getValues().map(x => x.map(disp)); },
    setValues(vals) { vals.forEach((row, i) => { s.rows[r-1+i] = s.rows[r-1+i] || []; row.forEach((v, j) => s.rows[r-1+i][c-1+j] = v); }); return this; },
    setValue(v) { return this.setValues([[v]]); },
    setNumberFormat() { return this; }, setFontWeight() { return this; }, setBackground() { return this; }, setFontColor() { return this; },
  });
  Object.assign(s, {
    getDataRange: () => range(1, 1, Math.max(1, s.rows.length), width()),
    getRange: (r, c, nr = 1, nc = 1) => range(r, c, nr, nc),
    getLastRow: () => s.rows.length, setFrozenRows() {}, getParent: () => ss,
    deleteRow: r => { s.rows.splice(r - 1, 1); },
    insertColumnBefore: c => { s.rows.forEach(r => { while (r.length < c - 1) r.push(''); r.splice(c - 1, 0, ''); }); },
  });
  return s;
}
const sheets = {
  'Dashboard': makeSheet('Dashboard', [
    ['Ironman Tracker'],
    ['Wrestler','Practices Present','Practices Absent','Practice %','Open Mats','Kids Club Help','Youth Tournament','Penalty','Total Points','Ironman Status','', 'Wrestlers Tracked', '2'],
    ['Jamie Smith', 10, 0, '100%', 2, 1, 'Yes', 0, 34, 'ON TRACK', '', 'Current Ironmen', '1'],
    ['Sam Example', 8, 2, '80%', 0, 0, '', -5, 11, 'OFF TRACK'],
  ]),
  'Portal Access': makeSheet('Portal Access', [['Wrestler','School Email','Role'], ['Jamie Smith','smith2030@yourschool.org','wrestler'], ['Sam Example','example2028@yourschool.org','wrestler']]),
  'Settings': makeSheet('Settings', [['Minimum Practice Attendance %','95'], ['Practice points - Present','3']]),
  'Practice': makeSheet('Practice', [['Timestamp','Attendance [Jamie Smith]','Notes'], [new Date('2026-11-09'), 'Present', '']]),
  'Kids Club': makeSheet('Kids Club', [['Timestamp','Type','Attendance [Jamie Smith]','Attendance [Sam Example]','Notes'], [new Date('2026-11-10'), 'Kids Club Tournament', 'Absent', 'Present', '']]),
  'Roster': makeSheet('Roster', [['Name','Grad'], ['Jamie Smith','2030']]),
  'Descent Plans': makeSheet('Descent Plans', [
    ['School Email','Wrestler','Initial Weight','Loss Per Week','Min Weight Class','Min Weight','Initial · 11/02/2026','Week 1 · 11/09/2026','Week 2 · 11/16/2026'],
    ['smith2030@yourschool.org','Jamie Smith','150','2.2','138','137.5','150.00 (150, 157)','147.80 (150, 157)','145.60 (150, 157)'],
    ['example2028@yourschool.org','Sam Example','170','2.5','157','156','170.00 (175)','167.50 (175)','165.00 (165, 175)'],
  ]),
};
const ss = { getSheetByName: n => sheets[n] || null, insertSheet: n => (sheets[n] = makeSheet(n, [])), getSpreadsheetTimeZone: () => 'America/Chicago' };

let tokenClaims = {};
const ctx = {
  console, Date, JSON, Math, String, Number, Array, Object, Error, isNaN, encodeURIComponent, parseFloat,
  SpreadsheetApp: { getActive: () => ss, openById: () => ({ getSheets: () => [makeSheet('wp', [['h']])] }), flush() {} },
  Session: { getActiveUser: () => ({ getEmail: () => '' }), getScriptTimeZone: () => 'America/Chicago' },
  Utilities: {
    formatDate: (d, tz, fmt) => fmt === 'yyyy-MM-dd' ? d.toISOString().slice(0, 10) : d.toISOString(), parseDate: s => new Date(s),
    computeDigest: (_, s) => [...crypto.createHash('sha256').update(s).digest()],
    base64EncodeWebSafe: b => Buffer.from(b).toString('base64url'), DigestAlgorithm: { SHA_256: 1 },
  },
  CacheService: { getScriptCache: () => ({ get: () => null, put() {} }) },
  LockService: { getScriptLock: () => ({ waitLock() {}, releaseLock() {} }) },
  UrlFetchApp: { fetch: () => ({ getResponseCode: () => tokenClaims ? 200 : 400, getContentText: () => JSON.stringify(tokenClaims) }) },
  ContentService: { createTextOutput: t => ({ t, setMimeType() { return this; } }), MimeType: { JSON: 'json' } },
  HtmlService: {}, Logger: { log() {} },
};
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'Code.gs'), 'utf8'), ctx);
vm.runInContext("APP_CLIENT_IDS = ['test-ios.apps.googleusercontent.com']", ctx);

const now = Math.floor(Date.now() / 1000);
const good = email => ({ iss: 'https://accounts.google.com', aud: 'test-ios.apps.googleusercontent.com', exp: String(now + 3000), email_verified: 'true', email, hd: 'yourschool.org' });
function call(claims, body) { tokenClaims = claims; return JSON.parse(ctx.doPost({ postData: { contents: JSON.stringify({ idToken: 'a.b.c', ...body }) } }).t); }
let fails = 0;
function check(label, cond, extra) { console.log((cond ? 'PASS ' : 'FAIL ') + label + (cond ? '' : ' ' + JSON.stringify(extra))); if (!cond) fails++; }

let r = call(null, { action: 'ping' }); check('ping without token', r.ok && r.data.pong, r);
r = call({ ...good('smith2030@yourschool.org'), aud: 'other' }, { action: 'home' }); check('wrong aud rejected', !r.ok && r.error === 'auth', r);
r = call({ ...good('someone@gmail.com'), hd: undefined }, { action: 'home' }); check('gmail rejected', !r.ok && r.error === 'auth', r);
r = call({ ...good('smith2030@yourschool.org'), exp: String(now - 5) }, { action: 'home' }); check('expired rejected', !r.ok && r.error === 'auth', r);
r = call(good('nobody2029@yourschool.org'), { action: 'home' }); check('unknown student -> notfound', !r.ok && r.error === 'notfound', r);

const C = good('smith2030@yourschool.org');
r = call(C, { action: 'home' });
check('home: own stats only', r.ok && r.data.role === 'wrestler' && r.data.me.name === 'Jamie Smith' && !r.data.wrestlers, r);
check('home: descent locked before handbook', r.data.descent === null && r.data.descentLocked === true, r.data);
check('home: no initial weight leaked', !JSON.stringify(r.data).includes('150.00'), null);
r = call(C, { action: 'logWeighIn', weight: 'abc' }); check('typo weight rejected', !r.ok, r);
r = call(C, { action: 'logWeighIn', weight: 1475 }); check('1475 rejected', !r.ok, r);
r = call(C, { action: 'logWeighIn', weight: 147.4, when: 'before' }); check('log 147.4 before practice', r.ok && r.data.weighIn.weight === 147.4 && r.data.weighIn.when === 'before', r);
check('Weigh-Ins tab created with header', sheets['Weigh-Ins'].rows[0].join() === 'Timestamp,School Email,Wrestler,Weight,Source,When,Edited', sheets['Weigh-Ins'].rows[0]);
check('When column says Before practice', sheets['Weigh-Ins'].rows[1][5] === 'Before practice', sheets['Weigh-Ins'].rows[1]);
call(good('example2028@yourschool.org'), { action: 'logWeighIn', weight: 168 });
r = call(C, { action: 'weighIns' }); check('list returns only own rows', r.ok && r.data.weighIns.length === 1 && r.data.weighIns[0].weight === 147.4 && r.data.weighIns[0].when === 'before', r);
r = call(C, { action: 'signHandbook', typed: 'Jamie Smith' }); check('sign handbook', r.ok, r);
r = call(C, { action: 'home' });
check('descent unlocked after signing, own plan only', r.data.descent && r.data.descent.email === 'smith2030@yourschool.org' && !r.data.descents, r.data);
check('home includes weigh-ins', r.data.weighIns.length === 1, r.data);
for (let i = 0; i < 9; i++) call(C, { action: 'logWeighIn', weight: 147 });
r = call(C, { action: 'logWeighIn', weight: 147 }); check('daily limit', !r.ok && /10 weigh-ins/.test(r.message), r);
r = call(C, { action: 'teamWeighIns' }); check('wrestler cannot get team weigh-ins', !r.ok && /coaches/i.test(r.message), r);
r = call(C, { action: 'handbookList' }); check('wrestler cannot get handbook list', !r.ok && /coaches/i.test(r.message), r);
const COACH = good('coach@yourschool.org');
r = call(COACH, { action: 'teamWeighIns' });
const jamie = r.ok && r.data.wrestlers.find(w => w.name === 'Jamie Smith');
const sam = r.ok && r.data.wrestlers.find(w => w.name === 'Sam Example');
check('coach gets every wrestler\'s weigh-ins', r.ok && jamie && jamie.weighIns.length === 10 && sam && sam.weighIns.length === 1 && sam.weighIns[0].weight === 168, r);
check('team weigh-ins newest first', jamie && new Date(jamie.weighIns[0].at) >= new Date(jamie.weighIns[9].at), jamie);
check('missing when saved as Other', sheets['Weigh-Ins'].rows.some(x => x[1] === 'example2028@yourschool.org' && x[5] === 'Other'), sheets['Weigh-Ins'].rows);
check('team weigh-ins carry when', sam && sam.weighIns[0].when === 'other', sam);
r = call(COACH, { action: 'teamWeighIns', limit: 3 }); check('limit per wrestler', r.ok && r.data.wrestlers.find(w => w.name === 'Jamie Smith').weighIns.length === 3, r);
// A Weigh-Ins tab made before the When column existed: header gets F1, old rows untouched and read as blank.
sheets['Weigh-Ins'].rows[0] = ['Timestamp','School Email','Wrestler','Weight','Source'];
sheets['Weigh-Ins'].rows.push([new Date(), 'example2028@yourschool.org', 'Sam Example', 170, 'app / self-reported']);
r = call(good('example2028@yourschool.org'), { action: 'weighIns' });
check('old tab gets When header', sheets['Weigh-Ins'].rows[0][5] === 'When', sheets['Weigh-Ins'].rows[0]);
check('old row reads with blank when', r.ok && r.data.weighIns.length === 2 && r.data.weighIns.some(x => x.weight === 170 && x.when === ''), r);
r = call(COACH, { action: 'handbookList' }); check('coach gets handbook list', r.ok && r.data.signed.length === 1 && r.data.missing.indexOf('Sam Example') > -1, r);
// Coach weigh-ins: punch in a wrestler's weight, fix an entry (old value noted in Edited), delete one.
const WI = () => sheets['Weigh-Ins'].rows;
r = call(C, { action: 'coachLogWeighIn', wrestlerEmail: 'example2028@yourschool.org', weight: 165 }); check('wrestler cannot punch in weights', !r.ok && /coaches/i.test(r.message), r);
r = call(COACH, { action: 'coachLogWeighIn', wrestlerEmail: 'nobody2029@yourschool.org', weight: 165 }); check('coach log: unknown email rejected', !r.ok && /Portal Access/.test(r.message), r);
r = call(COACH, { action: 'coachLogWeighIn', wrestlerEmail: 'example2028@yourschool.org', weight: 999 }); check('coach log: bad weight rejected', !r.ok && /their weight/.test(r.message), r);
r = call(COACH, { action: 'coachLogWeighIn', wrestlerEmail: 'Example2028@yourschool.org', weight: 164.84, when: 'before' });
const coachRow = WI()[WI().length - 1];
check('coach log: row saved with coach source', r.ok && r.data.weighIn.weight === 164.8 && coachRow[2] === 'Sam Example' && coachRow[4] === 'coach / coach@yourschool.org' && coachRow[5] === 'Before practice', coachRow);
coachRow[0] = new Date('2026-11-10T21:15:00.000Z');   // its own time, apart from rows this test made in the same millisecond
const coachAt = coachRow[0].toISOString();
r = call(good('example2028@yourschool.org'), { action: 'weighIns' });
check('wrestler sees the coach entry with its source', r.ok && r.data.weighIns.some(x => x.weight === 164.8 && x.source.startsWith('coach')), r);
const nRows = WI().length;
r = call(C, { action: 'editWeighIn', wrestlerEmail: 'example2028@yourschool.org', at: coachAt, weight: 160 }); check('wrestler cannot edit', !r.ok && /coaches/i.test(r.message) && WI()[nRows - 1][3] === 164.8, r);
r = call(COACH, { action: 'editWeighIn', wrestlerEmail: 'example2028@yourschool.org', at: coachAt, weight: 165.2, when: 'after' });
const ed = WI()[nRows - 1];
check('edit: row updated in place, old value noted', r.ok && r.data.changed && WI().length === nRows && ed[3] === 165.2 && ed[5] === 'After practice' && /by coach@yourschool.org: was 164\.8 \(Before practice\)/.test(ed[6]), ed);
check('edit: app gets edited note', r.data.weighIn.edited === ed[6] && r.data.weighIn.when === 'after', r.data);
r = call(COACH, { action: 'editWeighIn', wrestlerEmail: 'example2028@yourschool.org', at: coachAt, weight: 165.2, when: 'after' });
check('edit: no change = no new note', r.ok && !r.data.changed && WI()[nRows - 1][6] === ed[6], r);
r = call(COACH, { action: 'editWeighIn', wrestlerEmail: 'example2028@yourschool.org', at: coachAt, weight: 166 });
check('edit: second fix appends to the note, keeps when', r.ok && WI()[nRows - 1][5] === 'After practice' && WI()[nRows - 1][6].split('; ').length === 2, WI()[nRows - 1]);
r = call(COACH, { action: 'editWeighIn', wrestlerEmail: 'smith2030@yourschool.org', at: '2020-01-01T00:00:00.000Z', weight: 150 });
check('edit: must match the wrestler too', !r.ok && /no longer on the sheet/.test(r.message), r);
r = call(C, { action: 'deleteWeighIn', wrestlerEmail: 'example2028@yourschool.org', at: coachAt }); check('wrestler cannot delete', !r.ok && WI().length === nRows, r);
r = call(COACH, { action: 'deleteWeighIn', wrestlerEmail: 'example2028@yourschool.org', at: coachAt });
check('delete: removes just that row', r.ok && WI().length === nRows - 1 && !WI().some(x => x[4] && String(x[4]).startsWith('coach')), WI().length);
r = call(COACH, { action: 'deleteWeighIn', wrestlerEmail: 'example2028@yourschool.org', at: coachAt }); check('delete twice: not found', !r.ok, r);
// Weight classes: plan by default, coach override on the "Weight Classes" tab, cleared back to the plan.
r = call(C, { action: 'setWeightClass', wrestlerEmail: 'example2028@yourschool.org', weightClass: '157' }); check('wrestler cannot set weight class', !r.ok && /coaches/i.test(r.message) && !sheets['Weight Classes'], r);
r = call(COACH, { action: 'setWeightClass', wrestlerEmail: 'example2028@yourschool.org', weightClass: '158' }); check('weight class must be a real class', !r.ok && /weight classes/.test(r.message), r);
r = call(COACH, { action: 'setWeightClass', wrestlerEmail: 'example2028@yourschool.org', weightClass: '165' });
check('set weight class makes tab + row', r.ok && r.data.weightClass === '165' && sheets['Weight Classes'].rows[1].slice(0, 4).join() === 'example2028@yourschool.org,Sam Example,165,coach@yourschool.org', sheets['Weight Classes'] && sheets['Weight Classes'].rows);
r = call(COACH, { action: 'setWeightClass', wrestlerEmail: 'example2028@yourschool.org', weightClass: '157' });
check('changing it updates the same row', r.ok && sheets['Weight Classes'].rows.length === 2 && sheets['Weight Classes'].rows[1][2] === '157', sheets['Weight Classes'].rows);
r = call(COACH, { action: 'home' }); check('coach home has overrides', r.ok && r.data.classOverrides['example2028@yourschool.org'].weightClass === '157', r.data.classOverrides);
r = call(good('example2028@yourschool.org'), { action: 'home' }); check('wrestler sees own override only', r.ok && r.data.weightClass === '157' && !r.data.classOverrides, r.data.weightClass);
r = call(C, { action: 'home' }); check('other wrestler has none', r.ok && r.data.weightClass === '', r.data.weightClass);
r = call(COACH, { action: 'setWeightClass', wrestlerEmail: 'example2028@yourschool.org', weightClass: '' });
check('clear goes back to the plan (row removed)', r.ok && r.data.weightClass === '' && sheets['Weight Classes'].rows.length === 1, sheets['Weight Classes'].rows);
r = call(COACH, { action: 'home' }); check('coach home = team view', r.ok && r.data.role === 'coach' && r.data.wrestlers.length === 2, r);
// Attendance (coach only), same tabs the website writes.
r = call(C, { action: 'attendance', kind: 'practice', date: '2026-11-16' }); check('wrestler cannot get attendance', !r.ok && /coaches/i.test(r.message), r);
r = call(C, { action: 'saveAttendance', kind: 'practice', date: '2026-11-16', marks: {} }); check('wrestler cannot save attendance', !r.ok && /coaches/i.test(r.message) && sheets['Practice'].rows.length === 2, r);
r = call(COACH, { action: 'attendance', kind: 'bogus', date: '2026-11-16' }); check('unknown attendance kind', !r.ok && /Unknown attendance/.test(r.message), r);
r = call(COACH, { action: 'attendance', kind: 'practice', date: '2026-11-16' });
check('new practice date: roster + recent', r.ok && !r.data.exists && r.data.names.join() === 'Jamie Smith,Sam Example' && r.data.recent[0] === '2026-11-09', r);
r = call(COACH, { action: 'saveAttendance', kind: 'practice', date: '2026-11-16', marks: { 'Jamie Smith': 'Present' }, notes: 'Sam sick' });
const P = sheets['Practice'].rows;
check('save new practice', r.ok && r.data.present === 1 && r.data.total === 2 && !r.data.updated && P.length === 3, r);
check('missing wrestler column added before Notes', P[0].join() === 'Timestamp,Attendance [Jamie Smith],Attendance [Sam Example],Notes', P[0]);
check('row values: Present / Absent / notes', P[2][1] === 'Present' && P[2][2] === 'Absent' && P[2][3] === 'Sam sick', P[2]);
r = call(COACH, { action: 'saveAttendance', kind: 'practice', date: '2026-11-16', marks: { 'Jamie Smith': 'Present', 'Sam Example': 'Present' } });
check('re-save edits the same row (no double count)', r.ok && r.data.updated && r.data.present === 2 && sheets['Practice'].rows.length === 3, r);
r = call(COACH, { action: 'attendance', kind: 'practice', date: '2026-11-16' });
check('load saved practice', r.ok && r.data.exists && r.data.marks['Sam Example'] === 'Present', r);
r = call(COACH, { action: 'attendance', kind: 'kidstourn', date: '2026-11-10' });
check('youth tournament reads typed Kids Club row', r.ok && r.data.exists && r.data.marks['Sam Example'] === 'Present' && r.data.marks['Jamie Smith'] === 'Absent', r);
r = call(COACH, { action: 'attendance', kind: 'kidshelp', date: '2026-11-10' });
check('youth practice ignores tournament row', r.ok && !r.data.exists, r);
r = call(COACH, { action: 'saveAttendance', kind: 'kidshelp', date: '2026-11-10', marks: { 'Sam Example': 'Present' } });
check('youth practice saves its own typed row', r.ok && sheets['Kids Club'].rows.length === 3 && sheets['Kids Club'].rows[2][1] === 'Kids Club Help', sheets['Kids Club'].rows);
r = call(COACH, { action: 'saveAttendance', kind: 'practice', date: 'Nov 16' }); check('bad date rejected', !r.ok && /date/i.test(r.message), r);
// Power/Speed: tracked only, own tab made on first save (not on view), counts show in stats + snapshot.
r = call(COACH, { action: 'attendance', kind: 'power', date: '2026-11-17' });
check('power: viewing does not create the tab', r.ok && !r.data.exists && r.data.names.length === 2 && !sheets['Power/Speed'], r);
r = call(COACH, { action: 'home' });
check('power: no tab = 0 and no snapshot row', r.ok && r.data.wrestlers[0].power === '0' && !('Power/Speed Sessions' in r.data.team), r.data.team);
r = call(COACH, { action: 'saveAttendance', kind: 'power', date: '2026-11-17', marks: { 'Sam Example': 'Present' } });
const M = sheets['Power/Speed'] && sheets['Power/Speed'].rows;
check('power: tab created on save', r.ok && M && M[0].join() === 'Timestamp,Attendance [Jamie Smith],Attendance [Sam Example],Notes' && M[1][2] === 'Present', M);
r = call(COACH, { action: 'saveAttendance', kind: 'power', date: '2026-11-18', marks: { 'Sam Example': 'Present', 'Jamie Smith': 'Present' } });
r = call(COACH, { action: 'home' });
const samM = r.data.wrestlers.find(w => w.name === 'Sam Example');
check('power: counts per wrestler + sessions', samM.power === '2' && r.data.team['Power/Speed Sessions'] === '2', [samM, r.data.team]);
check('power: points untouched', samM.total === '11', samM);
r = call(C, { action: 'home' }); check('power: wrestler sees own count', r.ok && r.data.me.power === '1', r.data.me);
r = call(C, { action: 'nope' }); check('unknown action', !r.ok && r.error === 'badrequest', r);
console.log(fails ? fails + ' FAILED' : 'ALL PASSED');
process.exit(fails ? 1 : 0);
