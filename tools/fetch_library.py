#!/usr/bin/env python3
"""fetch_library.py — загрузчик CC0-библиотеки ассетов для blockparty.

Источники (решение владельца от 12.10):
  Poly Haven: модели glTF 1K (все); HDRI 2K .hdr (только уличные);
              текстуры 1K JPG (все) + 2K JPG (строгий фильтр категорий).
  ambientCG: 1K-JPG (все) + 2K-JPG (категории природы/построек).
  OpenGameArt: 6 фиксированных страниц (проверять CC0 на странице).

Вежливость: одна загрузка за раз, паузы, повторы, докачка (повторный запуск
пропускает скачанное по размеру файла). Прогресс и метаданные — manifest.json.
Запуск: python3 tools/fetch_library.py [ph|acg|oga|catalog|all]
"""
import json, os, re, sys, io, csv, time, random, urllib.request, urllib.error, zipfile, html.parser

ROOT = os.path.expanduser("~/blockparty/library")
B = "https://api.polyhaven.com"
UA = {"User-Agent": "blockparty-library-fetcher/1.0 (polite; sequential)"}
MANIFEST = os.path.join(ROOT, "manifest.json")

STRICT_CATS = {re.sub(r"[^a-z]", "", x) for x in [
    "wood", "planks", "plank", "stone", "rock", "ground", "sand", "moss",
    "bark", "brick", "bricks", "masonry", "roof", "roofing", "roofs",
    "plaster", "paving", "paving stone", "paving stones", "pavingstone"]}
ACG_PREFIX = {"ground", "dirt", "grassfree", "stone", "stones", "pebbles",
    "rocks", "rock", "sand", "moss", "bark", "wood", "planks", "boards",
    "bricks", "brick", "stonewall", "masonry", "blocks", "roof", "roofs",
    "tiles", "tile", "shingles", "plaster", "paving", "pavingstones", "path", "gravel"}
OGA_PAGES = [
    ("deer-female", "https://opengameart.org/content/deer-female"),
    ("old-deer-male", "https://opengameart.org/content/old-deer-male"),
    ("rabbit-51722", "https://opengameart.org/node/51722"),
    ("fish-49204", "https://opengameart.org/node/49204"),
    ("bird", "https://opengameart.org/content/bird"),
    ("wolf-3d", "https://opengameart.org/content/3d-wolf"),
]

def load_manifest():
    if os.path.exists(MANIFEST):
        return json.load(open(MANIFEST))
    return {"done": {}, "failed": {}, "meta": {}}

def save_manifest(m):
    json.dump(m, open(MANIFEST, "w"), indent=0, ensure_ascii=False)

def get_json(url, tries=4):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read().decode())
        except Exception as e:
            if i == tries - 1:
                raise
            time.sleep(2 * (i + 1))

def http_get_bytes(url, tries=5):
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=300) as r:
                return r.read()
        except Exception as e:
            last = e
            time.sleep(min(30, 3 * (i + 1)))
    raise last

def download(url, dest, size=None):
    """Скачивает файл, если его нет или размер не совпал. Возвращает статус."""
    if os.path.exists(dest) and size is not None and os.path.getsize(dest) == size:
        return "skip"
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".part"
    for i in range(5):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=600) as r, open(tmp, "wb") as f:
                while True:
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
            if size is not None and os.path.getsize(tmp) != size:
                raise IOError(f"size mismatch: {os.path.getsize(tmp)} != {size}")
            os.replace(tmp, dest)
            return "ok"
        except Exception:
            time.sleep(min(60, 5 * (i + 1)))
    if os.path.exists(tmp):
        os.remove(tmp)
    raise IOError(f"failed: {url}")

def ph_tex_jpgs(f, res):
    out = {}
    for m, mv in f.items():
        if isinstance(mv, dict):
            jpg = mv.get(res, {}).get("jpg")
            if isinstance(jpg, dict) and jpg.get("url"):
                out[m] = jpg
    return out

def normcat(cats):
    return [re.sub(r"[^a-z]", "", c.lower()) for c in (cats or [])]

def ph(m):
    os.makedirs(f"{ROOT}/polyhaven", exist_ok=True)
    # --- модели: все, glTF 1K ---
    assets = get_json(f"{B}/assets?type=models")
    n = 0
    for aid, a in assets.items():
        key = f"ph_model:{aid}"
        if m["done"].get(key):
            continue
        try:
            f = get_json(f"{B}/files/{aid}")
            g = f.get("gltf", {}).get("1k", {}).get("gltf", {})
            d = f"{ROOT}/polyhaven/models/{aid}"
            if g.get("url"):
                download(g["url"], f"{d}/{aid}_1k.gltf", g.get("size"))
            for inc, idata in (g.get("include") or {}).items():
                if idata.get("url"):
                    download(idata["url"], f"{d}/{inc}", idata.get("size"))
            prev = f.get("Diffuse", {}).get("1k", {}).get("jpg", {})
            if prev.get("url"):
                download(prev["url"], f"{d}/preview.jpg")
            m["done"][key] = d
            m["meta"][key] = {"name": a.get("name", aid), "cat": ",".join(a.get("categories", [])[:2]),
                "url": f"https://polyhaven.com/a/{aid}", "authors": ",".join(a.get("authors", {}).keys()),
                "license": "CC0", "anims": ""}
            n += 1
            time.sleep(0.6)
            if n % 25 == 0:
                save_manifest(m); print(f"models {n}...", flush=True)
        except Exception as e:
            m["failed"][key] = str(e)
    # --- HDRI: уличные, 2K ---
    assets = get_json(f"{B}/assets?type=hdris")
    outdoor = {aid: a for aid, a in assets.items()
               if not any(c in ("studio", "indoor", "interior", "interiors", "studio_small", "studio_large")
                          for c in normcat(a.get("categories")))}
    print(f"HDRI уличных: {len(outdoor)}", flush=True)
    n = 0
    for aid, a in outdoor.items():
        key = f"ph_hdri:{aid}"
        if m["done"].get(key):
            continue
        try:
            f = get_json(f"{B}/files/{aid}")
            d = f"{ROOT}/polyhaven/hdris/{aid}"
            hdr = f.get("hdri", {}).get("2k", {}).get("hdr", {})
            if hdr.get("url"):
                download(hdr["url"], f"{d}/{aid}_2k.hdr", hdr.get("size"))
            prev = f.get("tonemapped", {}).get("1k", {}).get("jpg", {})
            if prev.get("url"):
                download(prev["url"], f"{d}/preview.jpg")
            m["done"][key] = d
            m["meta"][key] = {"name": a.get("name", aid), "cat": ",".join(a.get("categories", [])[:2]),
                "url": f"https://polyhaven.com/a/{aid}", "authors": ",".join(a.get("authors", {}).keys()),
                "license": "CC0", "anims": ""}
            n += 1
            time.sleep(0.6)
            if n % 25 == 0:
                save_manifest(m); print(f"hdris {n}...", flush=True)
        except Exception as e:
            m["failed"][key] = str(e)
    # --- текстуры: 1K все, 2K строгий фильтр ---
    assets = get_json(f"{B}/assets?type=textures")
    n = 0
    for aid, a in assets.items():
        strict = any(c in STRICT_CATS for c in normcat(a.get("categories")))
        key = f"ph_tex:{aid}"
        if m["done"].get(key):
            continue
        try:
            f = get_json(f"{B}/files/{aid}")
            d = f"{ROOT}/polyhaven/textures/{aid}"
            for res in ("1k", "2k"):
                if res == "2k" and not strict:
                    continue
                for mapn, jd in ph_tex_jpgs(f, res).items():
                    download(jd["url"], f"{d}/{aid}_{mapn.lower()}_{res}.jpg", jd.get("size"))
            if "Diffuse" in ph_tex_jpgs(f, "1k"):
                jd = ph_tex_jpgs(f, "1k")["Diffuse"]
                download(jd["url"], f"{d}/preview.jpg")
            m["done"][key] = d
            m["meta"][key] = {"name": a.get("name", aid), "cat": ",".join(a.get("categories", [])[:2]),
                "url": f"https://polyhaven.com/a/{aid}", "authors": ",".join(a.get("authors", {}).keys()),
                "license": "CC0", "anims": "", "strict2k": strict}
            n += 1
            time.sleep(0.5)
            if n % 25 == 0:
                save_manifest(m); print(f"textures {n}...", flush=True)
        except Exception as e:
            m["failed"][key] = str(e)
    save_manifest(m)

def acg(m):
    req = urllib.request.Request("https://ambientcg.com/api/v2/downloads_csv", headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r:
        rows = list(csv.DictReader(io.StringIO(r.read().decode("utf-8", "replace"))))
    by_asset = {}
    for row in rows:
        aid = row["assetId"]
        attr = row.get("downloadAttribute", "")
        if attr in ("1K-JPG", "2K-JPG"):
            prefix = "".join(c for c in aid if c.isalpha()).lower()
            if attr == "2K-JPG" and prefix not in ACG_PREFIX:
                continue
            by_asset.setdefault(aid, []).append(row)
    print(f"ambientCG к загрузке: {len(by_asset)} ассетов", flush=True)
    n = 0
    for aid, rws in by_asset.items():
        key = f"acg:{aid}"
        if m["done"].get(key):
            continue
        prefix = "".join(c for c in aid if c.isalpha())
        d = f"{ROOT}/ambientcg/{prefix}/{aid}"
        try:
            for row in rws:
                attr = row["downloadAttribute"]
                zpath = f"{d}/{aid}_{attr}.zip"
                if not os.path.exists(zpath.replace(".zip", ".done")):
                    data = http_get_bytes(row["downloadLink"])
                    os.makedirs(d, exist_ok=True)
                    with open(zpath, "wb") as f:
                        f.write(data)
                    with zipfile.ZipFile(zpath) as z:
                        z.extractall(d)
                    os.remove(zpath)
                    open(zpath.replace(".zip", ".done"), "w").close()
            prevs = [x for x in os.listdir(d) if "preview" in x.lower() and x.lower().endswith((".jpg", ".png"))] if os.path.isdir(d) else []
            m["done"][key] = d
            m["meta"][key] = {"name": aid, "cat": prefix, "url": f"https://ambientcg.com/view?id={aid}",
                "authors": "ambientCG (Lennart Demes)", "license": "CC0", "anims": ""}
            n += 1
            time.sleep(0.6)
            if n % 25 == 0:
                save_manifest(m); print(f"ambientcg {n}...", flush=True)
        except Exception as e:
            m["failed"][key] = str(e)
    save_manifest(m)

class LinkParser(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(); self.hrefs = []; self.meta = {}
    def handle_starttag(self, tag, attrs):
        ad = dict(attrs)
        if tag == "a" and ad.get("href"):
            self.hrefs.append(ad["href"])
        if tag == "meta" and ad.get("property") == "og:image":
            self.meta["og"] = ad.get("content")

def oga(m):
    for slug, url in OGA_PAGES:
        key = f"oga:{slug}"
        if m["done"].get(key):
            continue
        try:
            html_text = http_get_bytes(url).decode("utf-8", "replace")
            if "CC0" not in html_text:
                m["failed"][key] = "на странице нет пометки CC0 — пропущено по правилу"
                continue
            p = LinkParser(); p.feed(html_text)
            d = f"{ROOT}/opengameart/{slug}"
            files = [h for h in p.hrefs if "/sites/default/files/" in h and not h.endswith((".png.jpeg",))]
            for h in files:
                name = h.rsplit("/", 1)[-1].split("?")[0]
                if re.search(r"\.(zip|rar|7z|fbx|obj|blend|glb|gltf|png|jpg|md5|txt)$", name, re.I):
                    download(h if h.startswith("http") else "https://opengameart.org" + h, f"{d}/{name}")
            if p.meta.get("og"):
                download(p.meta["og"], f"{d}/preview.jpg")
            anims = "да" if re.search(r"animat|rigged|aromat", html_text, re.I) else "нет"
            m["done"][key] = d
            m["meta"][key] = {"name": slug, "cat": "животные", "url": url,
                "authors": "см. страницу", "license": "CC0", "anims": anims}
            time.sleep(1.0)
        except Exception as e:
            m["failed"][key] = str(e)
    save_manifest(m)

def catalog(m):
    import glob
    rows = [("имя", "источник", "категория", "ссылка", "автор", "лицензия", "размер_мб", "путь", "анимации")]
    for key, d in m["done"].items():
        meta = m["meta"].get(key, {})
        src = key.split(":")[0]
        size = 0
        for fp in glob.glob(f"{d}/**", recursive=True):
            if os.path.isfile(fp):
                size += os.path.getsize(fp)
        rows.append((meta.get("name", key), src, meta.get("cat", ""), meta.get("url", ""),
                     meta.get("authors", ""), meta.get("license", ""), round(size / 1024 / 1024, 1),
                     d.replace(ROOT, "library"), meta.get("anims", "")))
    with open(f"{ROOT}/catalog.csv", "w", newline="") as f:
        csv.writer(f).writerows(rows)
    cards = []
    for r in rows[1:]:
        prev = os.path.join(ROOT, r[7], "preview.jpg")
        if os.path.exists(prev):
            cards.append(f'<div class="c" data-cat="{r[2]}"><img src="{r[7]}/preview.jpg" loading="lazy"><p><b>{r[0]}</b><br><small>{r[1]} · {r[2]}</small></p></div>')
    html_out = ("<html><head><meta charset='utf-8'><title>blockparty library</title><style>"
        "body{font-family:sans-serif;background:#181818;color:#eee}.g{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px;padding:16px}"
        ".c{background:#242424;border-radius:8px;overflow:hidden}.c img{width:100%;height:140px;object-fit:cover}"
        ".c p{margin:6px 8px;font-size:12px}#f{padding:12px}#f select{background:#333;color:#eee}</style></head><body>"
        "<div id='f'>Фильтр: <select onchange=\"document.querySelectorAll('.c').forEach(e=>e.style.display=(!this.value||e.dataset.cat.includes(this.value))?'':'none')\">"
        "<option value=''>все</option><option value='models'>модели</option><option value='hdris'>HDRI</option><option value='textures'>текстуры</option>"
        "<option value='ambientcg'>ambientCG</option><option value='животные'>животные</option></select></div>"
        f"<div class='g'>{''.join(cards)}</div></body></html>")
    open(f"{ROOT}/catalog.html", "w").write(html_out)
    print(f"catalog: {len(rows)-1} ассетов", flush=True)

if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    m = load_manifest()
    if what in ("ph", "all"):
        ph(m)
    if what in ("acg", "all"):
        acg(m)
    if what in ("oga", "all"):
        oga(m)
    catalog(m)
    ok = len(m["done"]); bad = len(m["failed"])
    print(f"DONE: ok={ok} failed={bad}", flush=True)
    for k, v in list(m["failed"].items())[:20]:
        print("FAIL", k, v)
