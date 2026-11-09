/* sidebar + guard for admin pages */
window.AdminShell = async function (active, roles) {
  const me = await K.STAFF.guard(roles || []);
  if (!me) return null;
  const links = [
    ['index', '/admin/index.html', 'ภาพรวม', ['admin', 'mc', 'register', 'souvenir']],
    ['participants', '/admin/participants.html', 'ผู้ร่วมงาน', ['admin', 'register', 'souvenir']],
    ['stations', '/admin/stations.html', 'ฐานกิจกรรม & QR', ['admin']],
    ['souvenir', '/admin/souvenir.html', 'ของที่ระลึก', ['admin', 'souvenir']],
    ['draw', '/admin/draw.html', 'Lucky Draw', ['admin']],
    ['settings', '/admin/settings.html', 'ตั้งค่า & ทีมงาน', ['admin']],
    ['stage', '/stage/index.html', 'เปิดจอเวที ↗', ['admin', 'mc']],
    ['staff', '/staff/souvenir.html', 'หน้าเจ้าหน้าที่รับของ ↗', ['admin', 'souvenir']]
  ];
  const side = document.getElementById('side');
  side.innerHTML = '<div class="brand" style="padding:0 12px 4px">KLIQ</div><div class="t">KLIQ Admin</div>' +
    links.filter(l => l[3].indexOf(me.role) >= 0).map(l => `<a href="${l[1]}" class="${l[0] === active ? 'on' : ''}">${l[2]}</a>`).join('') +
    `<div class="who"><span>${K.esc(me.name)} · ${K.esc(me.role)}</span><button type="button" id="logout">ออกจากระบบ</button></div>`;
  document.getElementById('logout').onclick = () => K.STAFF.logout();
  return me;
};
