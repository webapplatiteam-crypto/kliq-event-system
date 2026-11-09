"""Local stand-in for Supabase during testing: serves web/ and answers POST /rest/v1/rpc/<fn>
by calling the same SQL function as the anon role in local Postgres.
python3 shim.py <web_dir> <pg_socket_dir> <pg_port> <db> <http_port>
"""
import json, os, subprocess, sys, re
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

WEB, SOCK, PGPORT, DB, PORT = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])


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


class H(SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=WEB, **k)

    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path.split('?')[0] == '/config.js':
            body = f"window.KLIQ_CONFIG={{SUPABASE_URL:'http://127.0.0.1:{PORT}',SUPABASE_ANON_KEY:'test'}};".encode()
            self.send_response(200); self.send_header('Content-Type', 'text/javascript'); self.send_header('Content-Length', str(len(body)))
            self.end_headers(); self.wfile.write(body); return
        return super().do_GET()

    def do_OPTIONS(self):
        self.send_response(204)
        for k, v in [('Access-Control-Allow-Origin', '*'), ('Access-Control-Allow-Headers', '*'), ('Access-Control-Allow-Methods', 'POST')]:
            self.send_header(k, v)
        self.end_headers()

    def do_POST(self):
        m = re.match(r'^/rest/v1/rpc/([a-z_]+)$', self.path)
        if not m:
            self.send_error(404); return
        n = int(self.headers.get('Content-Length') or 0)
        args = json.loads(self.rfile.read(n) or b'{}')
        q = f"set role anon; select {m.group(1)}({', '.join(f'{k} => {lit(v)}' for k, v in args.items())})"
        r = subprocess.run(['psql', '-h', SOCK, '-p', PGPORT, '-U', 'postgres', '-d', DB, '-At', '-q', '-c', q], capture_output=True, text=True)
        if r.returncode != 0:
            body = json.dumps({'message': r.stderr.strip()}).encode(); code = 400
            print('SQL ERROR', m.group(1), r.stderr.strip()[:300], flush=True)
        else:
            body = (r.stdout.strip() or 'null').encode(); code = 200
        self.send_response(code)
        self.send_header('Content-Type', 'application/json'); self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)


ThreadingHTTPServer(('127.0.0.1', PORT), H).serve_forever()
