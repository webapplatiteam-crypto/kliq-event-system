-- ล้างข้อมูลทดสอบ 13 พ.ย. 2569 (ผู้ร่วมงานทดสอบ 1 คน + รางวัลทดสอบ 1 ชิ้น + ผลจับฉลาก)
-- รันใน Supabase → SQL Editor ครั้งเดียว · รายชื่อลงทะเบียนล่วงหน้า 264 คน และรางวัลจริง 4 ชิ้น ไม่ถูกแตะ
begin;
delete from draw_results where prize_id in (select id from prizes where name like '[ทดสอบ]%') or participant_id in (select id from participants where phone in ('0811110001','0811110002'));
delete from prizes where name like '[ทดสอบ]%';
delete from stamps where participant_id in (select id from participants where phone in ('0811110001','0811110002'));
delete from final_draws where true;
delete from participants where phone in ('0811110001','0811110002');
delete from audit_log where at >= '2026-11-13 11:00+07' and action in ('participant_edit','prize_handover','prize_draw','draw','final_create');
update series set next_no = 1;
alter sequence participant_ref_seq restart with 1;
commit;
select (select count(*) from participants) as participants, (select count(*) from prizes) as prizes,
       (select count(*) from draw_results) as results, (select count(*) from preregistrations) as prereg;
