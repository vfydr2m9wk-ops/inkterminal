import { V86 } from "./vendor/v86/libv86.mjs?v=2";
import { Terminal } from "./vendor/xterm/xterm.mjs";
import { FitAddon } from "./vendor/xterm/addon-fit.mjs";

const params = new URLSearchParams(location.search);
if (params.has("embed")) document.body.classList.add("embed");

const statusEl = document.getElementById("status");
const setStatus = (t) => { statusEl.textContent = t; };

// ---------- Terminal (xterm.js) ----------
const term = new Terminal({
  cursorBlink: true,
  fontFamily: 'ui-monospace, Menlo, "SF Mono", monospace',
  fontSize: Number(params.get("font")) || (Math.min(screen.width, screen.height) < 500 ? 12 : 15),
  theme: { background: "#0d1117", foreground: "#e6edf3", cursor: "#3fb950" },
  scrollback: 5000,
});
const fit = new FitAddon();
term.loadAddon(fit);
term.open(document.getElementById("term"));
fit.fit();
term.focus();
document.getElementById("term").addEventListener("click", () => term.focus());

// ---------- Saved state (IndexedDB) ----------
const DB = "inkterminal", STORE = "state", KEY = "vm";
function idb() {
  return new Promise((ok, fail) => {
    const r = indexedDB.open(DB, 1);
    r.onupgradeneeded = () => r.result.createObjectStore(STORE);
    r.onsuccess = () => ok(r.result);
    r.onerror = () => fail(r.error);
  });
}
async function idbOp(mode, fn) {
  const db = await idb();
  return new Promise((ok, fail) => {
    const tx = db.transaction(STORE, mode);
    const req = fn(tx.objectStore(STORE));
    tx.oncomplete = () => ok(req && req.result);
    tx.onerror = () => fail(tx.error);
  });
}
const loadState = () => idbOp("readonly", (s) => s.get(KEY)).catch(() => undefined);
const saveStateDb = (buf) => idbOp("readwrite", (s) => s.put(buf, KEY));
const clearStateDb = () => idbOp("readwrite", (s) => s.delete(KEY));

// ---------- Emulator (v86) ----------
const saved = params.has("fresh") ? undefined : await loadState();
const config = {
  wasm_path: "vendor/v86/v86.wasm",
  memory_size: 64 * 1024 * 1024,
  vga_memory_size: 2 * 1024 * 1024,
  bios: { url: "bios/seabios.bin" },
  vga_bios: { url: "bios/vgabios.bin" },
  bzimage: { url: "images/inkterminal-bzImage.bin?v=2" },
  cmdline: "console=ttyS0 quiet tsc=reliable mitigations=off random.trust_cpu=on",
  disable_keyboard: true,
  disable_mouse: true,
  disable_speaker: true,
  autostart: true,
};
if (saved) config.initial_state = { buffer: saved };

setStatus(saved ? "Restaurando sessão salva…" : "Iniciando Linux…");
const emulator = new V86(config);

// Serial output -> terminal, batched per frame so it stays fast.
let pending = [];
let scheduled = false;
let booted = !!saved;
emulator.add_listener("serial0-output-byte", (byte) => {
  pending.push(byte);
  if (!booted) { booted = true; setStatus("Pronto"); }
  if (!scheduled) {
    scheduled = true;
    requestAnimationFrame(() => {
      term.write(new Uint8Array(pending));
      pending = [];
      scheduled = false;
    });
  }
});
emulator.add_listener("emulator-ready", () => {
  if (saved) { setStatus("Pronto (sessão restaurada)"); emulator.serial0_send("\n"); }
});

// ---------- Input ----------
let ctrl = false;
const ctrlBtn = document.getElementById("key-ctrl");
const setCtrl = (v) => { ctrl = v; ctrlBtn.classList.toggle("on", v); };

function send(data) { emulator.serial0_send(data); }

term.onData((data) => {
  if (ctrl && data.length === 1) {
    const c = data.toUpperCase().charCodeAt(0);
    if (c >= 64 && c <= 95) data = String.fromCharCode(c - 64);
    setCtrl(false);
  }
  send(data);
});

const KEYS = {
  esc: "\x1b", tab: "\t", up: "\x1b[A", down: "\x1b[B",
  right: "\x1b[C", left: "\x1b[D", "ctrl-c": "\x03",
};
document.getElementById("keys").addEventListener("click", (e) => {
  const b = e.target.closest("button");
  if (!b) return;
  if (b.dataset.key === "ctrl") setCtrl(!ctrl);
  else if (b.dataset.key) send(KEYS[b.dataset.key]);
  else if (b.dataset.text) send(b.dataset.text);
  term.focus();
});
// Keep the soft keyboard open when tapping the extra keys.
document.getElementById("keys").addEventListener("mousedown", (e) => e.preventDefault());

// ---------- Resize ----------
// On iOS the soft keyboard covers the page instead of shrinking it, so size
// the layout to the visible area. That keeps the extra-keys bar above the keyboard.
const vv = window.visualViewport;
function refit() {
  if (vv) {
    document.body.style.height = vv.height + "px";
    window.scrollTo(0, 0);
  }
  fit.fit();
}
window.addEventListener("resize", refit);
if (vv) { vv.addEventListener("resize", refit); vv.addEventListener("scroll", () => window.scrollTo(0, 0)); }
refit();
// The guest runs `resize` at login (see /etc/profile); after a layout change,
// typing `resize` updates the size inside Linux.

// ---------- Buttons ----------
document.getElementById("btn-save").addEventListener("click", async () => {
  try {
    setStatus("Salvando…");
    const buf = await emulator.save_state();
    await saveStateDb(buf);
    setStatus(`Salvo (${(buf.byteLength / 1048576).toFixed(1)} MB)`);
  } catch (err) {
    console.error(err);
    setStatus("Não foi possível salvar");
  }
  term.focus();
});
document.getElementById("btn-reset").addEventListener("click", async () => {
  await clearStateDb().catch(() => {});
  location.search = params.has("embed") ? "?embed=1&fresh=1" : "?fresh=1";
});

window.inkterminal = { emulator, term };
