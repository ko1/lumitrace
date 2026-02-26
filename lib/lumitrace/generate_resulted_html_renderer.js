(function() {
  const payloadEl = document.getElementById("lumitrace-payload");
  const app = document.getElementById("lumitrace-app");
  if (!payloadEl || !app) return;

  const SL = 0;
  const SC = 1;
  const EL = 2;
  const EC = 3;

  function escHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;");
  }

  function normalizeTypeCounts(types) {
    if (!types) return {};
    if (Array.isArray(types)) {
      const out = {};
      for (const t of types) {
        const key = String(t || "");
        if (!key) continue;
        out[key] = (out[key] || 0) + 1;
      }
      return out;
    }
    if (typeof types === "object") {
      const out = {};
      for (const [k, v] of Object.entries(types)) {
        const key = String(k || "");
        if (!key) continue;
        let count = Number(v) || 0;
        if (count <= 0) count = 1;
        out[key] = (out[key] || 0) + count;
      }
      return out;
    }
    const key = String(types || "");
    return key ? { [key]: 1 } : {};
  }

  function typeListText(types, onlyIfMultiple) {
    const counts = normalizeTypeCounts(types);
    const entries = Object.entries(counts).sort(([a], [b]) => a.localeCompare(b));
    if (onlyIfMultiple && entries.length <= 1) return null;
    if (entries.length === 0) return "(no types)";
    return "types: " + entries.map(([k, v]) => `${k}(${v})`).join(", ");
  }

  function valueTypeName(v) {
    if (v === null) return "NilClass";
    if (Array.isArray(v)) return "Array";
    switch (typeof v) {
      case "number": return Number.isInteger(v) ? "Integer" : "Float";
      case "string": return "String";
      case "boolean": return "Boolean";
      case "undefined": return "NilClass";
      case "object": return "Object";
      default: return typeof v;
    }
  }

  function formatValue(v, type) {
    const value = v == null ? "nil" : String(v);
    return `${value} (${type || valueTypeName(v)})`;
  }

  function lastValueToPair(lastValue) {
    if (lastValue == null) return [null, null];
    if (typeof lastValue !== "object" || Array.isArray(lastValue)) return [lastValue, null];
    const type = lastValue.type || null;
    if (Object.prototype.hasOwnProperty.call(lastValue, "value")) return [lastValue.value, type];
    if (Object.prototype.hasOwnProperty.call(lastValue, "preview")) return [lastValue.preview, type];
    if (Object.prototype.hasOwnProperty.call(lastValue, "inspect")) return [lastValue.inspect, type];
    return [JSON.stringify(lastValue), type];
  }

  function summarizeValues(values, total, allTypes) {
    if (!values || values.length === 0) {
      const multi = typeListText(allTypes, false);
      return multi || "";
    }

    const n = total == null ? values.length : Number(total);
    const lastVals = values.slice(-3);
    const firstIndex = n - lastVals.length + 1;
    const lines = [];
    const extra = n - lastVals.length;
    if (extra > 0) lines.push(`... (+${extra} more)`);

    lastVals.forEach((v, i) => {
      const idx = firstIndex + i;
      const [valueText, typeText] = lastValueToPair(v);
      lines.push(`#${idx}: ${formatValue(valueText, typeText)}`);
    });

    const multi = typeListText(allTypes, true);
    if (multi) lines.push(multi);
    return lines.join("\n");
  }

  function lineClassFor(expected, executed) {
    if (executed > 0) return " hit";
    if (expected > 0) return " miss";
    return "";
  }

  function lineInRanges(line, ranges) {
    if (!ranges || ranges.length === 0) return true;
    return ranges.some((range) => {
      if (!Array.isArray(range) || range.length < 2) return false;
      const start = Number(range[0]);
      const end = Number(range[1]);
      return line >= start && line <= end;
    });
  }

  function sourceLines(source) {
    const matches = String(source || "").match(/[^\n]*\n|[^\n]+/g);
    if (!matches) return [];
    return matches.map((line) => line.endsWith("\n") ? line.slice(0, -1) : line);
  }

  function lineStatsForFile(trace) {
    const expectedByLine = Object.create(null);
    const executedByLine = Object.create(null);
    const seen = Object.create(null);

    for (const event of trace || []) {
      const loc = event && event.location;
      if (!Array.isArray(loc) || loc.length < 4) continue;
      const sl = Number(loc[SL]);
      const el = Number(loc[EL]);
      if (!(sl > 0) || !(el > 0)) continue;
      const key = `${sl}:${loc[SC]}:${el}:${loc[EC]}`;
      if (seen[key]) continue;
      seen[key] = true;
      for (let line = sl; line <= el; line += 1) {
        expectedByLine[line] = (expectedByLine[line] || 0) + 1;
        if (Number(event.total) > 0) {
          executedByLine[line] = (executedByLine[line] || 0) + 1;
        }
      }
    }

    return { expectedByLine, executedByLine };
  }

  function expressionLineCoverageForTrace(trace) {
    const expectedLines = new Set();
    const executedLines = new Set();
    const seen = new Set();

    for (const event of trace || []) {
      if (!event || event.kind === "arg") continue;
      const loc = event.location;
      if (!Array.isArray(loc) || loc.length < 4) continue;

      const sl = Number(loc[SL]);
      const sc = Number(loc[SC]);
      const el = Number(loc[EL]);
      const ec = Number(loc[EC]);
      if (!(sl > 0) || !(el > 0)) continue;

      const key = `${sl}:${sc}:${el}:${ec}`;
      if (seen.has(key)) continue;
      seen.add(key);

      for (let line = sl; line <= el; line += 1) {
        expectedLines.add(line);
        if (Number(event.total) > 0) executedLines.add(line);
      }
    }

    return {
      executed: executedLines.size,
      expected: expectedLines.size
    };
  }

  function aggregateEventsForLine(trace, lineno, lineLen, fileIndex) {
    const buckets = new Map();
    const spans = [];

    for (const event of trace || []) {
      const loc = event && event.location;
      if (!Array.isArray(loc) || loc.length < 4) continue;
      const sline = Number(loc[SL]);
      const scol = Number(loc[SC]);
      const eline = Number(loc[EL]);
      const ecol = Number(loc[EC]);
      if (lineno < sline || lineno > eline) continue;

      let s;
      let t;
      let marker;
      if (sline === eline) {
        s = scol;
        t = ecol;
        marker = true;
      } else if (lineno === sline) {
        s = scol;
        t = lineLen;
        marker = false;
      } else if (lineno === eline) {
        s = 0;
        t = ecol;
        marker = true;
      } else {
        s = 0;
        t = lineLen;
        marker = false;
      }

      if (!(t > s)) continue;
      spans.push({ start_col: s, end_col: t });

      const keyId = `${fileIndex}:${sline}:${scol}:${eline}:${ecol}`;
      buckets.set(keyId, {
        key_id: keyId,
        start_col: s,
        end_col: t,
        marker,
        kind: event.kind || "expr",
        name: event.name || null,
        sampled_values: event.sampled_values || [],
        types: event.types || {},
        total: Number(event.total) || 0,
        suppress_miss: false
      });
    }

    const out = Array.from(buckets.values());
    for (const b of out) {
      const depth = spans.filter((sp) => b.start_col >= sp.start_col && b.end_col <= sp.end_col).length;
      b.depth = Math.min(5, Math.max(1, depth));
    }
    out.sort((a, b) => a.start_col - b.start_col);
    return out;
  }

  function renderLineHtml(lineText, events) {
    const opens = Object.create(null);
    const closes = Object.create(null);

    for (const e of events) {
      const s = Number(e.start_col);
      const t = Number(e.end_col);
      if (!(t > s)) continue;

      const values = e.sampled_values || [];
      const allTypes = e.types || {};
      const total = Number(e.total) || 0;
      const label = e.kind === "arg" && e.name ? `arg ${e.name}` : null;

      let valueText;
      if (total === 0) {
        valueText = label ? `${label}: (not hit)` : "(not hit)";
      } else {
        const summary = summarizeValues(values, total, allTypes);
        if (label) {
          valueText = summary ? `${label}: ${summary}` : label;
        } else {
          valueText = summary;
        }
      }

      const tooltipHtml = escHtml(valueText);
      const depthClass = `depth-${e.depth || 1}`;
      const missClass = total === 0 && !e.suppress_miss ? " miss" : "";
      const keyAttr = escHtml(e.key_id || "");
      const openTag = `<span class=\"expr hit ${depthClass}${missClass}\" data-key=\"${keyAttr}\">`;

      let closeTag = "</span>";
      if (e.marker !== false) {
        let marker = "🔎";
        if (total === 0) marker = "∅";
        else if (e.kind === "arg") marker = "🧷";

        let markerClass = "marker";
        if (total === 0 && !e.suppress_miss) markerClass = "marker miss";
        if (e.kind === "arg") markerClass += " arg";
        closeTag = `<span class=\"${markerClass}\" data-key=\"${keyAttr}\" aria-hidden=\"true\">${marker}<span class=\"tooltip\">${tooltipHtml}</span></span></span>`;
      }

      const len = t - s;
      (opens[s] ||= []).push({ len, start: s, end: t, tag: openTag });
      (closes[t] ||= []).push({ len, start: s, end: t, tag: closeTag });
    }

    const positions = Array.from(new Set([
      ...Object.keys(opens).map(Number),
      ...Object.keys(closes).map(Number)
    ])).sort((a, b) => a - b);

    let out = "";
    let cursor = 0;

    for (const pos of positions) {
      if (pos > cursor) out += escHtml(lineText.slice(cursor, pos));
      if (closes[pos]) {
        closes[pos]
          .slice()
          .sort((a, b) => (b.start - a.start) || (a.len - b.len))
          .forEach((c) => { out += c.tag; });
      }
      if (opens[pos]) {
        opens[pos]
          .slice()
          .sort((a, b) => b.end - a.end)
          .forEach((o) => { out += o.tag; });
      }
      cursor = pos;
    }

    if (cursor < lineText.length) out += escHtml(lineText.slice(cursor));
    return out;
  }

  function buildLineNode(lineno, lineText, lineClass, innerHtml, options) {
    const opts = options || {};
    const line = document.createElement("span");
    line.className = `line${lineClass}`;
    line.dataset.line = String(lineno);
    line.id = `line-${lineno}`;

    const ln = opts.lineHref ? document.createElement("a") : document.createElement("span");
    ln.className = `ln${opts.lineHref ? " ln-link" : ""}`;
    ln.textContent = String(lineno);
    if (opts.lineHref) {
      ln.href = opts.lineHref(lineno);
      ln.title = `Link to line ${lineno}`;
      ln.addEventListener("click", (event) => {
        if (!opts.onLineClick) return;
        if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
        event.preventDefault();
        opts.onLineClick(lineno);
      });
    }
    line.appendChild(ln);
    line.appendChild(document.createTextNode(" "));

    if (innerHtml == null) {
      line.appendChild(document.createTextNode(lineText));
    } else {
      const wrapper = document.createElement("span");
      wrapper.innerHTML = innerHtml;
      while (wrapper.firstChild) line.appendChild(wrapper.firstChild);
    }

    return line;
  }

  function buildEllipsisNode() {
    const line = document.createElement("span");
    line.className = "line ellipsis";
    line.dataset.line = "...";

    const ln = document.createElement("span");
    ln.className = "ln";
    ln.textContent = "...";
    line.appendChild(ln);
    return line;
  }

  function renderFileSection(file, fileIndex, options) {
    const opts = options || {};
    const section = document.createElement("section");
    section.className = "file-section";

    if (opts.includeTitle !== false) {
      const h2 = document.createElement("h2");
      h2.className = "file";
      h2.textContent = file.display_path || file.path || `file-${fileIndex + 1}`;
      section.appendChild(h2);
    }

    const pre = document.createElement("pre");
    pre.className = "code";
    const code = document.createElement("code");
    pre.appendChild(code);

    const lines = sourceLines(file.source || "");
    const ranges = Array.isArray(file.ranges) ? file.ranges : null;
    const trace = Array.isArray(file.trace) ? file.trace : [];
    const { expectedByLine, executedByLine } = lineStatsForFile(trace);

    let prevLineno = null;
    let firstLineno = null;
    let lastLineno = null;

    lines.forEach((lineText, idx) => {
      const lineno = idx + 1;
      if (!lineInRanges(lineno, ranges)) return;
      if (firstLineno == null) firstLineno = lineno;
      if (prevLineno != null && lineno > prevLineno + 1) {
        code.appendChild(buildEllipsisNode());
      }

      const evs = aggregateEventsForLine(trace, lineno, lineText.length, fileIndex);
      const expected = expectedByLine[lineno] || 0;
      const executed = executedByLine[lineno] || 0;
      const lineClass = lineClassFor(expected, executed);
      if (expected > 0 && executed === 0) {
        evs.forEach((e) => { e.suppress_miss = true; });
      }

      if (evs.length === 0) {
        code.appendChild(buildLineNode(lineno, lineText, lineClass, null, opts));
      } else {
        code.appendChild(buildLineNode(lineno, lineText, lineClass, renderLineHtml(lineText, evs), opts));
      }

      prevLineno = lineno;
      lastLineno = lineno;
    });

    if (firstLineno != null && firstLineno > 1) {
      code.insertBefore(buildEllipsisNode(), code.firstChild);
    }
    if (lastLineno != null && lastLineno < lines.length) {
      code.appendChild(buildEllipsisNode());
    }

    section.appendChild(pre);
    return section;
  }

  function bindMarkerHover(root) {
    root.querySelectorAll(".marker").forEach((marker) => {
      marker.addEventListener("mouseenter", () => {
        root.querySelectorAll(".expr.active").forEach((el) => el.classList.remove("active"));
        const key = marker.dataset.key;
        if (key) {
          root.querySelectorAll(`.expr[data-key=\"${key}\"]`).forEach((el) => el.classList.add("active"));
        } else {
          const expr = marker.closest(".expr");
          if (expr) expr.classList.add("active");
        }
      });
      marker.addEventListener("mouseleave", () => {
        const key = marker.dataset.key;
        if (key) {
          root.querySelectorAll(`.expr[data-key=\"${key}\"]`).forEach((el) => el.classList.remove("active"));
        } else {
          const expr = marker.closest(".expr");
          if (expr) expr.classList.remove("active");
        }
      });
    });
  }

  function fileDisplayPath(file, idx) {
    return String((file && (file.display_path || file.path)) || `file-${idx + 1}`);
  }

  function fileUrlKey(file, idx) {
    return fileDisplayPath(file, idx).replace(/\\/g, "/");
  }

  function encodeHashFileKey(key) {
    return encodeURIComponent(String(key || "")).replace(/%2F/g, "/");
  }

  function decodeHashFileKey(value) {
    try {
      return decodeURIComponent(String(value || ""));
    } catch (_e) {
      return String(value || "");
    }
  }

  function parseHashStateFromLocation() {
    const raw = String(window.location.hash || "").replace(/^#/, "");
    if (!raw) return { fileKey: null, line: null };

    if (!raw.includes("=")) {
      return { fileKey: decodeHashFileKey(raw), line: null };
    }

    const params = new URLSearchParams(raw);
    const fileRaw = params.get("file");
    const lineRaw = params.get("line");
    const lineNum = lineRaw == null ? null : Number.parseInt(lineRaw, 10);

    return {
      fileKey: fileRaw ? decodeHashFileKey(fileRaw) : null,
      line: Number.isFinite(lineNum) && lineNum > 0 ? lineNum : null
    };
  }

  function buildHashForSelection(fileKey, line) {
    const parts = [];
    if (fileKey) parts.push(`file=${encodeHashFileKey(fileKey)}`);
    if (line && Number(line) > 0) parts.push(`line=${Number(line)}`);
    return `#${parts.join("&")}`;
  }

  function setLocationHashSelection(fileKey, line) {
    const hash = buildHashForSelection(fileKey, line);
    if (window.location.hash === hash) return;
    if (window.history && typeof window.history.replaceState === "function") {
      try {
        window.history.replaceState(null, "", hash);
        return;
      } catch (_e) {
        // `about:srcdoc` (runv preview) can reject replaceState with a file:// hash URL.
      }
    }
    try {
      window.location.hash = hash;
    } catch (_e) {
      // Ignore hash update failures in restricted embedding contexts.
    }
  }

  function buildFileTree(files) {
    const root = { dirs: new Map(), files: [] };

    files.forEach((file, idx) => {
      const key = fileUrlKey(file, idx);
      const display = fileDisplayPath(file, idx).replace(/\\/g, "/");
      const parts = display.split("/").filter(Boolean);
      const filename = parts.pop() || display || `file-${idx + 1}`;

      let node = root;
      let currentPath = "";
      for (const part of parts) {
        currentPath = currentPath ? `${currentPath}/${part}` : part;
        if (!node.dirs.has(part)) {
          node.dirs.set(part, { name: part, path: currentPath, dirs: new Map(), files: [] });
        }
      node = node.dirs.get(part);
    }
      const coverage = expressionLineCoverageForTrace(Array.isArray(file.trace) ? file.trace : []);
      const coverageText = coverage.expected > 0 ? ` (${coverage.executed}/${coverage.expected})` : "";
      node.files.push({ label: filename, key, file, index: idx, path: display, coverageText });
    });

    return root;
  }

  function treeNodeContainsSelection(node, selectedKey) {
    if (!node) return false;
    if ((node.files || []).some((f) => f.key === selectedKey)) return true;
    for (const child of (node.dirs || new Map()).values()) {
      if (treeNodeContainsSelection(child, selectedKey)) return true;
    }
    return false;
  }

  function renderFileTreeNode(node, selectedKey, onSelect, level) {
    const ul = document.createElement("ul");
    ul.className = "tree-list";
    ul.dataset.level = String(level || 0);

    const dirs = Array.from((node.dirs || new Map()).values()).sort((a, b) => a.name.localeCompare(b.name));
    const files = Array.from(node.files || []).sort((a, b) => a.path.localeCompare(b.path));

    dirs.forEach((dirNode) => {
      const li = document.createElement("li");
      li.className = "tree-dir";

      const details = document.createElement("details");
      details.className = "tree-folder";
      details.open = treeNodeContainsSelection(dirNode, selectedKey);

      const summary = document.createElement("summary");
      summary.className = "tree-folder-label";
      summary.textContent = dirNode.name;
      details.appendChild(summary);

      details.appendChild(renderFileTreeNode(dirNode, selectedKey, onSelect, (level || 0) + 1));
      li.appendChild(details);
      ul.appendChild(li);
    });

    files.forEach((entry) => {
      const li = document.createElement("li");
      li.className = "tree-file";

      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "tree-file-btn";
      const name = document.createElement("span");
      name.className = "tree-file-name";
      name.textContent = entry.label;
      btn.appendChild(name);

      if (entry.coverageText) {
        const meta = document.createElement("span");
        meta.className = "tree-file-meta";
        meta.textContent = entry.coverageText;
        btn.appendChild(meta);
      }

      btn.dataset.fileKey = entry.key;
      if (entry.key === selectedKey) {
        btn.classList.add("active");
        btn.setAttribute("aria-current", "page");
      }
      btn.addEventListener("click", () => onSelect(entry.key));
      li.appendChild(btn);
      ul.appendChild(li);
    });

    return ul;
  }

  function preferredInitialFileKey(files) {
    if (!files || files.length === 0) return null;
    const hashKey = parseHashStateFromLocation().fileKey;
    if (hashKey) {
      const byDisplay = files.find((file, idx) => fileUrlKey(file, idx) === hashKey);
      if (byDisplay) return fileUrlKey(byDisplay, files.indexOf(byDisplay));

      const byPath = files.find((file) => String(file.path || "") === hashKey);
      if (byPath) return fileUrlKey(byPath, files.indexOf(byPath));
    }
    return fileUrlKey(files[0], 0);
  }

  function preferredInitialLineNumber() {
    return parseHashStateFromLocation().line;
  }

  function focusLineInViewer(viewer, lineno) {
    viewer.querySelectorAll(".line.line-target").forEach((el) => el.classList.remove("line-target"));
    if (!(lineno > 0)) return;
    const target = viewer.querySelector(`.line[data-line="${lineno}"]`);
    if (!target) return;
    target.classList.add("line-target");
    if (typeof target.scrollIntoView === "function") {
      target.scrollIntoView({ block: "center", inline: "nearest" });
    }
  }

  function render(payload) {
    app.textContent = "";

    const files = payload && Array.isArray(payload.files) ? payload.files : [];
    if (files.length === 0) {
      const empty = document.createElement("p");
      empty.className = "hint";
      empty.textContent = "No files to render.";
      app.appendChild(empty);
      return;
    }

    const hint = document.createElement("div");
    hint.className = "hint";
    hint.textContent = "Hover highlighted text to see recorded values.";
    app.appendChild(hint);

    const mode = document.createElement("div");
    mode.className = "mode";
    mode.textContent = payload && payload.meta && payload.meta.mode_text ? payload.meta.mode_text : "";
    app.appendChild(mode);

    const shell = document.createElement("div");
    shell.className = `report-layout${files.length <= 1 ? " single-file" : ""}`;
    app.appendChild(shell);

    const sidebar = document.createElement("aside");
    sidebar.className = "report-sidebar";
    shell.appendChild(sidebar);

    const treeTitle = document.createElement("div");
    treeTitle.className = "tree-title";
    treeTitle.textContent = `Files (${files.length})`;
    sidebar.appendChild(treeTitle);

    const treeMount = document.createElement("div");
    treeMount.className = "tree-scroll";
    sidebar.appendChild(treeMount);

    const main = document.createElement("section");
    main.className = "report-main";
    shell.appendChild(main);

    const mainHead = document.createElement("div");
    mainHead.className = "report-main-head";
    main.appendChild(mainHead);

    const currentPath = document.createElement("div");
    currentPath.className = "current-file";
    mainHead.appendChild(currentPath);

    const viewer = document.createElement("div");
    viewer.className = "report-viewer";
    main.appendChild(viewer);

    const fileKeyToEntry = new Map();
    files.forEach((file, idx) => fileKeyToEntry.set(fileUrlKey(file, idx), { file, idx }));

    let selectedKey = preferredInitialFileKey(files);
    let selectedLine = preferredInitialLineNumber();

    function renderTree() {
      treeMount.textContent = "";
      const treeRoot = buildFileTree(files);
      treeMount.appendChild(renderFileTreeNode(treeRoot, selectedKey, (key) => selectFile(key, true, null), 0));
    }

    function renderSelectedFile() {
      viewer.textContent = "";
      const entry = fileKeyToEntry.get(selectedKey);
      if (!entry) return;

      currentPath.textContent = fileDisplayPath(entry.file, entry.idx);

      viewer.appendChild(renderFileSection(entry.file, entry.idx, {
        includeTitle: false,
        lineHref: (lineno) => buildHashForSelection(selectedKey, lineno),
        onLineClick: (lineno) => selectLine(lineno, true)
      }));
      bindMarkerHover(viewer);
      focusLineInViewer(viewer, selectedLine);
    }

    function selectLine(lineno, updateHash) {
      const n = Number(lineno);
      selectedLine = Number.isFinite(n) && n > 0 ? n : null;
      renderSelectedFile();
      if (updateHash) setLocationHashSelection(selectedKey, selectedLine);
    }

    function selectFile(key, updateHash, nextLine) {
      if (!fileKeyToEntry.has(key)) return;
      if (arguments.length >= 3) {
        selectedLine = nextLine && Number(nextLine) > 0 ? Number(nextLine) : null;
      } else if (key !== selectedKey) {
        selectedLine = null;
      }
      selectedKey = key;
      renderTree();
      renderSelectedFile();
      if (updateHash) setLocationHashSelection(key, selectedLine);
    }

    window.addEventListener("hashchange", () => {
      const state = parseHashStateFromLocation();
      if (state.fileKey && state.fileKey !== selectedKey && fileKeyToEntry.has(state.fileKey)) {
        selectFile(state.fileKey, false, state.line);
        return;
      }
      if (state.fileKey === selectedKey || (!state.fileKey && selectedKey)) {
        selectedLine = state.line;
        renderSelectedFile();
      }
    });

    selectFile(selectedKey, true);
  }

  try {
    const payload = JSON.parse(payloadEl.textContent || "{}");
    render(payload);
  } catch (error) {
    app.textContent = `Failed to render Lumitrace HTML: ${error}`;
  }
})();
