// Web Worker hosting the in-browser demo backend (GitHub Pages build only).
// Loads Pyodide, installs the backend's pure-Python dependencies, restores this visitor's demo database from
// IndexedDB (or the shipped demo.db), then answers API requests posted from the page.
importScripts('https://cdn.jsdelivr.net/pyodide/v0.27.2/full/pyodide.js');

const DB_KEY = 'demo.db';
function idb() {
  return new Promise((resolve, reject) => {
    const r = indexedDB.open('ceevora-budget-demo', 1);
    r.onupgradeneeded = () => r.result.createObjectStore('files');
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });
}
async function idbOp(mode, fn) {
  try {
    const db = await idb();
    return await new Promise((resolve, reject) => {
      const tx = db.transaction('files', mode);
      const req = fn(tx.objectStore('files'));
      tx.oncomplete = () => resolve(req && req.result);
      tx.onerror = () => reject(tx.error);
    });
  } catch (e) {
    return undefined; // private mode / storage blocked: demo still works, just without persistence
  }
}
const fetchBytes = async (path) => {
  const r = await fetch(path, { cache: 'no-cache' });
  if (!r.ok) throw new Error(`${path}: HTTP ${r.status}`);
  return new Uint8Array(await r.arrayBuffer());
};

const ready = (async () => {
  const py = await loadPyodide();
  await py.loadPackage(['micropip']);
  await py.pyimport('micropip').install(['anyio==4.8.0', 'starlette==0.41.3', 'fastapi==0.115.6', 'PyJWT==2.10.1']);
  await py.loadPackage(['sqlite3', 'ssl']);
  py.FS.mkdirTree('/demo/app');
  const manifest = JSON.parse(new TextDecoder().decode(await fetchBytes('manifest.json')));
  for (const f of manifest.app) py.FS.writeFile(`/demo/app/${f}`, await fetchBytes(`app/${f}`));
  py.FS.writeFile('/demo/bridge.py', await fetchBytes('bridge.py'));
  const saved = await idbOp('readonly', (s) => s.get(DB_KEY));
  py.FS.writeFile('/demo/demo.db', saved || (await fetchBytes('demo.db')));
  await py.runPythonAsync("import sys; sys.path.insert(0, '/demo'); import bridge");
  return { py, bridge: py.pyimport('bridge') };
})();

self.onmessage = async ({ data }) => {
  const { id, op } = data;
  try {
    if (op === 'reset') {
      await idbOp('readwrite', (s) => s.delete(DB_KEY));
      return self.postMessage({ id, ok: true, res: 'reset' });
    }
    const { py, bridge } = await ready;
    if (op === 'ping') return self.postMessage({ id, ok: true, res: 'ready' });
    const res = await bridge.handle(data.method, data.url, data.headers, data.body ?? null);
    if (data.method !== 'GET') {
      const bytes = py.FS.readFile('/demo/demo.db');
      await idbOp('readwrite', (s) => s.put(bytes, DB_KEY));
    }
    self.postMessage({ id, ok: true, res });
  } catch (e) {
    self.postMessage({ id, ok: false, error: String((e && e.message) || e) });
  }
};
