#!/usr/bin/env bash
set -euo pipefail

# ── config ──────────────────────────────────────────────────────────────────
VM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="/home/ace/apps/Commet-src"
DOWNLOADS_DIR="/home/ace/apps/Synapse/data/commet/web/downloads"
VERSION_TAG="${1:-v0.4.1-matzke.13}"
HOST_PORT=8018
QEMU_MEMORY=8G
QEMU_CPUS=4
# ────────────────────────────────────────────────────────────────────────────

log() { echo "[$(date +%T)] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ── step 1: package source ───────────────────────────────────────────────────
log "Packaging source..."
SOURCE_ZIP="$VM_DIR/commet-source.zip"
cd "$SRC_DIR"
zip -r "$SOURCE_ZIP" . \
    --exclude "*.git*" \
    --exclude "*/build/*" \
    --exclude "*/.dart_tool/*" \
    --exclude "*/windows/flutter/generated_*" \
    -q
log "Source ZIP: $(du -sh "$SOURCE_ZIP" | cut -f1)"

# ── step 2: start HTTP server ────────────────────────────────────────────────
UPLOAD_DIR="$(mktemp -d)"
INSTALLER_PATH="$UPLOAD_DIR/installer.exe"
ZIP_PATH="$UPLOAD_DIR/artifact.zip"

log "Starting artifact server on port $HOST_PORT..."
python3 - "$HOST_PORT" "$VM_DIR" "$UPLOAD_DIR" << 'PYEOF' &
import sys, http.server, os, threading

port = int(sys.argv[1])
serve_dir = sys.argv[2]
upload_dir = sys.argv[3]

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass
    def do_GET(self):
        path = os.path.join(serve_dir, self.path.lstrip('/'))
        if os.path.isfile(path):
            with open(path, 'rb') as f: data = f.read()
            self.send_response(200)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_response(404); self.end_headers()
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        data = self.rfile.read(length)
        if self.path == '/upload/installer':
            dest = os.path.join(upload_dir, 'installer.exe')
        elif self.path == '/upload/zip':
            dest = os.path.join(upload_dir, 'artifact.zip')
        else:
            self.send_response(404); self.end_headers(); return
        with open(dest, 'wb') as f: f.write(data)
        self.send_response(200); self.end_headers()
        print(f"[server] received {self.path} ({len(data)//1024}KB)", flush=True)

http.server.HTTPServer(('0.0.0.0', port), Handler).serve_forever()
PYEOF

SERVER_PID=$!
cleanup() {
    kill $SERVER_PID 2>/dev/null || true
    rm -rf "$UPLOAD_DIR"
    [ -n "${QEMU_PID:-}" ] && kill "$QEMU_PID" 2>/dev/null || true
}
trap cleanup EXIT

sleep 1
log "Server PID $SERVER_PID"

# ── step 3: start QEMU VM ────────────────────────────────────────────────────
OVMF_CODE="$(find /usr/share/OVMF /usr/share/ovmf -name 'OVMF_CODE*.fd' 2>/dev/null | head -1)"
[ -z "$OVMF_CODE" ] && die "OVMF_CODE.fd not found — install ovmf package"

log "Starting QEMU VM..."
qemu-system-x86_64 \
    -enable-kvm \
    -m "$QEMU_MEMORY" \
    -smp "$QEMU_CPUS" \
    -cpu host \
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
    -drive "if=pflash,format=raw,file=$VM_DIR/OVMF_VARS.fd" \
    -drive "file=$VM_DIR/commet-win.qcow2,format=qcow2,if=virtio,cache=writeback" \
    -netdev "user,id=net0,hostfwd=tcp::2222-:22" \
    -device "virtio-net-pci,netdev=net0" \
    -serial "file:$VM_DIR/serial.log" \
    -display none \
    -daemonize \
    -pidfile "$VM_DIR/qemu.pid"
QEMU_PID=$(cat "$VM_DIR/qemu.pid")
log "QEMU PID $QEMU_PID"

# ── step 4: wait for artifacts ───────────────────────────────────────────────
log "Waiting for build to complete (this takes 30-60 min on first run)..."
TIMEOUT=7200  # 2 hours
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if [ -f "$INSTALLER_PATH" ] && [ -f "$ZIP_PATH" ]; then
        log "Artifacts received!"
        break
    fi
    sleep 30
    ELAPSED=$((ELAPSED + 30))
    # Check VM is still alive
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
        die "QEMU process died unexpectedly — check $VM_DIR/serial.log"
    fi
    log "Still waiting... (${ELAPSED}s elapsed)"
done
[ -f "$INSTALLER_PATH" ] || die "Timed out waiting for installer"
[ -f "$ZIP_PATH" ]       || die "Timed out waiting for ZIP"

# ── step 5: deploy ────────────────────────────────────────────────────────────
VERSION_SHORT="${VERSION_TAG#v}"   # strip leading 'v' for filenames
INSTALLER_DEST="$DOWNLOADS_DIR/commet-matzke-windows-x64-${VERSION_SHORT}-installer.exe"
ZIP_DEST="$DOWNLOADS_DIR/commet-matzke-windows-x64-${VERSION_SHORT}.zip"

# Backup previous latest
TIMESTAMP=$(date +%Y%m%d%H%M%S)
for f in "$DOWNLOADS_DIR/commet-matzke-windows-x64-installer.exe" \
          "$DOWNLOADS_DIR/commet-matzke-windows-x64.zip"; do
    [ -f "$f" ] && cp "$f" "${f}.bak-${TIMESTAMP}"
done

cp "$INSTALLER_PATH" "$INSTALLER_DEST"
cp "$ZIP_PATH"        "$ZIP_DEST"
cp "$INSTALLER_PATH" "$DOWNLOADS_DIR/commet-matzke-windows-x64-installer.exe"
cp "$ZIP_PATH"        "$DOWNLOADS_DIR/commet-matzke-windows-x64.zip"

log "Deployed:"
log "  $INSTALLER_DEST"
log "  $ZIP_DEST"

# ── step 6: graceful VM shutdown ─────────────────────────────────────────────
log "Shutting down VM..."
kill "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

log "Done. Run update-downloads-html.sh or manually update downloads.html."
