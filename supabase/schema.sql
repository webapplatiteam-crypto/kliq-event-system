-- =====================================================================
-- KLIQ Experience – ระบบลงทะเบียน สุ่มการ์ด Passport 6 ฐาน ของที่ระลึก และ Lucky Draw
-- รันไฟล์นี้ครั้งเดียวใน Supabase > SQL Editor (โปรเจกต์ใหม่)
-- ทุกตารางปิดไม่ให้อ่าน/เขียนตรง ใช้ได้เฉพาะผ่านฟังก์ชันด้านล่างเท่านั้น
-- =====================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- ตาราง
-- ---------------------------------------------------------------------
create table if not exists settings (
  id                     int primary key default 1 check (id = 1),
  event_name             text not null default 'KLIQ Grand Launch Experience',
  max_participants       int  not null default 400 check (max_participants > 0),
  series_quota           int  not null default 80  check (series_quota > 0),
  min_stamp_interval_sec int  not null default 0 check (min_stamp_interval_sec >= 0),     -- 0 = สแกนฐานถัดไปได้ทันที
  registration_open      boolean not null default true,
  cutoff_at              timestamptz,
  announce_text          text not null default 'ประกาศผลบนเวที',
  final_claim_sec        int  not null default 30 check (final_claim_sec between 10 and 600),
  final_order            text[],                 -- กำหนดลำดับการ์ดล่วงหน้า (ไม่บังคับ): ตำแหน่ง 1..(5-n) = คัดออก, ตำแหน่ง 6-r = รางวัลที่ r · null = สุ่ม
  souvenir_basic_name    text not null default 'ของที่ระลึกทั่วไป',
  souvenir_premium_name  text not null default 'ของที่ระลึกพิเศษ (เล่นครบทุกฐาน)',
  updated_at             timestamptz not null default now()
);
insert into settings (id) values (1) on conflict do nothing;

create table if not exists series (
  code     text primary key,               -- U I F N C
  name     text not null unique,
  color    text not null,
  tagline  text not null default '',
  sort     int  not null default 0,
  next_no  int  not null default 1
);

create table if not exists preregistrations (
  phone        text primary key,
  name         text not null,
  email        text,
  company      text,
  series_code  text references series(code),
  imported_at  timestamptz not null default now()
);

create sequence if not exists participant_ref_seq;

create table if not exists participants (
  id           uuid primary key default gen_random_uuid(),
  ref_code     text not null unique,
  token        text not null unique,
  phone        text not null unique,
  name         text not null,
  email        text,
  company      text,
  series_code  text not null references series(code),
  ticket_no    text not null unique,
  source       text not null check (source in ('pre','walkin')),
  consent_at   timestamptz not null,
  created_at   timestamptz not null default now(),
  completed_at timestamptz,
  souvenir_at  timestamptz,
  souvenir_by  uuid,
  souvenir_tier text check (souvenir_tier in ('basic','premium')),   -- basic = ไม่ได้เล่น/ไม่ครบ · premium = ครบทุกฐาน
  souvenir_upgraded_at timestamptz
);
create index if not exists participants_created_idx on participants(created_at desc);

create table if not exists stations (
  id        int primary key,
  name      text not null,
  qr_token  text not null unique,
  active    boolean not null default true,
  sort      int not null default 0
);

create table if not exists stamps (
  participant_id uuid not null references participants(id) on delete cascade,
  station_id     int  not null references stations(id),
  created_at     timestamptz not null default now(),
  primary key (participant_id, station_id)
);
create index if not exists stamps_participant_time_idx on stamps(participant_id, created_at desc);

create table if not exists staff (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,
  display_name  text not null,
  role          text not null,
  pin_hash      text not null,
  active        boolean not null default true,
  failed_count  int not null default 0,
  locked_until  timestamptz,
  created_at    timestamptz not null default now()
);

-- เจ้าหน้าที่ประจำฐาน (role = station) ผูกกับฐาน 1 ฐาน: เปิดหน้า QR ของฐานบนมือถือและดูจำนวนคนที่สแกน
alter table staff drop constraint if exists staff_role_check;
alter table staff add constraint staff_role_check check (role in ('admin','souvenir','mc','register','station'));
alter table staff add column if not exists station_id int references stations(id) on delete set null;

create table if not exists staff_sessions (
  token       text primary key,
  staff_id    uuid not null references staff(id) on delete cascade,
  expires_at  timestamptz not null,
  created_at  timestamptz not null default now()
);

create table if not exists prizes (
  id        serial primary key,
  name      text not null,
  kind      text not null check (kind in ('final','normal','grand')),
  rank      int,                         -- รอบชิง: อันดับรางวัล 1 / 2 / 3
  quantity  int  not null check (quantity > 0),
  sort      int  not null default 0,
  description text,                      -- รายละเอียด เช่น รุ่น/สี/มูลค่า
  image     text                         -- รูปประกอบ (data URL ย่อแล้วจากหน้าแอดมิน ≤ 300KB)
);
alter table prizes add column if not exists description text;
alter table prizes add column if not exists image text;

-- รองรับกรณีเคยรัน schema รุ่นก่อน
alter table prizes add column if not exists rank int;
alter table settings add column if not exists final_claim_sec int not null default 30;
alter table settings add column if not exists souvenir_basic_name text not null default 'ของที่ระลึกทั่วไป';
alter table settings add column if not exists souvenir_premium_name text not null default 'ของที่ระลึกพิเศษ (เล่นครบทุกฐาน)';
alter table settings add column if not exists final_order text[];
alter table participants add column if not exists souvenir_tier text check (souvenir_tier in ('basic','premium'));
alter table participants add column if not exists souvenir_upgraded_at timestamptz;
alter table prizes drop constraint if exists prizes_kind_check;
alter table prizes add constraint prizes_kind_check check (kind in ('final','normal','grand'));
update prizes set kind = 'final', rank = 1 where kind = 'grand';

create table if not exists draw_results (
  id             serial primary key,
  prize_id       int  not null references prizes(id),
  participant_id uuid not null references participants(id),
  drawn_at       timestamptz not null default now(),
  drawn_by       uuid references staff(id),
  voided         boolean not null default false,
  voided_at      timestamptz,
  void_reason    text
);
alter table draw_results add column if not exists void_reason text;
-- มอบรางวัลที่จุดรับรางวัลแล้ว (สแกน QR ผู้ชนะ) — ไว้ตรวจสอบหลังงาน
alter table draw_results add column if not exists received_at timestamptz;
alter table draw_results add column if not exists received_by uuid references staff(id);
-- คนเดียวได้รางวัลที่ยังไม่ถูกยกเลิกได้แค่ครั้งเดียว
create unique index if not exists draw_results_one_win on draw_results(participant_id) where not voided;

create table if not exists grand_draws (
  id               serial primary key,
  prize_id         int not null references prizes(id),
  finalists        uuid[] not null,          -- เรียงตามซีรีส์
  elimination      uuid[] not null,          -- ลำดับคัดออก (ไม่รวมผู้ชนะ)
  winner_id        uuid not null,
  revealed         int not null default 0,   -- คัดออกไปแล้วกี่คน
  done             boolean not null default false,
  created_at       timestamptz not null default now(),
  created_by       uuid references staff(id)
);

-- v3: คัดการ์ดออกทีละใบจนเหลือเท่าจำนวนรางวัล (3 ใบ) แล้วเปิดการ์ดทีละใบให้รางวัลที่ 3 → 2 → 1
--     หมุนวงล้อสุ่มคนจากผู้ถือการ์ดใบนั้น (แต่ละรางวัลจึงคนละ SKU) ผู้ถูกเรียกต้องยืนยันว่าอยู่ในงาน ไม่อยู่ = สุ่มใหม่
create table if not exists final_draws (
  id                  serial primary key,
  series_order        text[] not null,          -- ลำดับเปิดการ์ด: ตำแหน่ง 1=OUT 2=IN 3=IN 4=OUT 5=IN (การ์ด IN ยังไม่รู้อันดับ ดู rank_cards)
  pool_count          int not null,             -- (ไม่ใช้แล้ว เก็บไว้เพื่อความเข้ากันได้)
  step                int not null default 0,   -- จำนวนการ์ดที่เปิดแล้ว (คัดออก + เปิดให้รางวัล) 0..5
  pending_participant uuid references participants(id),   -- คนที่วงล้อหยุด รอยืนยันว่าอยู่ในงาน
  pending_rank        int,
  pending_at          timestamptz,
  done                boolean not null default false,
  created_at          timestamptz not null default now(),
  created_by          uuid references staff(id)
);
-- อัปเกรดจากเวอร์ชันเก่า (ตารางเดิมมี top5/top3) โดยไม่ลบข้อมูล
alter table final_draws drop column if exists top5, drop column if exists top3;
alter table final_draws add column if not exists pending_participant uuid references participants(id),
                        add column if not exists pending_rank int,
                        add column if not exists pending_at timestamptz;
alter table final_draws alter column pool_count set default 0;
alter table final_draws add column if not exists pending_prize int references prizes(id);
alter table final_draws add column if not exists rank_cards text[];   -- [การ์ดรางวัลที่ 3, ที่ 2, ที่ 1] สุ่มจากการ์ด IN ตอนเริ่ม เปิดทีละใบ
alter table settings alter column min_stamp_interval_sec set default 0;
update settings set min_stamp_interval_sec = 0 where id = 1 and min_stamp_interval_sec = 180;   -- ค่าเดิมของเวอร์ชันก่อน → สแกนฐานถัดไปได้ทันที

create table if not exists audit_log (
  id         bigserial primary key,
  at         timestamptz not null default now(),
  staff_id   uuid,
  action     text not null,
  detail     jsonb
);

-- ปิดการเข้าถึงตรงทุกตาราง (ไม่มี policy = anon/authenticated อ่านเขียนไม่ได้)
alter table settings         enable row level security;
alter table series           enable row level security;
alter table preregistrations enable row level security;
alter table participants     enable row level security;
alter table stations         enable row level security;
alter table stamps           enable row level security;
alter table staff            enable row level security;
alter table staff_sessions   enable row level security;
alter table prizes           enable row level security;
alter table draw_results     enable row level security;
alter table grand_draws      enable row level security;
alter table audit_log        enable row level security;
alter table final_draws      enable row level security;

-- ---------------------------------------------------------------------
-- ฟังก์ชันช่วย (ภายใน)
-- ---------------------------------------------------------------------
create or replace function _norm_phone(p text) returns text
language plpgsql immutable as $$
declare d text := regexp_replace(coalesce(p,''), '\D', '', 'g');
begin
  if d like '66%' and length(d) = 11 then d := '0' || substr(d, 3); end if;
  if d !~ '^0\d{8,9}$' then return null; end if;
  return d;
end $$;

create or replace function _rand_token(n int default 24) returns text
language sql volatile set search_path = public, extensions as $$
  select translate(encode(extensions.gen_random_bytes(n), 'base64'), '+/=', '-_');
$$;

create or replace function _mask_name(n text) returns text
language sql immutable as $$
  select string_agg(
           case when char_length(w) <= 2 then w else left(w, 2) || '**' end, ' ')
  from unnest(string_to_array(trim(coalesce(n,'')), ' ')) as w where w <> '';
$$;

create or replace function _mask_phone(p text) returns text
language sql immutable as $$
  select case when length(p) >= 9 then left(p, 3) || '-XXX-' || right(p, 4) else p end;
$$;

-- ตรวจ session เจ้าหน้าที่ คืนแถว staff หรือ null
create or replace function _staff_from_token(p_token text, p_roles text[]) returns staff
language plpgsql security definer set search_path = public, extensions as $$
declare s staff;
begin
  select st.* into s from staff_sessions ss join staff st on st.id = ss.staff_id
   where ss.token = p_token and ss.expires_at > now() and st.active;
  if s.id is null then return null; end if;
  if s.role <> 'admin' and not (s.role = any(p_roles)) then return null; end if;
  return s;
end $$;

-- ชื่อแบบปิดบางส่วน ใช้ถามยืนยัน "ใช่คุณ ... ไหม" ตอนกรอกเบอร์ซ้ำ (ชื่อเต็ม + นามสกุลตัวแรก)
create or replace function _name_hint(n text) returns text
language sql immutable as $$
  select case when array_length(parts, 1) >= 2
              then parts[1] || ' ' || left(parts[array_length(parts, 1)], 1) || '.'
              else coalesce(parts[1], '') end
    from (select regexp_split_to_array(trim(coalesce(n, '')), '\s+') as parts) x;
$$;

create or replace function _participant_json(p participants) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'ref_code', p.ref_code, 'name', p.name, 'phone_masked', _mask_phone(p.phone),
    'series_code', p.series_code, 'series_name', s.name, 'series_color', s.color, 'series_tagline', s.tagline,
    'ticket_no', p.ticket_no, 'source', p.source, 'created_at', p.created_at,
    'completed_at', p.completed_at, 'souvenir_at', p.souvenir_at, 'souvenir_tier', p.souvenir_tier, 'souvenir_upgraded_at', p.souvenir_upgraded_at)
  from series s where s.code = p.series_code;
$$;

create or replace function _stamps_json(p_id uuid) returns jsonb
language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'station_id', st.id, 'name', st.name, 'done', sp.created_at is not null, 'at', sp.created_at)
         order by st.sort, st.id), '[]'::jsonb)
  from stations st left join stamps sp on sp.station_id = st.id and sp.participant_id = p_id
  where st.active;
$$;

-- ---------------------------------------------------------------------
-- ฝั่งผู้ร่วมงาน (เรียกได้โดยไม่ต้องล็อกอิน)
-- ---------------------------------------------------------------------
create or replace function event_info() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'event_name', s.event_name,
    'registration_open', s.registration_open and (s.cutoff_at is null or now() < s.cutoff_at),
    'announce_text', s.announce_text,
    'souvenir_basic_name', s.souvenir_basic_name, 'souvenir_premium_name', s.souvenir_premium_name,
    'series', (select jsonb_agg(jsonb_build_object('code', code, 'name', name, 'color', color, 'tagline', tagline) order by sort) from series),
    'stations', (select count(*) from stations where active))
  from settings s where s.id = 1;
$$;

create or replace function register_participant(
  p_phone text, p_walkin boolean default false, p_name text default null, p_email text default null,
  p_company text default null, p_series text default null, p_consent boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  ph text := _norm_phone(p_phone);
  cfg settings;
  existing participants;
  pre preregistrations;
  v_name text; v_email text; v_company text; v_series text;
  total int;
  seq_no int;
  new_p participants;
begin
  if ph is null then return jsonb_build_object('ok', false, 'code', 'BAD_PHONE'); end if;

  -- เบอร์เดิม = เข้าสิทธิ์เดิม
  select * into existing from participants where phone = ph;
  if existing.id is not null then
    return jsonb_build_object('ok', true, 'existing', true, 'name_hint', _name_hint(existing.name), 'token', existing.token, 'participant', _participant_json(existing));
  end if;

  if not coalesce(p_consent, false) then return jsonb_build_object('ok', false, 'code', 'NEED_CONSENT'); end if;

  -- ล็อกการลงทะเบียนทีละคน เพื่อให้นับโควตาและเลขลุ้นโชคถูกต้องเสมอ
  perform pg_advisory_xact_lock(42001);

  select * into existing from participants where phone = ph;   -- เช็กอีกรอบหลังได้ล็อก
  if existing.id is not null then
    return jsonb_build_object('ok', true, 'existing', true, 'name_hint', _name_hint(existing.name), 'token', existing.token, 'participant', _participant_json(existing));
  end if;

  select * into cfg from settings where id = 1;
  if not cfg.registration_open or (cfg.cutoff_at is not null and now() >= cfg.cutoff_at) then
    return jsonb_build_object('ok', false, 'code', 'CLOSED');
  end if;
  select count(*) into total from participants;
  if total >= cfg.max_participants then return jsonb_build_object('ok', false, 'code', 'FULL'); end if;

  if coalesce(p_walkin, false) then
    v_name := nullif(trim(p_name), '');
    if v_name is null then return jsonb_build_object('ok', false, 'code', 'NEED_NAME'); end if;
    v_email := nullif(trim(p_email), ''); v_company := nullif(trim(p_company), ''); v_series := nullif(p_series, '');
    if v_company is null then return jsonb_build_object('ok', false, 'code', 'NEED_COMPANY'); end if;
  else
    select * into pre from preregistrations where phone = ph;
    if pre.phone is null then return jsonb_build_object('ok', false, 'code', 'NOT_PREREGISTERED'); end if;
    v_name := pre.name; v_email := pre.email; v_company := pre.company; v_series := pre.series_code;
  end if;

  -- สุ่มการ์ด (ซีรีส์) ให้ จากซีรีส์ที่ยังไม่เต็มโควตา
  v_series := null;
  select s.code into v_series from series s
    left join participants p on p.series_code = s.code
   group by s.code
  having count(p.id) < cfg.series_quota
   order by random() limit 1;
  if v_series is null then return jsonb_build_object('ok', false, 'code', 'FULL'); end if;

  update series set next_no = next_no + 1 where code = v_series returning next_no - 1 into seq_no;

  insert into participants (ref_code, token, phone, name, email, company, series_code, ticket_no, source, consent_at)
  values ('PP-' || lpad(nextval('participant_ref_seq')::text, 4, '0'), _rand_token(24), ph, v_name, v_email, v_company,
          v_series, v_series || '-' || lpad(seq_no::text, 3, '0'),
          case when coalesce(p_walkin, false) then 'walkin' else 'pre' end, now())
  returning * into new_p;

  return jsonb_build_object('ok', true, 'existing', false, 'token', new_p.token, 'participant', _participant_json(new_p));
end $$;

create or replace function get_passport(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p participants; prize jsonb;
begin
  select * into p from participants where token = p_token;
  if p.id is null then return jsonb_build_object('ok', false, 'code', 'NO_PARTICIPANT'); end if;
  select jsonb_build_object('prize', z.name, 'kind', z.kind, 'rank', z.rank, 'image', z.image, 'description', z.description, 'at', r.drawn_at, 'received_at', r.received_at, 'check', upper(substr(md5(r.id::text || p.token), 1, 6)))
    into prize from draw_results r join prizes z on z.id = r.prize_id
   where r.participant_id = p.id and not r.voided limit 1;
  return jsonb_build_object('ok', true, 'participant', _participant_json(p), 'stamps', _stamps_json(p.id),
    'won', prize, 'event', event_info(),
    'grand', (select jsonb_build_object('name', name, 'description', description, 'image', image) from prizes where kind = 'final' and rank = 1 order by id limit 1),
    'called', (select jsonb_build_object('rank', g.pending_rank, 'at', g.pending_at,
                 'prize', z.name, 'image', z.image, 'description', z.description)
               from final_draws g left join prizes z on z.kind = 'final' and z.rank = g.pending_rank
               where g.pending_participant = p.id and not g.done limit 1));
end $$;

create or replace function collect_stamp(p_token text, p_station_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p participants; st stations; cfg settings; last_at timestamptz; prev timestamptz;
  wait int; done_count int; total_st int;
begin
  select * into p from participants where token = p_token for update;
  if p.id is null then return jsonb_build_object('ok', false, 'code', 'NO_PARTICIPANT'); end if;
  select * into st from stations where qr_token = p_station_token;
  if st.id is null or not st.active then return jsonb_build_object('ok', false, 'code', 'BAD_STATION'); end if;

  select created_at into prev from stamps where participant_id = p.id and station_id = st.id;
  if prev is not null then
    return jsonb_build_object('ok', false, 'code', 'ALREADY', 'station', st.name, 'at', prev);
  end if;

  select * into cfg from settings where id = 1;
  select max(created_at) into last_at from stamps where participant_id = p.id;
  if last_at is not null and cfg.min_stamp_interval_sec > 0 then
    wait := ceil(cfg.min_stamp_interval_sec - extract(epoch from (now() - last_at)));
    if wait > 0 then return jsonb_build_object('ok', false, 'code', 'TOO_SOON', 'wait_sec', wait); end if;
  end if;

  insert into stamps (participant_id, station_id) values (p.id, st.id) on conflict do nothing;

  select count(*) into total_st from stations where active;
  select count(*) into done_count from stamps sp join stations s on s.id = sp.station_id and s.active where sp.participant_id = p.id;
  if done_count >= total_st and p.completed_at is null then
    update participants set completed_at = now() where id = p.id;
  end if;

  return jsonb_build_object('ok', true, 'station', st.name, 'station_id', st.id, 'done', done_count, 'total', total_st,
                            'completed', done_count >= total_st);
end $$;

-- ---------------------------------------------------------------------
-- เจ้าหน้าที่: ล็อกอินด้วยรหัส + PIN
-- ---------------------------------------------------------------------
create or replace function staff_login(p_code text, p_pin text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s staff; tok text;
begin
  select * into s from staff where code = upper(trim(p_code)) and active;
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'BAD_LOGIN'); end if;
  if s.locked_until is not null and s.locked_until > now() then
    return jsonb_build_object('ok', false, 'code', 'LOCKED', 'until', s.locked_until);
  end if;
  if s.pin_hash <> extensions.crypt(coalesce(p_pin, ''), s.pin_hash) then
    update staff set failed_count = failed_count + 1,
                     locked_until = case when failed_count + 1 >= 5 then now() + interval '10 minutes' else null end
     where id = s.id;
    return jsonb_build_object('ok', false, 'code', 'BAD_LOGIN');
  end if;
  update staff set failed_count = 0, locked_until = null where id = s.id;
  tok := _rand_token(32);
  insert into staff_sessions (token, staff_id, expires_at) values (tok, s.id, now() + interval '18 hours');
  delete from staff_sessions where expires_at < now();
  return jsonb_build_object('ok', true, 'token', tok, 'role', s.role, 'name', s.display_name, 'code', s.code, 'station_id', s.station_id);
end $$;

create or replace function staff_me(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s staff;
begin
  s := _staff_from_token(p_token, array['admin','souvenir','mc','register','station']);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  return jsonb_build_object('ok', true, 'role', s.role, 'name', s.display_name, 'code', s.code, 'station_id', s.station_id);
end $$;

-- หน้าเจ้าหน้าที่ประจำฐาน: ข้อมูลฐานของตัวเอง + จำนวนที่สแกนแล้ว (แอดมินดูได้ทุกฐานโดยส่ง p_station_id)
create or replace function station_me(p_token text, p_station_id int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s staff; st stations; sid int;
begin
  s := _staff_from_token(p_token, array['station']);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  sid := case when s.role = 'admin' then coalesce(p_station_id, s.station_id) else s.station_id end;
  select * into st from stations where id = sid;
  if st.id is null then return jsonb_build_object('ok', false, 'code', 'NO_STATION'); end if;
  return jsonb_build_object('ok', true, 'id', st.id, 'name', st.name, 'sort', st.sort, 'active', st.active, 'qr_token', st.qr_token,
    'count', (select count(*) from stamps where station_id = st.id),
    'last10', (select coalesce(jsonb_agg(jsonb_build_object('ticket_no', p.ticket_no, 'name', _mask_name(p.name), 'at', sp.created_at) order by sp.created_at desc), '[]'::jsonb)
               from (select * from stamps where station_id = st.id order by created_at desc limit 10) sp join participants p on p.id = sp.participant_id),
    'staff', s.display_name);
end $$;

create or replace function staff_logout(p_token text) returns jsonb
language sql security definer set search_path = public as $$
  delete from staff_sessions where token = p_token;
  select jsonb_build_object('ok', true);
$$;

-- ---------------------------------------------------------------------
-- จุดรับของที่ระลึก
-- ---------------------------------------------------------------------
create or replace function souvenir_lookup(p_token text, p_query text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s staff; p participants; q text := trim(coalesce(p_query, '')); ph text;
begin
  s := _staff_from_token(p_token, array['souvenir']);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  if q like 'KLIQ:%' then q := substr(q, 6); end if;
  ph := _norm_phone(q);
  select * into p from participants
   where upper(ref_code) = upper(q) or upper(ticket_no) = upper(q) or (ph is not null and phone = ph)
   limit 1;
  if p.id is null then
    if ph is not null and exists (select 1 from preregistrations where phone = ph) then
      return jsonb_build_object('ok', false, 'code', 'NOT_REGISTERED');   -- มีชื่อลงทะเบียนล่วงหน้า แต่ยังไม่ได้กดลงทะเบียนที่หน้างาน
    end if;
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND');
  end if;
  return jsonb_build_object('ok', true, 'participant', _participant_json(p) || jsonb_build_object('phone_masked', _mask_phone(p.phone)),
    'stamps', _stamps_json(p.id),
    'souvenir_by', (select display_name from staff where id = p.souvenir_by),
    'prize', (select jsonb_build_object('id', r.id, 'name', z.name, 'rank', z.rank, 'kind', z.kind, 'image', z.image, 'drawn_at', r.drawn_at,
                 'received_at', r.received_at, 'received_by', (select display_name from staff where id = r.received_by))
                from draw_results r join prizes z on z.id = r.prize_id where r.participant_id = p.id and not r.voided limit 1),
    -- ระดับของที่ระลึกที่ควรได้ ณ ตอนนี้: ครบทุกฐาน = premium, อื่น ๆ = basic
    'tier_now', case when p.completed_at is not null then 'premium' else 'basic' end,
    'tier_name', case when p.completed_at is not null then (select souvenir_premium_name from settings) else (select souvenir_basic_name from settings) end,
    'basic_name', (select souvenir_basic_name from settings), 'premium_name', (select souvenir_premium_name from settings),
    -- ยังมอบได้ไหม: ยังไม่เคยรับ หรือรับแบบทั่วไปไปแล้วแต่ตอนนี้เล่นครบ (มอบแบบพิเศษเพิ่ม)
    'can_redeem', p.souvenir_at is null or (p.souvenir_tier = 'basic' and p.completed_at is not null),
    'upgrade', p.souvenir_at is not null and p.souvenir_tier = 'basic' and p.completed_at is not null,
    'given_basic', (select count(*) from participants where souvenir_at is not null and souvenir_tier = 'basic'),
    'given_premium', (select count(*) from participants where souvenir_at is not null and souvenir_tier = 'premium'),
    'stock_left', greatest(0, (select max_participants from settings) - (select count(*) from participants where souvenir_at is not null)));
end $$;

create or replace function souvenir_redeem(p_token text, p_ref text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s staff; p participants; tier text;
begin
  s := _staff_from_token(p_token, array['souvenir']);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  select * into p from participants where ref_code = upper(trim(p_ref)) for update;
  if p.id is null then return jsonb_build_object('ok', false, 'code', 'NOT_FOUND'); end if;
  tier := case when p.completed_at is not null then 'premium' else 'basic' end;
  if p.souvenir_at is not null then
    if p.souvenir_tier = 'basic' and tier = 'premium' then          -- เคยรับแบบทั่วไป ตอนนี้ครบทุกฐาน → มอบแบบพิเศษเพิ่ม
      update participants set souvenir_tier = 'premium', souvenir_upgraded_at = now(), souvenir_by = s.id where id = p.id;
      insert into audit_log (staff_id, action, detail) values (s.id, 'souvenir_upgrade', jsonb_build_object('ref', p.ref_code));
      return jsonb_build_object('ok', true, 'ref_code', p.ref_code, 'name', p.name, 'tier', 'premium', 'upgraded', true);
    end if;
    return jsonb_build_object('ok', false, 'code', 'ALREADY_REDEEMED', 'at', p.souvenir_at, 'tier', p.souvenir_tier,
                              'by', (select display_name from staff where id = p.souvenir_by));
  end if;
  update participants set souvenir_at = now(), souvenir_by = s.id, souvenir_tier = tier where id = p.id;
  insert into audit_log (staff_id, action, detail) values (s.id, 'souvenir', jsonb_build_object('ref', p.ref_code, 'tier', tier));
  return jsonb_build_object('ok', true, 'ref_code', p.ref_code, 'name', p.name, 'tier', tier, 'upgraded', false);
end $$;

-- ---------------------------------------------------------------------
-- แอดมิน
-- ---------------------------------------------------------------------
-- จุดรับรางวัล: สแกน QR ผู้ชนะแล้วกดยืนยันมอบรางวัล (บันทึกเวลา + เจ้าหน้าที่)
create or replace function prize_handover(p_token text, p_ref text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s staff; p participants; r draw_results; z prizes;
begin
  s := _staff_from_token(p_token, array['souvenir']);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  select * into p from participants where upper(ref_code) = upper(trim(coalesce(p_ref, '')));
  if p.id is null then return jsonb_build_object('ok', false, 'code', 'NOT_FOUND'); end if;
  select * into r from draw_results where participant_id = p.id and not voided limit 1 for update;
  if r.id is null then return jsonb_build_object('ok', false, 'code', 'NO_PRIZE'); end if;
  if r.received_at is not null then return jsonb_build_object('ok', false, 'code', 'PRIZE_RECEIVED', 'received_at', r.received_at); end if;
  update draw_results set received_at = now(), received_by = s.id where id = r.id;
  select * into z from prizes where id = r.prize_id;
  insert into audit_log (staff_id, action, detail) values (s.id, 'prize_handover', jsonb_build_object('ref', p.ref_code, 'result', r.id, 'prize', z.name));
  return jsonb_build_object('ok', true, 'prize', z.name, 'rank', z.rank, 'name', p.name);
end $$;

create or replace function admin_stats(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s staff; cfg settings;
begin
  s := _staff_from_token(p_token, array['mc','register','souvenir']);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  select * into cfg from settings where id = 1;
  return jsonb_build_object('ok', true,
    'settings', to_jsonb(cfg),
    'registered', (select count(*) from participants),
    'pre', (select count(*) from participants where source = 'pre'),
    'walkin', (select count(*) from participants where source = 'walkin'),
    'preregistered_total', (select count(*) from preregistrations),
    'preregistered_arrived', (select count(*) from preregistrations pr where exists (select 1 from participants p where p.phone = pr.phone)),
    'started', (select count(distinct participant_id) from stamps),
    'completed', (select count(*) from participants where completed_at is not null),
    'souvenir', (select count(*) from participants where souvenir_at is not null),
    'souvenir_basic', (select count(*) from participants where souvenir_at is not null and souvenir_tier = 'basic'),
    'souvenir_premium', (select count(*) from participants where souvenir_at is not null and souvenir_tier = 'premium'),
    'avg_complete_min', (select round(avg(extract(epoch from (completed_at - (select min(created_at) from stamps x where x.participant_id = p.id))) / 60)::numeric, 0)
                           from participants p where completed_at is not null),
    'series', (select jsonb_agg(jsonb_build_object('code', se.code, 'name', se.name, 'color', se.color,
                 'count', (select count(*) from participants p where p.series_code = se.code)) order by se.sort) from series se),
    'stations', (select jsonb_agg(jsonb_build_object('id', st.id, 'name', st.name, 'active', st.active,
                 'count', (select count(*) from stamps sp where sp.station_id = st.id)) order by st.sort, st.id) from stations st),
    'winners', (select count(*) from draw_results where not voided));
end $$;

create or replace function admin_participants(p_token text, p_search text default '', p_filter text default 'all',
                                              p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s staff; q text := '%' || lower(trim(coalesce(p_search, ''))) || '%'; rows jsonb; total int;
begin
  s := _staff_from_token(p_token, array['register','souvenir']);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  with f as (
    select p.*, (select count(*) from stamps sp where sp.participant_id = p.id) as stamp_count
      from participants p
     where (q = '%%' or lower(p.name) like q or p.phone like q or lower(p.ref_code) like q or lower(p.ticket_no) like q
            or lower(coalesce(p.company,'')) like q)
       and case p_filter
             when 'pre' then p.source = 'pre'
             when 'walkin' then p.source = 'walkin'
             when 'completed' then p.completed_at is not null
             when 'souvenir' then p.souvenir_at is not null
             when 'waiting' then p.completed_at is not null and (p.souvenir_at is null or p.souvenir_tier = 'basic')
             else true end
  )
  select count(*), coalesce(jsonb_agg(r order by r->>'created_at' desc), '[]'::jsonb) into total, rows from (
    select jsonb_build_object('ref_code', ref_code, 'name', name, 'phone', phone, 'email', email, 'company', company,
             'series_code', series_code, 'ticket_no', ticket_no, 'source', source, 'stamps', stamp_count,
             'completed_at', completed_at, 'souvenir_at', souvenir_at, 'souvenir_tier', souvenir_tier, 'created_at', created_at) as r
      from f order by created_at desc limit greatest(1, least(p_limit, 500)) offset greatest(0, p_offset)) x;
  select count(*) into total from participants p
   where (q = '%%' or lower(p.name) like q or p.phone like q or lower(p.ref_code) like q or lower(p.ticket_no) like q
          or lower(coalesce(p.company,'')) like q)
     and case p_filter
           when 'pre' then p.source = 'pre' when 'walkin' then p.source = 'walkin'
           when 'completed' then p.completed_at is not null when 'souvenir' then p.souvenir_at is not null
           when 'waiting' then p.completed_at is not null and (p.souvenir_at is null or p.souvenir_tier = 'basic') else true end;
  return jsonb_build_object('ok', true, 'total', total, 'rows', rows);
end $$;

create or replace function admin_export(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s staff;
begin
  s := _staff_from_token(p_token, array[]::text[]);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object(
      'ref_code', p.ref_code, 'ticket_no', p.ticket_no, 'name', p.name, 'phone', p.phone, 'email', p.email,
      'company', p.company, 'series', se.name, 'source', p.source, 'registered_at', p.created_at,
      'stamps', (select count(*) from stamps sp where sp.participant_id = p.id),
      'completed_at', p.completed_at, 'souvenir_at', p.souvenir_at, 'souvenir_tier', p.souvenir_tier,
      'prize', (select z.name from draw_results r join prizes z on z.id = r.prize_id where r.participant_id = p.id and not r.voided limit 1),
      'prize_received_at', (select r.received_at from draw_results r where r.participant_id = p.id and not r.voided limit 1))
      order by p.created_at)
    from participants p join series se on se.code = p.series_code), '[]'::jsonb));
end $$;

-- รายชื่อลงทะเบียนล่วงหน้า + สถานะว่ามาถึงงานแล้ว (ลงทะเบียนรับการ์ดแล้ว) หรือยัง
create or replace function admin_prereg_list(p_token text, p_search text default null, p_filter text default 'all',
                                             p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s staff; q text := nullif(trim(coalesce(p_search, '')), '');
begin
  s := _staff_from_token(p_token, array['register']);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  return (with base as (
      select pr.*, p.ref_code, p.ticket_no, p.created_at as arrived_at
        from preregistrations pr left join participants p on p.phone = pr.phone
       where (q is null or pr.name ilike '%' || q || '%' or pr.phone like '%' || q || '%' or coalesce(pr.company, '') ilike '%' || q || '%' or coalesce(pr.email, '') ilike '%' || q || '%')
         and (p_filter = 'all' or (p_filter = 'arrived' and p.id is not null) or (p_filter = 'pending' and p.id is null)))
    select jsonb_build_object('ok', true, 'total', (select count(*) from base),
      'arrived', (select count(*) from preregistrations pr where exists (select 1 from participants p where p.phone = pr.phone)),
      'all', (select count(*) from preregistrations),
      'rows', (select coalesce(jsonb_agg(jsonb_build_object('phone', phone, 'name', name, 'email', email, 'company', company, 'imported_at', imported_at,
                 'ref_code', ref_code, 'ticket_no', ticket_no, 'arrived_at', arrived_at) order by arrived_at desc nulls last, name), '[]'::jsonb)
               from (select * from base order by arrived_at desc nulls last, name limit p_limit offset p_offset) x)));
end $$;

-- ===== แอดมินแก้ไขข้อมูลผู้ร่วมงาน / รายชื่อล่วงหน้า (กรณีกรอกผิด) — admin เท่านั้น =====
create or replace function admin_participant_update(p_token text, p_ref_code text, p_name text, p_phone text,
                                                    p_email text default null, p_company text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s staff; p participants; ph text := _norm_phone(p_phone); nm text := nullif(trim(coalesce(p_name,'')), '');
begin
  s := _staff_from_token(p_token, array[]::text[]);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  select * into p from participants where ref_code = upper(trim(coalesce(p_ref_code,'')));
  if p.id is null then return jsonb_build_object('ok', false, 'code', 'NOT_FOUND'); end if;
  if nm is null then return jsonb_build_object('ok', false, 'code', 'NEED_NAME'); end if;
  if ph is null then return jsonb_build_object('ok', false, 'code', 'BAD_PHONE'); end if;
  if ph <> p.phone and exists (select 1 from participants x where x.phone = ph and x.id <> p.id) then
    return jsonb_build_object('ok', false, 'code', 'PHONE_TAKEN');
  end if;
  insert into audit_log (staff_id, action, detail) values (s.id, 'participant_edit', jsonb_build_object('ref', p.ref_code,
    'before', jsonb_build_object('name', p.name, 'phone', p.phone, 'email', p.email, 'company', p.company),
    'after', jsonb_build_object('name', nm, 'phone', ph, 'email', nullif(trim(coalesce(p_email,'')), ''), 'company', nullif(trim(coalesce(p_company,'')), ''))));
  update participants set name = nm, phone = ph, email = nullif(trim(coalesce(p_email,'')), ''),
         company = nullif(trim(coalesce(p_company,'')), '') where id = p.id;
  return jsonb_build_object('ok', true, 'ref_code', p.ref_code, 'name', nm, 'phone', ph);
end $$;

-- ลบผู้ร่วมงาน (แอดมินเท่านั้น) — ลบแสตมป์และผลจับฉลากที่ถูกยกเลิกไปด้วย · ถ้ายังถือรางวัลอยู่ต้องยกเลิกสิทธิ์ก่อน
create or replace function admin_participant_delete(p_token text, p_ref_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s staff; p participants;
begin
  s := _staff_from_token(p_token, array[]::text[]);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  select * into p from participants where ref_code = upper(trim(coalesce(p_ref_code,'')));
  if p.id is null then return jsonb_build_object('ok', false, 'code', 'NOT_FOUND'); end if;
  if exists (select 1 from draw_results where participant_id = p.id and not voided) then return jsonb_build_object('ok', false, 'code', 'HAS_PRIZE'); end if;
  if exists (select 1 from final_draws where pending_participant = p.id and not done) then return jsonb_build_object('ok', false, 'code', 'HAS_PRIZE'); end if;
  insert into audit_log (staff_id, action, detail) values (s.id, 'participant_delete', jsonb_build_object('ref', p.ref_code, 'name', p.name, 'phone', p.phone, 'ticket', p.ticket_no));
  update final_draws set pending_participant = null where pending_participant = p.id;
  delete from draw_results where participant_id = p.id;
  delete from stamps where participant_id = p.id;
  delete from participants where id = p.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function admin_prereg_update(p_token text, p_old_phone text, p_phone text, p_name text,
                                               p_email text default null, p_company text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s staff; old text := _norm_phone(p_old_phone); ph text := _norm_phone(p_phone); nm text := nullif(trim(coalesce(p_name,'')), '');
begin
  s := _staff_from_token(p_token, array[]::text[]);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  if old is null or not exists (select 1 from preregistrations where phone = old) then return jsonb_build_object('ok', false, 'code', 'NOT_FOUND'); end if;
  if nm is null then return jsonb_build_object('ok', false, 'code', 'NEED_NAME'); end if;
  if ph is null then return jsonb_build_object('ok', false, 'code', 'BAD_PHONE'); end if;
  if ph <> old and exists (select 1 from preregistrations where phone = ph) then return jsonb_build_object('ok', false, 'code', 'PHONE_TAKEN'); end if;
  update preregistrations set phone = ph, name = nm, email = nullif(trim(coalesce(p_email,'')), ''),
         company = nullif(trim(coalesce(p_company,'')), '') where phone = old;
  insert into audit_log (staff_id, action, detail) values (s.id, 'prereg_edit', jsonb_build_object('old_phone', old, 'phone', ph, 'name', nm));
  return jsonb_build_object('ok', true, 'phone', ph, 'name', nm);
end $$;

create or replace function admin_prereg_delete(p_token text, p_phone text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s staff; ph text := _norm_phone(p_phone); n int;
begin
  s := _staff_from_token(p_token, array[]::text[]);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  if ph is null then return jsonb_build_object('ok', false, 'code', 'NOT_FOUND'); end if;
  delete from preregistrations where phone = ph; get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('ok', false, 'code', 'NOT_FOUND'); end if;
  insert into audit_log (staff_id, action, detail) values (s.id, 'prereg_delete', jsonb_build_object('phone', ph));
  return jsonb_build_object('ok', true);
end $$;

create or replace function admin_import_prereg(p_token text, p_rows jsonb, p_replace boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s staff; r jsonb; ph text; ok int := 0; bad jsonb := '[]'::jsonb; ser text;
begin
  s := _staff_from_token(p_token, array[]::text[]);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  if p_replace then delete from preregistrations where phone is not null; end if;   -- Supabase บล็อก DELETE/UPDATE ที่ไม่มี WHERE (และ WHERE true ถูก planner ตัดทิ้ง จึงต้องใช้เงื่อนไขจริง)
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    ph := _norm_phone(r->>'phone');
    if ph is null or nullif(trim(r->>'name'), '') is null then
      bad := bad || jsonb_build_array(r); continue;
    end if;
    select code into ser from series where upper(name) = upper(trim(coalesce(r->>'series',''))) or code = upper(trim(coalesce(r->>'series','')));
    insert into preregistrations (phone, name, email, company, series_code)
    values (ph, trim(r->>'name'), nullif(trim(r->>'email'), ''), nullif(trim(r->>'company'), ''), ser)
    on conflict (phone) do update set name = excluded.name, email = excluded.email, company = excluded.company,
                                      series_code = excluded.series_code, imported_at = now();
    ok := ok + 1;
  end loop;
  insert into audit_log (staff_id, action, detail) values (s.id, 'import_prereg', jsonb_build_object('ok', ok, 'bad', jsonb_array_length(bad)));
  return jsonb_build_object('ok', true, 'imported', ok, 'rejected', bad, 'total', (select count(*) from preregistrations));
end $$;

create or replace function admin_stations(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s staff;
begin
  s := _staff_from_token(p_token, array[]::text[]);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
    'id', st.id, 'name', st.name, 'qr_token', st.qr_token, 'active', st.active, 'sort', st.sort,
    'count', (select count(*) from stamps sp where sp.station_id = st.id)) order by st.sort, st.id) from stations st), '[]'::jsonb));
end $$;

create or replace function admin_station_save(p_token text, p_id int, p_name text, p_active boolean, p_rotate boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s staff;
begin
  s := _staff_from_token(p_token, array[]::text[]);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  update stations set name = coalesce(nullif(trim(p_name), ''), name), active = coalesce(p_active, active),
         qr_token = case when p_rotate then _rand_token(12) else qr_token end
   where id = p_id;
  insert into audit_log (staff_id, action, detail) values (s.id, 'station_save', jsonb_build_object('id', p_id, 'rotate', p_rotate));
  return jsonb_build_object('ok', true);
end $$;

create or replace function admin_settings_save(p_token text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s staff;
begin
  s := _staff_from_token(p_token, array[]::text[]);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  update settings set
    event_name             = coalesce(nullif(trim(p->>'event_name'), ''), event_name),
    max_participants       = coalesce((p->>'max_participants')::int, max_participants),
    series_quota           = coalesce((p->>'series_quota')::int, series_quota),
    min_stamp_interval_sec = coalesce((p->>'min_stamp_interval_sec')::int, min_stamp_interval_sec),
    registration_open      = coalesce((p->>'registration_open')::boolean, registration_open),
    cutoff_at              = case when p ? 'cutoff_at' then nullif(p->>'cutoff_at', '')::timestamptz else cutoff_at end,
    announce_text          = coalesce(p->>'announce_text', announce_text),
    final_claim_sec        = coalesce((p->>'final_claim_sec')::int, final_claim_sec),
    souvenir_basic_name    = coalesce(nullif(trim(p->>'souvenir_basic_name'), ''), souvenir_basic_name),
    souvenir_premium_name  = coalesce(nullif(trim(p->>'souvenir_premium_name'), ''), souvenir_premium_name),
    final_order            = case when p ? 'final_order' then
                               (case when jsonb_typeof(p->'final_order') = 'array' and jsonb_array_length(p->'final_order') = 5
                                     then (select array_agg(x) from jsonb_array_elements_text(p->'final_order') x) end)
                             else final_order end,
    updated_at             = now()
  where id = 1;
  insert into audit_log (staff_id, action, detail) values (s.id, 'settings', p);
  return jsonb_build_object('ok', true);
end $$;

create or replace function admin_staff_list(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s staff;
begin
  s := _staff_from_token(p_token, array[]::text[]);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
    'code', code, 'display_name', display_name, 'role', role, 'active', active, 'locked', locked_until > now(),
    'station_id', station_id, 'station_name', (select name from stations where id = staff.station_id)) order by role, code) from staff), '[]'::jsonb));
end $$;

drop function if exists admin_staff_save(text, text, text, text, text, boolean);
create or replace function admin_staff_save(p_token text, p_code text, p_name text, p_role text, p_pin text default null,
                                            p_active boolean default true, p_station_id int default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s staff; c text := upper(trim(coalesce(p_code, '')));
begin
  s := _staff_from_token(p_token, array[]::text[]);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  if c !~ '^[A-Z0-9_-]{3,20}$' then return jsonb_build_object('ok', false, 'code', 'BAD_CODE'); end if;
  if p_role not in ('admin','souvenir','mc','register','station') then return jsonb_build_object('ok', false, 'code', 'BAD_ROLE'); end if;
  if p_role = 'station' and (p_station_id is null or not exists (select 1 from stations where id = p_station_id)) then return jsonb_build_object('ok', false, 'code', 'NEED_STATION'); end if;
  if p_pin is not null and p_pin <> '' and p_pin !~ '^\d{6}$' then return jsonb_build_object('ok', false, 'code', 'BAD_PIN'); end if;
  if c = s.code and (p_role <> 'admin' or not p_active) then return jsonb_build_object('ok', false, 'code', 'SELF_LOCKOUT'); end if;
  if exists (select 1 from staff where code = c) then
    update staff set display_name = coalesce(nullif(trim(p_name), ''), display_name), role = p_role, active = p_active, station_id = case when p_role = 'station' then p_station_id else null end,
           pin_hash = case when coalesce(p_pin, '') <> '' then extensions.crypt(p_pin, extensions.gen_salt('bf')) else pin_hash end,
           failed_count = 0, locked_until = null
     where code = c;
    if not p_active then delete from staff_sessions where staff_id = (select id from staff where code = c); end if;
  else
    if coalesce(p_pin, '') = '' then return jsonb_build_object('ok', false, 'code', 'BAD_PIN'); end if;
    insert into staff (code, display_name, role, pin_hash, station_id)
    values (c, coalesce(nullif(trim(p_name), ''), c), p_role, extensions.crypt(p_pin, extensions.gen_salt('bf')), case when p_role = 'station' then p_station_id end);
  end if;
  insert into audit_log (staff_id, action, detail) values (s.id, 'staff_save', jsonb_build_object('code', c, 'role', p_role));
  return jsonb_build_object('ok', true);
end $$;

create or replace function admin_prizes(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s staff;
begin
  s := _staff_from_token(p_token, array['mc']);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
    'id', z.id, 'name', z.name, 'kind', z.kind, 'rank', z.rank, 'quantity', z.quantity, 'sort', z.sort,
    'description', z.description, 'image', z.image,
    'won', (select count(*) from draw_results r where r.prize_id = z.id and not r.voided)) order by z.kind, z.rank nulls last, z.sort, z.id) from prizes z), '[]'::jsonb));
end $$;

drop function if exists admin_prize_save(text, int, text, text, int, int);
drop function if exists admin_prize_save(text, int, text, text, int, int, int);
create or replace function admin_prize_save(p_token text, p_id int, p_name text, p_kind text, p_quantity int, p_sort int default 0, p_rank int default null, p_description text default null, p_image text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s staff;
begin
  s := _staff_from_token(p_token, array[]::text[]);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  if p_kind not in ('final','normal') or coalesce(p_quantity, 0) < 1 or nullif(trim(p_name), '') is null
     or (p_kind = 'final' and coalesce(p_rank, 0) not between 1 and 3) then
    return jsonb_build_object('ok', false, 'code', 'BAD_INPUT');
  end if;
  -- รูป: null = ไม่เปลี่ยน, '' = ลบรูป, อื่น ๆ ต้องเป็น data:image/… ไม่เกิน 300KB
  if p_image is not null and p_image <> '' and (p_image not like 'data:image/%' or length(p_image) > 300000) then
    return jsonb_build_object('ok', false, 'code', 'BAD_IMAGE');
  end if;
  if p_id is null then
    insert into prizes (name, kind, quantity, sort, rank, description, image)
    values (trim(p_name), p_kind, case when p_kind = 'final' then 1 else p_quantity end, coalesce(p_sort, 0), case when p_kind = 'final' then p_rank end,
            nullif(trim(coalesce(p_description, '')), ''), nullif(p_image, ''));
  else
    update prizes set name = trim(p_name), kind = p_kind, quantity = case when p_kind = 'final' then 1 else p_quantity end,
           sort = coalesce(p_sort, sort), rank = case when p_kind = 'final' then p_rank end,
           description = case when p_description is null then description else nullif(trim(p_description), '') end,
           image = case when p_image is null then image when p_image = '' then null else p_image end
     where id = p_id;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- Lucky Draw
-- ผู้มีสิทธิ์ = ลงทะเบียนก่อนเวลาตัดยอด และยังไม่ได้รางวัล (รายการที่ยกเลิกแล้วไม่นับเป็นสิทธิ์อีก)
-- ---------------------------------------------------------------------
create or replace function _eligible() returns setof participants
language sql stable set search_path = public as $$
  select p.* from participants p, settings s
   where s.id = 1 and (s.cutoff_at is null or p.created_at < s.cutoff_at)
     and not exists (select 1 from draw_results r where r.participant_id = p.id);
$$;

-- ลบรางวัล (แอดมิน) — ลบผลจับฉลากของรางวัลนั้นด้วย ใช้เก็บกวาดรางวัลทดสอบ/ตั้งผิด
create or replace function admin_prize_delete(p_token text, p_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s staff; z prizes;
begin
  s := _staff_from_token(p_token, array[]::text[]);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  select * into z from prizes where id = p_id;
  if z.id is null then return jsonb_build_object('ok', false, 'code', 'NOT_FOUND'); end if;
  if exists (select 1 from draw_results where prize_id = z.id and not voided) then return jsonb_build_object('ok', false, 'code', 'PRIZE_AWARDED'); end if;
  delete from draw_results where prize_id = z.id;
  delete from prizes where id = z.id;
  insert into audit_log (staff_id, action, detail) values (s.id, 'prize_delete', jsonb_build_object('id', z.id, 'name', z.name));
  return jsonb_build_object('ok', true);
end $$;

-- ล้างข้อมูลผู้ร่วมงานทั้งหมด (ซ้อม/เริ่มงานใหม่) — แอดมินพิมพ์ยืนยัน RESET · เก็บรายชื่อล่วงหน้า รางวัล ฐาน ทีมงาน การตั้งค่า
create or replace function admin_reset_event(p_token text, p_confirm text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s staff; n int;
begin
  s := _staff_from_token(p_token, array[]::text[]);
  if s.id is null or s.role <> 'admin' then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  if coalesce(p_confirm, '') <> 'RESET' then return jsonb_build_object('ok', false, 'code', 'BAD_INPUT'); end if;
  select count(*) into n from participants;
  delete from draw_results where id is not null;
  delete from final_draws where id is not null;
  delete from grand_draws where id is not null;
  delete from stamps where participant_id is not null;
  delete from participants where id is not null;
  perform setval('participant_ref_seq', 1, false);
  update series set next_no = 1 where code is not null;
  update settings set cutoff_at = null, registration_open = true, updated_at = now() where id = 1;
  insert into audit_log (staff_id, action, detail) values (s.id, 'reset_event', jsonb_build_object('participants_removed', n));
  return jsonb_build_object('ok', true, 'removed', n);
end $$;

-- รีเซ็ตเฉพาะลักกี้ดรอว์ (ผลจับฉลาก + รอบชิง) — เก็บผู้ร่วมงาน การ์ด แสตมป์ ไว้ทั้งหมด · แอดมินพิมพ์ยืนยัน RESET
create or replace function admin_reset_draw(p_token text, p_confirm text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s staff; n int;
begin
  s := _staff_from_token(p_token, array[]::text[]);
  if s.id is null or s.role <> 'admin' then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  if coalesce(p_confirm, '') <> 'RESET' then return jsonb_build_object('ok', false, 'code', 'BAD_INPUT'); end if;
  select count(*) into n from draw_results;
  delete from draw_results where id is not null;
  delete from final_draws where id is not null;
  delete from grand_draws where id is not null;
  insert into audit_log (staff_id, action, detail) values (s.id, 'reset_draw', jsonb_build_object('results_removed', n));
  return jsonb_build_object('ok', true, 'removed', n);
end $$;

create or replace function draw_eligible_count(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s staff;
begin
  s := _staff_from_token(p_token, array['mc']);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  return jsonb_build_object('ok', true, 'eligible', (select count(*) from _eligible()),
    'by_series', (select jsonb_agg(jsonb_build_object('code', se.code, 'name', se.name,
                   'count', (select count(*) from _eligible() e where e.series_code = se.code)) order by se.sort) from series se));
end $$;

-- ---------------------------------------------------------------------
-- รอบชิงรางวัลใหญ่ (Final)
-- เปิดการ์ดทีละใบ 5 ครั้ง (สุ่มว่าใบไหน): ใบที่ 1 OUT · ใบที่ 2 IN · ใบที่ 3 IN · ใบที่ 4 OUT · ใบที่ 5 IN
-- จากนั้นเปิดว่าการ์ด IN ใบไหนเป็นรางวัลที่ 3 (step 6) → หมุนวงล้อ → ใบไหนเป็นรางวัลที่ 2 (step 7) → หมุน → ใบสุดท้าย = รางวัลที่ 1 (step 8) → หมุน (อันดับที่มีหลายชิ้น เช่น ที่ 3 สองชิ้น หมุนซ้ำจากการ์ดใบเดียวกัน)
-- ผลทั้งหมดสุ่มและล็อกไว้ตั้งแต่กดเริ่ม กดซ้ำหรือรีเฟรชไม่เปลี่ยนผล
-- ---------------------------------------------------------------------
drop function if exists draw_grand_create(text, int);
drop function if exists draw_grand_state(text, int);
drop function if exists draw_grand_next(text, int);
drop function if exists _final_cuts();

create or replace function _final_ranks() returns int[]
language sql stable set search_path = public as $$
  select coalesce(array_agg(rank order by rank desc), '{}') from (select distinct rank from prizes where kind = 'final' and rank between 1 and 3) x;
$$;

-- ตำแหน่งการ์ดของรางวัลที่ r ใน series_order (IN ใบแรก=ที่ 3, ใบสอง=ที่ 2, ใบสุดท้าย=ที่ 1)
drop function if exists _final_pos(int);
drop function if exists _final_rank_at(int);
-- การ์ดของรางวัลที่ r (rank_cards[1]=ที่ 3, [2]=ที่ 2, [3]=ที่ 1) · เปิดให้เห็นเมื่อ step >= 5 + (4 - r)
create or replace function _final_card(g final_draws, r int) returns text
language sql immutable as $$ select (coalesce(g.rank_cards, array[g.series_order[2], g.series_order[3], g.series_order[5]]))[4 - r]; $$;   -- รอบเก่าที่ไม่มี rank_cards ใช้ตำแหน่ง 2/3/5
create or replace function _final_reveal_step(r int) returns int
language sql immutable as $$ select 5 + (4 - r); $$;

-- รางวัลชิ้นถัดไปที่ยังไม่มีผู้รับ (อันดับท้ายสุดก่อน ชิ้นที่สร้างก่อนก่อน)
create or replace function _final_next_prize() returns prizes
language sql stable set search_path = public as $$
  select z.* from prizes z where z.kind = 'final' and z.rank between 1 and 3
     and not exists (select 1 from draw_results d where d.prize_id = z.id and not d.voided)
   order by z.rank desc, z.id limit 1;
$$;

-- ผู้มีสิทธิ์ของรางวัลที่ r: ถือการ์ดใบที่เปิดให้รางวัลนั้น ยังไม่เคยถูกเรียก (รับแล้ว/ไม่อยู่ ไม่ถูกสุ่มซ้ำ)
create or replace function _final_pool(g final_draws, r int) returns setof participants
language sql stable set search_path = public as $$
  select e.* from _eligible() e where e.series_code = _final_card(g, r)
     and e.id is distinct from g.pending_participant;
$$;

create or replace function _final_json(g final_draws) returns jsonb
language plpgsql stable set search_path = public as $$
declare ranks int[] := _final_ranks(); z prizes; nxt int; pp participants; phase text; pz prizes; revealed boolean;
begin
  z := _final_next_prize(); nxt := z.rank;
  revealed := nxt is not null and g.step >= _final_reveal_step(nxt);
  phase := case when g.done or nxt is null then 'done' when g.step < 5 then 'cut' when not revealed then 'reveal' else 'spin' end;
  if g.pending_participant is not null then select * into pp from participants where id = g.pending_participant; end if;
  if g.pending_prize is not null then select * into pz from prizes where id = g.pending_prize; end if;
  return jsonb_build_object(
    'id', g.id, 'step', g.step, 'cuts', 5, 'done', g.done, 'phase', phase,
    'ranks', to_jsonb(ranks), 'next_rank', case when not g.done then nxt end,
    'next_prize', case when not g.done and z.id is not null then jsonb_build_object('id', z.id, 'rank', z.rank, 'name', z.name, 'description', z.description, 'image', z.image,
        'seq', (select count(*) + 1 from draw_results d join prizes y on y.id = d.prize_id where y.kind = 'final' and y.rank = z.rank and not d.voided),
        'of', (select count(*) from prizes y where y.kind = 'final' and y.rank = z.rank)) end,
    'next_card', case when revealed then _final_card(g, nxt) end,
    'pool_left', case when revealed then (select count(*) from _final_pool(g, nxt)) else 0 end,
    'pool_tickets', case when revealed then (select coalesce(jsonb_agg(ticket_no order by random()), '[]'::jsonb) from _final_pool(g, nxt)) else '[]'::jsonb end,
    'series', (select jsonb_agg(jsonb_build_object(
        'code', se.code, 'name', se.name, 'color', se.color, 'tagline', se.tagline, 'pos', pos,
        'out', pos in (1, 4) and g.step >= pos,
        'in', pos in (2, 3, 5) and g.step >= pos,
        'rank', (select r from unnest(array[3, 2, 1]) r where _final_card(g, r) = se.code and g.step >= _final_reveal_step(r) limit 1),
        'holders', (select count(*) from _eligible() e where e.series_code = se.code)) order by se.sort)
       from (select se.*, coalesce(array_position(g.series_order, se.code), 9) as pos from series se) se),
    'pending', case when pp.id is null then null else jsonb_build_object(
        'ticket_no', pp.ticket_no, 'name', _mask_name(pp.name), 'rank', g.pending_rank, 'at', g.pending_at,
        'card', _final_card(g, g.pending_rank),
        'prize', pz.name, 'prize_id', pz.id, 'description', pz.description, 'image', pz.image) end,
    'winners', (select coalesce(jsonb_agg(jsonb_build_object('rank', z2.rank, 'prize', z2.name, 'prize_id', z2.id, 'ticket_no', p.ticket_no, 'card', p.series_code,
                  'name', _mask_name(p.name), 'at', d.drawn_at) order by z2.rank, z2.id), '[]'::jsonb)
                from draw_results d join prizes z2 on z2.id = d.prize_id join participants p on p.id = d.participant_id
               where z2.kind = 'final' and not d.voided),
    'noshows', (select coalesce(jsonb_agg(jsonb_build_object('rank', z2.rank, 'ticket_no', p.ticket_no, 'name', _mask_name(p.name), 'at', d.voided_at) order by d.voided_at), '[]'::jsonb)
                from draw_results d join prizes z2 on z2.id = d.prize_id join participants p on p.id = d.participant_id
               where z2.kind = 'final' and d.voided and d.void_reason = 'noshow'));
end $$;

create or replace function final_state(p_token text, p_draw_id int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s staff; g final_draws;
begin
  s := _staff_from_token(p_token, array['mc']);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  if p_draw_id is null then select * into g from final_draws order by id desc limit 1;
  else select * into g from final_draws where id = p_draw_id; end if;
  return jsonb_build_object('ok', true, 'draw', case when g.id is null then null else _final_json(g) end,
    'claim_sec', (select final_claim_sec from settings where id = 1),
    'prizes', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'rank', rank, 'name', name, 'description', description, 'image', image,
                 'won', (select count(*) from draw_results d where d.prize_id = prizes.id and not d.voided) > 0) order by rank, id), '[]'::jsonb)
               from prizes where kind = 'final' and rank between 1 and 3));
end $$;

create or replace function final_create(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s staff; g final_draws; ord text[]; tries int := 0; okay boolean := false; r int;
begin
  s := _staff_from_token(p_token, array['mc']);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  perform pg_advisory_xact_lock(42002);
  select * into g from final_draws order by id desc limit 1;
  if g.id is not null then
    if g.done then return jsonb_build_object('ok', false, 'code', 'FINAL_DONE'); end if;
    return final_state(p_token, g.id);
  end if;
  -- ต้องมีรางวัลครบทั้ง 3 อันดับ (การ์ด IN 3 ใบ = 3 อันดับ)
  for r in 1..3 loop
    if not exists (select 1 from prizes where kind = 'final' and rank = r) then
      return jsonb_build_object('ok', false, 'code', 'NO_FINAL_PRIZE', 'rank', r);
    end if;
  end loop;
  -- ทุกรางวัลมีผู้รับแล้ว (เช่น เล่นจบแล้วแต่ตารางรอบถูกล้าง) → ไม่เปิดรอบใหม่ ต้องยกเลิกสิทธิ์หรือล้างข้อมูลก่อน
  if (_final_next_prize()).id is null then return jsonb_build_object('ok', false, 'code', 'FINAL_DONE'); end if;
  if not exists (select 1 from _eligible()) then return jsonb_build_object('ok', false, 'code', 'NOT_ENOUGH'); end if;
  -- ถ้าแอดมินกำหนดลำดับการ์ดไว้ล่วงหน้า (ครบ 5 ใบ ไม่ซ้ำ รหัสถูกต้อง) ใช้ลำดับนั้น
  select final_order into ord from settings where id = 1;
  if ord is not null and array_length(ord, 1) = 5
     and (select count(distinct x) from unnest(ord) x) = 5
     and not exists (select 1 from unnest(ord) x where x not in (select code from series)) then
    -- ล็อก: ตำแหน่ง IN 2, 3, 5 = การ์ดรางวัลที่ 3, 2, 1 ตามที่แอดมินตั้ง
    insert into final_draws (series_order, rank_cards, pool_count, created_by) values (ord, array[ord[2], ord[3], ord[5]], (select count(*) from _eligible()), s.id) returning * into g;
    insert into audit_log (staff_id, action, detail) values (s.id, 'final_create', jsonb_build_object('draw', g.id, 'order', ord, 'ranks', g.rank_cards, 'locked', true));
    return final_state(p_token, g.id);
  end if;
  -- สุ่มลำดับการ์ด โดยพยายามให้การ์ด IN (ตำแหน่ง 2, 3, 5) มีผู้มีสิทธิ์อย่างน้อย 1 คน
  loop
    select array_agg(code order by random()) into ord from series;
    select bool_and((select count(*) from _eligible() e where e.series_code = ord[i]) >= 1) into okay
      from unnest(array[2, 3, 5]) i;
    tries := tries + 1;
    exit when okay or tries >= 50;
  end loop;
  -- สุ่มว่าการ์ด IN ใบไหนเป็นรางวัลที่ 3 / 2 / 1 (เปิดทีละใบบนเวที)
  insert into final_draws (series_order, rank_cards, pool_count, created_by)
  values (ord, (select array_agg(c order by random()) from unnest(array[ord[2], ord[3], ord[5]]) c), (select count(*) from _eligible()), s.id) returning * into g;
  insert into audit_log (staff_id, action, detail) values (s.id, 'final_create', jsonb_build_object('draw', g.id, 'order', ord, 'ranks', g.rank_cards));
  return final_state(p_token, g.id);
end $$;

-- กด 1 ครั้ง = เปิดการ์ดใบถัดไป (OUT/IN) · เมื่อครบ 5 ใบ = หมุนวงล้อสุ่มคนของรางวัลชิ้นถัดไป
create or replace function final_next(p_token text, p_draw_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s staff; g final_draws; z prizes; w participants;
begin
  s := _staff_from_token(p_token, array['mc']);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  select * into g from final_draws where id = p_draw_id for update;
  if g.id is null then return jsonb_build_object('ok', false, 'code', 'NOT_FOUND'); end if;
  if g.done then return final_state(p_token, g.id); end if;
  if g.step < 5 then
    update final_draws set step = step + 1 where id = g.id;
    insert into audit_log (staff_id, action, detail) values (s.id, 'final_open', jsonb_build_object('draw', g.id, 'pos', g.step + 1, 'card', g.series_order[g.step + 1],
      'result', case when g.step + 1 in (1, 4) then 'out' else 'in' end));
    return final_state(p_token, g.id);
  end if;
  if g.pending_participant is not null then return jsonb_build_object('ok', false, 'code', 'PENDING'); end if;
  z := _final_next_prize();
  if z.id is null then update final_draws set done = true where id = g.id; return final_state(p_token, g.id); end if;
  if g.step < _final_reveal_step(z.rank) then                              -- เปิดว่าการ์ดใบไหนเป็นรางวัลนี้
    update final_draws set step = _final_reveal_step(z.rank) where id = g.id;
    insert into audit_log (staff_id, action, detail) values (s.id, 'final_reveal', jsonb_build_object('draw', g.id, 'rank', z.rank, 'card', _final_card(g, z.rank)));
    return final_state(p_token, g.id);
  end if;
  select * into w from _final_pool(g, z.rank) order by random() limit 1;   -- หมุนวงล้อ
  if w.id is null then return jsonb_build_object('ok', false, 'code', 'NOT_ENOUGH'); end if;
  update final_draws set pending_participant = w.id, pending_rank = z.rank, pending_prize = z.id, pending_at = now() where id = g.id;
  insert into audit_log (staff_id, action, detail) values (s.id, 'final_spin', jsonb_build_object('draw', g.id, 'rank', z.rank, 'prize', z.id, 'participant', w.id));
  return final_state(p_token, g.id);
end $$;

create or replace function final_claim(p_token text, p_draw_id int, p_present boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s staff; g final_draws; pz int;
begin
  s := _staff_from_token(p_token, array['mc']);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  select * into g from final_draws where id = p_draw_id for update;
  if g.id is null then return jsonb_build_object('ok', false, 'code', 'NOT_FOUND'); end if;
  if g.pending_participant is null then return jsonb_build_object('ok', false, 'code', 'NO_PENDING'); end if;
  pz := g.pending_prize;
  if pz is null then select id into pz from prizes where kind = 'final' and rank = g.pending_rank order by id limit 1; end if;
  if pz is null then return jsonb_build_object('ok', false, 'code', 'NO_FINAL_PRIZE'); end if;
  if p_present then
    insert into draw_results (prize_id, participant_id, drawn_by) values (pz, g.pending_participant, s.id);
    insert into audit_log (staff_id, action, detail) values (s.id, 'final_award', jsonb_build_object('draw', g.id, 'rank', g.pending_rank, 'prize', pz, 'participant', g.pending_participant));
  else
    insert into draw_results (prize_id, participant_id, drawn_by, voided, voided_at, void_reason)
    values (pz, g.pending_participant, s.id, true, now(), 'noshow');
    insert into audit_log (staff_id, action, detail) values (s.id, 'final_noshow', jsonb_build_object('draw', g.id, 'rank', g.pending_rank, 'prize', pz, 'participant', g.pending_participant));
  end if;
  update final_draws set pending_participant = null, pending_rank = null, pending_prize = null, pending_at = null where id = g.id returning * into g;
  if (_final_next_prize()).id is null then update final_draws set done = true where id = g.id; end if;
  return final_state(p_token, g.id);
end $$;

-- แอดมินยกเลิกสิทธิ์ผู้ได้รางวัลภายหลัง (เช่น ตรวจแล้วไม่ตรงเงื่อนไข): เปิดรางวัลนั้นให้หมุนใหม่บนเวที
-- ฟังก์ชันนี้สุ่มแทนทันทีโดยไม่ผ่านวงล้อ สำหรับกรณีงานเลิกแล้ว (สุ่มให้รางวัลชิ้นแรกของอันดับนั้นที่ยังว่าง)
create or replace function final_replace(p_token text, p_rank int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s staff; g final_draws; pz int; w participants; rid int;
begin
  s := _staff_from_token(p_token, array['mc']);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  perform pg_advisory_xact_lock(42002);
  select * into g from final_draws order by id desc limit 1;
  if g.id is null or g.step < _final_reveal_step(p_rank) then return jsonb_build_object('ok', false, 'code', 'NOT_FOUND'); end if;
  select z.id into pz from prizes z where z.kind = 'final' and z.rank = p_rank
     and not exists (select 1 from draw_results d where d.prize_id = z.id and not d.voided) order by z.id limit 1;
  if pz is null then
    if exists (select 1 from prizes where kind = 'final' and rank = p_rank) then return jsonb_build_object('ok', false, 'code', 'PRIZE_DONE'); end if;
    return jsonb_build_object('ok', false, 'code', 'NO_FINAL_PRIZE');
  end if;
  select * into w from _final_pool(g, p_rank) order by random() limit 1;
  if w.id is null then return jsonb_build_object('ok', false, 'code', 'NOT_ENOUGH'); end if;
  insert into draw_results (prize_id, participant_id, drawn_by) values (pz, w.id, s.id) returning id into rid;
  insert into audit_log (staff_id, action, detail) values (s.id, 'final_replace', jsonb_build_object('rank', p_rank, 'prize', pz, 'result', rid));
  return jsonb_build_object('ok', true, 'ticket_no', w.ticket_no, 'name', _mask_name(w.name), 'rank', p_rank,
                            'prize', (select name from prizes where id = pz));
end $$;

create or replace function draw_prize_next(p_token text, p_prize_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s staff; z prizes; w participants; won int; rid int;
begin
  s := _staff_from_token(p_token, array['mc']);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  perform pg_advisory_xact_lock(42002);
  select * into z from prizes where id = p_prize_id and kind = 'normal';
  if z.id is null then return jsonb_build_object('ok', false, 'code', 'BAD_PRIZE'); end if;
  select count(*) into won from draw_results where prize_id = z.id and not voided;
  if won >= z.quantity then return jsonb_build_object('ok', false, 'code', 'PRIZE_DONE'); end if;
  select * into w from _eligible() order by random() limit 1;
  if w.id is null then return jsonb_build_object('ok', false, 'code', 'NOT_ENOUGH'); end if;
  insert into draw_results (prize_id, participant_id, drawn_by) values (z.id, w.id, s.id) returning id into rid;
  insert into audit_log (staff_id, action, detail) values (s.id, 'prize_draw', jsonb_build_object('result', rid));
  return jsonb_build_object('ok', true, 'result_id', rid, 'n', won + 1, 'quantity', z.quantity, 'image', z.image, 'description', z.description,
    'ticket_no', w.ticket_no, 'name', _mask_name(w.name), 'series_name', (select name from series where code = w.series_code));
end $$;

create or replace function draw_results_list(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s staff;
begin
  s := _staff_from_token(p_token, array['mc']);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
    'id', r.id, 'prize', z.name, 'prize_id', z.id, 'kind', z.kind, 'rank', z.rank, 'ticket_no', p.ticket_no,
    'name', case when s.role = 'admin' then p.name else _mask_name(p.name) end,
    'phone', case when s.role = 'admin' then p.phone else _mask_phone(p.phone) end,
    'series_name', se.name, 'drawn_at', r.drawn_at, 'voided', r.voided, 'received_at', r.received_at,
    'received_by', (select display_name from staff where id = r.received_by)) order by r.id desc)
    from draw_results r join prizes z on z.id = r.prize_id join participants p on p.id = r.participant_id
    join series se on se.code = p.series_code), '[]'::jsonb));
end $$;

-- ผู้ได้รางวัลไม่อยู่ในงาน: ยกเลิกแล้วสุ่มใหม่ได้ (คนที่ถูกยกเลิกจะไม่ได้สิทธิ์อีก)
create or replace function draw_void(p_token text, p_result_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s staff;
begin
  s := _staff_from_token(p_token, array[]::text[]);
  if s.id is null then return jsonb_build_object('ok', false, 'code', 'AUTH'); end if;
  update draw_results set voided = true, voided_at = now(), void_reason = 'admin' where id = p_result_id and not voided;
  -- ถ้าเป็นรางวัลรอบชิง เปิดรอบให้หมุนวงล้อรางวัลนั้นใหม่ได้
  update final_draws set done = false where done and exists (
    select 1 from draw_results d join prizes z on z.id = d.prize_id where d.id = p_result_id and z.kind = 'final');
  insert into audit_log (staff_id, action, detail) values (s.id, 'draw_void', jsonb_build_object('result', p_result_id));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- สิทธิ์การเรียกฟังก์ชัน: ปิดทั้งหมดก่อน แล้วเปิดเฉพาะฟังก์ชันสาธารณะ
-- ---------------------------------------------------------------------
revoke all on all functions in schema public from public, anon, authenticated;
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

grant execute on function
  event_info(), register_participant(text, boolean, text, text, text, text, boolean), get_passport(text),
  collect_stamp(text, text), staff_login(text, text), staff_me(text), staff_logout(text), station_me(text, int),
  souvenir_lookup(text, text), souvenir_redeem(text, text), prize_handover(text, text),
  admin_stats(text), admin_participants(text, text, text, int, int), admin_export(text),
  admin_import_prereg(text, jsonb, boolean), admin_stations(text), admin_station_save(text, int, text, boolean, boolean),
  admin_settings_save(text, jsonb), admin_staff_list(text), admin_staff_save(text, text, text, text, text, boolean, int), admin_prereg_list(text, text, text, int, int),
  admin_participant_update(text, text, text, text, text, text), admin_participant_delete(text, text), admin_prereg_update(text, text, text, text, text, text), admin_prereg_delete(text, text),
  admin_prizes(text), admin_prize_save(text, int, text, text, int, int, int, text, text), admin_prize_delete(text, int), admin_reset_event(text, text), admin_reset_draw(text, text),
  draw_eligible_count(text), final_create(text), final_state(text, int), final_next(text, int), final_claim(text, int, boolean), final_replace(text, int),
  draw_prize_next(text, int), draw_results_list(text), draw_void(text, int)
to anon, authenticated;
