/* KLIQ Experience – shared client helpers (no build step, no dependencies) */
(function () {
  const CFG = window.KLIQ_CONFIG || {};
  const LS = {
    get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch (e) {} },
    del(k) { try { localStorage.removeItem(k); } catch (e) {} }
  };

  const MESSAGES = {
    BAD_PHONE: 'เบอร์โทรไม่ถูกต้อง กรุณากรอกเบอร์ 9–10 หลัก',
    NEED_CONSENT: 'กรุณายอมรับนโยบายความเป็นส่วนตัวก่อนลงทะเบียน',
    NEED_NAME: 'กรุณากรอกชื่อ - นามสกุล',
    NEED_COMPANY: 'กรุณากรอกชื่อบริษัท / ร้านค้า',
    PRIZE_AWARDED: 'รางวัลนี้มีผู้ได้รับแล้ว ยกเลิกสิทธิ์ก่อนจึงลบได้',
    HAS_PRIZE: 'คนนี้ได้รับรางวัลอยู่ · ไปที่ Lucky Draw กด "ยกเลิกสิทธิ์" ก่อนจึงลบได้',
    PHONE_TAKEN: 'เบอร์นี้มีคนใช้อยู่แล้ว ตรวจสอบอีกครั้ง',
    NOT_PREREGISTERED: 'ไม่พบเบอร์นี้ในรายชื่อลงทะเบียนล่วงหน้า กรุณาลงทะเบียนแบบ Walk-in',
    FULL: 'ขออภัย สิทธิ์ลุ้นรางวัลเต็มแล้ว ยังเดินชมงานและเล่นฐานได้ตามปกติ',
    CLOSED: 'ปิดรับลงทะเบียนลุ้นโชคแล้ว ติดตามประกาศผลบนเวที',
    NO_PARTICIPANT: 'ไม่พบข้อมูลผู้ร่วมงาน กรุณาลงทะเบียนใหม่ด้วยเบอร์เดิม',
    BAD_STATION: 'QR Code ไม่ถูกต้อง กรุณาสแกน QR จากเจ้าหน้าที่ประจำฐาน',
    ALREADY: 'คุณได้แสตมป์ฐานนี้แล้ว ไปฐานถัดไปได้เลย',
    TOO_SOON: 'สแกนเร็วเกินไป กรุณาทำกิจกรรมให้เสร็จแล้วสแกนอีกครั้ง',
    BAD_LOGIN: 'รหัสเจ้าหน้าที่หรือ PIN ไม่ถูกต้อง',
    LOCKED: 'ใส่ PIN ผิดหลายครั้ง ระบบล็อกไว้ 10 นาที หรือให้แอดมินปลดล็อก',
    AUTH: 'หมดเวลาการใช้งาน กรุณาเข้าสู่ระบบใหม่',
    NOT_FOUND: 'ไม่พบผู้ร่วมงาน · ตรวจสอบเบอร์/รหัส หรือให้ลูกค้าลงทะเบียนก่อน',
    NOT_REGISTERED: 'เบอร์นี้มีชื่อลงทะเบียนล่วงหน้า แต่ยังไม่ได้กดลงทะเบียนรับการ์ดที่หน้างาน · ให้ลูกค้าเปิดหน้าลงทะเบียนก่อน',
    NOT_COMPLETE: 'ผู้ร่วมงานยังเล่นไม่ครบทุกฐาน',
    ALREADY_REDEEMED: 'รับของที่ระลึกไปแล้ว',
    NO_PRIZE: 'คนนี้ไม่ได้เป็นผู้ได้รับรางวัล',
    PRIZE_RECEIVED: 'มอบรางวัลให้คนนี้ไปแล้ว · ห้ามมอบซ้ำ',
    PRIZE_DONE: 'รางวัลนี้สุ่มครบจำนวนแล้ว',
    NOT_ENOUGH: 'ผู้มีสิทธิ์ไม่พอสำหรับการสุ่ม',
    DRAW_IN_PROGRESS: 'มีการสุ่มรางวัลนี้ค้างอยู่ เปิดต่อจากรอบเดิม',
    BAD_PRIZE: 'ไม่พบรางวัล',
    BAD_CODE: 'รหัสเจ้าหน้าที่ใช้ได้เฉพาะ A-Z 0-9 _ - ยาว 3–20 ตัว',
    BAD_ROLE: 'บทบาทไม่ถูกต้อง',
    BAD_PIN: 'PIN ต้องเป็นตัวเลข 6 หลัก',
    SELF_LOCKOUT: 'ไม่สามารถลดสิทธิ์หรือปิดบัญชีของตัวเองได้',
    BAD_INPUT: 'ข้อมูลไม่ครบหรือไม่ถูกต้อง',
    NETWORK: 'เชื่อมต่ออินเทอร์เน็ตไม่ได้ กรุณาลองใหม่อีกครั้ง',
    CONFIG: 'ยังไม่ได้ตั้งค่าการเชื่อมต่อระบบ (config.js)'
  };

  function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

  async function rpc(fn, args, opts) {
    opts = opts || {};
    if (!CFG.SUPABASE_URL || CFG.SUPABASE_URL.indexOf('YOUR-PROJECT') >= 0) return { ok: false, code: 'CONFIG' };
    const tries = opts.tries || 3;
    for (let i = 0; i < tries; i++) {
      try {
        const ctl = new AbortController();
        const t = setTimeout(() => ctl.abort(), opts.timeout || 12000);
        const res = await fetch(CFG.SUPABASE_URL.replace(/\/$/, '') + '/rest/v1/rpc/' + fn, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            apikey: CFG.SUPABASE_ANON_KEY,
            Authorization: 'Bearer ' + CFG.SUPABASE_ANON_KEY
          },
          body: JSON.stringify(args || {}),
          signal: ctl.signal
        });
        clearTimeout(t);
        if (res.status >= 500 || res.status === 429) throw new Error('server ' + res.status);
        const data = await res.json();
        if (!res.ok) { console.error(fn, data); return { ok: false, code: 'SERVER', detail: data && data.message }; }
        return data;
      } catch (e) {
        if (i === tries - 1) return { ok: false, code: 'NETWORK' };
        await sleep(600 * (i + 1));
      }
    }
  }

  function msg(r) {
    if (!r) return MESSAGES.NETWORK;
    if (r.code === 'TOO_SOON' && r.wait_sec) {
      const m = Math.floor(r.wait_sec / 60), s = r.wait_sec % 60;
      return 'สแกนเร็วเกินไป กรุณาทำกิจกรรมให้เสร็จแล้วสแกนอีกครั้งใน ' + (m ? m + ' นาที ' : '') + s + ' วินาที';
    }
    return MESSAGES[r.code] || ('เกิดข้อผิดพลาด (' + (r.code || 'UNKNOWN') + ') กรุณาลองใหม่');
  }

  function $(sel, root) { return (root || document).querySelector(sel); }
  function $$(sel, root) { return Array.from((root || document).querySelectorAll(sel)); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }
  function fmtTime(iso) {
    if (!iso) return '';
    const d = new Date(iso);
    return d.toLocaleTimeString('th-TH', { hour: '2-digit', minute: '2-digit' }) + ' น.';
  }
  function fmtDateTime(iso) {
    if (!iso) return '';
    const d = new Date(iso);
    return d.toLocaleDateString('th-TH', { day: 'numeric', month: 'short' }) + ' ' + fmtTime(iso);
  }

  let toastTimer;
  function toast(text, kind) {
    let el = $('#toast');
    if (!el) { el = document.createElement('div'); el.id = 'toast'; el.setAttribute('role', 'status'); document.body.appendChild(el); }
    el.className = 'toast show ' + (kind || '');
    el.textContent = text;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.className = 'toast ' + (kind || ''); }, 3800);
  }

  function busy(btn, on, label) {
    if (!btn) return;
    if (on) { btn.dataset.label = btn.innerHTML; btn.disabled = true; btn.innerHTML = label || 'กำลังดำเนินการ…'; }
    else { btn.disabled = false; if (btn.dataset.label) btn.innerHTML = btn.dataset.label; }
  }

  // ----- participant session
  // จำผู้ร่วมงานในเครื่องนี้ 1 วัน (ต่ออายุทุกครั้งที่เปิด) · ถ้าหมดอายุหรือเปิดจากแอป/เบราว์เซอร์อื่น ให้กรอกเบอร์ยืนยันตัวตนใหม่ได้ที่หน้าฐาน
  const P_TTL = 24 * 60 * 60 * 1000;
  const P = {
    token() { const t = LS.get('kliq_pt'); if (!t) return null; const at = +LS.get('kliq_pt_at') || 0; if (at && Date.now() - at > P_TTL) { P.clear(); return null; } LS.set('kliq_pt_at', String(Date.now())); return t; },
    set(t) { LS.set('kliq_pt', t); LS.set('kliq_pt_at', String(Date.now())); },
    clear() { LS.del('kliq_pt'); LS.del('kliq_pt_at'); }
  };

  // ----- staff session
  const STAFF = {
    get() { try { return JSON.parse(LS.get('kliq_staff') || 'null'); } catch (e) { return null; } },
    set(s) { LS.set('kliq_staff', JSON.stringify(s)); },
    clear() { LS.del('kliq_staff'); },
    token() { const s = STAFF.get(); return s && s.token; },
    // ใช้บนหน้าที่ต้องล็อกอิน: roles = บทบาทที่อนุญาต (admin ผ่านทุกหน้า)
    async guard(roles) {
      const s = STAFF.get();
      if (!s || !s.token) { location.href = '/staff/login.html?next=' + encodeURIComponent(location.pathname + location.search); return null; }
      if (s.role !== 'admin' && roles && roles.indexOf(s.role) < 0) { location.href = STAFF.home(s.role); return null; }
      const me = await rpc('staff_me', { p_token: s.token });
      if (me && me.code === 'AUTH') { STAFF.clear(); location.href = '/staff/login.html'; return null; }
      return s;
    },
    home(role) {
      return { admin: '/admin/index.html', souvenir: '/staff/souvenir.html', mc: '/stage/index.html', register: '/admin/participants.html', station: '/staff/station.html' }[role] || '/staff/login.html';
    },
    async logout() {
      const t = STAFF.token();
      if (t) await rpc('staff_logout', { p_token: t }, { tries: 1 });
      STAFF.clear();
      location.href = '/staff/login.html';
    }
  };

  // ----- QR
  function qrSvg(text, size) {
    const q = window.qrcode(0, 'M');
    q.addData(text);
    q.make();
    const n = q.getModuleCount(), m = 2, cell = (size || 200) / (n + m * 2);
    let path = '';
    for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) if (q.isDark(r, c)) path += 'M' + (c + m) + ' ' + (r + m) + 'h1v1h-1z';
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + (n + m * 2) + ' ' + (n + m * 2) + '" width="' + (size || 200) +
      '" height="' + (size || 200) + '" shape-rendering="crispEdges" role="img" aria-label="QR Code"><rect width="100%" height="100%" fill="#fff"/><path d="' + path + '" fill="#111"/></svg>';
  }

  // ----- camera scanner (jsQR): onCode(text) return true to stop
  async function startScanner(videoEl, onCode, onError) {
    let stream, stopped = false, raf;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: 'environment' } }, audio: false });
    } catch (e) { onError && onError(e); return { stop() {} }; }
    videoEl.srcObject = stream;
    videoEl.setAttribute('playsinline', '');
    videoEl.muted = true;
    await videoEl.play().catch(() => {});
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    let last = 0;
    function tick(ts) {
      if (stopped) return;
      raf = requestAnimationFrame(tick);
      if (ts - last < 120 || videoEl.readyState < 2) return;
      last = ts;
      const w = videoEl.videoWidth, h = videoEl.videoHeight;
      if (!w) return;
      const scale = Math.min(1, 640 / Math.max(w, h));
      canvas.width = Math.round(w * scale); canvas.height = Math.round(h * scale);
      ctx.drawImage(videoEl, 0, 0, canvas.width, canvas.height);
      const img = ctx.getImageData(0, 0, canvas.width, canvas.height);
      const code = window.jsQR(img.data, img.width, img.height, { inversionAttempts: 'dontInvert' });
      if (code && code.data) {
        const stop = onCode(code.data);
        if (stop) ctl.stop();
      }
    }
    const ctl = {
      stop() { stopped = true; cancelAnimationFrame(raf); stream && stream.getTracks().forEach(t => t.stop()); },
      pause() { stopped = true; cancelAnimationFrame(raf); },
      resume() { if (!stopped) return; stopped = false; raf = requestAnimationFrame(tick); }
    };
    raf = requestAnimationFrame(tick);
    return ctl;
  }

  // ----- CSV
  function toCSV(rows, cols) {
    const q = v => { v = v == null ? '' : String(v); return /[",\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
    return '﻿' + [cols.map(c => q(c.label)).join(',')].concat(rows.map(r => cols.map(c => q(typeof c.get === 'function' ? c.get(r) : r[c.key])).join(','))).join('\r\n');
  }
  function parseCSV(text) {
    text = text.replace(/^﻿/, '');
    const rows = []; let row = [], cur = '', inQ = false;
    for (let i = 0; i < text.length; i++) {
      const ch = text[i];
      if (inQ) {
        if (ch === '"') { if (text[i + 1] === '"') { cur += '"'; i++; } else inQ = false; }
        else cur += ch;
      } else if (ch === '"') inQ = true;
      else if (ch === ',' || ch === '\t') { row.push(cur); cur = ''; }
      else if (ch === '\n' || ch === '\r') { if (ch === '\r' && text[i + 1] === '\n') i++; row.push(cur); rows.push(row); row = []; cur = ''; }
      else cur += ch;
    }
    if (cur !== '' || row.length) { row.push(cur); rows.push(row); }
    return rows.filter(r => r.some(c => c.trim() !== ''));
  }
  // ----- Excel (.xlsx) โดยไม่พึ่งไลบรารี: สร้าง ZIP (stored) + XML ของ SpreadsheetML · ข้อความทั้งหมดเก็บแบบ inline string
  function toXLSX(rows, cols, sheetName) {
    const enc = new TextEncoder();
    const xml = v => String(v == null ? '' : v).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/[\x00-\x08\x0B\x0C\x0E-\x1F]/g, '');
    const colRef = i => { let s = ''; i++; while (i > 0) { const m = (i - 1) % 26; s = String.fromCharCode(65 + m) + s; i = Math.floor((i - 1) / 26); } return s; };
    const cell = (c, r, v, style) => {
      if (v == null || v === '') return '';
      const ref = colRef(c) + r;
      if (typeof v === 'number' && isFinite(v)) return `<c r="${ref}"${style ? ` s="${style}"` : ''}><v>${v}</v></c>`;
      return `<c r="${ref}" t="inlineStr"${style ? ` s="${style}"` : ''}><is><t xml:space="preserve">${xml(v)}</t></is></c>`;
    };
    const head = cols.map((c, i) => cell(i, 1, c.label, 1)).join('');
    const body = rows.map((r, ri) => '<row r="' + (ri + 2) + '">' + cols.map((c, ci) => cell(ci, ri + 2, typeof c.get === 'function' ? c.get(r) : r[c.key])).join('') + '</row>').join('');
    const widths = cols.map((c, i) => { const w = Math.min(60, Math.max(10, ...[c.label, ...rows.slice(0, 200).map(r => typeof c.get === 'function' ? c.get(r) : r[c.key])].map(v => String(v == null ? '' : v).length * 1.15 + 2))); return `<col min="${i + 1}" max="${i + 1}" width="${w.toFixed(1)}" customWidth="1"/>`; }).join('');
    const sheet = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>${widths}</cols><sheetData><row r="1">${head}</row>${body}</sheetData><autoFilter ref="A1:${colRef(cols.length - 1)}${rows.length + 1}"/></worksheet>`;
    const styles = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF1A1714"/></patternFill></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" applyFont="1" applyFill="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>`;
    const wb = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="${xml((sheetName || 'Sheet1').slice(0, 31))}" sheetId="1" r:id="rId1"/></sheets></workbook>`;
    const files = [
      ['[Content_Types].xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>`],
      ['_rels/.rels', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`],
      ['xl/workbook.xml', wb],
      ['xl/_rels/workbook.xml.rels', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`],
      ['xl/styles.xml', styles],
      ['xl/worksheets/sheet1.xml', sheet],
    ];
    // ZIP (ไม่บีบอัด) + CRC32
    const T = (() => { const t = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
    const crc = b => { let c = 0xFFFFFFFF; for (let i = 0; i < b.length; i++) c = T[(c ^ b[i]) & 0xFF] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; };
    const d = new Date(), dosT = (d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1), dosD = ((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate();
    const parts = [], central = []; let off = 0;
    const u16 = n => [n & 255, (n >> 8) & 255], u32 = n => [n & 255, (n >> 8) & 255, (n >> 16) & 255, (n >>> 24) & 255];
    for (const [name, content] of files) {
      const nm = enc.encode(name), data = enc.encode(content), c = crc(data);
      const local = new Uint8Array([...u32(0x04034b50), ...u16(20), ...u16(0x0800), ...u16(0), ...u16(dosT), ...u16(dosD), ...u32(c), ...u32(data.length), ...u32(data.length), ...u16(nm.length), ...u16(0), ...nm]);
      parts.push(local, data);
      central.push(new Uint8Array([...u32(0x02014b50), ...u16(20), ...u16(20), ...u16(0x0800), ...u16(0), ...u16(dosT), ...u16(dosD), ...u32(c), ...u32(data.length), ...u32(data.length), ...u16(nm.length), ...u16(0), ...u16(0), ...u16(0), ...u16(0), ...u32(0), ...u32(off), ...nm]));
      off += local.length + data.length;
    }
    const cdSize = central.reduce((a, b) => a + b.length, 0);
    const end = new Uint8Array([...u32(0x06054b50), ...u16(0), ...u16(0), ...u16(files.length), ...u16(files.length), ...u32(cdSize), ...u32(off), ...u16(0)]);
    return new Blob([...parts, ...central, end], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
  }
  function download(name, content, type) {
    const blob = content instanceof Blob ? content : new Blob([content], { type: type || 'text/csv;charset=utf-8' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob); a.download = name;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  }

  const SERIES_IMG = { U: 'uno', I: 'ikon', F: 'forma', N: 'nova', C: 'casa' };
  function seriesImg(code, kind) { return '/assets/kliq-' + (SERIES_IMG[code] || 'ikon') + '-' + (kind || 'l') + '.webp'; }
  function inkFor(code) { return code === 'F' || code === 'C' ? '#1A1714' : '#F2F0EC'; }

  window.K = { rpc, msg, $, $$, esc, fmtTime, fmtDateTime, toast, busy, P, STAFF, qrSvg, startScanner, toCSV, toXLSX, parseCSV, download, seriesImg, inkFor, sleep, LS };
})();
