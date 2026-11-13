/* KLIQ DEMO backend: re-implements every database function in the browser.
   Data lives in this viewer's localStorage only. Not for production. */
(function () {
  const KEY = 'kliq_demo_db_v12';
  const SERIES = [
    { code: 'U', name: 'UNO', color: '#808A70', tagline: 'KLIQ WITH SIMPLIFY', sort: 1 },
    { code: 'I', name: 'IKON', color: '#15435A', tagline: 'KLIQ YOUR STYLE', sort: 2 },
    { code: 'F', name: 'FORMA', color: '#DCC7B3', tagline: 'KLIQ EVERY HOTEL', sort: 3 },
    { code: 'N', name: 'NOVA', color: '#533D37', tagline: 'KLIQ TO BALANCE', sort: 4 },
    { code: 'C', name: 'CASA', color: '#96979C', tagline: 'KLIQ IN EVERY DETAILS', sort: 5 }
  ];
  const FIRST = ['สมชาย', 'สุดา', 'วิชัย', 'นภัสสร', 'กิตติพงษ์', 'ธนพล', 'พิมพ์ชนก', 'วรวุฒิ', 'ศิริพร', 'อนุชา', 'ปิยะนุช', 'ณัฐวุฒิ', 'จิราพร', 'ชยพล', 'มณีรัตน์', 'อรทัย', 'ประวิทย์', 'กมลวรรณ', 'สุรศักดิ์', 'เบญจมาศ'];
  const LAST = ['ใจดี', 'แก้วใส', 'มีสุข', 'ศรีวงศ์', 'วงศ์ทอง', 'มั่นคง', 'ทองดี', 'ชัยมงคล', 'บุญมา', 'สายทอง', 'พรหมมา', 'คำแสง', 'รัตนกุล', 'ศักดิ์ดี', 'พูลสวัสดิ์', 'เจริญสุข'];
  const COMPANY = ['บริษัท สว่างไฟฟ้า จำกัด', 'ร้านไฟฟ้าบางนา', 'หจก. ลักซ์ โฮม', 'บริษัท ดีไซน์ ลิฟวิ่ง', 'ร้านวัสดุก่อสร้างชัยพัฒน์', 'ร้านโคมไฟสยาม', 'บริษัท เมโทร อิเล็คทริค'];

  const now = () => new Date().toISOString();
  const minsAgo = m => new Date(Date.now() - m * 60000).toISOString();
  const uid = () => 'p' + Math.random().toString(36).slice(2, 10) + Date.now().toString(36);
  const tok = (n) => { let s = ''; const a = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789'; for (let i = 0; i < n; i++) s += a[Math.floor(Math.random() * a.length)]; return s; };
  const pick = arr => arr[Math.floor(Math.random() * arr.length)];
  const shuffle = arr => { const a = arr.slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };
  const nameHint = n => { const p = String(n || '').trim().split(/\s+/); return p.length >= 2 ? p[0] + ' ' + p[p.length - 1][0] + '.' : (p[0] || ''); };
  const normPhone = p => { let d = String(p || '').replace(/\D/g, ''); if (d.startsWith('66') && d.length === 11) d = '0' + d.slice(2); return /^0\d{8,9}$/.test(d) ? d : null; };
  const maskName = n => String(n || '').trim().split(/\s+/).map(w => w.length <= 2 ? w : w.slice(0, 2) + '**').join(' ');
  const maskPhone = p => p && p.length >= 9 ? p.slice(0, 3) + '-XXX-' + p.slice(-4) : p;
  const pad = (n, w) => String(n).padStart(w, '0');

  function fresh() {
    const db = {
      settings: { id: 1, event_name: 'KLIQ Grand Launch Experience', max_participants: 400, series_quota: 80, min_stamp_interval_sec: 0, final_claim_sec: 30, final_order: null, souvenir_basic_name: 'ของที่ระลึกทั่วไป', souvenir_premium_name: 'ของที่ระลึกพิเศษ (เล่นครบทุกฐาน)',
        registration_open: true, cutoff_at: null, announce_text: 'ประกาศผลบนเวที 19:00 น.', updated_at: now() },
      series: SERIES.map(s => Object.assign({ next_no: 1 }, s)),
      prereg: [], participants: [], stamps: [], staff: [], sessions: [], prizes: [], results: [], finals: [], audit: [],
      stations: [1, 2, 3, 4, 5, 6].map(i => ({ id: i, name: ['LUMENCRAFT', 'LIGHTING SOLUTION', 'KLIQ ROOM EXPERIENCE', 'KLIQ IKON MATCH', 'KLIQ CUSTOM COLORS', 'LiTon'][i - 1], qr_token: 'DEMO-ST' + i + '-' + tok(6), active: true, sort: i })),
      refSeq: 1, prizeSeq: 1, resultSeq: 1, finalSeq: 1
    };
    db.staff = [
      { id: 's1', code: 'ADMIN01', display_name: 'ผู้ดูแลระบบหลัก', role: 'admin', pin: '123456', active: true, failed: 0, locked_until: null },
      { id: 's2', code: 'STAFF01', display_name: 'น้องเอ จุดรับของ', role: 'souvenir', pin: '123456', active: true, failed: 0, locked_until: null },
      { id: 's3', code: 'MC01', display_name: 'พิธีกร', role: 'mc', pin: '123456', active: true, failed: 0, locked_until: null },
      { id: 's4', code: 'REG01', display_name: 'จุดลงทะเบียน', role: 'register', pin: '123456', active: true, failed: 0, locked_until: null },
      { id: 's5', code: 'ST01', display_name: 'พี่บี ประจำฐาน 1', role: 'station', station_id: 1, pin: '123456', active: true, failed: 0, locked_until: null }
    ];
    db.prizes = [
      { id: 1, name: 'iPhone 18 Pro', kind: 'final', rank: 1, quantity: 1, sort: 1 },
      { id: 2, name: 'iPad Gen 11', kind: 'final', rank: 2, quantity: 1, sort: 2 },
      { id: 3, name: 'หูฟังอินเอียร์ Beyerdynamic', kind: 'final', rank: 3, quantity: 1, sort: 3 },
      { id: 4, name: 'หูฟังไร้สาย KEF Mu7', kind: 'final', rank: 3, quantity: 1, sort: 4 }
    ];
    db.prizeSeq = 5;
    // 60 pre-registered names, 20 of them not yet checked in
    for (let i = 0; i < 60; i++) {
      db.prereg.push({ phone: '08' + pad(1000000 + i * 7919 % 9000000, 8), name: pick(FIRST) + ' ' + pick(LAST), email: 'guest' + (i + 1) + '@example.com', company: pick(COMPANY) });
    }
    db.prereg[0].phone = '0811111111'; db.prereg[0].name = 'สมชาย ใจดี'; db.prereg[0].company = 'บริษัท สว่างไฟฟ้า จำกัด';
    db.prereg[1].phone = '0822222222'; db.prereg[1].name = 'สุดา แก้วใส';
    // 132 already registered: 40 pre + 92 walk-in, with stamps at various stages
    const regAt = (i) => minsAgo(180 - i * 1.2);
    const addP = (src, name, phone, company, i) => {
      const r = register(db, { phone, name, company, walkin: src === 'walkin', consent: true, created_at: regAt(i) });
      return db.participants.find(p => p.id === r.id);
    };
    const made = [];
    for (let i = 2; i < 42; i++) made.push(addP('pre', db.prereg[i].name, db.prereg[i].phone, db.prereg[i].company, i));
    for (let i = 0; i < 92; i++) made.push(addP('walkin', pick(FIRST) + ' ' + pick(LAST), '09' + pad(10000000 + i * 1237, 8), pick(COMPANY), 42 + i));
    made.forEach((p, i) => {
      const n = i % 9 === 0 ? 6 : i % 4 === 0 ? 5 : i % 3 === 0 ? 3 : i % 2 === 0 ? 2 : i % 5 === 0 ? 0 : 1;
      for (let s = 1; s <= n; s++) db.stamps.push({ participant_id: p.id, station_id: s, created_at: minsAgo(150 - i - (6 - s) * 9) });
      if (n === 6) { p.completed_at = minsAgo(100 - i * 0.5); if (i % 2 === 0) { p.souvenir_at = minsAgo(80 - i * 0.4); p.souvenir_by = 's2'; p.souvenir_tier = 'premium'; } }
      else if (i % 7 === 3) { p.souvenir_at = minsAgo(70 - i * 0.3); p.souvenir_by = 's2'; p.souvenir_tier = 'basic'; }
    });
    return db;
  }

  function register(db, a) {
    const ph = normPhone(a.phone); if (!ph) return { ok: false, code: 'BAD_PHONE' };
    const ex = db.participants.find(p => p.phone === ph);
    if (ex) return { ok: true, existing: true, token: ex.token, participant: pj(db, ex), id: ex.id };
    if (!a.consent) return { ok: false, code: 'NEED_CONSENT' };
    const cfg = db.settings;
    if (!cfg.registration_open || (cfg.cutoff_at && Date.now() >= new Date(cfg.cutoff_at))) return { ok: false, code: 'CLOSED' };
    if (db.participants.length >= cfg.max_participants) return { ok: false, code: 'FULL' };
    let name, email, company;
    if (a.walkin) { name = (a.name || '').trim(); if (!name) return { ok: false, code: 'NEED_NAME' }; email = a.email || null; company = (a.company || '').trim() || null; if (!company) return { ok: false, code: 'NEED_COMPANY' }; }
    else { const pre = db.prereg.find(x => x.phone === ph); if (!pre) return { ok: false, code: 'NOT_PREREGISTERED' }; name = pre.name; email = pre.email; company = pre.company; }
    const open = db.series.filter(s => db.participants.filter(p => p.series_code === s.code).length < cfg.series_quota);
    if (!open.length) return { ok: false, code: 'FULL' };
    const se = pick(open); const no = se.next_no++;
    const p = { id: uid(), ref_code: 'PP-' + pad(db.refSeq++, 4), token: tok(24), phone: ph, name, email, company, series_code: se.code,
      ticket_no: se.code + '-' + pad(no, 3), source: a.walkin ? 'walkin' : 'pre', created_at: a.created_at || now(), completed_at: null, souvenir_at: null, souvenir_by: null, souvenir_tier: null, souvenir_upgraded_at: null };
    db.participants.push(p);
    return Object.assign({ ok: true, existing: false, token: p.token, participant: pj(db, p) }, p);
  }
  const ser = (db, c) => db.series.find(s => s.code === c);
  const pj = (db, p) => { const s = ser(db, p.series_code); return { ref_code: p.ref_code, name: p.name, phone_masked: maskPhone(p.phone), series_code: p.series_code, series_name: s.name, series_color: s.color, series_tagline: s.tagline, ticket_no: p.ticket_no, source: p.source, created_at: p.created_at, completed_at: p.completed_at, souvenir_at: p.souvenir_at, souvenir_tier: p.souvenir_tier || null, souvenir_upgraded_at: p.souvenir_upgraded_at || null }; };
  const stampsJson = (db, pid) => db.stations.filter(s => s.active).sort((a, b) => a.sort - b.sort).map(s => { const sp = db.stamps.find(x => x.participant_id === pid && x.station_id === s.id); return { station_id: s.id, name: s.name, done: !!sp, at: sp ? sp.created_at : null }; });
  const staffFrom = (db, token, roles) => { const ss = db.sessions.find(x => x.token === token && new Date(x.expires_at) > new Date()); if (!ss) return null; const st = db.staff.find(x => x.id === ss.staff_id && x.active); if (!st) return null; if (st.role !== 'admin' && !roles.includes(st.role)) return null; return st; };
  const AUTH = { ok: false, code: 'AUTH' };
  const eligible = db => db.participants.filter(p => (!db.settings.cutoff_at || new Date(p.created_at) < new Date(db.settings.cutoff_at)) && !db.results.some(r => r.participant_id === p.id));
  const staffName = (db, id) => (db.staff.find(s => s.id === id) || {}).display_name;
  const eventInfo = db => ({ event_name: db.settings.event_name, registration_open: db.settings.registration_open && (!db.settings.cutoff_at || Date.now() < new Date(db.settings.cutoff_at)), announce_text: db.settings.announce_text, souvenir_basic_name: db.settings.souvenir_basic_name, souvenir_premium_name: db.settings.souvenir_premium_name,
    series: db.series.map(s => ({ code: s.code, name: s.name, color: s.color, tagline: s.tagline })), stations: db.stations.filter(s => s.active).length });
  // รอบชิง v3: เปิดการ์ด 5 ใบ ตำแหน่ง 1 OUT · 2 IN · 3 IN · 4 OUT · 5 IN แล้วเปิดว่าการ์ด IN ใบไหนเป็นที่ 3 (step 6) / ที่ 2 (step 7) / ที่ 1 (step 8) · รางวัลอันดับเดียวกันหลายชิ้นหมุนซ้ำจากการ์ดเดิม
  const finalRanks = db => [...new Set(db.prizes.filter(z => z.kind === 'final' && z.rank >= 1 && z.rank <= 3).map(z => z.rank))].sort((a, b) => b - a);
  const finalCard = (g, r) => (g.rank_cards || [g.series_order[1], g.series_order[2], g.series_order[4]])[3 - r];
  const revealStep = r => 5 + (4 - r);
  const finalPool = (db, g, r) => eligible(db).filter(p => p.series_code === finalCard(g, r) && p.id !== g.pending_participant);
  const finalPrize = (db, r) => db.prizes.find(z => z.kind === 'final' && z.rank === r);
  const finalNextPrize = db => db.prizes.filter(z => z.kind === 'final' && z.rank >= 1 && z.rank <= 3 && !db.results.some(d => d.prize_id === z.id && !d.voided)).sort((a, b) => b.rank - a.rank || a.id - b.id)[0] || null;
  const finalJson = (db, g) => {
    const step = g.step, pos = c => g.series_order.indexOf(c) + 1, ranks = finalRanks(db);
    const isFinal = d => (db.prizes.find(z => z.id === d.prize_id) || {}).kind === 'final';
    const z = finalNextPrize(db), nxt = z ? z.rank : null, revealed = nxt != null && step >= revealStep(nxt);
    const phase = g.done || nxt == null ? 'done' : step < 5 ? 'cut' : !revealed ? 'reveal' : 'spin';
    const pool = revealed ? finalPool(db, g, nxt) : [], pp = g.pending_participant && db.participants.find(x => x.id === g.pending_participant);
    const pz = g.pending_prize && db.prizes.find(x => x.id === g.pending_prize);
    const fin = db.results.filter(isFinal);
    const row = d => { const z2 = db.prizes.find(x => x.id === d.prize_id), p = db.participants.find(x => x.id === d.participant_id); return { rank: z2.rank, prize: z2.name, prize_id: z2.id, ticket_no: p.ticket_no, card: p.series_code, name: maskName(p.name), at: d.drawn_at }; };
    return { id: g.id, step, cuts: 5, done: g.done, phase, ranks, next_rank: g.done ? null : nxt,
      next_prize: !g.done && z ? { id: z.id, rank: z.rank, name: z.name, description: z.description || null, image: z.image || null,
        seq: db.results.filter(d => !d.voided && isFinal(d) && db.prizes.find(x => x.id === d.prize_id).rank === z.rank).length + 1, of: db.prizes.filter(x => x.kind === 'final' && x.rank === z.rank).length } : null,
      next_card: revealed ? finalCard(g, nxt) : null,
      pool_left: pool.length, pool_tickets: shuffle(pool.map(p => p.ticket_no)),
      series: db.series.map(se => { const ps = pos(se.code); return { code: se.code, name: se.name, color: se.color, tagline: se.tagline, pos: ps, out: [1, 4].includes(ps) && step >= ps, in: [2, 3, 5].includes(ps) && step >= ps, rank: [3, 2, 1].find(r => finalCard(g, r) === se.code && step >= revealStep(r)) || null, holders: eligible(db).filter(p => p.series_code === se.code).length }; }),
      pending: pp ? { ticket_no: pp.ticket_no, name: maskName(pp.name), rank: g.pending_rank, at: g.pending_at, card: finalCard(g, g.pending_rank), prize: pz ? pz.name : null, prize_id: pz ? pz.id : null, description: pz ? pz.description || null : null, image: pz ? pz.image || null : null } : null,
      winners: fin.filter(d => !d.voided).map(row).sort((a, b) => a.rank - b.rank || a.prize_id - b.prize_id),
      noshows: fin.filter(d => d.voided && d.void_reason === 'noshow').map(d => Object.assign(row(d), { at: d.voided_at })) };
  };
  const finalPrizes = db => db.prizes.filter(z => z.kind === 'final' && z.rank >= 1 && z.rank <= 3).sort((a, b) => a.rank - b.rank || a.id - b.id).map(z => ({ id: z.id, rank: z.rank, name: z.name, description: z.description || null, image: z.image || null, won: db.results.some(d => d.prize_id === z.id && !d.voided) }));

  const FN = {
    event_info: db => eventInfo(db),
    register_participant: (db, a) => { const r = register(db, { phone: a.p_phone, walkin: a.p_walkin, name: a.p_name, email: a.p_email, company: a.p_company, consent: a.p_consent }); return r.ok ? { ok: true, existing: r.existing, name_hint: r.existing ? nameHint(r.participant.name) : undefined, token: r.token, participant: r.participant } : r; },
    get_passport: (db, a) => { const p = db.participants.find(x => x.token === a.p_token); if (!p) return { ok: false, code: 'NO_PARTICIPANT' };
      const r = db.results.find(x => x.participant_id === p.id && !x.voided); const z = r && db.prizes.find(x => x.id === r.prize_id);
      return { ok: true, participant: pj(db, p), stamps: stampsJson(db, p.id), won: r ? { prize: z.name, kind: z.kind, rank: z.rank, image: z.image || null, description: z.description || null, at: r.drawn_at, received_at: r.received_at || null, check: ('DEMO' + r.id).slice(0, 6) } : null, event: eventInfo(db),
        grand: (z1 => z1 ? { name: z1.name, description: z1.description || null, image: z1.image || null } : null)(db.prizes.find(z => z.kind === 'final' && z.rank === 1)),
        called: (g => { if (!g) return null; const z = db.prizes.find(x => x.id === g.pending_prize) || finalPrize(db, g.pending_rank) || {}; return { rank: g.pending_rank, at: g.pending_at, prize: z.name, image: z.image || null, description: z.description || null }; })(db.finals.find(g => g.pending_participant === p.id && !g.done)) }; },
    collect_stamp: (db, a) => { const p = db.participants.find(x => x.token === a.p_token); if (!p) return { ok: false, code: 'NO_PARTICIPANT' };
      const st = db.stations.find(s => s.qr_token === a.p_station_token); if (!st || !st.active) return { ok: false, code: 'BAD_STATION' };
      const prev = db.stamps.find(x => x.participant_id === p.id && x.station_id === st.id); if (prev) return { ok: false, code: 'ALREADY', station: st.name, at: prev.created_at };
      const last = db.stamps.filter(x => x.participant_id === p.id).map(x => +new Date(x.created_at)).sort((x, y) => y - x)[0];
      if (last && db.settings.min_stamp_interval_sec > 0) { const w = Math.ceil(db.settings.min_stamp_interval_sec - (Date.now() - last) / 1000); if (w > 0) return { ok: false, code: 'TOO_SOON', wait_sec: w }; }
      db.stamps.push({ participant_id: p.id, station_id: st.id, created_at: now() });
      const total = db.stations.filter(s => s.active).length, done = db.stamps.filter(x => x.participant_id === p.id && db.stations.some(s => s.id === x.station_id && s.active)).length;
      if (done >= total && !p.completed_at) p.completed_at = now();
      return { ok: true, station: st.name, station_id: st.id, done, total, completed: done >= total }; },
    staff_login: (db, a) => { const s = db.staff.find(x => x.code === String(a.p_code || '').trim().toUpperCase() && x.active); if (!s) return { ok: false, code: 'BAD_LOGIN' };
      if (s.locked_until && new Date(s.locked_until) > new Date()) return { ok: false, code: 'LOCKED' };
      if (s.pin !== a.p_pin) { s.failed++; if (s.failed >= 5) s.locked_until = new Date(Date.now() + 600000).toISOString(); return { ok: false, code: 'BAD_LOGIN' }; }
      s.failed = 0; s.locked_until = null; const t = tok(32); db.sessions.push({ token: t, staff_id: s.id, expires_at: new Date(Date.now() + 18 * 3600000).toISOString() });
      return { ok: true, token: t, role: s.role, name: s.display_name, code: s.code, station_id: s.station_id || null }; },
    staff_me: (db, a) => { const s = staffFrom(db, a.p_token, ['admin', 'souvenir', 'mc', 'register', 'station']); return s ? { ok: true, role: s.role, name: s.display_name, code: s.code, station_id: s.station_id || null } : AUTH; },
    station_me: (db, a) => { const s = staffFrom(db, a.p_token, ['station']); if (!s) return AUTH; const sid = s.role === 'admin' ? (a.p_station_id || s.station_id) : s.station_id; const st = db.stations.find(x => x.id === sid); if (!st) return { ok: false, code: 'NO_STATION' };
      const sp = db.stamps.filter(x => x.station_id === st.id).sort((x, y) => y.created_at.localeCompare(x.created_at));
      return { ok: true, id: st.id, name: st.name, sort: st.sort, active: st.active, qr_token: st.qr_token, count: sp.length, staff: s.display_name, last10: sp.slice(0, 10).map(x => { const p = db.participants.find(q => q.id === x.participant_id) || {}; return { ticket_no: p.ticket_no, name: maskName(p.name || ''), at: x.created_at }; }) }; },
    staff_logout: (db, a) => { db.sessions = db.sessions.filter(x => x.token !== a.p_token); return { ok: true }; },
    souvenir_lookup: (db, a) => { const s = staffFrom(db, a.p_token, ['souvenir']); if (!s) return AUTH; let q = String(a.p_query || '').trim(); if (q.startsWith('KLIQ:')) q = q.slice(5); const ph = normPhone(q);
      const p = db.participants.find(x => x.ref_code.toUpperCase() === q.toUpperCase() || x.ticket_no.toUpperCase() === q.toUpperCase() || (ph && x.phone === ph)); if (!p) return { ok: false, code: ph && db.prereg.some(x => x.phone === ph) ? 'NOT_REGISTERED' : 'NOT_FOUND' };
      const prem = !!p.completed_at, cfg = db.settings;
      const pr = db.results.find(x => x.participant_id === p.id && !x.voided), pz = pr && db.prizes.find(x => x.id === pr.prize_id);
      return { ok: true, participant: pj(db, p), stamps: stampsJson(db, p.id), souvenir_by: staffName(db, p.souvenir_by),
        prize: pr ? { id: pr.id, name: pz.name, rank: pz.rank, kind: pz.kind, image: pz.image || null, drawn_at: pr.drawn_at, received_at: pr.received_at || null, received_by: staffName(db, pr.received_by) } : null,
        tier_now: prem ? 'premium' : 'basic', tier_name: prem ? cfg.souvenir_premium_name : cfg.souvenir_basic_name, basic_name: cfg.souvenir_basic_name, premium_name: cfg.souvenir_premium_name,
        can_redeem: !p.souvenir_at || (p.souvenir_tier === 'basic' && prem), upgrade: !!p.souvenir_at && p.souvenir_tier === 'basic' && prem,
        given_basic: db.participants.filter(x => x.souvenir_at && x.souvenir_tier === 'basic').length, given_premium: db.participants.filter(x => x.souvenir_at && x.souvenir_tier === 'premium').length,
        stock_left: Math.max(0, cfg.max_participants - db.participants.filter(x => x.souvenir_at).length) }; },
    souvenir_redeem: (db, a) => { const s = staffFrom(db, a.p_token, ['souvenir']); if (!s) return AUTH; const p = db.participants.find(x => x.ref_code === String(a.p_ref || '').trim().toUpperCase()); if (!p) return { ok: false, code: 'NOT_FOUND' };
      const tier = p.completed_at ? 'premium' : 'basic';
      if (p.souvenir_at) { if (p.souvenir_tier === 'basic' && tier === 'premium') { p.souvenir_tier = 'premium'; p.souvenir_upgraded_at = now(); p.souvenir_by = s.id; return { ok: true, ref_code: p.ref_code, name: p.name, tier: 'premium', upgraded: true }; }
        return { ok: false, code: 'ALREADY_REDEEMED', at: p.souvenir_at, tier: p.souvenir_tier, by: staffName(db, p.souvenir_by) }; }
      p.souvenir_at = now(); p.souvenir_by = s.id; p.souvenir_tier = tier; return { ok: true, ref_code: p.ref_code, name: p.name, tier, upgraded: false }; },
    admin_stats: (db, a) => { const s = staffFrom(db, a.p_token, ['mc', 'register', 'souvenir']); if (!s) return AUTH; const P = db.participants;
      const comp = P.filter(p => p.completed_at); const avg = comp.length ? Math.round(comp.reduce((t, p) => { const f = db.stamps.filter(x => x.participant_id === p.id).map(x => +new Date(x.created_at)); return t + (new Date(p.completed_at) - Math.min(...f)) / 60000; }, 0) / comp.length) : null;
      return { ok: true, settings: db.settings, registered: P.length, pre: P.filter(p => p.source === 'pre').length, walkin: P.filter(p => p.source === 'walkin').length, preregistered_total: db.prereg.length,
        started: new Set(db.stamps.map(x => x.participant_id)).size, completed: comp.length, souvenir: P.filter(p => p.souvenir_at).length, souvenir_basic: P.filter(p => p.souvenir_at && p.souvenir_tier === 'basic').length, souvenir_premium: P.filter(p => p.souvenir_at && p.souvenir_tier === 'premium').length, avg_complete_min: avg,
        series: db.series.map(se => ({ code: se.code, name: se.name, color: se.color, count: P.filter(p => p.series_code === se.code).length })),
        stations: db.stations.sort((x, y) => x.sort - y.sort).map(st => ({ id: st.id, name: st.name, active: st.active, count: db.stamps.filter(x => x.station_id === st.id).length })),
        winners: db.results.filter(r => !r.voided).length }; },
    admin_participants: (db, a) => { const s = staffFrom(db, a.p_token, ['register', 'souvenir']); if (!s) return AUTH; const q = String(a.p_search || '').trim().toLowerCase(), f = a.p_filter || 'all';
      const rows = db.participants.filter(p => (!q || p.name.toLowerCase().includes(q) || p.phone.includes(q) || p.ref_code.toLowerCase().includes(q) || p.ticket_no.toLowerCase().includes(q) || (p.company || '').toLowerCase().includes(q)))
        .filter(p => f === 'pre' ? p.source === 'pre' : f === 'walkin' ? p.source === 'walkin' : f === 'completed' ? p.completed_at : f === 'souvenir' ? p.souvenir_at : f === 'waiting' ? p.completed_at && p.souvenir_tier !== 'premium' : true)
        .sort((x, y) => y.created_at.localeCompare(x.created_at));
      const off = Math.max(0, a.p_offset || 0), lim = Math.min(500, Math.max(1, a.p_limit || 50));
      return { ok: true, total: rows.length, rows: rows.slice(off, off + lim).map(p => ({ ref_code: p.ref_code, name: p.name, phone: p.phone, email: p.email, company: p.company, series_code: p.series_code, ticket_no: p.ticket_no, source: p.source, stamps: db.stamps.filter(x => x.participant_id === p.id).length, completed_at: p.completed_at, souvenir_at: p.souvenir_at, created_at: p.created_at })) }; },
    admin_export: (db, a) => { const s = staffFrom(db, a.p_token, []); if (!s) return AUTH;
      return { ok: true, rows: db.participants.slice().sort((x, y) => x.created_at.localeCompare(y.created_at)).map(p => { const r = db.results.find(x => x.participant_id === p.id && !x.voided); return { ref_code: p.ref_code, ticket_no: p.ticket_no, name: p.name, phone: p.phone, email: p.email, company: p.company, series: ser(db, p.series_code).name, source: p.source, registered_at: p.created_at, stamps: db.stamps.filter(x => x.participant_id === p.id).length, completed_at: p.completed_at, souvenir_at: p.souvenir_at, prize: r ? db.prizes.find(z => z.id === r.prize_id).name : null }; }) }; },
    admin_import_prereg: (db, a) => { const s = staffFrom(db, a.p_token, []); if (!s) return AUTH; if (a.p_replace) db.prereg = []; let ok = 0; const bad = [];
      (a.p_rows || []).forEach(r => { const ph = normPhone(r.phone); if (!ph || !String(r.name || '').trim()) { bad.push(r); return; } const ex = db.prereg.find(x => x.phone === ph); const row = { phone: ph, name: String(r.name).trim(), email: r.email || null, company: r.company || null }; if (ex) Object.assign(ex, row); else db.prereg.push(row); ok++; });
      return { ok: true, imported: ok, rejected: bad, total: db.prereg.length }; },
    admin_participant_update: (db, a) => { const s = staffFrom(db, a.p_token, []); if (!s) return AUTH; const p = db.participants.find(x => x.ref_code === String(a.p_ref_code || '').trim().toUpperCase()); if (!p) return { ok: false, code: 'NOT_FOUND' };
      const nm = String(a.p_name || '').trim(), ph = normPhone(a.p_phone); if (!nm) return { ok: false, code: 'NEED_NAME' }; if (!ph) return { ok: false, code: 'BAD_PHONE' };
      if (ph !== p.phone && db.participants.some(x => x.phone === ph && x.id !== p.id)) return { ok: false, code: 'PHONE_TAKEN' };
      Object.assign(p, { name: nm, phone: ph, email: String(a.p_email || '').trim() || null, company: String(a.p_company || '').trim() || null }); return { ok: true, ref_code: p.ref_code, name: nm, phone: ph }; },
    admin_participant_delete: (db, a) => { const s = staffFrom(db, a.p_token, []); if (!s) return AUTH; const i = db.participants.findIndex(x => x.ref_code === String(a.p_ref_code || '').trim().toUpperCase()); if (i < 0) return { ok: false, code: 'NOT_FOUND' }; const p = db.participants[i];
      if (db.results.some(x => x.participant_id === p.id && !x.voided) || db.finals.some(g => g.pending_participant === p.id && !g.done)) return { ok: false, code: 'HAS_PRIZE' };
      db.finals.forEach(g => { if (g.pending_participant === p.id) g.pending_participant = null; }); db.results = db.results.filter(x => x.participant_id !== p.id); db.stamps = db.stamps.filter(x => x.participant_id !== p.id); db.participants.splice(i, 1); return { ok: true }; },
    admin_prereg_update: (db, a) => { const s = staffFrom(db, a.p_token, []); if (!s) return AUTH; const old = normPhone(a.p_old_phone), r = old && db.prereg.find(x => x.phone === old); if (!r) return { ok: false, code: 'NOT_FOUND' };
      const nm = String(a.p_name || '').trim(), ph = normPhone(a.p_phone); if (!nm) return { ok: false, code: 'NEED_NAME' }; if (!ph) return { ok: false, code: 'BAD_PHONE' };
      if (ph !== old && db.prereg.some(x => x.phone === ph)) return { ok: false, code: 'PHONE_TAKEN' };
      Object.assign(r, { phone: ph, name: nm, email: String(a.p_email || '').trim() || null, company: String(a.p_company || '').trim() || null }); return { ok: true, phone: ph, name: nm }; },
    admin_prereg_delete: (db, a) => { const s = staffFrom(db, a.p_token, []); if (!s) return AUTH; const ph = normPhone(a.p_phone), i = db.prereg.findIndex(x => x.phone === ph); if (i < 0) return { ok: false, code: 'NOT_FOUND' }; db.prereg.splice(i, 1); return { ok: true }; },
    admin_stations: (db, a) => { const s = staffFrom(db, a.p_token, []); if (!s) return AUTH; return { ok: true, rows: db.stations.slice().sort((x, y) => x.sort - y.sort).map(st => ({ id: st.id, name: st.name, qr_token: st.qr_token, active: st.active, sort: st.sort, count: db.stamps.filter(x => x.station_id === st.id).length })) }; },
    admin_station_save: (db, a) => { const s = staffFrom(db, a.p_token, []); if (!s) return AUTH; const st = db.stations.find(x => x.id === a.p_id); if (st) { if (a.p_name && a.p_name.trim()) st.name = a.p_name.trim(); if (a.p_active != null) st.active = a.p_active; if (a.p_rotate) st.qr_token = 'DEMO-ST' + st.id + '-' + tok(6); } return { ok: true }; },
    admin_settings_save: (db, a) => { const s = staffFrom(db, a.p_token, []); if (!s) return AUTH; const p = a.p || {}, c = db.settings;
      if ('final_order' in p) c.final_order = Array.isArray(p.final_order) && p.final_order.length === 5 ? p.final_order : null;
      ['event_name', 'announce_text', 'souvenir_basic_name', 'souvenir_premium_name'].forEach(k => { if (p[k] != null && String(p[k]).trim()) c[k] = p[k]; }); ['max_participants', 'series_quota', 'min_stamp_interval_sec', 'final_claim_sec'].forEach(k => { if (p[k] != null && !isNaN(+p[k])) c[k] = +p[k]; });
      if (p.registration_open != null) c.registration_open = !!p.registration_open; if ('cutoff_at' in p) c.cutoff_at = p.cutoff_at ? new Date(p.cutoff_at).toISOString() : null; c.updated_at = now(); return { ok: true }; },
    admin_staff_list: (db, a) => { const s = staffFrom(db, a.p_token, []); if (!s) return AUTH; return { ok: true, rows: db.staff.map(x => ({ code: x.code, display_name: x.display_name, role: x.role, active: x.active, locked: !!(x.locked_until && new Date(x.locked_until) > new Date()), station_id: x.station_id || null, station_name: (db.stations.find(st => st.id === x.station_id) || {}).name || null })) }; },
    admin_staff_save: (db, a) => { const s = staffFrom(db, a.p_token, []); if (!s) return AUTH; const c = String(a.p_code || '').trim().toUpperCase();
      if (!/^[A-Z0-9_-]{3,20}$/.test(c)) return { ok: false, code: 'BAD_CODE' }; if (!['admin', 'souvenir', 'mc', 'register', 'station'].includes(a.p_role)) return { ok: false, code: 'BAD_ROLE' }; if (a.p_role === 'station' && !db.stations.some(x => x.id === a.p_station_id)) return { ok: false, code: 'NEED_STATION' };
      if (a.p_pin && !/^\d{6}$/.test(a.p_pin)) return { ok: false, code: 'BAD_PIN' }; if (c === s.code && (a.p_role !== 'admin' || !a.p_active)) return { ok: false, code: 'SELF_LOCKOUT' };
      const ex = db.staff.find(x => x.code === c);
      if (ex) { if (a.p_name && a.p_name.trim()) ex.display_name = a.p_name.trim(); ex.role = a.p_role; ex.station_id = a.p_role === 'station' ? a.p_station_id : null; ex.active = a.p_active !== false; if (a.p_pin) ex.pin = a.p_pin; ex.failed = 0; ex.locked_until = null; if (!ex.active) db.sessions = db.sessions.filter(x => x.staff_id !== ex.id); }
      else { if (!a.p_pin) return { ok: false, code: 'BAD_PIN' }; db.staff.push({ id: uid(), code: c, display_name: (a.p_name || '').trim() || c, role: a.p_role, station_id: a.p_role === 'station' ? a.p_station_id : null, pin: a.p_pin, active: true, failed: 0, locked_until: null }); }
      return { ok: true }; },
    admin_prizes: (db, a) => { const s = staffFrom(db, a.p_token, ['mc']); if (!s) return AUTH; return { ok: true, rows: db.prizes.slice().sort((x, y) => x.kind.localeCompare(y.kind) || (x.rank || 99) - (y.rank || 99) || x.sort - y.sort).map(z => Object.assign({}, z, { won: db.results.filter(r => r.prize_id === z.id && !r.voided).length })) }; },
    admin_prize_delete: (db, a) => { const s = staffFrom(db, a.p_token, []); if (!s) return AUTH; const i = db.prizes.findIndex(z => z.id === a.p_id); if (i < 0) return { ok: false, code: 'NOT_FOUND' }; if (db.results.some(r => r.prize_id === a.p_id && !r.voided)) return { ok: false, code: 'PRIZE_AWARDED' }; db.results = db.results.filter(r => r.prize_id !== a.p_id); db.prizes.splice(i, 1); return { ok: true }; },
    admin_reset_draw: (db, a) => { const s = staffFrom(db, a.p_token, []); if (!s || s.role !== 'admin') return AUTH; if (a.p_confirm !== 'RESET') return { ok: false, code: 'BAD_INPUT' }; const n = db.results.length; db.results = []; db.finals = []; return { ok: true, removed: n }; },
    admin_reset_event: (db, a) => { const s = staffFrom(db, a.p_token, []); if (!s || s.role !== 'admin') return AUTH; if (a.p_confirm !== 'RESET') return { ok: false, code: 'BAD_INPUT' }; const n = db.participants.length; db.results = []; db.finals = []; db.stamps = []; db.participants = []; db.series.forEach(x => { x.next_no = 1; }); db.refSeq = 1; db.settings.cutoff_at = null; db.settings.registration_open = true; return { ok: true, removed: n }; },
    admin_prize_save: (db, a) => { const s = staffFrom(db, a.p_token, []); if (!s) return AUTH; if (!['final', 'normal'].includes(a.p_kind) || !(a.p_quantity >= 1) || !String(a.p_name || '').trim() || (a.p_kind === 'final' && !(a.p_rank >= 1 && a.p_rank <= 3))) return { ok: false, code: 'BAD_INPUT' };
      if (a.p_image && (!a.p_image.startsWith('data:image/') || a.p_image.length > 300000)) return { ok: false, code: 'BAD_IMAGE' };
      const row = { name: a.p_name.trim(), kind: a.p_kind, quantity: a.p_kind === 'final' ? 1 : a.p_quantity, rank: a.p_kind === 'final' ? a.p_rank : null };
      const ex = a.p_id != null && db.prizes.find(z => z.id === a.p_id); if (ex) Object.assign(ex, row); else db.prizes.push(Object.assign({ id: db.prizeSeq++, sort: a.p_sort || 0 }, row)); return { ok: true }; },
    draw_eligible_count: (db, a) => { const s = staffFrom(db, a.p_token, ['mc']); if (!s) return AUTH; const e = eligible(db); return { ok: true, eligible: e.length, by_series: db.series.map(se => ({ code: se.code, name: se.name, count: e.filter(p => p.series_code === se.code).length })) }; },
    final_state: (db, a) => { const s = staffFrom(db, a.p_token, ['mc']); if (!s) return AUTH; const g = a.p_draw_id ? db.finals.find(x => x.id === a.p_draw_id) : db.finals[db.finals.length - 1]; return { ok: true, draw: g ? finalJson(db, g) : null, claim_sec: db.settings.final_claim_sec || 60, prizes: finalPrizes(db) }; },
    final_create: (db, a) => { const s = staffFrom(db, a.p_token, ['mc']); if (!s) return AUTH; const last = db.finals[db.finals.length - 1];
      if (last) { if (last.done) return { ok: false, code: 'FINAL_DONE' }; return FN.final_state(db, { p_token: a.p_token, p_draw_id: last.id }); }
      for (const r of [1, 2, 3]) if (!finalPrize(db, r)) return { ok: false, code: 'NO_FINAL_PRIZE', rank: r };
      if (!finalNextPrize(db)) return { ok: false, code: 'FINAL_DONE' };
      const e = eligible(db); if (!e.length) return { ok: false, code: 'NOT_ENOUGH' };
      let order, tries = 0;
      const lock = db.settings.final_order, codes = db.series.map(x => x.code);
      let locked = false;
      if (lock && lock.length === 5 && new Set(lock).size === 5 && lock.every(c => codes.includes(c))) { order = lock.slice(); locked = true; }
      else do { order = shuffle(codes); tries++; } while (tries < 50 && ![1, 2, 4].every(i => e.some(p => p.series_code === order[i])));
      const ins = [order[1], order[2], order[4]];
      const g = { id: db.finalSeq++, series_order: order, rank_cards: locked ? ins : shuffle(ins), pool_count: e.length, step: 0, pending_participant: null, pending_rank: null, pending_prize: null, pending_at: null, done: false, created_at: now() };
      db.finals.push(g); return FN.final_state(db, { p_token: a.p_token, p_draw_id: g.id }); },
    final_next: (db, a) => { const s = staffFrom(db, a.p_token, ['mc']); if (!s) return AUTH; const g = db.finals.find(x => x.id === a.p_draw_id); if (!g) return { ok: false, code: 'NOT_FOUND' }; if (g.done) return FN.final_state(db, { p_token: a.p_token, p_draw_id: g.id });
      if (g.step < 5) { g.step++; return FN.final_state(db, { p_token: a.p_token, p_draw_id: g.id }); }
      if (g.pending_participant) return { ok: false, code: 'PENDING' };
      const z = finalNextPrize(db); if (!z) { g.done = true; return FN.final_state(db, { p_token: a.p_token, p_draw_id: g.id }); }
      if (g.step < revealStep(z.rank)) { g.step = revealStep(z.rank); return FN.final_state(db, { p_token: a.p_token, p_draw_id: g.id }); }
      const w = pick(finalPool(db, g, z.rank)); if (!w) return { ok: false, code: 'NOT_ENOUGH' };
      g.pending_participant = w.id; g.pending_rank = z.rank; g.pending_prize = z.id; g.pending_at = now(); return FN.final_state(db, { p_token: a.p_token, p_draw_id: g.id }); },
    final_claim: (db, a) => { const s = staffFrom(db, a.p_token, ['mc']); if (!s) return AUTH; const g = db.finals.find(x => x.id === a.p_draw_id); if (!g) return { ok: false, code: 'NOT_FOUND' }; if (!g.pending_participant) return { ok: false, code: 'NO_PENDING' };
      const pz = db.prizes.find(x => x.id === g.pending_prize) || finalPrize(db, g.pending_rank); if (!pz) return { ok: false, code: 'NO_FINAL_PRIZE' };
      if (a.p_present) db.results.push({ id: db.resultSeq++, prize_id: pz.id, participant_id: g.pending_participant, drawn_at: now(), voided: false });
      else db.results.push({ id: db.resultSeq++, prize_id: pz.id, participant_id: g.pending_participant, drawn_at: now(), voided: true, voided_at: now(), void_reason: 'noshow' });
      g.pending_participant = null; g.pending_rank = null; g.pending_prize = null; g.pending_at = null; if (!finalNextPrize(db)) g.done = true;
      return FN.final_state(db, { p_token: a.p_token, p_draw_id: g.id }); },
    final_replace: (db, a) => { const s = staffFrom(db, a.p_token, ['mc']); if (!s) return AUTH; const g = db.finals[db.finals.length - 1]; if (!g || g.step < revealStep(a.p_rank)) return { ok: false, code: 'NOT_FOUND' };
      const pz = db.prizes.filter(z => z.kind === 'final' && z.rank === a.p_rank).sort((x, y) => x.id - y.id).find(z => !db.results.some(r => r.prize_id === z.id && !r.voided));
      if (!pz) return { ok: false, code: finalPrize(db, a.p_rank) ? 'PRIZE_DONE' : 'NO_FINAL_PRIZE' }; const w = pick(finalPool(db, g, a.p_rank)); if (!w) return { ok: false, code: 'NOT_ENOUGH' };
      db.results.push({ id: db.resultSeq++, prize_id: pz.id, participant_id: w.id, drawn_at: now(), voided: false }); if (!finalNextPrize(db)) g.done = true; return { ok: true, ticket_no: w.ticket_no, name: maskName(w.name), rank: a.p_rank, prize: pz.name }; },
    draw_prize_next: (db, a) => { const s = staffFrom(db, a.p_token, ['mc']); if (!s) return AUTH; const z = db.prizes.find(x => x.id === a.p_prize_id && x.kind === 'normal'); if (!z) return { ok: false, code: 'BAD_PRIZE' }; const won = db.results.filter(r => r.prize_id === z.id && !r.voided).length; if (won >= z.quantity) return { ok: false, code: 'PRIZE_DONE' };
      const w = pick(eligible(db)); if (!w) return { ok: false, code: 'NOT_ENOUGH' }; const id = db.resultSeq++; db.results.push({ id, prize_id: z.id, participant_id: w.id, drawn_at: now(), voided: false }); return { ok: true, result_id: id, n: won + 1, quantity: z.quantity, image: z.image || null, description: z.description || null, ticket_no: w.ticket_no, name: maskName(w.name), series_name: ser(db, w.series_code).name }; },
    prize_handover: (db, a) => { const s = staffFrom(db, a.p_token, ['souvenir']); if (!s) return AUTH; const p = db.participants.find(x => x.ref_code === String(a.p_ref || '').trim().toUpperCase()); if (!p) return { ok: false, code: 'NOT_FOUND' };
      const r = db.results.find(x => x.participant_id === p.id && !x.voided); if (!r) return { ok: false, code: 'NO_PRIZE' }; if (r.received_at) return { ok: false, code: 'PRIZE_RECEIVED', received_at: r.received_at };
      r.received_at = now(); r.received_by = s.id; const z = db.prizes.find(x => x.id === r.prize_id); return { ok: true, prize: z.name, rank: z.rank, name: p.name }; },
    draw_results_list: (db, a) => { const s = staffFrom(db, a.p_token, ['mc']); if (!s) return AUTH; return { ok: true, rows: db.results.slice().reverse().map(r => { const z = db.prizes.find(x => x.id === r.prize_id), p = db.participants.find(x => x.id === r.participant_id); return { id: r.id, prize: z.name, prize_id: z.id, kind: z.kind, rank: z.rank, ticket_no: p.ticket_no, name: s.role === 'admin' ? p.name : maskName(p.name), phone: s.role === 'admin' ? p.phone : maskPhone(p.phone), series_name: ser(db, p.series_code).name, drawn_at: r.drawn_at, voided: r.voided, received_at: r.received_at || null, received_by: staffName(db, r.received_by) }; }) }; },
    draw_void: (db, a) => { const s = staffFrom(db, a.p_token, []); if (!s) return AUTH; const r = db.results.find(x => x.id === a.p_result_id); if (r && !r.voided) { r.voided = true; r.voided_at = now(); r.void_reason = 'admin'; if ((db.prizes.find(z => z.id === r.prize_id) || {}).kind === 'final') db.finals.forEach(g => { if (g.done) g.done = false; }); } return { ok: true }; }
  };

  function load() { try { const s = localStorage.getItem(KEY); if (s) return JSON.parse(s); } catch (e) {} const db = fresh(); save(db); return db; }
  function save(db) { try { localStorage.setItem(KEY, JSON.stringify(db)); } catch (e) {} }

  window.KLIQ_DEMO = {
    call(fn, args) { const db = load(); const f = FN[fn]; if (!f) return { ok: false, code: 'SERVER', detail: 'no fn ' + fn }; const r = f(db, args || {}); save(db); return JSON.parse(JSON.stringify(r)); },
    reset() { try { localStorage.removeItem(KEY); localStorage.removeItem('kliq_pt'); localStorage.removeItem('kliq_staff'); localStorage.removeItem('kliq_revealed'); } catch (e) {} load(); },
    stations() { return load().stations; },
    sample() { const db = load(); return { prereg: db.prereg.filter(x => !db.participants.some(p => p.phone === x.phone)).slice(0, 5), completed: db.participants.filter(p => p.completed_at && !p.souvenir_at).slice(0, 3), stations: db.stations }; }
  };
})();
