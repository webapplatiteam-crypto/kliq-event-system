-- =====================================================================
-- ข้อมูลเริ่มต้น: ซีรีส์ ฐานกิจกรรม รางวัล และบัญชีแอดมินคนแรก
-- รันหลัง schema.sql  *** เปลี่ยน PIN ของแอดมินในบรรทัดที่มีคำว่า v_admin_pin ก่อนรัน ***
-- =====================================================================

insert into series (code, name, color, tagline, sort) values
  ('U', 'UNO',   '#808A70', 'KLIQ WITH SIMPLIFY',    1),
  ('I', 'IKON',  '#15435A', 'KLIQ YOUR STYLE',       2),
  ('F', 'FORMA', '#DCC7B3', 'KLIQ EVERY HOTEL',      3),
  ('N', 'NOVA',  '#533D37', 'KLIQ TO BALANCE',       4),
  ('C', 'CASA',  '#96979C', 'KLIQ IN EVERY DETAILS', 5)
on conflict (code) do nothing;

-- ชื่อฐาน 6 ฐาน (แก้ได้ในหลังบ้าน → ฐานกิจกรรม & QR)
insert into stations (id, name, qr_token, sort)
select n, v.name, _rand_token(12), n
from (values (1, 'LUMENCRAFT'), (2, 'LIGHTING SOLUTION'), (3, 'KLIQ ROOM EXPERIENCE'), (4, 'KLIQ IKON MATCH'), (5, 'KLIQ CUSTOM COLORS'), (6, 'LiTon')) v(n, name)
on conflict (id) do nothing;
-- ถ้าเคยรัน seed เดิมที่ตั้งชื่อ "ฐาน 1..6" ให้อัปเดตชื่อเป็นชุดใหม่
update stations st set name = v.name from (values (1, 'LUMENCRAFT'), (2, 'LIGHTING SOLUTION'), (3, 'KLIQ ROOM EXPERIENCE'), (4, 'KLIQ IKON MATCH'), (5, 'KLIQ CUSTOM COLORS'), (6, 'LiTon')) v(n, name)
where st.id = v.n and st.name = 'ฐาน ' || st.id;

-- รางวัลรอบชิง: ประกาศ ที่ 3 → ที่ 2 → ที่ 1 (แก้ชื่อได้ในหลังบ้าน)
insert into prizes (name, kind, quantity, sort, rank)
select * from (values ('iPhone 18 Pro Max', 'final', 1, 1, 1), ('iPad Gen 11', 'final', 1, 2, 2),
                      ('หูฟังอินเอียร์ Beyerdynamic', 'final', 1, 3, 3), ('หูฟังไร้สาย KEF Mu7', 'final', 1, 4, 3)) v(name, kind, quantity, sort, rank)
where not exists (select 1 from prizes);

do $$
declare
  v_admin_code text := 'ADMIN01';
  v_admin_pin  text := '000000';   -- <<< เปลี่ยนเป็นตัวเลข 6 หลักของคุณ
begin
  if v_admin_pin = '000000' or v_admin_pin !~ '^\d{6}$' then
    raise exception 'กรุณาเปลี่ยน v_admin_pin เป็นตัวเลข 6 หลัก (ห้ามใช้ 000000) แล้วรันใหม่';
  end if;
  insert into staff (code, display_name, role, pin_hash)
  values (v_admin_code, 'ผู้ดูแลระบบหลัก', 'admin', extensions.crypt(v_admin_pin, extensions.gen_salt('bf')))
  on conflict (code) do update set pin_hash = excluded.pin_hash, active = true, failed_count = 0, locked_until = null;
end $$;
