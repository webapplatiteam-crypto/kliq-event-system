"""ทดสอบฟังก์ชันฐานข้อมูลทั้งหมดในบทบาท anon (เหมือนเว็บจริงเรียกผ่าน Supabase)
ใช้: python3 db_test.py <socket_dir> <port> <db>
"""
import json, subprocess, sys, concurrent.futures as cf

SOCK, PORT, DB = sys.argv[1], sys.argv[2], sys.argv[3]
fails = []


def sql(q, role='anon'):
    pre = f'set role {role}; ' if role else ''
    r = subprocess.run(['psql', '-h', SOCK, '-p', PORT, '-U', 'postgres', '-d', DB, '-At', '-q', '-c', pre + q],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return {'_error': r.stderr.strip()}
    out = r.stdout.strip()
    try:
        return json.loads(out)
    except Exception:
        return out


def lit(v):
    if v is None:
        return 'null'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, (dict, list)):
        return "'" + json.dumps(v, ensure_ascii=False).replace("'", "''") + "'::jsonb"
    return "'" + str(v).replace("'", "''") + "'"


def rpc(fn, *args, role='anon'):
    return sql(f"select {fn}({', '.join(lit(a) for a in args)})", role)


def check(name, cond, info=''):
    print(('PASS ' if cond else 'FAIL ') + name + ('' if cond else f'  -> {info}'))
    if not cond:
        fails.append(name)


# --- ตาราง ห้าม anon เข้าตรง
r = sql('select * from participants limit 1')
check('anon cannot read tables directly', isinstance(r, dict) and 'permission denied' in r.get('_error', ''), r)
r = sql("select _rand_token(8)")
check('anon cannot call internal helpers', isinstance(r, dict) and '_error' in r, r)

# --- staff login
bad = rpc('staff_login', 'ADMIN01', '111111')
check('wrong PIN rejected', bad.get('code') == 'BAD_LOGIN', bad)
adm = rpc('staff_login', 'admin01', '246810')
check('admin login ok (case-insensitive code)', adm.get('ok') and adm.get('role') == 'admin', adm)
A = adm['token']

# create staff
for code, role in [('STAFF01', 'souvenir'), ('MC01', 'mc'), ('REG01', 'register')]:
    r = rpc('admin_staff_save', A, code, code, role, '135790', True)
    check(f'create staff {code}', r.get('ok'), r)
check('bad PIN format rejected', rpc('admin_staff_save', A, 'X01', 'x', 'mc', '12', True).get('code') == 'BAD_PIN')
check('admin cannot demote self', rpc('admin_staff_save', A, 'ADMIN01', 'x', 'mc', None, True).get('code') == 'SELF_LOCKOUT')
SV = rpc('staff_login', 'STAFF01', '135790')['token']
MC = rpc('staff_login', 'MC01', '135790')['token']
check('souvenir staff cannot use admin functions', rpc('admin_stations', SV).get('code') == 'AUTH')
check('mc cannot import', rpc('admin_import_prereg', MC, [], False).get('code') == 'AUTH')
check('bad token rejected', rpc('admin_stats', 'nope').get('code') == 'AUTH')

# station staff: bound to one station, sees its QR + count
check('station role needs a station', rpc('admin_staff_save', A, 'ST01', 'พี่บี', 'station', '135790', True, None).get('code') == 'NEED_STATION')
check('create station staff', rpc('admin_staff_save', A, 'ST01', 'พี่บี', 'station', '135790', True, 2).get('ok'))
sl = rpc('staff_login', 'ST01', '135790')
check('station login carries station_id', sl.get('ok') and sl['role'] == 'station' and sl['station_id'] == 2, sl)
ST = sl['token']
sm = rpc('station_me', ST)
check('station_me returns own station + qr token', sm.get('ok') and sm['id'] == 2 and sm['qr_token'] and sm['count'] == 0 and sm['staff'] == 'พี่บี', sm)
check('station staff cannot use admin / souvenir functions', rpc('admin_stations', ST).get('code') == 'AUTH' and rpc('souvenir_lookup', ST, 'x').get('code') == 'AUTH')
check('staff list shows station name', [x for x in rpc('admin_staff_list', A)['rows'] if x['code'] == 'ST01'][0]['station_name'] == 'LIGHTING SOLUTION')
check('admin can view any station via station_me', rpc('station_me', A, 3).get('name') == 'KLIQ ROOM EXPERIENCE')

# lockout after 5 fails
for _ in range(5):
    rpc('staff_login', 'REG01', '000001')
lk = rpc('staff_login', 'REG01', '135790')
check('lockout after 5 wrong PINs', lk.get('code') == 'LOCKED', lk)
rpc('admin_staff_save', A, 'REG01', 'REG01', 'register', None, True)  # admin unlocks
check('admin unlock works', rpc('staff_login', 'REG01', '135790').get('ok'))

# --- settings: 400 คน ซีรีส์ละ 80, interval 0 สำหรับทดสอบก่อน
check('settings save', rpc('admin_settings_save', A, {'max_participants': 400, 'series_quota': 80, 'min_stamp_interval_sec': 0}).get('ok'))

# --- pre-registration import
rows = [{'phone': f'08{i:08d}', 'name': f'Pre User {i}', 'email': f'p{i}@x.com', 'company': 'Co', 'series': 'IKON'} for i in range(1, 51)]
rows.append({'phone': '123', 'name': 'bad'})
imp = rpc('admin_import_prereg', A, rows, False)
check('import prereg 50 ok, 1 rejected', imp.get('imported') == 50 and len(imp.get('rejected', [])) == 1, imp)

# --- registration
check('bad phone', rpc('register_participant', 'abc', False, None, None, None, None, True).get('code') == 'BAD_PHONE')
check('needs consent', rpc('register_participant', '0800000001', False, None, None, None, None, False).get('code') == 'NEED_CONSENT')
check('not preregistered', rpc('register_participant', '0899999999', False, None, None, None, None, True).get('code') == 'NOT_PREREGISTERED')
check('walk-in needs name', rpc('register_participant', '0899999999', True, '', None, None, None, True).get('code') == 'NEED_NAME')
check('walk-in needs company', rpc('register_participant', '0899999999', True, 'สมชาย ใจดี', None, '', None, True).get('code') == 'NEED_COMPANY')
p1 = rpc('register_participant', '+66 80-000-0001', False, None, None, None, None, True)
check('pre-registered by phone (+66 format), random card, ticket matches card', p1.get('ok') and p1['participant']['ticket_no'] == p1['participant']['series_code'] + '-001', p1)
again = rpc('register_participant', '0800000001', False, None, None, None, None, True)
check('same phone returns same token', again.get('existing') and again['token'] == p1['token'], again)
T1 = p1['token']


# 399 more registrations in parallel (stress the lock)
def reg(i):
    return rpc('register_participant', f'09{i:08d}', True, f'Walk In {i}', None, 'บริษัททดสอบ', ['U', 'I', 'F', 'N', 'C'][i % 5] if i % 7 else 'U', True)


with cf.ThreadPoolExecutor(max_workers=24) as ex:
    res = list(ex.map(reg, range(1, 400)))
oks = [r for r in res if isinstance(r, dict) and r.get('ok')]
check('400 total registrations succeed concurrently', len(oks) == 399, [r for r in res if not (isinstance(r, dict) and r.get('ok'))][:3])
cnt = sql('select count(*) from participants', role=None)
check('participant count = 400', str(cnt) == '400', cnt)
dup = sql('select count(*) - count(distinct ticket_no) from participants', role=None)
check('ticket numbers unique', str(dup) == '0', dup)
per = sql("select json_object_agg(series_code, c) from (select series_code, count(*) c from participants group by 1) x", role=None)
check('no series over quota 80, all 5 cards used', all(v <= 80 for v in per.values()) and len(per) == 5, per)
mism = sql("select count(*) from participants where left(ticket_no, 1) <> series_code", role=None)
check('every ticket prefix matches its card', str(mism) == '0', mism)
full = rpc('register_participant', '0811111111', True, 'Late', None, 'Co', None, True)
check('401st gets FULL', full.get('code') == 'FULL', full)
check('existing user still re-enters when full', rpc('register_participant', '0800000001', False, None, None, None, None, True).get('ok'))

# --- passport + stamps
pp = rpc('get_passport', T1)
check('passport has 6 stations', pp.get('ok') and len(pp['stamps']) == 6, pp)
st = rpc('admin_stations', A)['rows']
toks = [s['qr_token'] for s in st]
check('bad station token', rpc('collect_stamp', T1, 'zzz').get('code') == 'BAD_STATION')
check('bad participant token', rpc('collect_stamp', 'zzz', toks[0]).get('code') == 'NO_PARTICIPANT')
r = rpc('collect_stamp', T1, toks[0])
check('stamp 1 ok', r.get('ok') and r['done'] == 1, r)
check('duplicate stamp rejected', rpc('collect_stamp', T1, toks[0]).get('code') == 'ALREADY')
rpc('admin_settings_save', A, {'min_stamp_interval_sec': 180})
ts = rpc('collect_stamp', T1, toks[1])
check('too soon rejected with wait time', ts.get('code') == 'TOO_SOON' and 170 <= ts['wait_sec'] <= 180, ts)
rpc('admin_settings_save', A, {'min_stamp_interval_sec': 0})
lu0 = rpc('souvenir_lookup', SV, p1['participant']['ref_code'])
check('before complete: lookup says basic tier, can redeem', lu0.get('ok') and lu0['tier_now'] == 'basic' and lu0['can_redeem'] and not lu0['upgrade'] and lu0['tier_name'] == 'ของที่ระลึกทั่วไป', lu0)
# คนที่ไม่เล่นเลยก็รับของทั่วไปได้
w0 = oks[2]; w0ref = w0['participant']['ref_code']
r0 = rpc('souvenir_redeem', SV, w0ref)
check('no-play participant gets basic souvenir', r0.get('ok') and r0['tier'] == 'basic' and not r0['upgraded'], r0)
check('basic redeemed twice blocked', rpc('souvenir_redeem', SV, w0ref).get('code') == 'ALREADY_REDEEMED')
# p1 รับแบบทั่วไปก่อน แล้วค่อยเล่นครบ → อัปเกรดได้
r1b = rpc('souvenir_redeem', SV, p1['participant']['ref_code'])
check('p1 gets basic before completing', r1b.get('ok') and r1b['tier'] == 'basic', r1b)
for t in toks[1:]:
    r = rpc('collect_stamp', T1, t)
check('6/6 completes passport', r.get('completed') and r['done'] == 6, r)
check('completed_at set', rpc('get_passport', T1)['participant']['completed_at'] is not None)

# deactivate a station -> 5 stations needed
rpc('admin_station_save', A, 6, 'LiTon', False, False)
T2 = oks[0]['token']
for t in toks[:5]:
    r = rpc('collect_stamp', T2, t)
check('inactive station not required (5/5 completes)', r.get('completed') and r['total'] == 5, r)
check('inactive station QR rejected', rpc('collect_stamp', T2, toks[5]).get('code') == 'BAD_STATION')
rpc('admin_station_save', A, 6, 'LiTon', True, False)
old = toks[0]
rpc('admin_station_save', A, 1, 'ฐาน KLIQ', True, True)
check('rotated QR: old token invalid', rpc('collect_stamp', oks[1]['token'], old).get('code') == 'BAD_STATION')

# --- souvenir
ref = p1['participant']['ref_code']
lu = rpc('souvenir_lookup', SV, 'KLIQ:' + ref)
check('lookup by QR payload', lu.get('ok') and lu['participant']['ref_code'] == ref, lu)
check('lookup by phone', rpc('souvenir_lookup', SV, '080-000-0001').get('ok'))
check('lookup prereg not yet registered → NOT_REGISTERED', rpc('souvenir_lookup', SV, '080-000-0002').get('code') == 'NOT_REGISTERED')
check('lookup unknown → NOT_FOUND', rpc('souvenir_lookup', SV, '0999999999').get('code') == 'NOT_FOUND')
check('lookup by ticket', rpc('souvenir_lookup', SV, p1['participant']['ticket_no']).get('ok'))
check('after complete: lookup shows premium + upgrade available', lu['tier_now'] == 'premium' and lu['upgrade'] and lu['can_redeem'] and lu['participant']['souvenir_tier'] == 'basic', {k: lu.get(k) for k in ['tier_now', 'upgrade', 'can_redeem']})
up = rpc('souvenir_redeem', SV, ref)
check('upgrade to premium ok', up.get('ok') and up['tier'] == 'premium' and up['upgraded'], up)
again = rpc('souvenir_redeem', SV, ref)
check('double redeem blocked after premium', again.get('code') == 'ALREADY_REDEEMED' and again.get('by') == 'STAFF01' and again.get('tier') == 'premium', again)
lu2 = rpc('souvenir_lookup', SV, ref)
check('lookup after premium: no upgrade, counts by tier', not lu2['can_redeem'] and not lu2['upgrade'] and lu2['given_premium'] == 1 and lu2['given_basic'] == 1, lu2)
check('passport shows premium tier + upgraded time', rpc('get_passport', T1)['participant']['souvenir_tier'] == 'premium' and rpc('get_passport', T1)['participant']['souvenir_upgraded_at'])
check('settings carry souvenir names + 30s default', rpc('event_info')['souvenir_premium_name'] == 'ของที่ระลึกพิเศษ (เล่นครบทุกฐาน)' and rpc('admin_stats', A)['settings']['final_claim_sec'] == 30)
check('rename souvenirs', rpc('admin_settings_save', A, {'souvenir_basic_name': 'พวงกุญแจ KLIQ', 'souvenir_premium_name': 'กระเป๋าผ้า KLIQ'}).get('ok') and rpc('souvenir_lookup', SV, ref)['premium_name'] == 'กระเป๋าผ้า KLIQ')
check('MC cannot redeem', rpc('souvenir_redeem', MC, ref).get('code') == 'AUTH')

# --- stats / list / export
stt = rpc('admin_stats', A)
check('stats numbers', stt['registered'] == 400 and stt['completed'] == 2 and stt['souvenir'] == 2 and stt['souvenir_premium'] == 1 and stt['souvenir_basic'] == 1, {k: stt.get(k) for k in ['registered', 'completed', 'souvenir', 'souvenir_basic', 'souvenir_premium']})
lst = rpc('admin_participants', A, 'pre user 1', 'all', 20, 0)
check('participant search', lst.get('ok') and lst['total'] >= 1, lst.get('total'))
check('filter waiting souvenir', rpc('admin_participants', A, '', 'waiting', 50, 0)['total'] == 1)
check('register role can list', rpc('admin_participants', rpc('staff_login', 'REG01', '135790')['token'], '', 'all', 5, 0).get('ok'))
ex = rpc('admin_export', A)
check('export 400 rows', len(ex['rows']) == 400)

# --- final draw v3: open 5 cards OUT/IN/IN/OUT/IN (random which), IN cards = rank 3/2/1, wheel per prize (rank 3 has 2 prizes)
pr = rpc('admin_prizes', MC)['rows']
fin = [p for p in pr if p['kind'] == 'final']
finals = {p['rank']: p for p in sorted(fin, key=lambda p: p['id'])}      # last prize per rank (rank 3 -> KEF)
first3 = [p for p in fin if p['rank'] == 3][0]
check('4 final prizes seeded (rank 1,2,3,3)', sorted(p['rank'] for p in fin) == [1, 2, 3, 3], pr)
check('same rank twice allowed', rpc('admin_prize_save', A, None, 'X', 'final', 1, 0, 2).get('ok'))
xid = [p for p in rpc('admin_prizes', MC)['rows'] if p['name'] == 'X'][0]['id']
sql(f"delete from prizes where id = {xid}", role=None)
check('normal prize added', rpc('admin_prize_save', A, None, 'ลำโพง', 'normal', 2, 5, None).get('ok'))
IMG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='
check('prize image + description saved', rpc('admin_prize_save', A, finals[1]['id'], 'iPhone 18 Pro Max', 'final', 1, 0, 1, '256GB สี Deep Blue', IMG).get('ok'))
check('bad image rejected', rpc('admin_prize_save', A, finals[1]['id'], 'iPhone 18 Pro Max', 'final', 1, 0, 1, None, 'http://x/y.png').get('code') == 'BAD_IMAGE')
z1 = [p for p in rpc('admin_prizes', MC)['rows'] if p['rank'] == 1][0]
check('admin_prizes returns image/description', z1['image'] == IMG and z1['description'] == '256GB สี Deep Blue', z1)
check('name-only save keeps image', rpc('admin_prize_save', A, finals[1]['id'], 'iPhone 18 Pro Max', 'final', 1, 0, 1).get('ok') and [p for p in rpc('admin_prizes', MC)['rows'] if p['rank'] == 1][0]['image'] == IMG)
check('passport shows grand prize with image', rpc('get_passport', T1)['grand']['image'] == IMG)
check('image removed with empty string', rpc('admin_prize_save', A, finals[1]['id'], 'iPhone 18 Pro Max', 'final', 1, 0, 1, None, '').get('ok') and [p for p in rpc('admin_prizes', MC)['rows'] if p['rank'] == 1][0]['image'] is None)
check('re-add image for stage test', rpc('admin_prize_save', A, finals[1]['id'], 'iPhone 18 Pro Max', 'final', 1, 0, 1, None, IMG).get('ok'))
normal = [p for p in rpc('admin_prizes', MC)['rows'] if p['kind'] == 'normal'][0]['id']
st0 = rpc('final_state', MC)
check('no final draw yet', st0.get('ok') and st0['draw'] is None and len(st0['prizes']) == 4 and st0['claim_sec'] == 30, st0)
check('final_state prizes carry image', [p for p in st0['prizes'] if p['rank'] == 1][0]['image'] == IMG)
# locked order = open order: pos1 OUT, pos2 IN(rank 3), pos3 IN(rank 2), pos4 OUT, pos5 IN(rank 1)
check('lock card order', rpc('admin_settings_save', A, {'final_order': ['U', 'I', 'F', 'N', 'C']}).get('ok') and rpc('admin_stats', A)['settings']['final_order'] == ['U', 'I', 'F', 'N', 'C'])
check('bad lock (4 items) ignored', rpc('admin_settings_save', A, {'final_order': ['U', 'N', 'I', 'F']}).get('ok') and rpc('admin_stats', A)['settings']['final_order'] is None)
check('lock again', rpc('admin_settings_save', A, {'final_order': ['U', 'I', 'F', 'N', 'C']}).get('ok'))
f = rpc('final_create', MC)['draw']
check('final created: 5 cards face down, phase cut', f['step'] == 0 and f['cuts'] == 5 and f['phase'] == 'cut' and len(f['series']) == 5 and not any(x['out'] or x['in'] or x['rank'] for x in f['series']) and f['next_rank'] == 3 and f['next_card'] is None, f)
check('next prize = first rank-3 prize (1 of 2)', f['next_prize']['rank'] == 3 and f['next_prize']['seq'] == 1 and f['next_prize']['of'] == 2 and f['next_prize']['id'] == first3['id'], f['next_prize'])
again = rpc('final_create', MC)['draw']
check('create again returns same in-progress draw', again['id'] == f['id'])
check('claim before spin rejected', rpc('final_claim', MC, f['id'], True).get('code') == 'NO_PENDING')
expect = [('U', 'out'), ('I', 'in'), ('F', 'in'), ('N', 'out'), ('C', 'in')]
for i, (code, kind) in enumerate(expect, 1):
    f = rpc('final_next', MC, f['id'])['draw']
    c = [x for x in f['series'] if x['code'] == code][0]
    check(f'open card {i}: {code} is {kind.upper()}, no rank yet', f['step'] == i and c['out'] == (kind == 'out') and c['in'] == (kind == 'in') and c['rank'] is None and c['pos'] == i, f['series'])
    check(f'after card {i}: phase ' + ('cut' if i < 5 else 'reveal'), f['phase'] == ('cut' if i < 5 else 'reveal'))
check('outs not adjacent: cards 1 and 4; 3 IN unranked', [x['code'] for x in f['series'] if x['out']] == ['U', 'N'] and [x['code'] for x in f['series'] if x['in']] == ['I', 'F', 'C'] and not any(x['rank'] for x in f['series']))
check('reveal phase: rank 3 next, card hidden, no pool', f['next_rank'] == 3 and f['next_card'] is None and f['pool_tickets'] == [] and f['pool_left'] == 0, f)
check('spin before reveal is a reveal, not a spin', rpc('final_next', MC, f['id'])['draw']['pending'] is None)
f = rpc('final_state', MC)['draw']
card3 = f['next_card']
check('rank 3 card revealed = IKON (locked), step 6, phase spin', f['step'] == 6 and f['phase'] == 'spin' and card3 == 'I' and [x['code'] for x in f['series'] if x['rank'] == 3] == ['I'] and f['pool_left'] > 0 and all(t.startswith('I-') for t in f['pool_tickets']) and len(f['pool_tickets']) == f['pool_left'], f)
check('other IN cards still unranked', [x['rank'] for x in f['series'] if x['code'] in ('F', 'C')] == [None, None])
f = rpc('final_next', MC, f['id'])['draw']
check('spin rank 3: pending person from card 3, prize = Beyerdynamic', f['pending'] and f['pending']['rank'] == 3 and f['pending']['card'] == card3 and f['pending']['ticket_no'].startswith('I-') and '**' in f['pending']['name'] and f['pending']['prize_id'] == first3['id'], f.get('pending'))
first = f['pending']['ticket_no']
check('spin again while pending rejected', rpc('final_next', MC, f['id']).get('code') == 'PENDING')
tok1 = sql(f"select token from participants where ticket_no = '{first}'", role=None)
pp = rpc('get_passport', tok1)
check('called person sees stage call on passport', pp.get('called') and pp['called']['rank'] == 3 and pp['called']['prize'] == first3['name'], pp.get('called'))
f = rpc('final_claim', MC, f['id'], False)['draw']
check('no-show: no pending, same prize still open on same card', f['pending'] is None and f['next_rank'] == 3 and f['next_prize']['id'] == first3['id'] and f['next_card'] == card3 and f['phase'] == 'spin' and len(f['noshows']) == 1 and f['noshows'][0]['ticket_no'] == first, f)
check('no-show person no longer called', rpc('get_passport', tok1).get('called') is None)
f = rpc('final_next', MC, f['id'])['draw']
check('re-spin picks a different person, same card', f['pending'] and f['pending']['ticket_no'] != first and f['pending']['ticket_no'].startswith('I-'), f.get('pending'))
f = rpc('final_claim', MC, f['id'], True)['draw']
w1 = f['winners'][0]['ticket_no']
check('rank 3 #1 awarded, next = rank 3 #2 (KEF) on same card, no reveal needed', len(f['winners']) == 1 and f['winners'][0]['rank'] == 3 and f['winners'][0]['prize_id'] == first3['id'] and f['next_rank'] == 3 and f['next_prize']['id'] == finals[3]['id'] and f['next_prize']['seq'] == 2 and f['next_card'] == card3 and f['phase'] == 'spin', f)
f = rpc('final_next', MC, f['id'])['draw']
check('second rank-3 spin: different person, same card', f['pending'] and f['pending']['ticket_no'] not in (first, w1) and f['pending']['ticket_no'].startswith('I-') and f['pending']['prize_id'] == finals[3]['id'], f.get('pending'))
f = rpc('final_claim', MC, f['id'], True)['draw']
check('both rank-3 prizes awarded, rank 2 needs reveal', len(f['winners']) == 2 and f['next_rank'] == 2 and f['phase'] == 'reveal' and f['next_card'] is None, f)
cards = {3: card3}
for rank in (2, 1):
    f = rpc('final_next', MC, f['id'])['draw']   # เปิดการ์ดของรางวัลนี้
    cards[rank] = f['next_card']
    check(f'rank {rank} card revealed = ' + {2: 'FORMA', 1: 'CASA'}[rank] + f' (step {5 + 4 - rank})', f['phase'] == 'spin' and f['step'] == 5 + 4 - rank and cards[rank] == {2: 'F', 1: 'C'}[rank] and all(t.startswith(cards[rank] + '-') for t in f['pool_tickets']), f)
    f = rpc('final_next', MC, f['id'])['draw']
    check(f'spin rank {rank}', f['pending'] and f['pending']['rank'] == rank and f['pending']['ticket_no'].startswith(cards[rank] + '-'), f.get('pending'))
    f = rpc('final_claim', MC, f['id'], True)['draw']
check('clear lock', rpc('admin_settings_save', A, {'final_order': None}).get('ok') and rpc('admin_stats', A)['settings']['final_order'] is None)
check('4 prizes on 3 different cards', len({w['card'] for w in f['winners']}) == 3 and sorted(x['rank'] for x in f['series'] if x['rank']) == [1, 2, 3] and sum(1 for x in f['series'] if x['out']) == 2, f)
check('final done after rank 1 claimed', f['done'] and f['next_rank'] is None and sorted(w['rank'] for w in f['winners']) == [1, 2, 3, 3], f)
check('winners are distinct people', len({w['ticket_no'] for w in f['winners']}) == 4)
check('extra next does nothing', rpc('final_next', MC, f['id'])['draw']['done'])
check('cannot run a second final', rpc('final_create', MC).get('code') == 'FINAL_DONE')
res = rpc('draw_results_list', A)['rows']
check('4 live final results with ranks 1,2,3,3', sorted(x['rank'] for x in res if x['kind'] == 'final' and not x['voided']) == [1, 2, 3, 3], res)
check('no-show recorded as voided result', any(x['kind'] == 'final' and x['voided'] and x['ticket_no'] == first for x in res), res)
r1 = [x for x in res if x['rank'] == 1 and not x['voided']][0]
check('rank 1 prize is iPhone 18 Pro Max', r1['prize'] == 'iPhone 18 Pro Max')
check('replace blocked while winner valid', rpc('final_replace', MC, 1).get('code') == 'PRIZE_DONE')
check('void rank 1', rpc('draw_void', A, r1['id']).get('ok'))
f = rpc('final_state', MC)['draw']
check('void re-opens the final for rank 1', not f['done'] and f['next_rank'] == 1, f)
rp = rpc('final_replace', MC, 1)
check('replacement from same card, different person', rp.get('ok') and rp['ticket_no'].startswith(cards[1] + '-') and rp['ticket_no'] != r1['ticket_no'], rp)
check('final prize not drawable via normal draw', rpc('draw_prize_next', MC, finals[1]['id']).get('code') == 'BAD_PRIZE')
for i in range(2):
    r = rpc('draw_prize_next', MC, normal)
    check(f'normal prize draw {i + 1}', r.get('ok') and r['n'] == i + 1, r)
check('normal prize quantity enforced', rpc('draw_prize_next', MC, normal).get('code') == 'PRIZE_DONE')
res = rpc('draw_results_list', A)['rows']
live = [x for x in res if not x['voided']]
check('6 live winners, all different people', len(live) == 6 and len({x['ticket_no'] for x in live}) == 6, live)
check('final re-closed after replacement', rpc('final_state', MC)['draw']['next_rank'] is None)
wt = sql(f"select token from participants where ticket_no = '{rp['ticket_no']}'", role=None)
wp = rpc('get_passport', wt)
check('replacement winner sees iPhone on passport', wp.get('won') and wp['won']['prize'] == 'iPhone 18 Pro Max', wp.get('won'))
# cutoff blocks registration and late registrants not eligible
rpc('admin_settings_save', A, {'cutoff_at': '2000-01-01T00:00:00Z'})
check('registration closed after cutoff', rpc('register_participant', '0822222222', True, 'X', None, 'Co', None, True).get('code') == 'CLOSED')
check('nobody eligible when cutoff before all registrations', rpc('draw_eligible_count', MC)['eligible'] == 0)
rpc('admin_settings_save', A, {'cutoff_at': ''})
check('cutoff cleared', rpc('draw_eligible_count', MC)['eligible'] == 400 - 8)   # 4 final + 2 normal + no-show + voided
check('logout', rpc('staff_logout', SV).get('ok') and rpc('staff_me', SV).get('code') == 'AUTH')

print('\nRESULT:', 'ALL PASS' if not fails else f'{len(fails)} FAILED: {fails}')
sys.exit(1 if fails else 0)
