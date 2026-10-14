const app = document.getElementById('app');
const shell = document.getElementById('beeper-shell');
const screen = document.getElementById('beeper-screen');
const content = document.getElementById('lcd-content');
const tabButtons = [...document.querySelectorAll('#lcd-tabs [data-tab]')];
const browserPreview = typeof window.GetParentResourceName !== 'function';

const state = {
    visible: browserPreview,
    tab: 'home',
    subview: null,
    cursor: { messages: 0, codes: 0, settings: 0, detail: 0 },
    pager: { number: '555-1430', capcode: '0143190', network: 'LOS SANTOS PAGING', label: 'RS BEEPER', memorySlots: 20, mode: 'mixed' },
    messages: [], unread: 0, locked: 0,
    battery: 82, batteryLow: false, powered: true,
    signal: { available: true, jammed: false, bars: 4, reason: 'SERVICE' },
    profile: { tone: 'classic', vibrate: true, silent: false, codeHints: false, uiScale: 100, uiX: 55, uiY: 38 },
    codebook: [], codebookEnabled: true
};

const audio = {
    classic: new Audio('sounds/pager_classic.ogg'),
    priority: new Audio('sounds/pager_priority.ogg'),
    key: new Audio('sounds/pager_key.ogg'),
    off: new Audio('sounds/pager_off.ogg'),
    denied: new Audio('sounds/pager_denied.ogg')
};
Object.values(audio).forEach(a => { a.volume = .42; });

function esc(value) { return String(value ?? '').replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[ch])); }
function clamp(v, min, max) { return Math.max(min, Math.min(max, Number(v))); }
function timeText(epoch) {
    const d = epoch ? new Date(Number(epoch) * 1000) : new Date();
    return d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', hour12: true }).replace(' ', '');
}
function dateText(epoch) {
    const d = epoch ? new Date(Number(epoch) * 1000) : new Date();
    return `${String(d.getMonth()+1).padStart(2,'0')}/${String(d.getDate()).padStart(2,'0')}`;
}
function requestId() { return `${Date.now()}-${Math.floor(Math.random()*100000)}`; }
async function rpc(action, payload = {}) {
    if (browserPreview) return previewRpc(action, payload);
    try {
        const response = await fetch(`https://${GetParentResourceName()}/rpc`, {
            method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({ requestId: requestId(), action, payload })
        });
        return await response.json();
    } catch (_) { return { ok: false, error: 'nui_error' }; }
}
function previewRpc(action, payload) {
    if (action === 'message.read') {
        const m = state.messages.find(x => String(x.id) === String(payload.id)); if (m) m.read = true;
    } else if (action === 'message.toggleLock') {
        const m = state.messages.find(x => String(x.id) === String(payload.id)); if (m) m.locked = !m.locked;
    } else if (action === 'message.delete') {
        state.messages = state.messages.filter(x => String(x.id) !== String(payload.id));
    } else if (action === 'profile.update') Object.assign(state.profile, payload.patch || payload);
    else if (action === 'pager.power') state.powered = payload.powered ?? !state.powered;
    return Promise.resolve({ ok: true, data: {} });
}
function beep(kind='key') {
    if (kind === 'incoming' && state.profile?.silent) return;
    const sound = kind === 'incoming' ? audio.classic : kind === 'priority' ? audio.priority : audio[kind] || audio.key;
    try { sound.currentTime = 0; sound.play().catch(() => {}); } catch (_) {}
}
function alertPhysical(priority='normal') {
    beep(priority === 'emergency' || priority === 'priority' ? 'priority' : 'incoming');
    if (state.profile?.vibrate) {
        shell.classList.remove('vibrate'); void shell.offsetWidth; shell.classList.add('vibrate');
        setTimeout(() => shell.classList.remove('vibrate'), 650);
    }
    screen.classList.remove('alert-flash'); void screen.offsetWidth; screen.classList.add('alert-flash');
    setTimeout(() => screen.classList.remove('alert-flash'), 1800);
}
function applyLayout() {
    const scale = clamp(state.profile?.uiScale ?? 100, 75, 120) / 100;
    // The stylesheet anchors the device from the right. Position is owned by
    // the profile, so clear that anchor or the two fight and left is ignored.
    shell.style.right = 'auto';
    shell.style.left = `${clamp(state.profile?.uiX ?? 55, 0, 100)}vw`;
    shell.style.top = `${clamp(state.profile?.uiY ?? 38, 0, 100)}vh`;
    shell.style.transform = `scale(${scale})`;
}
function signalText() {
    if (!state.powered) return 'OFF';
    const s = state.signal || {};
    if (!s.available) return s.jammed ? 'JAM' : 'NO';
    const bars = clamp(s.bars ?? 4, 0, 4);
    return `${'▮'.repeat(bars)}${'·'.repeat(4-bars)}`;
}
function updateHeader() {
    document.getElementById('lcd-signal').textContent = signalText();
    document.getElementById('lcd-brand').textContent = String(state.pager?.label || 'RS BEEPER').toUpperCase();
    const battery = Math.max(0, Math.round(Number(state.battery ?? 0)));
    const bat = document.getElementById('lcd-battery');
    bat.textContent = `BAT ${String(battery).padStart(3,'0')}`;
    bat.classList.toggle('low', battery <= 15);
    tabButtons.forEach(b => b.classList.toggle('active', b.dataset.tab === state.tab));
}
function latestMessage() { return state.messages?.[0] || null; }
function primaryText(message) {
    if (!message) return 'NO PAGES';
    return message.message || message.code || message.callback || 'PAGE';
}
function secondaryText(message) {
    if (!message) return state.pager?.network || 'PAGING NETWORK';
    if (message.callback) return `CALL ${message.callback}`;
    if (message.instructions) return message.instructions;
    return message.sender || 'UNKNOWN';
}
function renderHome() {
    if (!state.powered) return `<div class="lcd-empty">POWER OFF<br>SET → POWER TO TURN ON</div>`;
    if (!(state.signal?.available ?? true)) return `<div class="lcd-empty">${esc(state.signal?.reason || 'NO SERVICE')}<br>PAGES WILL WAIT</div>`;
    const m = latestMessage();
    return `<div class="lcd-home">
        <div class="home-count"><strong>${String(state.unread ?? 0).padStart(2,'0')}</strong><span>UNREAD</span></div>
        <div class="home-copy">
            <strong class="${m?.priority === 'emergency' ? 'priority' : ''}">${esc(primaryText(m))}</strong>
            <span>${esc(secondaryText(m))}</span>
            <span>${m ? `${dateText(m.createdAt)} ${timeText(m.createdAt)}` : esc(state.pager?.number || '')}</span>
        </div>
    </div>`;
}
function visibleSlice(items, cursor) {
    const count = 3;
    const maxStart = Math.max(0, items.length - count);
    const start = clamp(cursor - 1, 0, maxStart);
    return { start, rows: items.slice(start, start + count) };
}
function renderMessages() {
    const messages = state.messages || [];
    if (!messages.length) return `<div class="lcd-empty">NO SAVED PAGES<br>${esc(state.pager?.number || '')}</div>`;
    state.cursor.messages = clamp(state.cursor.messages, 0, messages.length - 1);
    const { start, rows } = visibleSlice(messages, state.cursor.messages);
    return `<div class="lcd-list">${rows.map((m, i) => {
        const index = start + i;
        const selected = index === state.cursor.messages;
        return `<div class="lcd-row ${selected?'selected':''}" data-message-index="${index}">
            <span class="index">${!m.read?'<i class="unread-dot"></i>':''}${String(index+1).padStart(2,'0')}</span>
            <span class="main">${esc(primaryText(m))}<small class="sub">${esc(m.sender || m.callback || 'UNKNOWN')}</small></span>
            <span class="side">${m.locked?'LOCK':timeText(m.createdAt)}</span>
        </div>`;
    }).join('')}</div>`;
}
function selectedMessage() { return (state.messages || [])[state.cursor.messages] || null; }
function renderMessageDetail() {
    const m = selectedMessage();
    if (!m) { state.subview = null; return renderMessages(); }
    const hint = state.profile?.codeHints && m.codeMeaning ? `${m.code}: ${m.codeMeaning}` : '';
    return `<div class="lcd-detail">
        <div class="detail-title"><span>${esc(m.sender || 'PAGE')}</span><span>${dateText(m.createdAt)} ${timeText(m.createdAt)}</span></div>
        <div class="detail-body">
            <strong>${esc(primaryText(m))}</strong>
            ${m.callback?`<span>CALLBACK ${esc(m.callback)}</span>`:''}
            ${m.instructions?`<span>${esc(m.instructions)}</span>`:''}
            ${hint?`<span>${esc(hint)}</span>`:''}
        </div>
        <div class="detail-foot">
            <button class="detail-action ${state.cursor.detail===0?'selected':''}" data-detail-action="0" type="button">${m.locked?'UNLOCK':'LOCK'}</button>
            <button class="detail-action ${state.cursor.detail===1?'selected':''}" data-detail-action="1" type="button">DELETE</button>
        </div>
    </div>`;
}
function renderCodes() {
    const codes = state.codebook || [];
    if (!state.codebookEnabled || !codes.length) return `<div class="lcd-empty">CODEBOOK OFF<br>KNOW YOUR NUMBERS</div>`;
    state.cursor.codes = clamp(state.cursor.codes, 0, codes.length - 1);
    const { start, rows } = visibleSlice(codes, state.cursor.codes);
    if (state.subview === 'code') {
        const entry = codes[state.cursor.codes];
        return `<div class="identity"><span>${esc(entry?.category || 'CODE')}</span><strong>${esc(entry?.code || '')}</strong><span>${esc(entry?.meaning || '')}</span></div>`;
    }
    return `<div class="lcd-list">${rows.map((entry, i) => {
        const index = start + i, selected = index === state.cursor.codes;
        return `<div class="lcd-row ${selected?'selected':''}" data-code-index="${index}"><span class="index">${String(index+1).padStart(2,'0')}</span><span class="main">${esc(entry.code)}<small class="sub">${esc(entry.meaning)}</small></span><span class="side">${esc(entry.category)}</span></div>`;
    }).join('')}</div>`;
}
function renderIdentity() {
    const used = (state.messages || []).length;
    const max = Number(state.pager?.memorySlots || 20);
    return `<div class="identity">
        <span>PAGER NUMBER</span><strong>${esc(state.pager?.number || 'UNASSIGNED')}</strong>
        <span>CAP ${esc(state.pager?.capcode || '-------')} · MEM ${used}/${max} · ${esc(state.pager?.network || '')}</span>
    </div>`;
}
function settingsEntries() {
    return [
        { key:'power', label:'POWER', value: state.powered?'ON':'OFF', type:'toggle' },
        { key:'silent', label:'SILENT', value: state.profile?.silent?'ON':'OFF', type:'profileToggle' },
        { key:'vibrate', label:'VIBRATE', value: state.profile?.vibrate?'ON':'OFF', type:'profileToggle' },
        { key:'codeHints', label:'CODE HINTS', value: state.profile?.codeHints?'ON':'OFF', type:'profileToggle' },
        { key:'uiScale', label:'SIZE', value:`${state.profile?.uiScale || 100}%`, type:'scale' },
        { key:'clear', label:'CLEAR READ', value:'GO', type:'action' },
        { key:'reset', label:'RESET SET', value:'GO', type:'action' }
    ];
}
function renderSettings() {
    const entries = settingsEntries();
    state.cursor.settings = clamp(state.cursor.settings, 0, entries.length - 1);
    const { start, rows } = visibleSlice(entries, state.cursor.settings);
    return `<div class="setting-list">${rows.map((entry, i) => {
        const index = start + i, selected = index === state.cursor.settings;
        return `<div class="setting-row ${selected?'selected':''}" data-setting-index="${index}"><span>${esc(entry.label)}</span><span class="setting-value">${esc(entry.value)}</span></div>`;
    }).join('')}</div>`;
}
function render() {
    app.classList.toggle('visible', state.visible);
    app.setAttribute('aria-hidden', state.visible ? 'false' : 'true');
    applyLayout(); updateHeader();
    if (!state.powered) content.innerHTML = `<div class="lcd-empty">POWER OFF<br>PRESS SELECT TO POWER ON</div>`;
    else if (state.tab === 'messages') content.innerHTML = state.subview === 'message' ? renderMessageDetail() : renderMessages();
    else if (state.tab === 'codes') content.innerHTML = renderCodes();
    else if (state.tab === 'identity') content.innerHTML = renderIdentity();
    else if (state.tab === 'settings') content.innerHTML = renderSettings();
    else content.innerHTML = renderHome();
    bindRows();
}
function showTab(tab) {
    const valid = ['home','messages','codes','identity','settings'];
    if (!valid.includes(tab)) return;
    state.tab = tab; state.subview = null; beep('key'); render();
}
const tabOrder = ['home','messages','codes','identity','settings'];

function moveHorizontal(direction) {
    if (!state.powered) { beep('denied'); return; }

    // Message actions are actually laid out side-by-side, so the pager's
    // physical left/right rocker controls them exactly as the artwork implies.
    if (state.tab === 'messages' && state.subview === 'message') {
        state.cursor.detail = (state.cursor.detail + direction + 2) % 2;
        beep('key'); render(); return;
    }

    // Everywhere else the rocker has one job: move left/right across the
    // pager's five top-level categories. It must never pretend to be an up/down
    // control for a vertical list.
    const at = Math.max(0, tabOrder.indexOf(state.tab));
    state.tab = tabOrder[(at + direction + tabOrder.length) % tabOrder.length];
    state.subview = null;
    beep('key'); render();
}

function moveVertical(direction, allowSettings = true) {
    if (!state.powered) { beep('denied'); return false; }

    let moved = false;
    if (state.tab === 'messages' && state.subview !== 'message') {
        const before = state.cursor.messages;
        state.cursor.messages = clamp(before + direction, 0, Math.max(0, (state.messages?.length || 1)-1));
        moved = state.cursor.messages !== before;
    } else if (state.tab === 'codes' && state.subview !== 'code' && state.codebookEnabled) {
        const before = state.cursor.codes;
        state.cursor.codes = clamp(before + direction, 0, Math.max(0, (state.codebook?.length || 1)-1));
        moved = state.cursor.codes !== before;
    } else if (allowSettings && state.tab === 'settings') {
        const before = state.cursor.settings;
        state.cursor.settings = clamp(before + direction, 0, settingsEntries().length-1);
        moved = state.cursor.settings !== before;
    }

    if (moved) { beep('key'); render(); }
    return moved;
}

function scrollPagerList(direction) {
    // The wheel is intentionally narrower than keyboard navigation: it only
    // scrolls the two long pager lists players naturally expect to scroll.
    // It never changes category, settings, detail actions, or any other view.
    if (state.tab === 'messages' && state.subview !== 'message') return moveVertical(direction, false);
    if (state.tab === 'codes' && state.subview !== 'code') return moveVertical(direction, false);
    return false;
}
async function markRead(m) {
    if (!m || m.read) return;
    m.read = true; state.unread = Math.max(0, Number(state.unread || 0)-1); render();
    const result = await rpc('message.read', { id: m.id });
    if (!result?.ok) beep('denied');
}
async function activateMessageDetail() {
    const m = selectedMessage(); if (!m) return;
    if (state.cursor.detail === 0) {
        const result = await rpc('message.toggleLock', { id: m.id });
        if (result?.ok) m.locked = !m.locked; else beep('denied');
    } else {
        if (m.locked) { beep('denied'); return; }
        const result = await rpc('message.delete', { id: m.id });
        if (result?.ok) { state.messages.splice(state.cursor.messages,1); state.cursor.messages = clamp(state.cursor.messages,0,Math.max(0,state.messages.length-1)); state.subview = null; }
        else beep('denied');
    }
    render();
}
async function activateSetting() {
    const entry = settingsEntries()[state.cursor.settings]; if (!entry) return;
    if (entry.type === 'toggle' && entry.key === 'power') {
        const wanted = !state.powered;
        const result = await rpc('pager.power', { powered: wanted });
        if (result?.ok) { state.powered = wanted; beep(wanted?'classic':'off'); } else beep('denied');
    } else if (entry.type === 'profileToggle') {
        const wanted = !state.profile[entry.key]; state.profile[entry.key] = wanted;
        const result = await rpc('profile.update', { patch: { [entry.key]: wanted } }); if (!result?.ok) beep('denied');
    } else if (entry.type === 'scale') {
        const next = Number(state.profile.uiScale || 100) >= 120 ? 75 : Number(state.profile.uiScale || 100)+5;
        state.profile.uiScale = next; await rpc('profile.update', { patch: { uiScale: next } });
    } else if (entry.key === 'clear') {
        const result = await rpc('message.clearRead'); if (!result?.ok) beep('denied');
    } else if (entry.key === 'reset') {
        const result = await rpc('profile.reset'); if (!result?.ok) beep('denied');
    }
    beep('key'); render();
}
async function selectCurrent() {
    if (!state.powered) {
        const result = await rpc('pager.power', { powered: true });
        if (result?.ok) { state.powered = true; beep('classic'); } else beep('denied');
        render(); return;
    }
    if (state.tab === 'home') { showTab('messages'); return; }
    if (state.tab === 'messages') {
        if (state.subview === 'message') { activateMessageDetail(); return; }
        const m = selectedMessage(); if (!m) return; state.subview = 'message'; state.cursor.detail = 0; markRead(m); beep('key'); render(); return;
    }
    if (state.tab === 'codes') { if ((state.codebook || []).length) { state.subview = state.subview === 'code' ? null : 'code'; beep('key'); render(); } return; }
    if (state.tab === 'settings') { activateSetting(); return; }
    beep('key');
}
function back() {
    if (state.subview) { state.subview = null; beep('key'); render(); return; }
    if (state.tab !== 'home') { state.tab = 'home'; beep('key'); render(); return; }
    state.visible = false; render(); rpc('ui.close');
}
function bindRows() {
    content.querySelectorAll('[data-message-index]').forEach(row => row.onclick = () => { state.cursor.messages = Number(row.dataset.messageIndex); selectCurrent(); });
    content.querySelectorAll('[data-code-index]').forEach(row => row.onclick = () => { state.cursor.codes = Number(row.dataset.codeIndex); selectCurrent(); });
    content.querySelectorAll('[data-setting-index]').forEach(row => row.onclick = () => { state.cursor.settings = Number(row.dataset.settingIndex); selectCurrent(); });
    content.querySelectorAll('[data-detail-action]').forEach(button => button.onclick = () => { state.cursor.detail = Number(button.dataset.detailAction); activateMessageDetail(); });
}

tabButtons.forEach(button => button.onclick = () => showTab(button.dataset.tab));
document.querySelectorAll('[data-hw]').forEach(button => button.onclick = () => {
    const action = button.dataset.hw;
    if (action === 'left') moveHorizontal(-1);
    else if (action === 'right') moveHorizontal(1);
    else if (action === 'select') selectCurrent();
    else if (action === 'back') back();
    else if (action === 'close') { state.visible = false; render(); rpc('ui.close'); }
});

document.addEventListener('keydown', event => {
    if (!state.visible) return;
    // ---------------------------------------------------------------------
    // Browser default-action guard
    //
    // While this UI is open the client runs SetNuiFocus(true, true), so CEF --
    // not the game -- sees these keys first. F11 is CEF's FULLSCREEN toggle:
    // pressing a device's own open/close key while its UI was focused drove
    // the embedded browser through a fullscreen transition and took the client
    // down with it. Opening was always safe because focus is not set yet, and
    // Escape was always safe because it already calls preventDefault below.
    // That asymmetry was the entire bug.
    //
    // preventDefault suppresses only the BROWSER's default action. The Lua
    // RegisterKeyMapping command is dispatched by the command system over raw
    // input (SetNuiFocusKeepInput), so the key still closes the device -- it
    // just no longer toggles fullscreen on the way out. F5 (reload), F10 (menu
    // bar) and F12 (devtools) are the same class of browser default and are
    // swallowed here for the same reason, whichever F-key a device is bound to.
    // ---------------------------------------------------------------------
    if (event.key === 'F5' || event.key === 'F10' || event.key === 'F11' || event.key === 'F12') {
        event.preventDefault();
        return;
    }
    if (event.key === 'Escape') { event.preventDefault(); state.visible = false; render(); rpc('ui.close'); return; }
    if (event.key === 'ArrowLeft') { event.preventDefault(); moveHorizontal(-1); }
    else if (event.key === 'ArrowRight') { event.preventDefault(); moveHorizontal(1); }
    else if (event.key === 'ArrowUp') { event.preventDefault(); moveVertical(-1); }
    else if (event.key === 'ArrowDown') { event.preventDefault(); moveVertical(1); }
    else if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); selectCurrent(); }
    else if (event.key === 'Backspace') { event.preventDefault(); back(); }
});

window.addEventListener('message', event => {
    const payload = event.data || {}; const data = payload.data || {};
    if (payload.action === 'requestClose') {
        state.visible = false;
        render();
        setTimeout(() => rpc('ui.close'), 0);
        return;
    }
    if (payload.action === 'visible') state.visible = data.visible === true;
    else if (payload.action === 'state') {
        const keep = { tab: state.tab, subview: state.subview, cursor: state.cursor, visible: state.visible };
        Object.assign(state, data); Object.assign(state, keep); state.profile = { ...(state.profile || {}) };
    } else if (payload.action === 'incoming') {
        if (data.summary?.profile) state.profile = { ...(state.profile || {}), ...data.summary.profile };
        const m = data.message || {}; const existing = state.messages.find(x => String(x.id) === String(m.id));
        if (!existing) state.messages.unshift(m);
        state.unread = data.summary?.unread ?? Math.max(1, Number(state.unread || 0)+1);
        state.battery = data.summary?.battery ?? state.battery; state.signal = data.summary?.signal ?? state.signal;
        alertPhysical(m.priority || 'normal');
    } else if (payload.action === 'pending') {
        if (data.summary?.profile) state.profile = { ...(state.profile || {}), ...data.summary.profile };
        const m = data.message || {}; if (m.id && !state.messages.find(x => String(x.id) === String(m.id))) state.messages.unshift(m);
        state.unread = data.summary?.unread ?? state.unread; state.signal = data.summary?.signal ?? state.signal;
        alertPhysical(m.priority || 'normal');
    } else if (payload.action === 'signal') state.signal = data;
    else if (payload.action === 'battery') state.battery = data.battery ?? state.battery;
    else if (payload.action === 'denied') beep('denied');
    render();
});

if (browserPreview) {
    const now = Math.floor(Date.now()/1000);
    state.messages = [
        { id:'demo1', sender:'JEN', message:'143', code:'143', codeMeaning:'I LOVE YOU', codeCategory:'LOVE', callback:'555-0198', instructions:'USE PAYPHONE', priority:'normal', createdAt:now-75, read:false, locked:false },
        { id:'demo2', sender:'DISPATCH', message:'911', code:'911', codeMeaning:'EMERGENCY / CALL NOW', callback:'555-0911', priority:'emergency', createdAt:now-580, read:true, locked:true },
        { id:'demo3', sender:'MARCUS', message:'123', code:'123', codeMeaning:'I MISS YOU', callback:'555-0123', createdAt:now-3600, read:true, locked:false }
    ];
    state.unread = 1; state.locked = 1;
    state.codebook = [
        {code:'07', meaning:'JUST KIDDING', category:'SOCIAL'}, {code:'23', meaning:'TE AMO', category:'LOVE'},
        {code:'45', meaning:'GOODNIGHT', category:'SOCIAL'}, {code:'56', meaning:'SWEET DREAMS', category:'LOVE'},
        {code:'123', meaning:'I MISS YOU', category:'LOVE'}, {code:'143', meaning:'I LOVE YOU', category:'LOVE'},
        {code:'193', meaning:'MISS ME?', category:'LOVE'}, {code:'303', meaning:'STOP PLAYING', category:'SOCIAL'},
        {code:'411', meaning:'INFORMATION / DETAILS', category:'UTILITY'}, {code:'423', meaning:'CALL ME', category:'CALLBACK'},
        {code:'477', meaning:'BEST FRIENDS FOREVER', category:'SOCIAL'}, {code:'911', meaning:'EMERGENCY / CALL NOW', category:'EMERGENCY'},
        {code:'07734', meaning:'HELLO (UPSIDE DOWN)', category:'CALCULATOR'}
    ];
}
render();

// ---------------------------------------------------------------------------
// Movable device
//
// Position already had an owner: profile.uiX / profile.uiY, stored per
// character on the server and re-applied by applyLayout() on EVERY render.
// An earlier version of this dragged with pixel offsets in localStorage, which
// looked right until you pressed a button -- the next render called
// applyLayout() and snapped the pager back to the profile position.
//
// So dragging writes to the profile instead of fighting it. That also makes the
// position better than it would have been: it is server-persisted per
// character, survives a reconnect, and follows the player between sessions.
//
// Details that matter:
//   * The chassis is the handle, never the screen -- LCD rows are clickable and
//     a drag starting on one would eat the click.
//   * vw/vh, not pixels, because that is what the profile stores and what keeps
//     the device in the same relative spot across resolutions.
//   * The server clamps 0-100 as well, so a bad value cannot strand the device.
//   * The RPC fires once on release, not on every move, so a drag is one write.
// ---------------------------------------------------------------------------
(function setupDrag() {
    if (!shell) return;
    let drag = null;

    function applyFromPointer(clientX, clientY) {
        const vw = Math.max(0, Math.min(100, ((clientX - drag.dx) / window.innerWidth) * 100));
        const vh = Math.max(0, Math.min(100, ((clientY - drag.dy) / window.innerHeight) * 100));
        state.profile = state.profile || {};
        state.profile.uiX = vw;
        state.profile.uiY = vh;
        applyLayout();
    }

    const grip = document.getElementById('beeper-grip');

    (grip || shell).addEventListener('pointerdown', (event) => {
        if (event.button !== 0) return;
        const rect = shell.getBoundingClientRect();
        drag = { dx: event.clientX - rect.left, dy: event.clientY - rect.top, moved: false };
        shell.classList.add('dragging');
        try { (grip || shell).setPointerCapture(event.pointerId); } catch (e) { /* ignore */ }
        event.preventDefault();
    });

    (grip || shell).addEventListener('pointermove', (event) => {
        if (!drag) return;
        drag.moved = true;
        applyFromPointer(event.clientX, event.clientY);
    });

    function endDrag(event) {
        if (!drag) return;
        const moved = drag.moved;
        drag = null;
        shell.classList.remove('dragging');
        try { (grip || shell).releasePointerCapture(event.pointerId); } catch (e) { /* ignore */ }
        if (!moved) return;
        // One write per drag, on release.
        rpc('profile.update', { patch: { uiX: state.profile.uiX, uiY: state.profile.uiY } });
    }
    (grip || shell).addEventListener('pointerup', endDrag);
    (grip || shell).addEventListener('pointercancel', endDrag);

    // Double-click the chassis returns the pager to the configured default.
    (grip || shell).addEventListener('dblclick', (event) => {
        state.profile = state.profile || {};
        state.profile.uiX = 55;
        state.profile.uiY = 38;
        applyLayout();
        rpc('profile.update', { patch: { uiX: 55, uiY: 38 } });
    });

    // ---------------------------------------------------------------------
    // Wheel scrolling
    //
    // The mouse wheel belongs to vertical pager content only. It works while
    // the pointer is over the LCD and only in MSG or CODE list view. It never
    // changes HOME / MSG / CODE / ID / SET, never toggles detail actions, and
    // never adjusts settings. Left/right on the pager remain true left/right.
    // ---------------------------------------------------------------------
    screen.addEventListener('wheel', (event) => {
        const direction = event.deltaY > 0 ? 1 : -1;
        const canScroll = state.powered && (
            (state.tab === 'messages' && state.subview !== 'message' && (state.messages?.length || 0) > 1) ||
            (state.tab === 'codes' && state.subview !== 'code' && state.codebookEnabled && (state.codebook?.length || 0) > 1)
        );
        if (!canScroll) return;
        event.preventDefault();
        scrollPagerList(direction);
    }, { passive: false });
})();
