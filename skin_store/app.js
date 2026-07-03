const params = new URLSearchParams(window.location.search);
const token = params.get("token") || "";
const state = {
  featured: [],
  external: [],
  installed: [],
  current: "",
  busy: new Set(),
};

const els = {
  summary: document.querySelector("#summary"),
  featuredGrid: document.querySelector("#featuredGrid"),
  externalGrid: document.querySelector("#externalGrid"),
  searchInput: document.querySelector("#searchInput"),
  sourceFilter: document.querySelector("#sourceFilter"),
  statusFilter: document.querySelector("#statusFilter"),
  refreshButton: document.querySelector("#refreshButton"),
  moreHint: document.querySelector("#moreHint"),
  featuredSection: document.querySelector("#featuredSection"),
  externalSection: document.querySelector("#externalSection"),
  toast: document.querySelector("#toast"),
};

function apiUrl(path) {
  return `${path}?token=${encodeURIComponent(token)}`;
}

async function apiGet(path) {
  const response = await fetch(apiUrl(path), { cache: "no-store" });
  const data = await response.json();
  if (!response.ok || data.ok === false) throw new Error(data.error || "请求失败");
  return data;
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
  const data = await response.json();
  if (!response.ok || data.ok === false) throw new Error(data.error || "请求失败");
  return data;
}

async function loadCatalog() {
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
    els.summary.textContent = `${state.featured.length} 个本地精选，${state.external.length} 个 Shimeji 浏览条目，当前：${state.current || "默认"}`;
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

  const featured = state.featured.filter((entry) => {
    if (source === "external") return false;
    return matches(entry, query, "featured") && (status === "all");
  });
  const external = state.external.filter((entry) => {
    if (source === "featured") return false;
    return matches(entry, query, "external") && (status === "all" || entry.status === status);
  });

  els.featuredSection.hidden = source === "external";
  els.externalSection.hidden = source === "featured";
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
    ...(entry.tags || []),
    ...(entry.features || []),
  ].join(" ").toLowerCase();
  return haystack.includes(query);
}

function featuredCard(entry, ids) {
  const installed = ids.has(entry.id);
  const selected = state.current === entry.id;
  const action = selected ? "已启用" : installed ? "启用" : "安装并启用";
  return `
    <article class="card featured">
      <div class="preview"><img src="${escapeAttr(entry.preview_url || "")}" alt=""></div>
      <div class="content">
        <div class="badges">
          <span class="badge green">本地直装</span>
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
      <div class="preview"><img src="${escapeAttr(entry.preview_url || "")}" loading="lazy" alt=""></div>
      <div class="content">
        <div class="badges">
          <span class="badge ${badge.className}">${badge.text}</span>
          ${entry.complexity ? `<span class="badge gray">${escapeHtml(entry.complexity)}</span>` : ""}
        </div>
        <div class="name">${escapeHtml(entry.name || entry.id)}</div>
        <div class="meta">${escapeHtml(entry.artist || "Cachomon")} · ${formatCount(entry.downloads)} 次下载</div>
        <p class="desc">${escapeHtml((entry.features || []).join(" / ") || "打开原站下载后导入 ZIP。")}</p>
        <div class="actions">
          <span class="meta">Shimeji</span>
          <button class="ghost" data-action="open-source" data-id="${escapeAttr(entry.id)}">打开原站</button>
        </div>
      </div>
    </article>
  `;
}

function bindActions() {
  document.querySelectorAll("button[data-action]").forEach((button) => {
    button.addEventListener("click", async () => {
      const action = button.dataset.action;
      const id = button.dataset.id;
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
    showToast(action === "open-source" ? "已打开原站页面。" : "皮肤已安装并启用。");
    await loadCatalog();
  } catch (error) {
    showToast(error.message);
    button.disabled = false;
    button.textContent = original;
  } finally {
    state.busy.delete(id);
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

let toastTimer = 0;
function showToast(message) {
  window.clearTimeout(toastTimer);
  els.toast.textContent = message;
  els.toast.classList.add("show");
  toastTimer = window.setTimeout(() => els.toast.classList.remove("show"), 2600);
}

els.refreshButton.addEventListener("click", loadCatalog);
els.searchInput.addEventListener("input", render);
els.sourceFilter.addEventListener("change", render);
els.statusFilter.addEventListener("change", render);

loadCatalog();
