from pathlib import Path
import json, re, hashlib, zipfile
from urllib.parse import unquote
root=Path(__file__).resolve().parents[4]
review=root/"docs/_drafts/asset_review/b01"
manifest=json.loads((review/"manifest.json").read_text(encoding="utf-8"))
files=[root/a["file"] for a in manifest["assets"]]
files+=sorted((root/"assets/prompts/b01").glob("*.txt"))
files+=[root/"assets/prompts/b01/README.md",root/"assets/ASSETS.md"]
files+=[review/n for n in ["manifest.json","QA.md","index.html","overview.html","overview.jpg","review_paper.jpg","review_gray.jpg","inspect_assets.ps1",".gdignore"]]
for a in manifest["assets"]:
 p=root/a["file"]
 assert p.read_bytes()[:8]==b"\x89PNG\r\n\x1a\n",p
 assert hashlib.sha256(p.read_bytes()).hexdigest()==a["sha256"],p
for p in [review/"overview.jpg",review/"review_paper.jpg",review/"review_gray.jpg"]:
 assert p.read_bytes()[:3]==b"\xff\xd8\xff",p
links=0
for p in files:
 if p.suffix==".html":
  refs=re.findall(r'(?:src|href)="([^"]+)"',p.read_text(encoding="utf-8"))
 elif p.suffix==".md":
  refs=re.findall(r'\]\(([^)]+)\)',p.read_text(encoding="utf-8"))
 else:continue
 for ref in refs:
  if "://" in ref or ref.startswith("#"):continue
  target=(p.parent/unquote(ref.split("#")[0])).resolve()
  assert target.is_file(),f"Broken link: {p.name}: {ref}"
  links+=1
zip_path=review/"b01_buildings_review.zip"
with zipfile.ZipFile(zip_path,"w",zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in files:z.write(p,p.relative_to(root).as_posix())
with zipfile.ZipFile(zip_path) as z:
 assert z.testzip() is None
 assert len(z.namelist())==len(files)
 for a in manifest["assets"]:
  assert hashlib.sha256(z.read(a["file"])).hexdigest()==a["sha256"]
print(json.dumps({"assets_verified":9,"local_links_verified":links,"archive_files":len(files),"archive_bytes":zip_path.stat().st_size,"archive_sha256":hashlib.sha256(zip_path.read_bytes()).hexdigest()},ensure_ascii=False))

