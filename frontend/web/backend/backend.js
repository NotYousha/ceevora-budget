// Page-side handle for the in-browser demo backend. The worker starts only when the app first calls it,
// so normal (server-backed) builds never download Pyodide.
window.ceevoraBackend = (() => {
  let worker;
  let seq = 0;
  const pending = new Map();
  function w() {
    if (!worker) {
      worker = new Worker(new URL('backend/worker.js', document.baseURI));
      worker.onmessage = ({ data }) => {
        const p = pending.get(data.id);
        pending.delete(data.id);
        if (p) data.ok ? p.resolve(data.res) : p.reject(new Error(data.error));
      };
    }
    return worker;
  }
  const send = (msg) => new Promise((resolve, reject) => {
    const id = ++seq;
    pending.set(id, { resolve, reject });
    w().postMessage({ ...msg, id });
  });
  return {
    request: (method, url, headers, body) => send({ op: 'request', method, url, headers, body }),
    ready: () => send({ op: 'ping' }),
    reset: () => send({ op: 'reset' }),
  };
})();
