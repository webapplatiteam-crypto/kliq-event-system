-- รีเซ็ตเฉพาะลักกี้ดรอว์ (ลบผลจับฉลาก + รอบชิง) — ผู้ร่วมงาน การ์ด แสตมป์ รายชื่อล่วงหน้า รางวัล ไม่ถูกแตะ
-- รันใน Supabase → SQL Editor · (ตั้งแต่ schema ล่าสุด ใช้ปุ่ม "รีเซ็ตลักกี้ดรอว์" ในหลังบ้าน → Lucky Draw แทนได้)
begin;
delete from draw_results where id is not null;
delete from final_draws where id is not null;
delete from grand_draws where id is not null;
commit;
select (select count(*) from participants) as participants_kept, (select count(*) from draw_results) as results, (select count(*) from final_draws) as finals;
