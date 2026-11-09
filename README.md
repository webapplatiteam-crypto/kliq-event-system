# KLIQ Event System

ระบบงานเปิดตัว KLIQ: ลงทะเบียน → สุ่มการ์ด → Passport 6 ฐาน → ของที่ระลึก 2 แบบ → รอบชิงรางวัลใหญ่บนเวที
เว็บ static (`web/`) + Supabase (`supabase/`) · ขึ้นเว็บบน Netlify

- **คู่มือขึ้นระบบจริง (ภาษาไทย):** [`README_TH.md`](README_TH.md)
- **ฐานข้อมูล:** `supabase/schema.sql` → `supabase/seed.sql` (แก้ `v_admin_pin` ก่อนรัน) · ล้างข้อมูลซ้อม `supabase/reset_event_data.sql`
- **เว็บ:** แก้ `web/config.js` (Project URL + anon key) แล้วลากโฟลเดอร์ `web` ขึ้น app.netlify.com/drop
- **ทดสอบ:** `tests/db_test.py` (ฐานข้อมูล 120 กรณี) · `tests/e2e.py` (เบราว์เซอร์ 53 กรณี) ดูวิธีรันในหัวไฟล์
- **เดโม in-browser:** `python3 demo-src/build_demo.py web <out>` ได้เว็บทดลองที่ไม่ต้องใช้ Supabase
