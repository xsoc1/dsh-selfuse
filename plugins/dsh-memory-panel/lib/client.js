/**
 * dsh-memory-panel 客户端半边（手工构建的 CJS factory bundle，无需打包步骤）。
 *
 * 结构：window.__ModuleLoader__.load({ id, factory }) 是 dsh-client-modules
 * 约定的工厂注册形式；factory 内以 require() 解析平台 seed（react 等）。
 * 数据经同源 fetch 读取宿主半边挂载的 /memory/api/* JSON 路由（见 lib/index.js）
 * —— 纯本地文件记忆，离线可用，不依赖任何云端服务或 LLM。
 */
var module = { exports: {} }; var exports = module.exports;
window.__ModuleLoader__.load({ id: 'dsh-memory-panel', factory: (require) => {

  var React = require('react');
  var useState = React.useState;
  var useEffect = React.useEffect;
  var h = React.createElement;

  var NS = 'settings.memoryPanel';
  var name = 'dsh-memory-panel';
  var inject = ['slots', 'locale'];

  /* ---------------- API（同源 fetch 封装） ---------------- */

  function get(suffix) {
    return fetch('/memory' + suffix).then(function (r) { return r.json(); }).then(unwrap);
  }

  function post(suffix, body) {
    return fetch('/memory' + suffix, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }).then(function (r) { return r.json(); }).then(unwrap);
  }

  function unwrap(j) {
    if (!j || j.ok !== true) {
      var e = (j && j.error) || {};
      throw new Error((e.code ? String(e.code) + ': ' : '') + (e.message || '记忆服务请求失败'));
    }
    return j.value;
  }

  function api() {
    return {
      status: function () { return get('/api/status'); },
      pages: function () { return get('/api/pages'); },
      page: function (id) { return get('/api/page?id=' + encodeURIComponent(id)); },
      notes: function (limit, offset) { return get('/api/notes?limit=' + limit + '&offset=' + offset); },
      note: function (id) { return get('/api/note?id=' + encodeURIComponent(id)); },
      saveNote: function (title, text) { return post('/api/note', { title: title, text: text }); },
      search: function (q) { return get('/api/search?q=' + encodeURIComponent(q)); },
    };
  }

  /* ---------------- 样式 ---------------- */

  var STYLE = '' +
    '[data-dsh-memory] { display: flex; flex-direction: column; gap: 12px; max-width: 860px; min-width: 0; color: var(--dsw-alias-label-primary); }' +
    '[data-dsh-memory] .dsm-status { margin: 0; font-size: 13px; color: var(--dsw-alias-label-tertiary); }' +
    '[data-dsh-memory] .dsm-card { border: 1px solid var(--dsw-alias-border); border-radius: 10px; padding: 12px 14px; background: var(--dsw-alias-bg-layer-1); }' +
    '[data-dsh-memory] .dsm-head { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin-bottom: 8px; }' +
    '[data-dsh-memory] .dsm-head h3 { margin: 0; font-size: 14px; font-weight: 600; }' +
    '[data-dsh-memory] .dsm-badge { font-size: 12px; padding: 1px 8px; border-radius: 999px; background: var(--dsw-alias-bg-layer-2); border: 1px solid var(--dsw-alias-border); }' +
    '[data-dsh-memory] .dsm-badge[data-tone="ok"] { color: var(--dsw-alias-success, #2ea043); border-color: currentColor; }' +
    '[data-dsh-memory] .dsm-kv { display: grid; grid-template-columns: auto 1fr; gap: 4px 12px; margin: 0; font-size: 13px; }' +
    '[data-dsh-memory] .dsm-kv dt { color: var(--dsw-alias-label-secondary); }' +
    '[data-dsh-memory] .dsm-kv dd { margin: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }' +
    '[data-dsh-memory] .dsm-row { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }' +
    '[data-dsh-memory] input[type="text"], [data-dsh-memory] textarea { background: var(--dsw-alias-bg-layer-2); color: var(--dsw-alias-label-primary); border: 1px solid var(--dsw-alias-border); border-radius: 6px; padding: 6px 8px; font-size: 13px; min-width: 0; }' +
    '[data-dsh-memory] input[type="text"] { width: 100%; box-sizing: border-box; }' +
    '[data-dsh-memory] textarea { width: 100%; box-sizing: border-box; resize: vertical; }' +
    '[data-dsh-memory] button { background: var(--dsw-alias-bg-layer-2); color: var(--dsw-alias-label-primary); border: 1px solid var(--dsw-alias-border); border-radius: 6px; padding: 4px 12px; font-size: 13px; cursor: pointer; }' +
    '[data-dsh-memory] button:hover:not(:disabled) { border-color: var(--dsw-alias-primary); }' +
    '[data-dsh-memory] button:disabled { opacity: 0.5; cursor: default; }' +
    '[data-dsh-memory] .dsm-tabs { display: flex; gap: 6px; }' +
    '[data-dsh-memory] .dsm-tab { border: 1px solid var(--dsw-alias-border); border-radius: 999px; padding: 3px 12px; font-size: 13px; }' +
    '[data-dsh-memory] .dsm-tab[data-active="true"] { border-color: var(--dsw-alias-primary); color: var(--dsw-alias-primary); }' +
    '[data-dsh-memory] .dsm-list { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 6px; }' +
    '[data-dsh-memory] .dsm-item { border: 1px solid var(--dsw-alias-border); border-radius: 8px; padding: 8px 10px; font-size: 13px; cursor: pointer; background: var(--dsw-alias-bg-layer-1); }' +
    '[data-dsh-memory] .dsm-item:hover { border-color: var(--dsw-alias-primary); }' +
    '[data-dsh-memory] .dsm-item-title { font-weight: 600; word-break: break-all; }' +
    '[data-dsh-memory] .dsm-item-meta { color: var(--dsw-alias-label-tertiary); font-size: 12px; word-break: break-all; }' +
    '[data-dsh-memory] .dsm-pre { margin: 0; white-space: pre-wrap; word-break: break-word; font-family: ui-monospace, "Cascadia Mono", Consolas, monospace; font-size: 12px; line-height: 1.6; max-height: 520px; overflow: auto; }' +
    '[data-dsh-memory] .dsm-banner { margin: 0; padding: 8px 10px; border-radius: 8px; font-size: 13px; }' +
    '[data-dsh-memory] .dsm-banner[data-ok="false"] { color: var(--dsw-alias-error, #d1242f); background: color-mix(in srgb, currentColor 10%, transparent); }' +
    '[data-dsh-memory] .dsm-banner[data-ok="true"] { color: var(--dsw-alias-success, #2ea043); background: color-mix(in srgb, currentColor 10%, transparent); }' +
    '[data-dsh-memory] .dsm-empty { color: var(--dsw-alias-label-tertiary); font-size: 13px; }';

  /* ---------------- 字典 ---------------- */

  var zh = {
    tab: '记忆',
    loading: '加载中…',
    error: '读取记忆失败',
    refresh: '刷新',
    retry: '重试',
    statusTitle: '本地记忆存储',
    store: '存储位置',
    countPages: '知识页',
    countNotes: '记忆条目',
    bytes: '占用空间',
    viewPages: '知识页',
    viewNotes: '记忆条目',
    viewSearch: '搜索',
    pagesEmpty: '暂无知识页（把 .md 放进 ~/.dsh/memory/knowledge/）',
    notesEmpty: '暂无记忆条目',
    noteTotal: '共 {n} 条',
    prev: '上一页',
    next: '下一页',
    back: '返回列表',
    pageDetail: '内容',
    emptyContent: '（空）',
    searchPlaceholder: '搜索记忆内容…',
    searchBtn: '搜索',
    searchEmpty: '输入关键词搜索知识页与记忆条目',
    resultsNone: '没有匹配的记忆',
    writeNote: '写一条记忆',
    writeTitlePlaceholder: '标题（可选）',
    writeTextPlaceholder: '记忆内容…',
    save: '保存',
    saved: '已保存：{n}',
    badgeOk: '本地',
    appendStandard: 'MB',
  };

  var en = {
    tab: 'Memory',
    loading: 'Loading…',
    error: 'Failed to read memory',
    refresh: 'Refresh',
    retry: 'Retry',
    statusTitle: 'Local memory',
    store: 'Store',
    countPages: 'Pages',
    countNotes: 'Notes',
    bytes: 'Size',
    viewPages: 'Pages',
    viewNotes: 'Notes',
    viewSearch: 'Search',
    pagesEmpty: 'No pages. Drop .md into ~/.dsh/memory/knowledge/',
    notesEmpty: 'No memory notes',
    noteTotal: '{n} notes',
    prev: 'Previous',
    next: 'Next',
    back: 'Back to list',
    pageDetail: 'Content',
    emptyContent: '(empty)',
    searchPlaceholder: 'Search memory…',
    searchBtn: 'Search',
    searchEmpty: 'Type keywords to search pages and notes',
    resultsNone: 'No matching memories',
    writeNote: 'Write a note',
    writeTitlePlaceholder: 'Title (optional)',
    writeTextPlaceholder: 'Memory content…',
    save: 'Save',
    saved: 'Saved: {n}',
    badgeOk: 'local',
    appendStandard: 'MB',
  };

  /* ---------------- 工具 ---------------- */

  function errText(err) {
    return err && err.message ? String(err.message) : String(err);
  }

  function sizeText(bytes, t) {
    if (typeof bytes !== 'number') return '0 KB';
    if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + ' MB';
    return Math.max(1, Math.round(bytes / 1024)) + ' KB';
  }

  /* ---------------- 组件 ---------------- */

  function MemoryTab(props) {
    var t = props.t;
    var panelApi = props.api || api;

    var stS = useState(null);        var status = stS[0];      var setStatus = stS[1];
    var fS = useState(false);        var failed = fS[0];       var setFailed = fS[1];
    var vS = useState('pages');      var view = vS[0];         var setView = vS[1];
    var pS = useState(null);         var pages = pS[0];        var setPages = pS[1];
    var nS = useState(null);         var notes = nS[0];        var setNotes = nS[1];
    var tS = useState(0);            var noteTotal = tS[0];    var setNoteTotal = tS[1];
    var oS = useState(0);            var noteOffset = oS[0];   var setNoteOffset = oS[1];
    var sS = useState(null);         var selId = sS[0];        var setSelId = sS[1];
    var sdS = useState(null);        var selDoc = sdS[0];      var setSelDoc = sdS[1];
    var qS = useState('');           var searchQ = qS[0];      var setSearchQ = qS[1];
    var rS = useState(null);         var results = rS[0];      var setResults = rS[1];
    var bS = useState('');           var busy = bS[0];         var setBusy = bS[1];
    var bnS = useState(null);        var banner = bnS[0];      var setBanner = bnS[1];
    var tkS = useState(0);           var tick = tkS[0];        var setTick = tkS[1];
    var wtS = useState('');          var wTitle = wtS[0];      var setWTitle = wtS[1];
    var wxS = useState('');          var wText = wxS[0];       var setWText = wxS[1];

    // 初始加载状态
    useEffect(function () {
      var current = true;
      setFailed(false);
      panelApi.status().then(function (st) {
        if (current) setStatus(st);
      }, function () {
        if (current) setFailed(true);
      });
      return function () { current = false; };
    }, [panelApi, tick]);

    // 视图数据加载
    useEffect(function () {
      var current = true;
      setBanner(null);
      if (view === 'pages') {
        setPages(null);
        panelApi.pages().then(function (r) {
          if (current) setPages((r && r.items) || []);
        }, function (err) {
          if (current) { setPages([]); setBanner({ ok: false, text: errText(err) }); }
        });
      } else if (view === 'notes') {
        setNotes(null);
        panelApi.notes(50, noteOffset).then(function (r) {
          if (current) { setNotes((r && r.items) || []); setNoteTotal((r && r.total) || 0); }
        }, function (err) {
          if (current) { setNotes([]); setBanner({ ok: false, text: errText(err) }); }
        });
      } else {
        setResults(null);
      }
      return function () { current = false; };
    }, [panelApi, view, noteOffset]);

    // 选中条目读取内容
    useEffect(function () {
      if (!selId) { setSelDoc(null); return; }
      var current = true;
      setSelDoc(null);
      var p = selId.kind === 'note' ? panelApi.note(selId.id) : panelApi.page(selId.id);
      p.then(function (r) {
        var doc = r && (r.note || r.page);
        if (current) setSelDoc(doc || { error: true });
      }, function (err) {
        if (current) setSelDoc({ error: true, message: errText(err) });
      });
      return function () { current = false; };
    }, [panelApi, selId]);

    function doRefresh() { setTick(function (v) { return v + 1; }); }

    function doSearch() {
      var q = searchQ.trim();
      if (!q) return;
      setBusy('search'); setResults(null);
      panelApi.search(q).then(function (r) {
        setResults((r && r.results) || []);
      }, function (err) {
        setBanner({ ok: false, text: errText(err) });
      }).then(function () { setBusy(''); });
    }

    function doSave() {
      var text = wText.trim();
      if (!text) return;
      setBusy('save');
      panelApi.saveNote(wTitle.trim(), text).then(function (r) {
        setWTitle(''); setWText('');
        setBanner({ ok: true, text: t('saved').replace('{n}', r.name || r.id || '') });
      }, function (err) {
        setBanner({ ok: false, text: errText(err) });
      }).then(function () { setBusy(''); });
    }

    var cfg = status;
    return h('div', { 'data-dsh-memory': '', 'aria-busy': busy !== '' },
      status ? h('div', { className: 'dsm-card' },
        h('div', { className: 'dsm-head' },
          h('h3', null, t('statusTitle')),
          h('span', { className: 'dsm-badge', 'data-tone': 'ok' }, t('badgeOk')),
          h('button', { type: 'button', onClick: doRefresh, disabled: busy !== '' }, t('refresh')),
        ),
        h('dl', { className: 'dsm-kv' },
          h('dt', null, t('store')), h('dd', null, cfg.store),
          h('dt', null, t('countPages')), h('dd', null, String(cfg.counts.pages)),
          h('dt', null, t('countNotes')), h('dd', null, String(cfg.counts.notes)),
          h('dt', null, t('bytes')), h('dd', null, sizeText(cfg.bytes, t)),
        ),
      ) : (failed
        ? h('div', { className: 'dsm-card' },
            h('p', { className: 'dsm-banner', 'data-ok': 'false', role: 'alert' }, t('error')),
            h('button', { type: 'button', onClick: doRefresh }, t('retry')),
          )
        : h('p', { className: 'dsm-status' }, t('loading'))),
      banner ? h('p', { className: 'dsm-banner', 'data-ok': String(banner.ok === true) }, banner.text) : null,
      h('div', { className: 'dsm-card' },
        h('div', { className: 'dsm-head' },
          h('div', { className: 'dsm-tabs' },
            h('button', { type: 'button', className: 'dsm-tab', 'data-active': String(view === 'pages'), onClick: function () { setView('pages'); } }, t('viewPages')),
            h('button', { type: 'button', className: 'dsm-tab', 'data-active': String(view === 'notes'), onClick: function () { setView('notes'); } }, t('viewNotes')),
            h('button', { type: 'button', className: 'dsm-tab', 'data-active': String(view === 'search'), onClick: function () { setView('search'); } }, t('viewSearch')),
          ),
        ),
        view === 'pages' ? renderPages(t, pages, selId, selDoc, setSelId) : null,
        view === 'notes' ? renderNotes(t, panelApi, notes, noteTotal, noteOffset, setNoteOffset, selId, selDoc, setSelId, wTitle, setWTitle, wText, setWText, doSave, busy) : null,
        view === 'search' ? renderSearch(t, searchQ, setSearchQ, doSearch, results, busy, setSelId, setView) : null,
      ),
    );
  }

  function renderPages(t, pages, selId, selDoc, setSelId) {
    if (selId && selId.kind === 'page') {
      return detail(t, selDoc, function () { setSelId(null); });
    }
    if (pages === null) return h('p', { className: 'dsm-status' }, t('loading'));
    if (pages.length === 0) return h('p', { className: 'dsm-empty' }, t('pagesEmpty'));
    return h('ul', { className: 'dsm-list' },
      pages.map(function (p) {
        return h('li', { key: p.id, className: 'dsm-item', onClick: function () { setSelId({ kind: 'page', id: p.id }); } },
          h('div', { className: 'dsm-item-title' }, p.name || p.id),
          h('div', { className: 'dsm-item-meta' }, p.id + '.md'),
        );
      }),
    );
  }

  function renderNotes(t, panelApi, notes, noteTotal, noteOffset, setNoteOffset, selId, selDoc, setSelId, wTitle, setWTitle, wText, setWText, doSave, busy) {
    if (selId && selId.kind === 'note') {
      return detail(t, selDoc, function () { setSelId(null); });
    }
    return h('div', null,
      h('div', { className: 'dsm-card', style: { marginBottom: '10px' } },
        h('h3', { className: 'dsm-item-title' }, t('writeNote')),
        h('input', { type: 'text', value: wTitle, placeholder: t('writeTitlePlaceholder'), onChange: function (e) { setWTitle(e.target.value); } }),
        h('textarea', { rows: 3, value: wText, placeholder: t('writeTextPlaceholder'), onChange: function (e) { setWText(e.target.value); } }),
        h('div', { className: 'dsm-row' },
          h('button', { type: 'button', disabled: busy !== '' || wText.trim() === '', onClick: doSave }, busy === 'save' ? t('loading') : t('save')),
        ),
      ),
      h('div', { className: 'dsm-head' },
        h('span', { className: 'dsm-item-meta' }, t('noteTotal').replace('{n}', String(noteTotal))),
      ),
      notes === null ? h('p', { className: 'dsm-status' }, t('loading'))
        : notes.length === 0 ? h('p', { className: 'dsm-empty' }, t('notesEmpty'))
        : h('ul', { className: 'dsm-list' },
            notes.map(function (n) {
              return h('li', { key: n.id, className: 'dsm-item', onClick: function () { setSelId({ kind: 'note', id: n.id }); } },
                h('div', { className: 'dsm-item-title' }, n.name || n.id),
                h('div', { className: 'dsm-item-meta' }, n.id + '.md'),
              );
            }),
          ),
      h('div', { className: 'dsm-row' },
        h('button', { type: 'button', disabled: noteOffset === 0, onClick: function () { setNoteOffset(Math.max(0, noteOffset - 50)); } }, t('prev')),
        h('button', { type: 'button', disabled: noteOffset + 50 >= noteTotal, onClick: function () { setNoteOffset(noteOffset + 50); } }, t('next')),
      ),
    );
  }

  function renderSearch(t, searchQ, setSearchQ, doSearch, results, busy, setSelId, setView) {
    return h('div', null,
      h('div', { className: 'dsm-row' },
        h('input', { type: 'text', value: searchQ, placeholder: t('searchPlaceholder'), onChange: function (e) { setSearchQ(e.target.value); } }),
        h('button', { type: 'button', disabled: busy !== '' || searchQ.trim() === '', onClick: doSearch }, busy === 'search' ? t('loading') : t('searchBtn')),
      ),
      results === null
        ? h('p', { className: 'dsm-empty' }, t('searchEmpty'))
        : results.length === 0
          ? h('p', { className: 'dsm-empty' }, t('resultsNone'))
          : h('ul', { className: 'dsm-list' },
              results.map(function (r) {
                return h('li', { key: r.kind + ':' + r.id, className: 'dsm-item', onClick: function () { setSelId({ kind: r.kind === 'note' ? 'note' : 'page', id: r.id }); setView(r.kind === 'note' ? 'notes' : 'pages'); } },
                  h('div', { className: 'dsm-item-title' }, (r.kind === 'note' ? '📝 ' : '📄 ') + (r.name || r.id)),
                  r.snippet ? h('div', { className: 'dsm-item-meta' }, r.snippet) : null,
                );
              }),
            ),
    );
  }

  function detail(t, selDoc, onBack) {
    var body = selDoc === null ? t('loading')
      : selDoc && selDoc.error ? (selDoc.message || t('error'))
      : (typeof selDoc.content === 'string' && selDoc.content ? selDoc.content : t('emptyContent'));
    return h('div', null,
      h('div', { className: 'dsm-row' },
        h('button', { type: 'button', onClick: onBack }, t('back')),
      ),
      h('p', { className: 'dsm-item-title' }, (selDoc && selDoc.name) || t('pageDetail')),
      h('pre', { className: 'dsm-pre' }, body),
    );
  }

  /* ---------------- 浏览器插件主体 ---------------- */

  function apply(ctx) {
    ctx.effect(function () {
      var el = document.createElement('style');
      el.setAttribute('data-plugin', name);
      el.textContent = STYLE;
      document.head.appendChild(el);
      return function () { el.remove(); };
    }, 'dsh-memory-panel: stylesheet');

    ctx.inject(['slots', 'locale'], function (scope) {
      var t = scope.locale.bind(NS);
      scope.slots.inject('settings.plugins.tab', function () {
        return scope.slots.register({
          name: 'settings.plugins.tab',
          id: 'memory',
          order: 45,
          label: function () { return t('tab'); },
          locale: NS,
          inject: function () { return { api: api() }; },
        }, MemoryTab);
      });
    });
  }

  module.exports = { name: name, inject: inject, apply: apply };
  return module.exports;
}});
