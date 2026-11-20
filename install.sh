#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${KUPADESK_BASE_URL:-https://raw.githubusercontent.com/kupakupar/kupadesk-antigravity/main}"
BASE_URL="${BASE_URL%/}"
TARGET_DIR="${KUPADESK_TARGET_DIR:-$HOME/.gemini/config/plugins/prompt-injector}"
SKIP_PATCH="${KUPADESK_SKIP_PATCH:-0}"

TMP_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

echo "[1/4] 正在获取 KupaDesk 最新发布清单 ($BASE_URL)..."
curl -fsSL "$BASE_URL/manifest.json" -o "$TMP_ROOT/manifest.json"

read -r VERSION EXPECTED_SHA ZIP_URL <<EOF
$(python3 - "$TMP_ROOT/manifest.json" "$BASE_URL" <<'PY'
import json, sys, urllib.parse
env = json.load(open(sys.argv[1], "r", encoding="utf-8"))
payload = json.loads(env["payload"])
base_url = sys.argv[2]
dl = str(payload.get("downloadUrl") or "")
zip_url = dl if dl.startswith(("http://", "https://")) else f"{base_url}/{dl.lstrip('/')}"
b_u = urllib.parse.urlparse(base_url)
z_u = urllib.parse.urlparse(zip_url)
if b_u.scheme != z_u.scheme or b_u.netloc != z_u.netloc:
    raise SystemExit("拒绝非同源下载地址")
print(payload["version"], str(payload["sha256"]).lower(), zip_url)
PY
)
EOF

ZIP_PATH="$TMP_ROOT/kupadesk-v${VERSION}.zip"
echo "[2/4] 正在下载 KupaDesk v${VERSION}..."
curl -fsSL "$ZIP_URL" -o "$ZIP_PATH"

echo "[3/4] 正在校验 SHA-256 并安全解压到 $TARGET_DIR..."
EXTRACT_DIR="$TMP_ROOT/extracted"
mkdir -p "$EXTRACT_DIR"
python3 - "$ZIP_PATH" "$EXPECTED_SHA" "$EXTRACT_DIR" <<'PY'
import hashlib, os, sys, zipfile
zip_path, expected_sha, out_dir = sys.argv[1], sys.argv[2], os.path.realpath(sys.argv[3])
with open(zip_path, "rb") as f:
    actual = hashlib.sha256(f.read()).hexdigest().lower()
if actual != expected_sha:
    raise SystemExit(f"SHA-256 校验失败: 期望 {expected_sha}, 实际 {actual}")
with zipfile.ZipFile(zip_path, "r") as zf:
    for info in zf.infolist():
        rel = info.filename.replace("\\", "/").lstrip("/")
        if not rel or rel.endswith("/"):
            continue
        parts = [p for p in rel.split("/") if p]
        lower = rel.lower()
        if ".." in parts or ":" in parts[0]:
            raise SystemExit(f"非法路径条目: {rel}")
        if rel == "rules/AGENTS.md" or lower.startswith(("scripts/", ".git/", "node_modules/")) or lower.endswith((".pem", ".key")):
            raise SystemExit(f"禁止条目: {rel}")
        dest = os.path.realpath(os.path.join(out_dir, *parts))
        if not dest.startswith(out_dir + os.sep):
            raise SystemExit(f"路径越界: {rel}")
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with zf.open(info, "r") as src, open(dest, "wb") as dst:
            dst.write(src.read())
if not os.path.isfile(os.path.join(out_dir, "plugin.json")):
    raise SystemExit("安装包缺少 plugin.json")
PY

SAVED_RULE=""
if [ -f "$TARGET_DIR/rules/AGENTS.md" ]; then
  SAVED_RULE="$TMP_ROOT/saved-AGENTS.md"
  cp "$TARGET_DIR/rules/AGENTS.md" "$SAVED_RULE"
fi
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
cp -R "$EXTRACT_DIR"/. "$TARGET_DIR"/
if [ -n "$SAVED_RULE" ] && [ -f "$SAVED_RULE" ]; then
  mkdir -p "$TARGET_DIR/rules"
  cp "$SAVED_RULE" "$TARGET_DIR/rules/AGENTS.md"
fi

echo "KupaDesk v${VERSION} 已安装到: $TARGET_DIR"
if [ "$SKIP_PATCH" != "1" ] && command -v node >/dev/null 2>&1 && [ -f "$TARGET_DIR/lib/cn-runner.cjs" ]; then
  echo "[4/4] 正在部署中文汉化、右键与红框入口并重启 Antigravity..."
  node "$TARGET_DIR/lib/cn-runner.cjs" --action install-all --auto-restart || echo "自动挂载失败，请在打开客户端后通过 KupaDesk 设置页点一键安装"
fi
echo "安装完成！"
