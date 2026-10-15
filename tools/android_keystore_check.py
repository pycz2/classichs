#!/usr/bin/env python3
"""Checks the Android signing secrets locally, in a browser page, before you put them
into GitHub (Settings → Secrets → Actions): ANDROID_KEYSTORE_BASE64,
ANDROID_KEYSTORE_USER (the key alias) and ANDROID_KEYSTORE_PASSWORD.
The page runs the same checks as .github/workflows/release.yml and says what is wrong
and how to fix it; it can also make a new keystore with the right settings.

Usage: python3 tools/android_keystore_check.py      (opens the page; Ctrl+C stops it)
Needs `keytool` (any Java). Listens on 127.0.0.1 only; a random token guards the page;
the secrets are never printed or stored (a temporary file is deleted at once).
"""
import base64
import binascii
import html
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = secrets.token_urlsafe(16)
KEYTOOL = shutil.which("keytool")


def keytool(*args, timeout=30):
    r = subprocess.run([KEYTOOL, *args], capture_output=True, text=True, timeout=timeout,
                       env={**os.environ, "LC_ALL": "C", "LANG": "C"})
    return r.returncode, (r.stdout + r.stderr).strip()


def step(ok, title, detail="", fix=""):
    return {"ok": ok, "title": title, "detail": detail, "fix": fix}


def check(b64: str, user: str, password: str) -> list:
    out = []
    # 1. the values as GitHub will keep them
    for name, v in (("ANDROID_KEYSTORE_USER", user), ("ANDROID_KEYSTORE_PASSWORD", password)):
        if v != v.strip():
            out.append(step(None, f"{name}: пробелы или переводы строки по краям",
                            "GitHub хранит секрет ровно так, как его вставили. CI убирает переводы строк, но не пробелы.",
                            "Вставьте значение заново, без пробелов до и после."))
    if not user.strip():
        out.append(step(False, "ANDROID_KEYSTORE_USER пустой", "", "Впишите alias ключа (например, classichs)."))
    if not password:
        out.append(step(False, "ANDROID_KEYSTORE_PASSWORD пустой", "", "Впишите пароль хранилища ключей."))
    user, password = user.strip(), password.strip("\r\n")
    # 2. base64 → file
    text = re.sub(r"\s+", "", b64)
    if not text:
        out.append(step(False, "ANDROID_KEYSTORE_BASE64 пустой", "", "Выполните: base64 -i ваш.keystore | pbcopy  и вставьте результат."))
        return out
    if "BEGIN" in b64:
        out.append(step(False, "ANDROID_KEYSTORE_BASE64 похож на сертификат PEM, а не на хранилище ключей",
                        "", "Закодируйте весь файл .keystore / .jks: base64 -i ваш.keystore | pbcopy"))
        return out
    try:
        data = base64.b64decode(text, validate=True)
    except (binascii.Error, ValueError) as e:
        out.append(step(False, "ANDROID_KEYSTORE_BASE64 — не корректный base64", str(e),
                        "Скопируйте заново целиком: base64 -i ваш.keystore | pbcopy  (без кавычек, ничего не обрезая)."))
        return out
    if re.fullmatch(rb"[A-Za-z0-9+/=\s]+", data[:200] or b"x"):
        out.append(step(False, "ANDROID_KEYSTORE_BASE64 закодирован в base64 дважды",
                        "После раскодирования это всё ещё текст base64.", "Закодируйте файл один раз: base64 -i ваш.keystore | pbcopy"))
        return out
    kind = "JKS" if data[:4] == b"\xfe\xed\xfe\xed" else ("PKCS12" if data[:1] == b"\x30" else "unknown")
    out.append(step(True, "ANDROID_KEYSTORE_BASE64 раскодируется", f"{len(data)} байт, похоже на {kind}."))
    if kind == "unknown":
        out.append(step(False, "Раскодированный файл — не хранилище ключей", "Его первые байты не похожи ни на JKS, ни на PKCS12.",
                        "Закодируйте сам файл .keystore / .jks, а не другой файл."))
        return out
    with tempfile.TemporaryDirectory() as d:
        f = os.path.join(d, "check.keystore")
        with open(os.open(f, os.O_WRONLY | os.O_CREAT, 0o600), "wb") as fh:
            fh.write(data)
        # 3. the store password
        rc, txt = keytool("-list", "-keystore", f, "-storepass", password)
        if rc != 0:
            if "password was incorrect" in txt or "Keystore was tampered" in txt or "keystore password" in txt.lower():
                out.append(step(False, "ANDROID_KEYSTORE_PASSWORD не открывает хранилище", "keytool: неверный пароль хранилища.",
                                "Укажите пароль, который вы вводили при создании хранилища (пароль хранилища)."))
            else:
                out.append(step(False, "keytool не может прочитать хранилище", txt[-400:], "Создайте хранилище заново (ниже)."))
            return out
        out.append(step(True, "ANDROID_KEYSTORE_PASSWORD открывает хранилище"))
        # 4. the alias
        aliases = re.findall(r"^(.+?), .*?(PrivateKeyEntry|trustedCertEntry|SecretKeyEntry),?\s*$", txt, re.M)  # "alias, Oct 16, 2026, PrivateKeyEntry,"
        names = [a for a, _ in aliases]
        listed = ", ".join(f"{a} ({k})" for a, k in aliases) or "none"
        match = [a for a, k in aliases if a == user]
        if not match:
            near = [a for a in names if a.lower() == user.lower()]
            fix = (f"Впишите в ANDROID_KEYSTORE_USER точно: {near[0]} (регистр важен)" if near else
                   (f"Впишите в ANDROID_KEYSTORE_USER alias ключа: {names[0]}" if names else "Создайте хранилище заново (ниже)."))
            out.append(step(False, f"В хранилище нет ключа с alias «{user}»", f"Alias в хранилище: {listed}.", fix))
            return out
        kinds = dict(aliases)
        if kinds.get(user) != "PrivateKeyEntry":
            out.append(step(False, f"«{user}» — это {kinds.get(user)}, а не закрытый ключ",
                            "Одним сертификатом APK не подписать.", "Укажите alias записи PrivateKeyEntry или создайте хранилище заново (ниже)."))
            return out
        out.append(step(True, f"ANDROID_KEYSTORE_USER «{user}» — закрытый ключ в хранилище"))
        # 5. key password == store password (Godot has one password for both)
        rc, txt = keytool("-certreq", "-keystore", f, "-storepass", password, "-keypass", password, "-alias", user,
                          "-file", os.path.join(d, "req.csr"))
        if rc != 0:
            out.append(step(False, "У ключа свой пароль, не такой, как у хранилища",
                            "Godot (и CI) используют ANDROID_KEYSTORE_PASSWORD для обоих.",
                            f"Дайте ключу тот же пароль: keytool -keypasswd -keystore ваш.keystore -alias {user}  "
                            "(введите пароль хранилища, затем старый пароль ключа, затем пароль хранилища как новый); "
                            "или переведите в PKCS12, где пароль всегда один: keytool -importkeystore -srckeystore ваш.keystore "
                            "-destkeystore new.keystore -deststoretype PKCS12  — и закодируйте new.keystore."))
            return out
        out.append(step(True, "Ключ открывается тем же паролем"))
        # 6. the certificate (information)
        rc, txt = keytool("-list", "-v", "-keystore", f, "-storepass", password, "-alias", user)
        until = re.search(r"until:\s*(.+)", txt)
        owner = re.search(r"Owner:\s*(.+)", txt)
        out.append(step(True, "Сертификат", f"Владелец: {owner.group(1) if owner else '?'}; действует до: {until.group(1) if until else '?'}."))
    out.append(step(True, "Всё верно: эти три секрета подпишут APK",
                    "Вставьте их в GitHub ровно так; следующий тег версии подпишет этим ключом.",
                    "Сохраните файл .keystore и пароль: обновление ставится поверх старой версии только с тем же ключом."))
    return out


def generate(alias: str, password: str) -> dict:
    alias = alias.strip() or "classichs"
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,64}", alias):
        return {"error": "В alias можно использовать буквы, цифры и _ . - (до 64 символов)."}
    password = password or secrets.token_urlsafe(18)
    if len(password) < 6:
        return {"error": "Пароль должен быть не короче 6 символов."}
    home = os.path.expanduser("~")
    path = os.path.join(home, "classichs-release.keystore")
    n = 1
    while os.path.exists(path):
        n += 1
        path = os.path.join(home, f"classichs-release-{n}.keystore")
    rc, txt = keytool("-genkeypair", "-keystore", path, "-storetype", "PKCS12", "-alias", alias, "-keyalg", "RSA",
                      "-keysize", "2048", "-validity", "10000", "-storepass", password, "-keypass", password,
                      "-dname", "CN=Classic HS", timeout=60)
    if rc != 0:
        return {"error": "keytool не сработал: " + txt[-400:]}
    os.chmod(path, 0o600)
    with open(path, "rb") as fh:
        b64 = base64.b64encode(fh.read()).decode()
    return {"path": path, "base64": b64, "user": alias, "password": password}


PAGE = r"""<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Подпись Android</title><style>
:root{--bg:#14100c;--p:#211912;--p2:#2b2018;--l:#46362a;--t:#f3e9d6;--m:#b4a387;--g:#f2c230;--ok:#55d47a;--no:#ff7a6b;--w:#ffae4a}
@media (prefers-color-scheme: light){:root{--bg:#f7f0e3;--p:#fffaf1;--p2:#f7eedc;--l:#e2d3b8;--t:#2a1f17;--m:#6c5a43;--g:#a8741a;--ok:#1f8a3a;--no:#b33a2c;--w:#b5651d}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--t);font:15.5px/1.55 -apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:860px;margin:0 auto;padding:28px 18px 60px}h1{color:var(--g);margin:0 0 4px}h2{margin:28px 0 8px}.m{color:var(--m)}
label{display:block;font-weight:600;margin:14px 0 4px}textarea,input{width:100%;font:13px ui-monospace,Menlo,monospace;background:var(--p);color:var(--t);border:1px solid var(--l);border-radius:9px;padding:9px}
textarea{height:110px}button{font:inherit;font-weight:600;margin-top:14px;padding:9px 18px;border-radius:9px;border:1px solid var(--g);background:var(--g);color:#1b140d;cursor:pointer}
button.s{background:var(--p2);color:var(--t);border-color:var(--l)}.card{background:var(--p);border:1px solid var(--l);border-radius:12px;padding:14px 16px;margin:12px 0}
.r{display:grid;grid-template-columns:28px 1fr;gap:8px;padding:9px 0;border-bottom:1px solid var(--l)}.r:last-child{border:0}.i{font-size:18px}
.ok .i{color:var(--ok)}.no .i{color:var(--no)}.wa .i{color:var(--w)}.d{color:var(--m);font-size:14px}.f{margin-top:4px;font-size:14px}.f b{color:var(--g)}
a{color:var(--g)}code{font:13px ui-monospace,Menlo,monospace;background:var(--p2);border:1px solid var(--l);border-radius:6px;padding:1px 5px}
.copy{display:flex;gap:8px;align-items:center}.copy input{flex:1}.copy button{margin:0;padding:6px 12px}
</style></head><body><main>
<h1>Подпись Android</h1>
<p class="m">Вставьте значения, которые вы положили в секреты GitHub (Settings → Secrets and variables → Actions). Страница проверит их так же, как CI, и скажет, что не так. Данные никуда не уходят: сервер работает только на этом компьютере.</p>
<form id="f">
<label>ANDROID_KEYSTORE_BASE64</label><textarea name="b64" placeholder="base64 файла хранилища ключей" spellcheck="false"></textarea>
<label>ANDROID_KEYSTORE_USER (alias ключа)</label><input name="user" autocomplete="off" spellcheck="false">
<label>ANDROID_KEYSTORE_PASSWORD</label><input name="password" type="password" autocomplete="off">
<button>Проверить</button></form>
<div id="out"></div>
<h2>Сделать новое хранилище ключей</h2>
<div class="card"><p class="m">Если старого файла нет или его не удаётся починить: страница создаст новый ключ PKCS12 (один пароль для хранилища и ключа, срок 27 лет), сохранит его в домашнюю папку и покажет три значения для GitHub. Важно: на телефоне, где уже стоит игра со старой подписью, нужно один раз удалить её перед установкой.</p>
<form id="g"><label>Alias</label><input name="alias" value="classichs"><label>Пароль (пусто — придумать случайный)</label><input name="password" type="password" autocomplete="new-password"><button class="s">Создать</button></form>
<div id="gen"></div></div>
<p class="m">Что дальше: <a href="https://github.com/pycz2/classichs/settings/secrets/actions" target="_blank" rel="noopener">секреты репозитория</a> → для каждого из трёх имён «Update» → вставить значение → сохранить. Новая подпись сработает со следующего тега версии.</p>
</main><script>
const T = "__TOKEN__";
function esc(s){const d=document.createElement("div");d.textContent=s||"";return d.innerHTML}
async function post(url, data){const r=await fetch(url,{method:"POST",headers:{"Content-Type":"application/json","X-Token":T},body:JSON.stringify(data)});return r.json()}
document.getElementById("f").onsubmit=async e=>{e.preventDefault();const f=new FormData(e.target);const out=document.getElementById("out");out.innerHTML='<div class="card m">Проверяю…</div>';
 const res=await post("/check",{b64:f.get("b64"),user:f.get("user"),password:f.get("password")});
 if(res.error){out.innerHTML='<div class="card no">'+esc(res.error)+'</div>';return}
 out.innerHTML='<div class="card">'+res.steps.map(s=>`<div class="r ${s.ok===true?"ok":s.ok===false?"no":"wa"}"><div class="i">${s.ok===true?"✔":s.ok===false?"✘":"!"}</div><div><b>${esc(s.title)}</b>${s.detail?'<div class="d">'+esc(s.detail)+'</div>':""}${s.fix?'<div class="f"><b>Как исправить:</b> '+esc(s.fix)+'</div>':""}</div></div>`).join("")+'</div>'};
document.getElementById("g").onsubmit=async e=>{e.preventDefault();const f=new FormData(e.target);const g=document.getElementById("gen");g.innerHTML='<p class="m">Создаю…</p>';
 const r=await post("/generate",{alias:f.get("alias"),password:f.get("password")});
 if(r.error){g.innerHTML='<p style="color:var(--no)">'+esc(r.error)+'</p>';return}
 const row=(n,v)=>`<label>${n}</label><div class="copy"><input readonly value="${esc(v)}"><button class="s" type="button" onclick="navigator.clipboard.writeText(this.previousElementSibling.value);this.textContent='Скопировано'">Копировать</button></div>`;
 g.innerHTML=`<p>Файл сохранён: <code>${esc(r.path)}</code>. Сохраните его и пароль в надёжном месте (например, в менеджере паролей).</p>`+row("ANDROID_KEYSTORE_BASE64",r.base64)+row("ANDROID_KEYSTORE_USER",r.user)+row("ANDROID_KEYSTORE_PASSWORD",r.password);
 const ff=document.getElementById("f");ff.b64.value=r.base64;ff.user.value=r.user;ff.password.value=r.password;};
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # never log requests (they carry secrets)
        pass

    def _send(self, code, body, ctype):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy", "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'")
        self.send_header("X-Frame-Options", "DENY")
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path != "/" + TOKEN:
            return self._send(404, "not found", "text/plain")
        self._send(200, PAGE.replace("__TOKEN__", TOKEN), "text/html; charset=utf-8")

    def do_POST(self):
        if self.headers.get("X-Token") != TOKEN or self.path not in ("/check", "/generate"):
            return self._send(403, "{}", "application/json")
        try:
            n = min(int(self.headers.get("Content-Length", "0")), 1 << 20)
            req = json.loads(self.rfile.read(n) or b"{}")
            if self.path == "/check":
                res = {"steps": check(str(req.get("b64", "")), str(req.get("user", "")), str(req.get("password", "")))}
            else:
                res = generate(str(req.get("alias", "")), str(req.get("password", "")))
        except Exception as e:  # report, never crash the page
            res = {"error": f"{type(e).__name__}: {html.escape(str(e))[:300]}"}
        self._send(200, json.dumps(res), "application/json")


def main():
    if not KEYTOOL:
        sys.exit("keytool not found: install Java (for example: brew install openjdk) and run again.")
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    url = f"http://127.0.0.1:{srv.server_address[1]}/{TOKEN}"
    print(f"Open: {url}\n(Ctrl+C to stop)", flush=True)
    if "--no-browser" not in sys.argv:
        webbrowser.open(url)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
