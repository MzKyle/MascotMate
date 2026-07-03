const params = new URLSearchParams(window.location.search);
const token = params.get("token") || "";
const MAX_UPLOAD_BYTES = 100 * 1024 * 1024;
const state = {
  featured: [],
  external: [],
  installed: [],
  current: "",
  busy: new Set(),
};

const els = {
  summary: document.querySelector("#summary"),
  installedGrid: document.querySelector("#installedGrid"),
  featuredGrid: document.querySelector("#featuredGrid"),
  externalGrid: document.querySelector("#externalGrid"),
  searchInput: document.querySelector("#searchInput"),
  sourceFilter: document.querySelector("#sourceFilter"),
  statusFilter: document.querySelector("#statusFilter"),
  refreshButton: document.querySelector("#refreshButton"),
  moreHint: document.querySelector("#moreHint"),
  installedSection: document.querySelector("#installedSection"),
  featuredSection: document.querySelector("#featuredSection"),
  externalSection: document.querySelector("#externalSection"),
  dropZone: document.querySelector("#dropZone"),
  importInput: document.querySelector("#importInput"),
  importButton: document.querySelector("#importButton"),
  sourceUrlInput: document.querySelector("#sourceUrlInput"),
  downloadImportButton: document.querySelector("#downloadImportButton"),
  importStatus: document.querySelector("#importStatus"),
  toast: document.querySelector("#toast"),
};

function apiUrl(path) {
  return `${path}?token=${encodeURIComponent(token)}`;
}

async function readJsonResponse(response, fallback) {
  let data = {};
  try {
    data = await response.json();
  } catch (_error) {
    data = {};
  }
  if (!response.ok || data.ok === false) throw new Error(data.error || fallback);
  return data;
}

async function apiGet(path) {
  const response = await fetch(apiUrl(path), { cache: "no-store" });
  return readJsonResponse(response, "请求失败");
}

async function apiPost(path, body) {
  const response = await fetch(path, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-MascotMate-Token": token,
    },
    body: JSON.stringify(body),
  });
  return readJsonResponse(response, "请求失败");
}

async function apiUpload(path, file) {
  const form = new FormData();
  form.append("file", file, file.name || "skin.zip");
  const response = await fetch(path, {
    method: "POST",
    headers: { "X-MascotMate-Token": token },
    body: form,
  });
  return readJsonResponse(response, "上传失败");
}

async function loadCatalog() {
  if (window.location.protocol === "file:") {
    els.summary.textContent = "请从桌宠右键菜单重新打开皮肤商店";
    showToast("本页面需要由本地 helper 服务打开，不能直接双击 HTML 文件。");
    return;
  }
  if (!token) {
    showToast("缺少本地会话 token，请从桌宠菜单重新打开皮肤商店。");
    return;
  }
  els.summary.textContent = "正在加载皮肤...";
  try {
    const data = await apiGet("/api/catalog");
    state.featured = data.featured || [];
    state.external = data.external || [];
    state.installed = data.installed || [];
    state.current = data.current_skin_id || "";
    els.summary.textContent = `${state.installed.length} 个本地皮肤，${state.featured.length} 个精选直装，${state.external.length} 个 Shimeji 浏览条目，当前：${state.current || "默认"}`;
    render();
  } catch (error) {
    els.summary.textContent = "皮肤商店连接失败";
    showToast(error.message);
  }
}

function installedIds() {
  return new Set(state.installed.map((item) => item.id));
}

function render() {
  const source = els.sourceFilter.value;
  const query = els.searchInput.value.trim().toLowerCase();
  const status = els.statusFilter.value;
  const ids = installedIds();

  const installed = state.installed.filter((entry) => {
    if (source !== "all" && source !== "installed") return false;
    return matches(entry, query, "installed") && status === "all";
  });
  const featured = state.featured.filter((entry) => {
    if (source !== "all" && source !== "featured") return false;
    return matches(entry, query, "featured") && status === "all";
  });
  const external = state.external.filter((entry) => {
    if (source !== "all" && source !== "external") return false;
    return matches(entry, query, "external") && (status === "all" || entry.status === status);
  });

  els.installedSection.hidden = source !== "all" && source !== "installed";
  els.featuredSection.hidden = source !== "all" && source !== "featured";
  els.externalSection.hidden = source !== "all" && source !== "external";
  els.installedGrid.innerHTML = installed.map((entry) => installedCard(entry)).join("");
  els.featuredGrid.innerHTML = featured.map((entry) => featuredCard(entry, ids)).join("");
  const visibleExternal = external.slice(0, 140);
  els.externalGrid.innerHTML = visibleExternal.map((entry) => externalCard(entry)).join("");
  els.moreHint.textContent = external.length > visibleExternal.length
    ? `已显示前 ${visibleExternal.length} 个结果，继续搜索可以缩小范围。`
    : "";
  bindActions();
}

function matches(entry, query, kind) {
  if (!query) return true;
  const haystack = [
    kind,
    entry.id,
    entry.name,
    entry.description,
    entry.artist,
    entry.status,
    entry.complexity,
    entry.kind,
    ...(entry.tags || []),
    ...(entry.features || []),
  ].join(" ").toLowerCase();
  return haystack.includes(query);
}

function installedCard(entry) {
  const selected = state.current === entry.id || entry.selected;
  return `
    <article class="card local-card">
      <div class="preview">${previewImage(entry.preview_url, entry.name || entry.id)}</div>
      <div class="content">
        <div class="badges">
          <span class="badge ${entry.kind === "user" ? "green" : "gray"}">${kindLabel(entry.kind)}</span>
          ${selected ? '<span class="badge">当前</span>' : ""}
        </div>
        <div class="name">${escapeHtml(entry.name || entry.id)}</div>
        <p class="desc">${selected ? "正在使用这款皮肤。" : "已安装，可直接切换。"} </p>
        <div class="actions">
          <span class="meta">${escapeHtml(entry.id)}</span>
          <button data-action="select" data-id="${escapeAttr(entry.id)}" ${selected ? "disabled" : ""}>${selected ? "当前" : "启用"}</button>
        </div>
      </div>
    </article>
  `;
}

function featuredCard(entry, ids) {
  const installed = ids.has(entry.id);
  const selected = state.current === entry.id;
  const action = selected ? "已启用" : installed ? "启用" : "安装并启用";
  return `
    <article class="card featured">
      <div class="preview">${previewImage(entry.preview_url, entry.name || entry.id)}</div>
      <div class="content">
        <div class="badges">
          <span class="badge green">一键直装</span>
          ${selected ? '<span class="badge">当前</span>' : installed ? '<span class="badge">已安装</span>' : ""}
        </div>
        <div class="name">${escapeHtml(entry.name || entry.id)}</div>
        <p class="desc">${escapeHtml(entry.description || "")}</p>
        <div class="meta">${escapeHtml((entry.tags || []).join(" / "))}</div>
        <div class="actions">
          <span class="meta">${formatSize(entry.size_bytes)}</span>
          <button data-action="${installed ? "select" : "install"}" data-id="${escapeAttr(entry.id)}" ${selected ? "disabled" : ""}>${action}</button>
        </div>
      </div>
    </article>
  `;
}

function externalCard(entry) {
  const badge = statusBadge(entry.status);
  return `
    <article class="card">
      <div class="preview">${previewImage(entry.preview_url, entry.name || entry.id, true)}</div>
      <div class="content">
        <div class="badges">
          <span class="badge ${badge.className}">${badge.text}</span>
          ${entry.complexity ? `<span class="badge gray">${escapeHtml(entry.complexity)}</span>` : ""}
        </div>
        <div class="name">${escapeHtml(entry.name || entry.id)}</div>
        <div class="meta">${escapeHtml(entry.artist || "Cachomon")} · ${formatCount(entry.downloads)} 次下载</div>
        <p class="desc">${escapeHtml((entry.features || []).join(" / ") || "打开原站下载后拖入 ZIP。")}</p>
        <div class="actions two">
          <button class="ghost" data-action="pick-import" type="button">导入 ZIP</button>
          <button data-action="open-source" data-id="${escapeAttr(entry.id)}">打开原站</button>
        </div>
      </div>
    </article>
  `;
}

function previewImage(url, alt, remote = false) {
  if (!url) return '<div class="preview-placeholder">ZIP</div>';
  const lazy = remote ? ' loading="lazy"' : "";
  return `<img src="${escapeAttr(url)}"${lazy} alt="${escapeAttr(alt || "")}">`;
}

function kindLabel(kind) {
  if (kind === "builtin") return "内置";
  if (kind === "packaged") return "随包";
  if (kind === "user") return "本地";
  return "已安装";
}

function bindActions() {
  document.querySelectorAll("button[data-action]").forEach((button) => {
    button.addEventListener("click", async () => {
      const action = button.dataset.action;
      const id = button.dataset.id || "";
      if (action === "pick-import") {
        els.importInput.click();
        return;
      }
      await runAction(button, action, id);
    });
  });
}

async function runAction(button, action, id) {
  if (state.busy.has(id)) return;
  state.busy.add(id);
  const original = button.textContent;
  button.disabled = true;
  button.textContent = action === "open-source" ? "打开中..." : "处理中...";
  try {
    if (action === "install") await apiPost("/api/install", { id });
    if (action === "select") await apiPost("/api/select", { id });
    if (action === "open-source") await apiPost("/api/open-source", { id });
    showToast(action === "open-source" ? "已打开原站页面，下载 ZIP 后可拖入本页。" : "皮肤已启用。");
    await loadCatalog();
  } catch (error) {
    showToast(error.message);
    button.disabled = false;
    button.textContent = original;
  } finally {
    state.busy.delete(id);
  }
}

async function importFile(file) {
  if (!file) return;
  if (!file.name.toLowerCase().endsWith(".zip")) {
    showToast("请选择 ZIP 文件。");
    return;
  }
  if (file.size <= 0) {
    showToast("ZIP 文件为空。");
    return;
  }
  if (file.size > MAX_UPLOAD_BYTES) {
    showToast("ZIP 文件超过 100MB 上限。");
    return;
  }
  els.importButton.disabled = true;
  els.importStatus.textContent = `正在导入 ${file.name}...`;
  try {
    const result = await apiUpload("/api/import-zip", file);
    showToast(result.message || "皮肤已导入并启用。");
    els.importStatus.textContent = `已启用：${result.skin_name || result.skin_id}`;
    await loadCatalog();
  } catch (error) {
    els.importStatus.textContent = "导入失败，请检查 ZIP 是否为皮肤包。";
    showToast(importErrorMessage(error));
  } finally {
    els.importButton.disabled = false;
    els.importInput.value = "";
  }
}

async function importUrl() {
  const url = els.sourceUrlInput.value.trim();
  if (!url) {
    showToast("请先粘贴 ZIP 下载链接。");
    return;
  }
  els.downloadImportButton.disabled = true;
  els.importStatus.textContent = "正在从原站下载并解析...";
  try {
    const result = await apiPost("/api/import-url", { url });
    showToast(result.message || "皮肤已导入并启用。");
    els.importStatus.textContent = `已启用：${result.skin_name || result.skin_id}`;
    els.sourceUrlInput.value = "";
    await loadCatalog();
  } catch (error) {
    els.importStatus.textContent = "下载或导入失败。";
    showToast(importErrorMessage(error));
  } finally {
    els.downloadImportButton.disabled = false;
  }
}

function statusBadge(status) {
  if (status === "free") return { text: "可下载", className: "green" };
  if (status === "beta") return { text: "Beta", className: "" };
  if (status === "patreon") return { text: "Patreon", className: "amber" };
  if (status === "unavailable") return { text: "不可下载", className: "gray" };
  return { text: "外部页面", className: "coral" };
}

function formatSize(value) {
  const bytes = Number(value || 0);
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return bytes ? `${bytes} B` : "未知大小";
}

function formatCount(value) {
  const count = Number(value || 0);
  if (count >= 10000) return `${(count / 10000).toFixed(1)}万`;
  return `${count}`;
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "\"": "&quot;",
    "'": "&#039;",
  }[char]));
}

function escapeAttr(value) {
  return escapeHtml(value);
}

function importErrorMessage(error) {
  if (error instanceof TypeError) {
    return "无法连接本地皮肤商店服务，请从桌宠右键菜单重新打开皮肤商店。";
  }
  return error.message || "导入失败。";
}

let toastTimer = 0;
function showToast(message) {
  window.clearTimeout(toastTimer);
  els.toast.textContent = message;
  els.toast.classList.add("show");
  toastTimer = window.setTimeout(() => els.toast.classList.remove("show"), 3000);
}

els.refreshButton.addEventListener("click", loadCatalog);
els.searchInput.addEventListener("input", render);
els.sourceFilter.addEventListener("change", render);
els.statusFilter.addEventListener("change", render);
els.importButton.addEventListener("click", () => els.importInput.click());
els.importInput.addEventListener("change", () => importFile(els.importInput.files[0]));
els.downloadImportButton.addEventListener("click", importUrl);
els.sourceUrlInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") importUrl();
});
els.dropZone.addEventListener("dragover", (event) => {
  event.preventDefault();
  els.dropZone.classList.add("dragging");
});
els.dropZone.addEventListener("dragleave", () => els.dropZone.classList.remove("dragging"));
els.dropZone.addEventListener("drop", (event) => {
  event.preventDefault();
  els.dropZone.classList.remove("dragging");
  importFile(event.dataTransfer.files[0]);
});

loadCatalog();
