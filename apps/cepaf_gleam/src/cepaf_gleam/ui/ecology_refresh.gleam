/// Browser observation only: one bounded GET, followed by a delayed next read.
/// Failed reads retain the displayed snapshot and announce stale/error state.
pub fn script() -> String {
  "(() => {
  const byId = id => document.getElementById(id);
  const status = byId('ecology-refresh-status');
  if (!status) return;
  let next = null, active = null, disposed = false;
  let lastCycle = null, lastChange = Date.now();
  const text = (id, value) => { const node = byId(id); if (node) node.textContent = String(value); };
  const announce = (state, message) => { status.dataset.state = state; status.textContent = message; };
  const read = async response => {
    if (!response.ok) throw new Error('HTTP ' + response.status);
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let body = '', size = 0;
    try {
      while (true) {
        const chunk = await reader.read();
        if (chunk.done) break;
        size += chunk.value.byteLength;
        if (size > 1048576) { await reader.cancel(); throw new Error('snapshot exceeds limit'); }
        body += decoder.decode(chunk.value, {stream: true});
      }
      return JSON.parse(body + decoder.decode());
    } finally { reader.releaseLock(); }
  };
  const refresh = async () => {
    if (disposed) return;
    if (document.hidden) { announce('paused', 'Refresh paused while this page is hidden.'); next = setTimeout(refresh, 2000); return; }
    active = new AbortController();
    const deadline = setTimeout(() => active && active.abort(), 1500);
    try {
      const state = await read(await fetch('/api/v1/ecology/swarm', {
        method: 'GET', cache: 'no-store', credentials: 'same-origin', signal: active.signal
      }));
      if (!Number.isSafeInteger(state.cycle_counter) || state.cycle_counter < 0 ||
          !Array.isArray(state.holons) || state.holons.length > 512 ||
          state.total_holons !== state.holons.length ||
          !Number.isSafeInteger(state.invocation_sequence)) throw new Error('invalid snapshot');
      const now = Date.now();
      const restarted = lastCycle !== null && state.cycle_counter < lastCycle;
      if (state.cycle_counter !== lastCycle) { lastChange = now; lastCycle = state.cycle_counter; }
      text('ecology-cycle', state.cycle_counter);
      text('ecology-participants', state.total_holons);
      text('ecology-invocations', state.invocation_sequence);
      text('ecology-receipts-json', JSON.stringify(state, null, 2));
      if (state.song && Number.isFinite(state.song.harmonic_consonance))
        text('ecology-consonance', (state.song.harmonic_consonance * 100).toFixed(1));
      const table = byId('ecology-participant-rows');
      if (table) table.replaceChildren(...state.holons.map(h => {
        const row = document.createElement('tr');
        const cells = table.dataset.layout === 'full'
          ? [h.id, h.name, h.plane, h.lifecycle + ' · ' + h.mode + ' · ' + h.successful_invocations + ' observed invocations']
          : [h.id, h.mode, h.active_capabilities + '/11', h.successful_invocations, h.last_outcome];
        for (const value of cells) { const cell = document.createElement('td'); cell.textContent = String(value); row.appendChild(cell); }
        return row;
      }));
      if (now - lastChange > 5000) announce('stale', 'Stale: the observed cycle has not advanced for over 5 seconds.');
      else announce('live', (restarted ? 'Runtime restarted; local state reset. ' : 'Live snapshot. ') + 'Last read ' + new Date(now).toLocaleTimeString() + '.');
    } catch (error) {
      if (!disposed) announce('error', 'Unavailable: ' + (error.name === 'AbortError' ? 'read timed out' : error.message) + '. Last displayed snapshot retained.');
    } finally {
      clearTimeout(deadline); active = null;
      if (!disposed) next = setTimeout(refresh, 2000);
    }
  };
  window.addEventListener('pagehide', () => { disposed = true; clearTimeout(next); if (active) active.abort(); }, {once: true});
  void refresh();
})();"
}
