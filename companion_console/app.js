const params = new URLSearchParams(window.location.search);
const token = params.get("token") || "";

const $ = (id) => document.getElementById(id);
const settingFields = {
  set_dialogue_tone: ["dialogueTone"],
  set_adaptation: ["adaptEnabled", "adaptStrength"],
  set_ai_expression: ["aiEnabled", "aiProvider", "aiTimeout"],
  set_ai_memory_summary: ["summaryEnabled", "summaryProvider", "summaryTimeout", "summaryMinEvents", "summaryMinInterval"],
};
const lastValues = new Map();
const latestSettings = new Map();
let commandVersion = 0;
let submissions = Promise.resolve();
let snapshotVersion = 0;
let renderedSnapshot = 0;
let scenarioVersion = 0;
let renderedScenario = 0;

function headers() {
  return token ? { "X-MascotMate-Token": token } : {};
}

async function apiGet(path, signal) {
  const response = await fetch(path, { headers: headers(), cache: "no-store", signal });
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
    signal: AbortSignal.timeout(10000),
  });
  const data = await response.json();
  if (!response.ok || data.ok === false) {
    const error = new Error(data.error || `HTTP ${response.status}`);
    error.rejected = true;
    throw error;
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

function renderSetting(id, value, forceFields) {
  if (!forceFields.includes(id) && lastValues.get(id) === value) return;
  lastValues.set(id, value);
  const input = $(id);
  if (input.type === "checkbox") input.checked = value;
  else input.value = value;
}

function renderSnapshot(snapshot, forceFields) {
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
  renderSetting("dialogueTone", valueAt(snapshot, ["config", "dialogue_tone"], "gentle"), forceFields);
  renderSetting("adaptEnabled", Boolean(adaptation.enabled), forceFields);
  renderSetting("adaptStrength", adaptation.strength || "visible", forceFields);
  const aiConfig = valueAt(snapshot, ["config", "ai_expression"], {});
  renderSetting("aiEnabled", Boolean(aiConfig.enabled), forceFields);
  renderSetting("aiProvider", aiConfig.provider || "local_stub", forceFields);
  renderSetting("aiTimeout", Number(aiConfig.timeout_ms || 800), forceFields);
  const summaryConfig = valueAt(snapshot, ["config", "ai_memory_summary"], {});
  renderSetting("summaryEnabled", Boolean(summaryConfig.enabled), forceFields);
  renderSetting("summaryProvider", summaryConfig.provider || "local_stub", forceFields);
  renderSetting("summaryTimeout", Number(summaryConfig.timeout_ms || 1500), forceFields);
  renderSetting("summaryMinEvents", Number(summaryConfig.min_events || 12), forceFields);
  renderSetting("summaryMinInterval", Number(summaryConfig.min_interval_seconds || 86400), forceFields);
  document.querySelectorAll("[data-mode]").forEach((button) => {
    button.classList.toggle("active", button.dataset.mode === valueAt(snapshot, ["runtime", "behavior_mode"], ""));
  });

  renderDecision(snapshot.last_decision || {});
  renderMemory(snapshot.memory || {}, snapshot.profile || {}, snapshot.last_expression || {}, snapshot.ai_expression || {}, snapshot.ai_memory_summary || {});
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

function renderMemory(memory, profile, lastExpression, aiStatus, summaryStatus) {
  const relationship = memory.relationship || {};
  setText("relationship", `${relationship.level || "-"} / ${relationship.familiarity ?? "-"}`);
  const favorites = valueAt(memory, ["preferences", "favorite_interactions"], []);
  setText("favorites", Array.isArray(favorites) && favorites.length ? favorites.join("、") : "-");
  const profilePrefs = profile.preferences || {};
  const profileSummary = [
    `照料 ${profilePrefs.care_tendency ?? "-"}`,
    `陪玩 ${profilePrefs.play_tendency ?? "-"}`,
    `打扰 ${profilePrefs.interruption_tolerance || "-"}`,
  ].join(" / ");
  setText("profileSummary", profileSummary);
  const lines = valueAt(memory, ["dialogue", "recent_lines"], []);
  if (Array.isArray(lines) && lines.length) {
    setText("recentExpressions", lines.slice(-3).map((item) => item.text).join(" / "));
  } else {
    setText("recentExpressions", "-");
  }
  if (lastExpression && lastExpression.key) {
    const reason = lastExpression.fallback_reason ? ` / ${lastExpression.fallback_reason}` : "";
    setText("lastExpression", `${lastExpression.key} / ${lastExpression.source || "-"}${reason}`);
  } else {
    setText("lastExpression", "-");
  }
  if (aiStatus && Object.keys(aiStatus).length) {
    const health = aiStatus.health || {};
    const stats = aiStatus.source_stats || {};
    const cache = aiStatus.cache || {};
    const available = aiStatus.available ? "可用" : "未确认";
    const configured = health.configured === undefined ? "-" : boolText(health.configured);
    const healthText = health.status ? ` / health ${health.status} / configured ${configured}` : "";
    const statsText = Object.keys(stats).length ? ` / ai ${stats.ai || 0} cache ${stats.ai_cache || 0} local ${stats.local || 0} fallback ${stats.fallback || 0}` : "";
    const cacheText = Object.keys(cache).length ? ` / cache ${cache.size || 0}/${cache.max_size || 0}` : "";
    const error = aiStatus.last_error ? ` / ${aiStatus.last_error}` : "";
    setText("aiStatus", `${aiStatus.enabled ? "开启" : "关闭"} / ${aiStatus.provider || "-"} / ${available}${healthText}${statsText}${cacheText}${error}`);
    const recent = Array.isArray(aiStatus.recent_results) ? aiStatus.recent_results.slice(-5).reverse() : [];
    setText("aiRecentResults", recent.length ? recent.map((item) => {
      const cacheHit = item.cache_hit ? " cache" : "";
      const latency = item.latency_ms === undefined ? "" : ` ${item.latency_ms}ms`;
      return `${item.key || "-"}:${item.source || "-"}${cacheHit}${latency}`;
    }).join(" / ") : "-");
    const fallbackReasons = Array.isArray(aiStatus.fallback_reasons) ? aiStatus.fallback_reasons.slice(-5).reverse() : [];
    setText("aiFallbackReasons", fallbackReasons.length ? fallbackReasons.map((item) => `${item.key || "-"}:${item.reason || "-"}`).join(" / ") : "-");
  } else {
    setText("aiStatus", "-");
    setText("aiRecentResults", "-");
    setText("aiFallbackReasons", "-");
  }
  const summary = summaryStatus && Object.keys(summaryStatus).length ? summaryStatus : valueAt(aiStatus, ["memory_summary"], {});
  if (summary && Object.keys(summary).length) {
    const reason = summary.last_error ? ` / ${summary.last_error}` : "";
    setText("aiMemorySummary", `${summary.enabled ? "开启" : "关闭"} / ${summary.provider || "-"} / ${summary.available ? "可用" : "未确认"}${reason}`);
  } else {
    setText("aiMemorySummary", "-");
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
    const adaptation = decision.adaptation || {};
    const thresholds = adaptation.enabled
      ? `cooldown x${Number(adaptation.cooldown_multiplier || 1).toFixed(2)} / hunger ${adaptation.hunger_threshold ?? "-"} / play ${adaptation.play_threshold ?? "-"}`
      : "-";
    const profile = valueAt(item, ["context", "profile", "preferences"], {});
    const profileText = profile && Object.keys(profile).length
      ? `profile care ${profile.care_tendency ?? "-"} play ${profile.play_tendency ?? "-"} interrupt ${profile.interruption_tolerance || "-"}`
      : "profile -";
    return `<div class="scenario-result ${ok}"><strong>${escapeHtml(item.label || item.id)} · ${mark}</strong><code>${escapeHtml(name)} | ${escapeHtml(reason)}</code><code>${escapeHtml(thresholds)} | ${escapeHtml(profileText)}</code></div>`;
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

async function loadSnapshot(forceFields = []) {
  const version = ++snapshotVersion;
  try {
    const data = await apiGet("/api/companion/snapshot");
    if (version < renderedSnapshot) return;
    renderedSnapshot = version;
    if (data.exists && data.snapshot) renderSnapshot(data.snapshot, forceFields);
    $("connection").textContent = data.exists ? "已连接" : "等待快照";
    $("connection").className = `status-pill ${data.exists ? "ok" : ""}`;
  } catch (error) {
    if (version < renderedSnapshot) return;
    renderedSnapshot = version;
    $("connection").textContent = "连接失败";
    $("connection").className = "status-pill error";
  }
}

async function loadScenarioResult() {
  const version = ++scenarioVersion;
  try {
    const data = await apiGet("/api/companion/scenario-result");
    if (data.exists && version >= renderedScenario) {
      renderedScenario = version;
      renderScenarios(data.result);
    }
  } catch (_error) {
    return;
  }
}

async function sendCommand(payload) {
  const version = ++commandVersion;
  const command = payload.command;
  latestSettings.set(command, version);
  const showFeedback = (message) => {
    const status = $("commandStatus");
    if (version === commandVersion && status.textContent !== message) status.textContent = message;
  };
  showFeedback("");
  // Preserve click order within this page while later commands wait independently.
  const response = submissions.then(() => apiPost("/api/companion/command", payload));
  submissions = response.catch(() => {});
  const unknown = () => showFeedback("暂时无法确认结果。");
  try {
    const data = await response;
    if (!data.command_id) {
      unknown();
      return;
    }
    const receipt = await watchDesktopCommand(data.command_id, apiGet, unknown);
    if (!receipt) return;
    const succeeded = receipt.status === "succeeded";
    showFeedback(succeeded ? "" : commandFailure(command, receipt));
    const fields = latestSettings.get(command) === version ? settingFields[command] : [];
    void loadSnapshot(fields);
    if (command === "run_scenario" && succeeded) void loadScenarioResult();
  } catch (error) {
    if (error.rejected) {
      showFeedback(commandFailure(command));
      if (latestSettings.get(command) === version) void loadSnapshot(settingFields[command]);
    } else {
      unknown();
    }
  }
}

function commandFailure(command, receipt) {
  if (receipt?.status === "expired") return "桌宠未执行此操作，请重试。";
  if (receipt?.error === "disabled" && command === "check_ai_health") return "AI 表达尚未开启。";
  if (receipt?.error === "disabled" && command === "summarize_memory") return "AI 记忆总结尚未开启。";
  return {
    set_behavior_mode: "模式切换失败，请重试。",
    check_ai_health: "AI 状态检查失败，请重试。",
    summarize_memory: "记忆总结失败，请重试。",
    rebuild_memory: "记忆重建失败，请重试。",
    run_scenario: "回放失败，请重试。",
  }[command] || "设置保存失败，请重试。";
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
  $("applyDialogueTone").addEventListener("click", () => sendCommand({
    command: "set_dialogue_tone",
    payload: { tone: $("dialogueTone").value },
  }));
  $("applyAiExpression").addEventListener("click", () => sendCommand({
    command: "set_ai_expression",
    payload: {
      enabled: $("aiEnabled").checked,
      provider: $("aiProvider").value,
      timeout_ms: Number($("aiTimeout").value || 800),
    },
  }));
  $("checkAiHealth").addEventListener("click", () => sendCommand({ command: "check_ai_health" }));
  $("applyAiSummary").addEventListener("click", () => sendCommand({
    command: "set_ai_memory_summary",
    payload: {
      enabled: $("summaryEnabled").checked,
      provider: $("summaryProvider").value,
      timeout_ms: Number($("summaryTimeout").value || 1500),
      min_events: Number($("summaryMinEvents").value || 12),
      min_interval_seconds: Number($("summaryMinInterval").value || 86400),
    },
  }));
  $("summarizeMemory").addEventListener("click", () => sendCommand({ command: "summarize_memory" }));
  $("rebuildMemory").addEventListener("click", () => sendCommand({ command: "rebuild_memory" }));
  $("scenarioButtons").addEventListener("click", (event) => {
    const button = event.target.closest("[data-scenario]");
    if (!button) return;
    sendCommand({
      command: "run_scenario",
      payload: { scenario_id: button.dataset.scenario },
    });
  });
}

bindControls();
loadSnapshot();
loadScenarioResult();
setInterval(loadSnapshot, 1000);
setInterval(loadScenarioResult, 2500);
