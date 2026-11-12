"""Build demo/ from web/: relative paths, in-browser backend, demo hub. python3 build_demo.py <web> <out>"""
import os, re, shutil, sys
WEB, OUT = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))
shutil.rmtree(OUT, ignore_errors=True)
shutil.copytree(WEB, OUT, ignore=shutil.ignore_patterns('vercel.json', 'config.js', '_headers', '_redirects', 'netlify.toml'))
shutil.copy(os.path.join(HERE, 'demo-backend.js'), os.path.join(OUT, 'demo-backend.js'))
shutil.copy(os.path.join(HERE, 'demo-hub.html'), os.path.join(OUT, 'index.html'))

ABS = re.compile(r'''(href=|src=|location\.href = |location\.replace\(|location\.href = \(|: ')(["'])/(?!/)''')
PATHS = ['index.html', 'passport.html', 'scan.html', 's.html', 'collection.html', 'privacy.html', 'staff/login.html', 'staff/souvenir.html', 'staff/station.html',
         'stage/index.html', 'stage/final.html', 'stage/prize.html', 'admin/index.html', 'admin/participants.html', 'admin/stations.html',
         'admin/souvenir.html', 'admin/draw.html', 'admin/settings.html', 'assets/', 'vendor/', 'app.js', 'app.css', 'config.js', 'admin/admin.js']

def rel(depth):
    return '../' * depth

for root, _, files in os.walk(OUT):
    for f in files:
        if not f.endswith(('.html', '.js')): continue
        p = os.path.join(root, f)
        depth = os.path.relpath(root, OUT).count(os.sep) + (0 if os.path.relpath(root, OUT) == '.' else 1)
        s = open(p, encoding='utf-8').read()
        if f == 'index.html' and depth == 0: continue  # hub already relative
        base = rel(depth)
        if f == 'app.js':
            s = s.replace("location.href = '/staff/login.html?next=' + encodeURIComponent(location.pathname + location.search)", "location.href = DEMO_BASE + 'staff/login.html?next=' + encodeURIComponent(location.pathname + location.search)")
            s = s.replace("location.href = '/staff/login.html'", "location.href = DEMO_BASE + 'staff/login.html'")
            s = s.replace("return { admin: '/admin/index.html', souvenir: '/staff/souvenir.html', mc: '/stage/index.html', register: '/admin/participants.html', station: '/staff/station.html' }[role] || '/staff/login.html';",
                          "return DEMO_BASE + ({ admin: 'admin/index.html', souvenir: 'staff/souvenir.html', mc: 'stage/index.html', register: 'admin/participants.html', station: 'staff/station.html' }[role] || 'staff/login.html');")
            assert 'DEMO_BASE + ({ admin' in s, 'home() rewrite failed'
            s = s.replace("function seriesImg(code, kind) { return '/assets/kliq-'", "function seriesImg(code, kind) { return DEMO_BASE + 'assets/kliq-'")
            s = s.replace("  async function rpc(fn, args, opts) {\n    opts = opts || {};",
                          "  async function rpc(fn, args, opts) {\n    if (window.KLIQ_DEMO) { await sleep(120 + Math.random() * 180); return window.KLIQ_DEMO.call(fn, args); }\n    opts = opts || {};")
            s = "var DEMO_BASE = (function(){ var p = location.pathname; var i = p.indexOf('/admin/'); if (i < 0) i = p.indexOf('/staff/'); if (i < 0) i = p.indexOf('/stage/'); return i >= 0 ? p.slice(0, i + 1) : p.slice(0, p.lastIndexOf('/') + 1); })();\n" + s
            open(p, 'w', encoding='utf-8').write(s); continue
        # absolute site paths -> relative
        s = re.sub(r'''(["'(])/(index\.html|passport\.html|scan\.html|s\.html|collection\.html|privacy\.html|staff/|stage/|admin/|assets/|vendor/|app\.js|app\.css|config\.js)''',
                   lambda m: m.group(1) + base + m.group(2), s)
        s = s.replace("location.replace('/')", "location.replace('" + base + "register.html')")
        s = s.replace("'/' + ", "'register.html' + ")
        s = s.replace(base + 'index.html', base + 'register.html')
        s = s.replace("const origin = location.origin;", "const origin = location.href.replace(/admin\\/stations\\.html.*$/, '').replace(/\\/$/, '');")
        s = s.replace("origin + '" + base + "s.html?t='", "origin + '/s.html?t='")
        s = s.replace("qrSvg(origin + '/', 200)", "qrSvg(origin + '/register.html', 200)")
        s = s.replace("data-url=\"${esc(origin + '/')}\"", "data-url=\"${esc(origin + '/register.html')}\"")
        # include demo backend before app.js
        s = s.replace('<script src="' + base + 'app.js"></script>', '<script src="' + base + 'demo-backend.js"></script><script src="' + base + 'app.js"></script>')
        s = s.replace('<script src="' + base + 'config.js"></script>', '<script>window.KLIQ_CONFIG={SUPABASE_URL:"demo",SUPABASE_ANON_KEY:"demo"};</script>')
        # demo banner on every page
        if f.endswith('.html'):
            s = s.replace('</body>', '<div id="demobar" style="position:fixed;left:0;right:0;bottom:0;z-index:99;background:#C9A063;color:#121212;font:400 12px/1.4 Kanit,sans-serif;text-align:center;padding:5px 12px env(safe-area-inset-bottom,0px)">DEMO · ข้อมูลตัวอย่าง เก็บในเบราว์เซอร์นี้เท่านั้น · <a href="' + base + 'index.html" style="color:#121212;font-weight:500">หน้าหลักทดลอง</a></div></body>')
        open(p, 'w', encoding='utf-8').write(s)

os.rename(os.path.join(OUT, 'index.html'), os.path.join(OUT, 'index.html'))  # hub
# registration page = original index.html, renamed
shutil.move(os.path.join(WEB, 'index.html'), os.path.join(OUT, 'register.html')) if False else None
s = open(os.path.join(WEB, 'index.html'), encoding='utf-8').read()
s = re.sub(r'''(["'(])/(passport\.html|privacy\.html|assets/|app\.js|app\.css|config\.js)''', r'\1\2', s)
s = s.replace("location.replace(next || '/passport.html')", "location.replace(next || 'passport.html')").replace("location.href = next || '/passport.html?welcome=1'", "location.href = next || 'passport.html?welcome=1'")
s = s.replace('<script src="app.js"></script>', '<script src="demo-backend.js"></script><script src="app.js"></script>')
s = s.replace('<script src="config.js"></script>', '<script>window.KLIQ_CONFIG={SUPABASE_URL:"demo",SUPABASE_ANON_KEY:"demo"};</script>')
s = s.replace('</body>', '<div id="demobar" style="position:fixed;left:0;right:0;bottom:0;z-index:99;background:#C9A063;color:#121212;font:400 12px/1.4 Kanit,sans-serif;text-align:center;padding:5px 12px env(safe-area-inset-bottom,0px)">DEMO · ข้อมูลตัวอย่าง เก็บในเบราว์เซอร์นี้เท่านั้น · <a href="index.html" style="color:#121212;font-weight:500">หน้าหลักทดลอง</a></div></body>')
open(os.path.join(OUT, 'register.html'), 'w', encoding='utf-8').write(s)
# scan page: QR URL -> relative s.html
p = os.path.join(OUT, 'scan.html'); s = open(p, encoding='utf-8').read()
s = s.replace("location.href = '/s.html?t='", "location.href = 's.html?t='").replace("location.href = '" + "s.html?t='", "location.href = 's.html?t='")
open(p, 'w', encoding='utf-8').write(s)
left = []
for root, _, files in os.walk(OUT):
    for f in files:
        if f.endswith(('.html', '.js')) and 'vendor' not in root and f != 'demo-backend.js':
            t = open(os.path.join(root, f), encoding='utf-8').read()
            for m in re.finditer(r'''(["'(])/(passport|scan|s\.html|collection|privacy|staff/|stage/|admin/|assets/|app\.|index\.html|register)''', t):
                left.append((f, m.group(0)))
print('built', OUT, 'absolute paths left:', left[:10])
