"""Browser end-to-end test over the local shim. python3 e2e.py <base_url> <pg_sock> <pg_port> <db> <shot_dir>"""
import asyncio, json, os, subprocess, sys
from playwright.async_api import async_playwright

BASE, SOCK, PGPORT, DB, SHOTS = sys.argv[1:6]
os.makedirs(SHOTS, exist_ok=True)
fails, console_errors = [], []


def db(q):
    r = subprocess.run(['psql', '-h', SOCK, '-p', PGPORT, '-U', 'postgres', '-d', DB, '-At', '-q', '-c', q], capture_output=True, text=True)
    return r.stdout.strip()


def check(name, cond, info=''):
    print(('PASS ' if cond else 'FAIL ') + name + ('' if cond else f'  -> {info}'), flush=True)
    if not cond: fails.append(name)


async def page_in(browser, mobile=True, perms=False):
    ctx = await browser.new_context(viewport={'width': 390, 'height': 844} if mobile else {'width': 1440, 'height': 900},
                                    device_scale_factor=2 if mobile else 1, permissions=['camera'] if perms else [])
    await ctx.route('https://fonts.googleapis.com/**', lambda r: r.fulfill(status=200, body='', content_type='text/css'))
    await ctx.route('https://fonts.gstatic.com/**', lambda r: r.fulfill(status=404, body=''))
    p = await ctx.new_page()
    p.on('console', lambda m: console_errors.append(f'{p.url} :: {m.text}') if m.type == 'error' else None)
    p.on('pageerror', lambda e: console_errors.append(f'{p.url} :: PAGEERROR {e}'))
    p.on('dialog', lambda d: asyncio.ensure_future(d.accept()))
    return ctx, p


async def shot(p, name, full=True):
    await p.wait_for_timeout(350)
    await p.screenshot(path=os.path.join(SHOTS, name + '.png'), full_page=full)


async def main():
    async with async_playwright() as pw:
        b = await pw.chromium.launch(args=['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream'])

        # ---------- admin setup
        actx, a = await page_in(b, mobile=False)
        await a.goto(BASE + '/admin/index.html')
        await a.wait_for_url('**/staff/login.html**')
        check('admin page redirects to login', '/staff/login.html' in a.url)
        await shot(a, '20_staff_login', False)
        await a.fill('#code', 'admin01'); await a.fill('#pin', '111111'); await a.click('#b')
        await a.wait_for_selector('#err:not([hidden])')
        check('wrong PIN shows error', 'ไม่ถูกต้อง' in await a.inner_text('#err'))
        await a.fill('#code', 'admin01'); await a.fill('#pin', '246810'); await a.click('#b')
        await a.wait_for_url('**/admin/index.html')
        await a.wait_for_selector('.kpi')
        check('admin dashboard loads', await a.locator('.kpi').count() == 6)

        await a.goto(BASE + '/admin/settings.html'); await a.wait_for_selector('#staff tr')
        await a.fill('#min_stamp_interval_sec', '0'); await a.click('#sf button[type=submit]')
        await a.wait_for_timeout(500)
        check('settings saved', db('select min_stamp_interval_sec from settings') == '0')
        for code, role in [('STAFF01', 'souvenir'), ('MC01', 'mc')]:
            await a.fill('#t_code', code); await a.fill('#t_name', code + ' name'); await a.select_option('#t_role', role); await a.fill('#t_pin', '135790')
            await a.click('#tf button[type=submit]'); await a.wait_for_timeout(500)
        check('staff created via UI', db("select count(*) from staff where code in ('STAFF01','MC01')") == '2')
        await shot(a, '25_admin_settings', True)

        # prize image + description via admin UI (image is shrunk in-browser and stored as data URL)
        import base64
        pimg = os.path.join(SHOTS, 'prize.png')
        with open(pimg, 'wb') as f:
            f.write(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='))
        await a.goto(BASE + '/admin/draw.html'); await a.wait_for_selector('#prizes [data-id]')
        row1 = a.locator('#prizes [data-id]').filter(has=a.locator('[data-k="rank"] option[value="1"]:checked')).first
        await row1.locator('[data-k="description"]').fill('256GB สี Deep Blue')
        await row1.locator('[data-k="file"]').set_input_files(pimg); await a.wait_for_timeout(600)
        await row1.locator('[data-save]').click(); await a.wait_for_timeout(800)
        check('prize image + description saved from admin', db("select (image like 'data:image/jpeg%') and description = '256GB สี Deep Blue' from prizes where kind='final' and rank=1") == 't')
        await shot(a, '24a_admin_prizes_image', True)

        csv = os.path.join(SHOTS, 'prereg.csv')
        with open(csv, 'w', encoding='utf-8-sig') as f:
            f.write('เบอร์โทร,ชื่อ - นามสกุล,อีเมล,บริษัท,ซีรีส์\n0811111111,สมชาย ใจดี,s@x.com,"บริษัท ก, จำกัด",IKON\n0822222222,สุดา แก้วใส,,,NOVA\nabc,bad,,,\n')
        await a.goto(BASE + '/admin/participants.html'); await a.wait_for_selector('#imp:visible')
        await a.click('#imp'); await a.set_input_files('#file', csv); await a.click('#doImp')
        await a.wait_for_selector('#impRes .lnotice')
        t = await a.inner_text('#impRes')
        check('CSV import (Thai headers, quoted comma) 2 ok 1 skipped', 'สำเร็จ 2' in t and 'ข้ามไป 1' in t, t)
        check('company with comma kept', db("select company from preregistrations where phone='0811111111'") == 'บริษัท ก, จำกัด')

        # ---------- participant: pre-registered
        pctx, p = await page_in(b)
        await p.goto(BASE + '/')
        await shot(p, '01_register', True)
        await p.fill('#phone', '081-111-1111'); await p.click('#submit')
        await p.wait_for_selector('#err:not([hidden])')
        check('consent required message', 'ยินยอม' in await p.inner_text('#err') or 'นโยบาย' in await p.inner_text('#err'))
        await p.check('#consent'); await p.click('#submit')
        await p.wait_for_url('**/passport.html**'); await p.wait_for_selector('#shuffle')
        await p.wait_for_timeout(700); await shot(p, '02a_card_shuffling', False)
        await p.wait_for_timeout(2300); await shot(p, '02b_card_revealed', False)
        await p.wait_for_selector('#shuffle.gone', timeout=5000)
        check('card shuffle reveals then hides', True)
        check('pre-reg ticket number -001 on a random card', '-001' in await p.inner_text('#ticket') and 'SERIES' in await p.inner_text('#ticket'))
        await shot(p, '02_passport_start', True)
        await p.reload(); await p.wait_for_selector('#ticket'); await p.wait_for_timeout(300)
        check('reveal only once', await p.locator('#shuffle').count() == 0)

        # not preregistered -> offer walk-in
        p2ctx, p2 = await page_in(b)
        await p2.goto(BASE + '/'); await p2.fill('#phone', '0899990000'); await p2.check('#consent'); await p2.click('#submit')
        await p2.wait_for_selector('#err button')
        await p2.click('#err button')
        check('switches to walk-in form', await p2.is_visible('#fname'))
        await p2.fill('#fname', 'วิชัย'); await p2.click('#submit'); await p2.wait_for_timeout(300)
        check('walk-in: surname required', 'นามสกุล' in await p2.inner_text('#err'))
        await p2.fill('#lname', 'มีสุข'); await p2.click('#submit'); await p2.wait_for_timeout(300)
        check('walk-in: company required, email optional', 'บริษัท' in await p2.inner_text('#err'))
        await p2.fill('#company', 'ร้านไฟฟ้า')
        await shot(p2, '03_walkin_form', True)
        await p2.click('#submit'); await p2.wait_for_selector('#ticket')
        check('walk-in name stored as "ชื่อ นามสกุล"', db("select name from participants where phone='0899990000'") == 'วิชัย มีสุข')
        # duplicate phone on a fresh device -> asks "is this you?" instead of silently logging in
        p3ctx, p3 = await page_in(b)
        await p3.goto(BASE + '/'); await p3.fill('#phone', '0899990000'); await p3.check('#consent'); await p3.click('#submit')
        await p3.wait_for_selector('#dup:not([hidden])')
        dt = await p3.inner_text('#dup')
        check('duplicate phone asks to confirm with masked name', 'วิชัย ม.' in dt and 'ใช่คุณหรือไม่' in dt, dt)
        await p3.click('#dupNo'); await p3.wait_for_timeout(200)
        check('"not me" clears phone and stays on register', await p3.input_value('#phone') == '' and 'passport' not in p3.url)
        await p3.fill('#phone', '0899990000'); await p3.click('#submit'); await p3.wait_for_selector('#dup:not([hidden])'); await p3.click('#dupYes')
        await p3.wait_for_url('**/passport.html**'); await p3.wait_for_selector('#ticket')
        check('"yes" opens the same card', db("select count(distinct ref_code) from participants where phone='0899990000'") == '1' and '-00' in await p3.inner_text('#ticket'))
        await shot(p3, '03b_duplicate_phone', True)
        t2 = await p2.inner_text('#ticket')
        check('walk-in got a card + ticket', '-00' in t2, t2)

        # bulk registrants so every series has people
        for i in range(25):
            db(f"set role anon; select register_participant('0900000{i:03d}', true, 'ผู้ร่วมงาน ทดสอบ{i}', null, 'บริษัททดสอบ', '{'UIFNC'[i % 5]}', true)")

        # ---------- stamps
        toks = db("select string_agg(qr_token, ' ' order by id) from stations").split()
        await p.goto(BASE + '/s.html?t=' + toks[0]); await p.wait_for_selector('.stamp-big')
        check('stamp success screen', 'ได้รับแสตมป์แล้ว' in await p.inner_text('main'))
        await shot(p, '05_stamp_success', False)
        await p.goto(BASE + '/s.html?t=' + toks[0]); await p.wait_for_selector('.alert-big')
        check('duplicate stamp alert', 'แสตมป์ฐานนี้แล้ว' in await p.inner_text('main'))
        await shot(p, '06_stamp_duplicate', False)
        await p.goto(BASE + '/s.html?t=BADTOKEN123456'); await p.wait_for_selector('.alert-big')
        check('bad QR alert', 'ไม่ถูกต้อง' in await p.inner_text('main'))
        for t in toks[1:5]:   # สแกนฐานถัดไปได้ทันที ไม่ต้องรอ
            await p.goto(BASE + '/s.html?t=' + t); await p.wait_for_selector('.stamp-big')
        check('no waiting between stations', await p.locator('.stamp-big').count() == 1)
        await p.goto(BASE + '/passport.html'); await p.wait_for_selector('.stations')
        check('passport shows 5/6', '5' in await p.inner_text('#jt + span') if await p.locator('#jt + span').count() else True)
        await shot(p, '04_passport_progress', True)

        # last stamp opened from native camera in another browser (no token) -> recovery by phone
        rctx, r = await page_in(b)
        await r.goto(BASE + '/s.html?t=' + toks[5]); await r.wait_for_selector('#rf')
        await shot(r, '07_stamp_recover', False)
        await r.fill('#ph', '0811111111'); await r.click('#rb'); await r.wait_for_selector('#dupYes')
        check('station recovery asks to confirm identity', 'สมชาย ใ.' in await r.inner_text('#rerr'), await r.inner_text('#rerr'))
        await r.click('#dupYes'); await r.wait_for_selector('.stamp-big')
        check('recovery by phone collects last stamp + complete', 'ครบทุกฐาน' in await r.inner_text('main'))
        await p.goto(BASE + '/passport.html'); await p.wait_for_selector('.pass svg')
        check('complete passport shows souvenir QR', await p.locator('.pass svg').count() == 1)
        await shot(p, '08_passport_complete', True)

        # scan page loads with fake camera
        sctx, s = await page_in(b, perms=True)
        await s.goto(BASE + '/'); await s.evaluate("localStorage.setItem('kliq_pt', 'x')")
        await s.goto(BASE + '/scan.html'); await s.wait_for_timeout(1500)
        check('scan page camera starts', await s.evaluate("!!document.querySelector('#v').srcObject"))

        # ---------- souvenir staff
        ref = db("select ref_code from participants where phone='0811111111'")
        ws_ctx, w = await page_in(b)
        await w.goto(BASE + '/staff/login.html'); await w.fill('#code', 'STAFF01'); await w.fill('#pin', '135790'); await w.click('#b')
        await w.wait_for_url('**/staff/souvenir.html'); await w.wait_for_selector('#q')
        await w.fill('#q', '0822222222'); await w.click('#sf button'); await w.wait_for_selector('#result .lnotice')
        check('lookup prereg not yet registered -> tells staff to register first', 'ยังไม่ได้กดลงทะเบียน' in await w.inner_text('#result'))
        # คนที่ไม่ได้เล่น → ของทั่วไป
        noplay = db("select ref_code from participants where phone='0900000003'")
        await w.fill('#q', noplay); await w.click('#sf button'); await w.wait_for_selector('#give')
        check('no-play participant: basic tier shown', await w.locator('.tier.basic').count() == 1 and 'ของที่ระลึกทั่วไป' in await w.inner_text('#give'))
        await shot(w, '09a_staff_souvenir_basic', True)
        await w.click('#give'); await w.wait_for_timeout(900)
        check('basic souvenir redeemed', db(f"select souvenir_tier from participants where ref_code='{noplay}'") == 'basic')
        # คนที่เล่นครบ → ของพิเศษ
        await w.fill('#q', ref); await w.click('#sf button'); await w.wait_for_selector('#give')
        check('completed participant: premium tier shown', await w.locator('.tier.prem').count() == 1 and 'พิเศษ' in await w.inner_text('#give'))
        await shot(w, '09_staff_souvenir_ready', True)
        await w.click('#give'); await w.wait_for_timeout(900)
        check('souvenir redeemed', 'ไปแล้ว' in await w.inner_text('#result') and db(f"select souvenir_tier from participants where ref_code='{ref}'") == 'premium')
        await shot(w, '10_staff_souvenir_done', True)
        await w.goto(BASE + '/admin/stations.html'); await w.wait_for_timeout(800)
        check('souvenir staff blocked from admin stations', '/staff/souvenir.html' in w.url, w.url)

        # ---------- station staff (phone page with the station QR + live count)
        db("insert into staff (code, display_name, role, pin_hash, station_id) values ('ST01', 'พี่บี', 'station', extensions.crypt('135790', extensions.gen_salt('bf')), 1)")
        stx, sp = await page_in(b)
        await sp.goto(BASE + '/staff/login.html'); await sp.fill('#code', 'ST01'); await sp.fill('#pin', '135790'); await sp.click('#b')
        await sp.wait_for_url('**/staff/station.html'); await sp.wait_for_selector('#qr svg')
        check('station staff lands on station page with QR + count', 'LUMENCRAFT' in await sp.inner_text('#stName') and (await sp.inner_text('#cnt')).strip() == db("select count(*) from stamps where station_id = 1"))
        await shot(sp, '27_station_staff', True)
        await sp.click('#full'); await sp.wait_for_selector('#big svg'); check('fullscreen QR shown', await sp.locator('#big svg').count() == 1)
        await sp.goto(BASE + '/admin/index.html'); await sp.wait_for_timeout(800)
        check('station staff blocked from admin', '/staff/station.html' in sp.url, sp.url)
        lp = await page_in(b); await lp[1].goto(BASE + '/'); check('register page has small staff link', await lp[1].locator('a[href="/staff/login.html"]').count() == 1)

        # ---------- MC stage
        mctx, m = await page_in(b, mobile=False)
        await m.goto(BASE + '/staff/login.html'); await m.fill('#code', 'MC01'); await m.fill('#pin', '135790'); await m.click('#b')
        await m.wait_for_url('**/stage/index.html'); await m.wait_for_selector('#list a')
        await shot(m, '11_stage_menu', False)
        await m.click('#list a >> nth=0'); await m.wait_for_url('**/stage/final.html'); await m.wait_for_selector('#go:not([disabled])')
        await m.wait_for_selector('#intro:not([hidden]) #iqr svg')
        check('stage opens with big QR intro (scan to get your card back)', await m.locator('#iqr svg').count() == 1 and 'สแกน' in await m.inner_text('#intro'))
        await shot(m, '12a_stage_qr_intro', False)
        await m.click('#introGo'); await m.wait_for_timeout(300)
        check('intro closes on ไปต่อ', await m.locator('#intro').is_hidden())
        await shot(m, '12_final_ready', False)
        ready = lambda: m.wait_for_selector('#go:not([disabled])', timeout=40000)
        await m.click('#go'); await ready()
        check('final: 5 cards face down', await m.locator('.scard').count() == 5 and await m.locator('.scard.out').count() == 0 and 'เปิดการ์ดใบที่ 1' in await m.inner_text('#go'))
        for i in range(5):
            await m.keyboard.press('Space'); await m.wait_for_timeout(2500)
            if i == 0: await shot(m, '13a_final_roulette', False)
            await m.wait_for_timeout(5500); await m.keyboard.press('Space')   # ข้ามช่วงค้าง 15 วิ (รอให้ไฟวิ่งหยุดก่อน)
            await ready()
            exp_out, exp_in = [1, 1, 1, 2, 2][i], [0, 1, 2, 2, 3][i]
            check(f'final: card {i + 1} opened -> OUT {exp_out} / IN {exp_in}', await m.locator('.scard.out').count() == exp_out and await m.locator('.scard.in').count() == exp_in)
            if i == 2: await shot(m, '13_final_cards_mid', False)
        check('final: ladder (4 prizes) + wheel shown, reveal rank-3 card next', await m.locator('#wheel').count() == 1 and await m.locator('.lad').count() == 4 and 'เปิดการ์ดรางวัลที่ 3 (ชิ้นที่ 1/2)' in await m.inner_text('#go') and await m.locator('.scard.ranked').count() == 0)
        await m.click('#go'); await m.wait_for_timeout(7500); await m.keyboard.press('Space'); await ready()   # เปิดการ์ดรางวัลที่ 3
        card3 = await m.get_attribute('.scard.pick', 'data-code')
        check('final: rank-3 card revealed = one of the IN cards', await m.locator('.scard.ranked').count() == 1 and await m.locator(f'.scard.in.ranked[data-code="{card3}"]').count() == 1 and 'หมุนวงล้อ' in await m.inner_text('#go'))
        await shot(m, '14a_final_wheel_ready', False)
        # หมุนรางวัลที่ 3 ชิ้นที่ 1 → ไม่อยู่ → หมุนใหม่ → อยู่ → ชิ้นที่ 2 → อยู่
        await m.click('#go'); await m.wait_for_timeout(3500); await shot(m, '14b_final_wheel_spinning', False)
        await m.wait_for_selector('#yes', timeout=20000); await shot(m, '14c_final_winner_popup', False)
        first = await m.inner_text('.mbox .tk')
        check('final: popup shows ticket from the rank-3 card + countdown', first.startswith(card3 + '-') and (await m.inner_text('#cd')).strip().isdigit())
        ctok = db(f"select token from participants where ticket_no = '{first}'")
        cctx, cp = await page_in(b)
        await cp.goto(BASE + '/'); await cp.evaluate(f"localStorage.setItem('kliq_pt', '{ctok}')")
        await cp.goto(BASE + '/passport.html'); await cp.wait_for_selector('.win')
        check('called person sees stage call on phone', 'ขึ้นเวที' in await cp.inner_text('.win'))
        await shot(cp, '14d_passport_called', True)
        await m.keyboard.press('n'); await m.wait_for_timeout(2200); await ready()
        p3a = db("select id from prizes where kind='final' and rank=3 order by id limit 1")
        check('final: no-show recorded, rank 3 #1 still open', await m.locator('.noshow').count() == 1 and first in await m.inner_text('.noshow') and await m.locator(f'.lad.now[data-prize="{p3a}"]').count() == 1)
        await m.click('#go'); await m.wait_for_selector('#yes', timeout=20000)
        second = await m.inner_text('.mbox .tk')
        check('final: re-spin picked a different person', second != first)
        await m.keyboard.press('Enter'); await m.wait_for_timeout(3800); await ready()
        check('final: rank 3 #1 awarded, #2 next on same card', await m.locator(f'.lad.won[data-prize="{p3a}"]').count() == 1 and 'รางวัลที่ 3 (ชิ้นที่ 2/2)' in await m.inner_text('#go') and await m.get_attribute('.scard.pick', 'data-code') == card3)
        await m.click('#go'); await m.wait_for_selector('#yes', timeout=20000)
        third = await m.inner_text('.mbox .tk')
        check('final: rank 3 #2 = third person from same card', third not in (first, second) and third.startswith(card3 + '-'))
        await shot(m, '14e_final_rank3b_popup', False)
        await m.keyboard.press('Enter'); await m.wait_for_timeout(3800); await ready()
        for rank in (2, 1):
            check(f'final: rank {rank} needs card reveal first', 'เปิดการ์ดรางวัลที่ ' + str(rank) in await m.inner_text('#go'))
            await m.click('#go'); await m.wait_for_timeout(7500 if rank == 2 else 1500)
            if rank == 2: await m.keyboard.press('Space')   # ปล่อยช่วงค้าง (ใบสุดท้ายไม่มีช่วงค้าง)
            await ready()
            check(f'final: rank {rank} card = another IN card', await m.locator('.scard.in.ranked.pick').count() == 1 and await m.get_attribute('.scard.pick', 'data-code') != card3 and await m.locator('.scard.ranked').count() == 4 - rank, (await m.get_attribute('.scard.pick', 'data-code'), await m.locator('.scard.ranked').count(), await m.inner_text('#go')))
            await m.click('#go'); await m.wait_for_selector('#yes', timeout=20000)
            await shot(m, f'14e_final_rank{rank}_popup', False)
            if rank == 1: check('rank 1 popup shows prize image + description', await m.locator('.mbox .mi').count() == 1 and 'Deep Blue' in await m.inner_text('.mbox .pd'))
            await m.click('#yes'); await m.wait_for_timeout(5600); await ready() if rank == 2 else m.wait_for_timeout(200)
        check('final: 4 winners on 3 different cards, button finished', await m.locator('.lad.won').count() == 4 and await m.is_disabled('#go') and db("select count(distinct p.series_code) from draw_results r join participants p on p.id=r.participant_id join prizes z on z.id=r.prize_id where z.kind='final' and not r.voided") == '3')
        await shot(m, '14f_final_done', False)
        await m.goto(BASE + '/stage/index.html'); await m.wait_for_selector('#list a')
        check('stage menu shows only the grand final', await m.locator('#list a').count() == 2 and 'ประกาศผลแล้ว' in await m.inner_text('#list'))
        await shot(m, '15_stage_menu', False)

        # winner sees banner
        wtok = db("select p.token from draw_results r join participants p on p.id=r.participant_id join prizes z on z.id=r.prize_id where z.kind='final' and z.rank=1 and not r.voided")
        wctx, wp = await page_in(b)
        await wp.goto(BASE + '/'); await wp.evaluate(f"localStorage.setItem('kliq_pt', '{wtok}')")
        await wp.goto(BASE + '/passport.html'); await wp.wait_for_selector('.win')
        check('winner sees banner on phone', 'iPhone 18 Pro Max' in await wp.inner_text('.win') and await wp.locator('.win img').count() == 1)
        await shot(wp, '16_passport_winner', True)
        check('winner passport shows QR for pickup', await wp.locator('.win svg').count() == 1)
        wref = db("select p.ref_code from draw_results r join participants p on p.id=r.participant_id join prizes z on z.id=r.prize_id where z.kind='final' and z.rank=1 and not r.voided")
        # pickup point: staff looks up winner -> handover button -> confirmed
        await w.fill('#q', wref); await w.click('#sf button'); await w.wait_for_selector('#handover')
        check('pickup point shows winner prize block', 'iPhone 18 Pro Max' in await w.inner_text('#handover'))
        await shot(w, '16b_staff_prize_handover', True)
        await w.click('#handover'); await w.wait_for_timeout(1000)
        check('handover recorded with staff', db(f"select count(*) from draw_results r join participants p on p.id=r.participant_id where p.ref_code='{wref}' and r.received_at is not null and r.received_by is not null") == '1')
        check('pickup page now shows received', 'มอบรางวัลแล้ว' in await w.inner_text('#result') and await w.locator('#handover').count() == 0)
        await wp.reload(); await wp.wait_for_selector('.win')
        check('winner passport shows received badge', 'รับรางวัลแล้ว' in await wp.inner_text('.win') and await wp.locator('.win svg').count() == 0)

        # ---------- admin pages
        for name, path, sel in [('21_admin_dashboard', '/admin/index.html', '.kpi'), ('22_admin_participants', '/admin/participants.html', '#rows tr td'),
                                ('23_admin_stations', '/admin/stations.html', '.qrcard'), ('24_admin_draw', '/admin/draw.html', '#res tr'),
                                ('26_admin_souvenir', '/admin/souvenir.html', '.kpi')]:
            await a.goto(BASE + path); await a.wait_for_selector(sel); await shot(a, name, True)
        await a.goto(BASE + '/admin/stations.html'); await a.wait_for_selector('.qrcard svg')
        check('stations page renders 7 QR codes', await a.locator('.qrcard svg').count() == 7)
        await a.goto(BASE + '/admin/participants.html'); await a.wait_for_function("document.querySelector('#total').textContent.indexOf('พบ') >= 0")
        check('participants list shows 27', '27' in await a.inner_text('#total'), await a.inner_text('#total'))
        # admin edits a participant's name/phone from the list
        await a.fill('#q', 'วิชัย'); await a.wait_for_timeout(600)
        await a.click('#rows tr[data-i] [data-ed]'); await a.wait_for_selector('#edit:not([hidden])')
        await a.fill('#edLname', 'แก้ไขแล้ว'); await a.fill('#edPhone', '0899990099'); await a.click('#edSave')
        await a.wait_for_selector('#edit[hidden]', state='attached'); await a.wait_for_timeout(500)
        check('admin edit participant persisted', db("select count(*) from participants where phone='0899990099' and name like '% แก้ไขแล้ว'") == '1')
        await shot(a, '22b_admin_edit', True)
        # admin deletes a participant from the modal (dialogs auto-accepted)
        db("set role anon; select register_participant('0899990055', true, 'ลบ ทิ้ง', null, 'Co', 'U', true)")
        await a.fill('#q', '0899990055'); await a.wait_for_timeout(700)
        await a.click('#rows tr[data-i] [data-ed]'); await a.wait_for_selector('#edit:not([hidden])')
        check('delete button shown for participant', 'ลบผู้ร่วมงาน' in await a.inner_text('#edDel'))
        await a.click('#edDel'); await a.wait_for_timeout(900)
        check('admin delete participant removed from DB', db("select count(*) from participants where phone='0899990055'") == '0')
        await a.fill('#q', ''); await a.wait_for_timeout(600)
        async with a.expect_download() as dl:
            await a.click('#exp')
        d = await dl.value; path = await d.path(); content = open(path, encoding='utf-8-sig').read()
        check('export CSV has header + 27 rows', len(content.strip().splitlines()) == 28, len(content.strip().splitlines()))
        await a.goto(BASE + '/admin/draw.html'); await a.wait_for_selector('[data-void]')
        rid = db("select r.id from draw_results r join prizes z on z.id = r.prize_id where z.kind = 'final' and z.rank = 1")
        await a.click(f'[data-void="{rid}"]'); await a.wait_for_selector('[data-replace="1"]')
        check('void from admin', db("select count(*) from draw_results where voided and void_reason = 'admin'") == '1')
        left = int(db("select count(*) from participants p where p.series_code = (select series_order[5] from final_draws order by id desc limit 1) and not exists (select 1 from draw_results r where r.participant_id = p.id)"))
        await a.click('[data-replace="1"]'); await a.wait_for_timeout(900)
        got = db("select count(*) from draw_results r join prizes z on z.id=r.prize_id where z.rank=1 and not r.voided")
        check('replace rank 1 from same card (or none left)', got == ('1' if left > 0 else '0'), (left, got))
        await shot(a, '24b_admin_draw_replaced', True)
        await a.goto(BASE + '/collection.html'); await shot(a, '17_collection', True)

        uniq = sorted(set(e for e in console_errors if 'favicon' not in e and 'fonts.g' not in e and '404' not in e))
        check('no JS errors in console', not uniq, uniq[:8])
        await b.close()
    print('\nRESULT:', 'ALL PASS' if not fails else f'{len(fails)} FAILED: {fails}')


asyncio.run(main())
