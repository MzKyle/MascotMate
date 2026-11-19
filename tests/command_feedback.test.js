const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.join(__dirname, "..");
const flush = () => new Promise(setImmediate);

function browser(page, respond) {
  let time = 0;
  const timers = [];
  const elements = new Map();
  const updates = [];
  function element(id) {
    if (!elements.has(id)) {
      let text = "";
      elements.set(id, {
        value: ["sourceFilter", "statusFilter"].includes(id) ? "all" : "",
        checked: false,
        classList: { add() {}, remove() {}, toggle() {} },
        addEventListener() {},
        get textContent() { return text; },
        set textContent(value) {
          text = value;
          updates.push([id, value]);
        },
      });
    }
    return elements.get(id);
  }

  function setTimeout(task, delay) {
    timers.push({ task, at: time + delay });
    return task;
  }
  function clearTimeout(task) {
    const index = timers.findIndex((timer) => timer.task === task);
    if (index >= 0) timers.splice(index, 1);
  }
  const context = vm.createContext({
    window: { location: new URL("http://127.0.0.1/?token=test"), setTimeout, clearTimeout },
    document: {
      querySelector: (selector) => element(selector.slice(1)),
      getElementById: element,
      querySelectorAll: () => [],
    },
    URLSearchParams,
    AbortSignal: { timeout: () => undefined },
    performance: { now: () => time },
    setTimeout,
    setInterval: () => {},
    fetch: async (url, options) => {
      const route = new URL(url, "http://127.0.0.1").pathname;
      const data = await respond(route, options);
      return { ok: true, json: async () => data };
    },
  });
  for (const source of ["skin_store/command_feedback.js", `${page}/app.js`]) {
    vm.runInContext(fs.readFileSync(path.join(root, source), "utf8"), context, { filename: source });
  }
  return {
    context,
    element,
    updates,
    async advance() {
      timers.sort((a, b) => a.at - b.at);
      const timer = timers.shift();
      assert.ok(timer, "expected a scheduled status check");
      time = timer.at;
      timer.task();
      await flush();
    },
  };
}

function deferred() {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
}

test("the console shows the actual setting with no intermediate text on fast success", async () => {
  let checks = 0;
  const ui = browser("companion_console", (route) => {
    if (route === "/api/companion/command") return { ok: true, command_id: "internal-id" };
    if (route === "/api/commands/internal-id") {
      return { receipt: { status: ++checks < 2 ? "running" : "succeeded" } };
    }
    if (route === "/api/companion/snapshot") {
      return { exists: true, snapshot: { config: { dialogue_tone: checks < 2 ? "gentle" : "calm" } } };
    }
    return { exists: false };
  });
  await flush();
  const completion = ui.context.sendCommand({ command: "set_dialogue_tone", payload: { tone: "calm" } });
  await flush();
  assert.equal(ui.element("dialogueTone").value, "gentle");
  assert.equal(ui.element("commandStatus").textContent, "");
  await ui.advance();
  await completion;
  assert.equal(ui.element("dialogueTone").value, "calm");
  assert.deepEqual(ui.updates.filter(([id]) => id === "commandStatus"), []);
});

test("an unknown console result is checked in the background and can resolve", async () => {
  let complete = false;
  const ui = browser("companion_console", (route) => {
    if (route === "/api/companion/command") return { command_id: "internal-id" };
    if (route === "/api/commands/internal-id") {
      return { receipt: { status: complete ? "succeeded" : "pending" } };
    }
    return { exists: false };
  });
  const completion = ui.context.sendCommand({ command: "summarize_memory" });
  await flush();
  for (let index = 0; index < 26; index += 1) await ui.advance();
  assert.equal(ui.element("commandStatus").textContent, "暂时无法确认结果。");
  complete = true;
  await ui.advance();
  await completion;
  assert.deepEqual(ui.updates.filter(([id]) => id === "commandStatus").map(([, value]) => value), ["暂时无法确认结果。", ""]);
});

test("a late console result cannot replace newer feedback or show protocol details", async () => {
  const older = deferred();
  let submissions = 0;
  const ui = browser("companion_console", (route) => {
    if (route === "/api/companion/command") return { command_id: `command-${++submissions}` };
    if (route === "/api/commands/command-1") return older.promise;
    if (route === "/api/commands/command-2") return { receipt: { status: "failed", error: "raw stack and command ID" } };
    return { exists: false };
  });
  const first = ui.context.sendCommand({ command: "set_dialogue_tone" });
  const second = ui.context.sendCommand({ command: "set_adaptation" });
  await second;
  assert.equal(ui.element("commandStatus").textContent, "设置保存失败，请重试。");
  older.resolve({ receipt: { status: "succeeded" } });
  await first;
  assert.equal(ui.element("commandStatus").textContent, "设置保存失败，请重试。");
});

test("skin selection depends on the confirmed catalog and ignores stale action messages", async () => {
  const older = deferred();
  const newer = deferred();
  let skin = "classic_shinchan";
  const ui = browser("skin_store", (route, options) => {
    if (route === "/api/select") return { command_id: JSON.parse(options.body).id };
    if (route === "/api/commands/older") return older.promise;
    if (route === "/api/commands/newer") return newer.promise;
    return { installed: [], current_skin_id: skin };
  });
  await flush();
  const first = ui.context.runAction({ disabled: false }, "select", "older");
  const second = ui.context.runAction({ disabled: false }, "select", "newer");
  await flush();
  assert.match(ui.element("summary").textContent, /classic_shinchan/);
  assert.equal(ui.element("toast").textContent, "");
  skin = "newer";
  newer.resolve({ receipt: { status: "succeeded" } });
  await second;
  older.resolve({ receipt: { status: "failed", error: "debug detail" } });
  await first;
  assert.match(ui.element("summary").textContent, /newer/);
  assert.equal(ui.element("toast").textContent, "");
  assert.ok(!ui.updates.some(([id, value]) => id === "summary" && value.includes("正在加载")));
});

test("skin selection keeps the existing skin on failure and describes uncertainty plainly", async () => {
  let status = "failed";
  const ui = browser("skin_store", (route) => {
    if (route === "/api/select") return { command_id: "hidden-id" };
    if (route === "/api/commands/hidden-id") {
      return { receipt: { status: "failed", error: "internal_execution_error", outcome_unknown: status === "unknown" } };
    }
    return { installed: [], current_skin_id: "classic_shinchan" };
  });
  await flush();
  const button = { disabled: false };
  await ui.context.runAction(button, "select", "new-skin");
  assert.equal(ui.element("toast").textContent, "皮肤切换失败，请重试。");
  assert.equal(button.disabled, false);
  status = "unknown";
  const nextAttempt = ui.context.runAction(button, "select", "new-skin");
  await flush();
  assert.equal(ui.element("toast").textContent, "暂时无法确认皮肤是否已启用。");
  assert.equal(button.disabled, false);
  assert.match(ui.element("summary").textContent, /classic_shinchan/);
  status = "failed";
  await ui.advance();
  await nextAttempt;
});
