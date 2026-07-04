const params = new URLSearchParams(window.location.search);
const token = params.get("token") || "";

const $ = (id) => document.getElementById(id);

function headers() {
  return token ? { "X-MascotMate-Token": token } : {};
}

async function apiGet(path) {
  const response = await fetch(path, { headers: headers(), cache: "no-store" });
  const data = await response.json();
  if (!response.ok || data.ok === false) {
    throw new Error(data.error || `HTTP ${response.status}`);
  }
  return data;
}

async function apiPost(path, payload) {
  const response = await fetch(path, {
    method: "POST",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const data = await response.json();
  if (!response.ok || data.ok === false) {
    throw new Error(data.error || `HTTP ${response.status}`);
  }
  return data;
}

function valueAt(source, path, fallback = "-") {
  let current = source;
  for (const key of path) {
    if (!current || typeof current !== "object" || !(key in current)) return fallback;
    current = current[key];
  }
  return current ?? fallback;
}

function setText(id, value) {
  $(id).textContent = value === "" || value === undefined || value === null ? "-" : String(value);
}

function setMeter(id, value) {
  const meter = $(id);
  const number = Number(value || 0);
  meter.value = Math.max(0, Math.min(100, number));
  setText(`${id}Text`, meter.value);
}

function formatTime(unix) {
  const number = Number(unix || 0);
  if (number <= 0) return "-";
  return new Date(number * 1000).toLocaleString();
}

function boolText(value) {
  return value ? "是" : "否";
}

function renderSnapshot(snapshot) {
  setText("updated", `更新 ${formatTime(snapshot.generated_at)}`);
  setText("mode", valueAt(snapshot, ["runtime", "behavior_mode"]));
  setText("period", valueAt(snapshot, ["runtime", "period"]));
  setText("busy", boolText(valueAt(snapshot, ["runtime", "busy"], false)));
  const transparent = valueAt(snapshot, ["window", "window_transparent"], false);
  const transparentBg = valueAt(snapshot, ["window", "viewport_transparent_bg"], false);
  setText("transparent", transparent && transparentBg ? "正常" : "检查");

  const state = snapshot.state || {};
  setMeter("mood", state.mood);
  setMeter("hunger", state.hunger);
  setMeter("energy", state.energy);
  setMeter("affection", state.affection);

  const adaptation = valueAt(snapshot, ["config", "behavior_adaptation"], {});
  $("adaptEnabled").checked = Boolean(adaptation.enabled);
  $("adaptStrength").value = adaptation.strength || "visible";
  document.querySelectorAll("[data-mode]").forEach((button) => {
    button.classList.toggle("active", button.dataset.mode === valueAt(snapshot, ["runtime", "behavior_mode"], ""));
  });

  renderDecision(snapshot.last_decision || {});
  renderMemory(snapshot.memory || {});
  renderEvents(snapshot.recent_events || []);
}

function renderDecision(decision) {
  const decisionName = decision.name ? `${decision.type}:${decision.name}` : decision.type || "-";
  setText("decisionType", decisionName);
  setText("decisionReason", decision.reason || valueAt(decision, ["intent", "reason"], "-"));
  const intent = decision.intent || {};
  const intentText = intent.type ? `${intent.type}:${intent.name || ""} / ${intent.source || "rule"}` : "-";
  setText("decisionIntent", intentText);
  const adaptation = decision.adaptation || {};
  if (adaptation.enabled) {
    const reasons = Array.isArray(adaptation.reasons) ? adaptation.reasons.join("；") : "";
    setText("decisionAdaptation", `${adaptation.strength} / cooldown x${Number(adaptation.cooldown_multiplier || 1).toFixed(2)} / ${reasons}`);
  } else {
    setText("decisionAdaptation", "-");
  }
}

function renderMemory(memory) {
  const relationship = memory.relationship || {};
  setText("relationship", `${relationship.level || "-"} / ${relationship.familiarity ?? "-"}`);
  const favorites = valueAt(memory, ["preferences", "favorite_interactions"], []);
  setText("favorites", Array.isArray(favorites) && favorites.length ? favorites.join("、") : "-");
  const lines = valueAt(memory, ["dialogue", "recent_lines"], []);
  if (Array.isArray(lines) && lines.length) {
    setText("recentExpressions", lines.slice(-3).map((item) => item.text).join(" / "));
  } else {
    setText("recentExpressions", "-");
  }
}

function renderEvents(events) {
  const rows = Array.isArray(events) ? events.slice(-30).reverse() : [];
  $("eventsBody").innerHTML = rows.map((event) => {
    const sequence = event.sequence ?? "";
    const kind = event.kind ?? "";
    const source = event.source ?? "";
    const mode = event.mode ?? valueAt(event, ["context", "mode"], "");
    return `<tr><td>${escapeHtml(sequence)}</td><td>${escapeHtml(kind)}</td><td>${escapeHtml(source)}</td><td>${escapeHtml(mode)}</td><td>${escapeHtml(formatTime(event.at))}</td></tr>`;
  }).join("");
}

function renderScenarios(result) {
  const scenarios = result && Array.isArray(result.scenarios) ? result.scenarios : [];
  $("scenarioResults").innerHTML = scenarios.map((item) => {
    const ok = item.passed ? "pass" : "fail";
    const mark = item.passed ? "通过" : "异常";
    const decision = item.decision || {};
    const name = decision.name ? `${decision.type}:${decision.name}` : decision.type || "-";
    const reason = decision.reason || valueAt(decision, ["intent", "reason"], "-");
    return `<div class="scenario-result ${ok}"><strong>${escapeHtml(item.label || item.id)} · ${mark}</strong><code>${escapeHtml(name)} | ${escapeHtml(reason)}</code></div>`;
  }).join("");
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  }[char]));
}

async function loadSnapshot() {
  try {
    const data = await apiGet("/api/companion/snapshot");
    if (data.exists && data.snapshot) renderSnapshot(data.snapshot);
    $("connection").textContent = data.exists ? "已连接" : "等待快照";
    $("connection").className = `status-pill ${data.exists ? "ok" : ""}`;
  } catch (error) {
    $("connection").textContent = "连接失败";
    $("connection").className = "status-pill error";
  }
}

async function loadScenarioResult() {
  try {
    const data = await apiGet("/api/companion/scenario-result");
    if (data.exists) renderScenarios(data.result);
  } catch (_error) {
    return;
  }
}

async function sendCommand(payload) {
  $("commandStatus").textContent = "发送中";
  try {
    const data = await apiPost("/api/companion/command", payload);
    $("commandStatus").textContent = data.message || "已发送";
  } catch (error) {
    $("commandStatus").textContent = error.message;
  }
}

function bindControls() {
  document.querySelectorAll("[data-mode]").forEach((button) => {
    button.addEventListener("click", () => sendCommand({
      command: "set_behavior_mode",
      payload: { mode: button.dataset.mode },
    }));
  });
  $("applyAdaptation").addEventListener("click", () => sendCommand({
    command: "set_adaptation",
    payload: {
      enabled: $("adaptEnabled").checked,
      strength: $("adaptStrength").value,
    },
  }));
  $("rebuildMemory").addEventListener("click", () => sendCommand({ command: "rebuild_memory" }));
  $("scenarioButtons").addEventListener("click", async (event) => {
    const button = event.target.closest("[data-scenario]");
    if (!button) return;
    await sendCommand({
      command: "run_scenario",
      payload: { scenario_id: button.dataset.scenario },
    });
    setTimeout(loadScenarioResult, 700);
  });
}

bindControls();
loadSnapshot();
loadScenarioResult();
setInterval(loadSnapshot, 1000);
setInterval(loadScenarioResult, 2500);
