-- =====================================================================
-- ล้างข้อมูลผู้ร่วมงานทั้งหมด (ใช้หลังซ้อม ก่อนเปิดงานจริง หรือหลังส่งมอบข้อมูลเพื่อลบตาม PDPA)
-- เก็บไว้: การตั้งค่า ซีรีส์ ฐาน (QR เดิม) รางวัล และบัญชีทีมงาน
-- *** ย้อนกลับไม่ได้ — Export ข้อมูลจากหน้าแอดมินก่อนเสมอ ***
-- =====================================================================
begin;
truncate draw_results, grand_draws, final_draws, stamps, participants, audit_log restart identity cascade;
-- ถ้าต้องการลบรายชื่อลงทะเบียนล่วงหน้าด้วย ให้เอา -- หน้าบรรทัดถัดไปออก
-- truncate preregistrations;
alter sequence participant_ref_seq restart with 1;
update series set next_no = 1 where true;
update settings set cutoff_at = null, registration_open = true, updated_at = now() where id = 1;
commit;
