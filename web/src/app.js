import { amountUSDForCategory } from "./core/ledger.js";
import { AppStore } from "./core/store.js";
import {
  escapeHtml,
  formatCurrency,
  formatDateTime,
  formatDuration,
  toNumber,
} from "./core/utils.js";
import { LocalStorageAdapter } from "./storage/localStorageAdapter.js";

const root = document.querySelector("#app");

const store = new AppStore(new LocalStorageAdapter());

const uiState = {
  activeTab: "dashboard",
  sessionCategoryId: null,
  manualOnly: false,
  editingCategoryId: null,
  importPolicy: "replaceExisting",
  sessionNote: "",
};

let latestState = null;
let flashMessage = null;
let flashTimeoutID = null;
let timerDisplayIntervalID = null;

function setFlash(type, text, timeoutMs = 4500) {
  flashMessage = { type, text };
  if (flashTimeoutID) {
    clearTimeout(flashTimeoutID);
  }

  flashTimeoutID = window.setTimeout(() => {
    flashMessage = null;
    render();
  }, timeoutMs);

  render();
}

function clearFlash() {
  flashMessage = null;
  if (flashTimeoutID) {
    clearTimeout(flashTimeoutID);
    flashTimeoutID = null;
  }
  render();
}

function ensureUISelections(state) {
  if (!state) {
    return;
  }

  if (state.activeSession?.categoryId) {
    uiState.sessionCategoryId = state.activeSession.categoryId;
    return;
  }

  if (uiState.sessionCategoryId && state.categories.some((category) => category.id === uiState.sessionCategoryId)) {
    return;
  }

  uiState.sessionCategoryId = state.categories[0]?.id || null;
}

function getSelectedSessionCategory(state) {
  if (!state) {
    return null;
  }
  return state.categories.find((category) => category.id === uiState.sessionCategoryId) || null;
}

function getEditingCategory(state) {
  if (!state || !uiState.editingCategoryId) {
    return null;
  }
  return state.categories.find((category) => category.id === uiState.editingCategoryId) || null;
}

function render() {
  if (!latestState) {
    return;
  }

  ensureUISelections(latestState);
  const dashboard = store.computeDashboard();
  const selectedCategory = getSelectedSessionCategory(latestState);
  const editingCategory = getEditingCategory(latestState);

  root.innerHTML = `
    <div class="shell">
      <header class="topbar">
        <div class="brand">
          <h1>Grind N Chill Web</h1>
          <p>Static-hosted, local-first, and cloud-ready.</p>
        </div>
        <nav class="tabs" aria-label="Main tabs">
          ${renderTab("dashboard", "Dashboard")}
          ${renderTab("session", "Session")}
          ${renderTab("categories", "Categories")}
          ${renderTab("history", "History")}
          ${renderTab("settings", "Settings")}
        </nav>
      </header>

      ${renderFlash()}

      <main class="content">
        ${uiState.activeTab === "dashboard" ? renderDashboard(dashboard) : ""}
        ${uiState.activeTab === "session" ? renderSession(latestState, selectedCategory) : ""}
        ${uiState.activeTab === "categories" ? renderCategories(latestState, editingCategory) : ""}
        ${uiState.activeTab === "history" ? renderHistory(latestState) : ""}
        ${uiState.activeTab === "settings" ? renderSettings(latestState) : ""}
      </main>
    </div>
  `;

  updateTimerDisplays();
  syncTimerLoop();
}

function renderTab(tab, label) {
  const selected = uiState.activeTab === tab;
  return `
    <button
      class="tab ${selected ? "is-active" : ""}"
      type="button"
      data-tab="${tab}"
      aria-pressed="${selected ? "true" : "false"}"
    >
      ${label}
    </button>
  `;
}

function renderFlash() {
  if (!flashMessage?.text) {
    return "";
  }

  return `
    <section class="flash flash-${flashMessage.type}">
      <p>${escapeHtml(flashMessage.text)}</p>
      <button type="button" class="ghost" data-action="flash-clear">Dismiss</button>
    </section>
  `;
}

function renderDashboard(dashboard) {
  const balanceTone = dashboard.balanceUSD < 0 ? "negative" : "positive";
  const todayTone = dashboard.today.ledgerChange < 0 ? "negative" : "positive";
  const highlight = dashboard.streakHighlight;
  const alerts = dashboard.streakRiskAlerts || [];
  const badges = dashboard.latestBadges || [];

  return `
    <section class="panel-grid">
      <article class="panel">
        <h2>Ledger Balance</h2>
        <p class="metric ${balanceTone}">${formatCurrency(dashboard.balanceUSD)}</p>
        <p class="muted">Net total across all entries.</p>
      </article>

      <article class="panel">
        <h2>Today</h2>
        <p class="metric ${todayTone}">${formatCurrency(dashboard.today.ledgerChange)}</p>
        <p class="muted">
          Grind ${formatCurrency(dashboard.today.gain)} · Chill ${formatCurrency(dashboard.today.spent)} · ${dashboard.today.count} entries
        </p>
      </article>

      <article class="panel">
        <h2>Totals</h2>
        <p class="metric">${dashboard.totalCategories} categories</p>
        <p class="muted">${dashboard.totalEntries} entries logged</p>
      </article>

      <article class="panel panel-wide">
        <h2>Active Session</h2>
        ${dashboard.activeSession
          ? `
            <p class="metric">${escapeHtml(dashboard.activeSession.category?.title || "Unknown")}</p>
            <p class="timer" data-elapsed>${formatDuration(dashboard.activeSession.elapsedSeconds)}</p>
            <p class="muted">Live amount: <strong data-live-amount>${formatCurrency(
              amountUSDForCategory({
                category: dashboard.activeSession.category,
                quantity: dashboard.activeSession.elapsedSeconds / 60,
                usdPerHour: latestState.settings.usdPerHour,
              })
            )}</strong></p>
          `
          : `<p class="muted">No active timer session.</p>`}
      </article>

      <article class="panel panel-wide">
        <h2>Streak Highlight</h2>
        ${highlight
          ? `
            <p><strong>${escapeHtml(highlight.title)}</strong> · ${highlight.type === "goodHabit" ? "Grind" : "Chill"}</p>
            <p class="muted">${escapeHtml(highlight.progressText)}</p>
            <p class="metric">${highlight.streak}${highlight.shortSuffix}</p>
          `
          : `<p class="muted">No active streak yet. Keep your categories moving consistently.</p>`}
      </article>

      <article class="panel panel-wide">
        <h2>Streak Risk Alerts</h2>
        ${alerts.length === 0
          ? `<p class="muted">No streaks at risk right now.</p>`
          : `
            <ul class="list">
              ${alerts
                .slice(0, 3)
                .map(
                  (alert) => `
                    <li>
                      <div>
                        <p><strong>${escapeHtml(alert.title)}</strong> · ${alert.type === "goodHabit" ? "Grind" : "Chill"}</p>
                        <p class="muted">${escapeHtml(alert.message)}</p>
                      </div>
                      <span class="pill ${alert.severity >= 3 ? "pill-danger" : "pill-watch"}">${alert.severity >= 3 ? "High" : "Watch"}</span>
                    </li>
                  `
                )
                .join("")}
            </ul>
          `}
      </article>

      <article class="panel panel-wide">
        <h2>Latest Badges</h2>
        ${badges.length === 0
          ? `<p class="muted">No badges yet. Hit streak milestones (3, 7, 30) to unlock them.</p>`
          : `
            <ul class="list">
              ${badges
                .map(
                  (badge) => `
                    <li>
                      <div>
                        <p><strong>${escapeHtml(badge.label)}</strong></p>
                        <p class="muted">${formatDateTime(badge.dateAwarded)}</p>
                      </div>
                    </li>
                  `
                )
                .join("")}
            </ul>
          `}
      </article>
    </section>
  `;
}

function renderSession(state, selectedCategory) {
  const categories = state.categories;
  const activeSession = state.activeSession;
  const activeCategory =
    activeSession && state.categories.find((category) => category.id === activeSession.categoryId)
      ? state.categories.find((category) => category.id === activeSession.categoryId)
      : null;

  const canStartTimer = selectedCategory && selectedCategory.unit === "time" && !activeSession;

  return `
    <section class="stack">
      <article class="panel">
        <h2>Session</h2>
        ${categories.length === 0
          ? `<p class="muted">Create a category first.</p>`
          : `
            <label class="field">
              <span>Category</span>
              <select id="session-category-select">
                ${categories
                  .map(
                    (category) => `
                      <option value="${category.id}" ${uiState.sessionCategoryId === category.id ? "selected" : ""}>
                        ${escapeHtml(category.title)} (${category.unit})
                      </option>
                    `
                  )
                  .join("")}
              </select>
            </label>
          `}

        ${activeSession
          ? `
            <div class="session-box">
              <p><strong>${escapeHtml(activeCategory?.title || "Unknown")}</strong></p>
              <p class="timer" data-elapsed>${formatDuration(store.getElapsedSeconds())}</p>
              <p class="muted">Live amount: <strong data-live-amount>${formatCurrency(
                amountUSDForCategory({
                  category: activeCategory,
                  quantity: store.getElapsedSeconds() / 60,
                  usdPerHour: state.settings.usdPerHour,
                })
              )}</strong></p>

              <div class="actions">
                ${activeSession.isPaused
                  ? `<button type="button" class="button" data-action="session-resume">Resume</button>`
                  : `<button type="button" class="button" data-action="session-pause">Pause</button>`}
                <button type="button" class="button strong" data-action="session-stop-save">Stop & Save</button>
              </div>

              <label class="field">
                <span>Session note</span>
                <textarea id="session-note" rows="2" placeholder="Optional">${escapeHtml(
                  uiState.sessionNote
                )}</textarea>
              </label>
            </div>
          `
          : `
            <div class="session-box">
              <p class="muted">Start a timer for Time categories only.</p>
              <button type="button" class="button strong" data-action="session-start" ${canStartTimer ? "" : "disabled"}>
                Start Session
              </button>
            </div>
          `}
      </article>

      <article class="panel">
        <h2>Manual Entry</h2>
        ${categories.length === 0
          ? `<p class="muted">Create a category first.</p>`
          : renderManualEntryForm(selectedCategory)}
      </article>
    </section>
  `;
}

function renderManualEntryForm(selectedCategory) {
  if (!selectedCategory) {
    return `<p class="muted">Choose a category.</p>`;
  }

  let label = "Quantity";
  let placeholder = "1";
  let helper = "";
  let defaultValue = "1";

  if (selectedCategory.unit === "time") {
    label = "Duration (minutes)";
    placeholder = "30";
    defaultValue = "30";
    helper = "1 to 600 minutes";
  }

  if (selectedCategory.unit === "count") {
    label = "Count";
    placeholder = "1";
    defaultValue = "1";
    helper = "1 to 500";
  }

  if (selectedCategory.unit === "money") {
    label = "Amount (USD)";
    placeholder = "5";
    defaultValue = "5";
    helper = "Positive USD amount";
  }

  return `
    <form id="manual-entry-form" class="form">
      <label class="field">
        <span>${label}</span>
        <input id="manual-quantity" name="quantity" type="number" step="0.01" min="0" value="${defaultValue}" placeholder="${placeholder}" required />
      </label>
      <p class="muted">${helper}</p>

      <label class="field">
        <span>Note</span>
        <input id="manual-note" name="note" type="text" maxlength="160" placeholder="Optional" />
      </label>

      <button class="button strong" type="submit">Save Manual Entry</button>
    </form>
  `;
}

function renderCategories(state, editingCategory) {
  const isEditing = Boolean(editingCategory);
  const formData = editingCategory || {
    title: "",
    type: "goodHabit",
    unit: "time",
    timeConversionMode: "multiplier",
    multiplier: 1,
    hourlyRateUSD: state.settings.usdPerHour,
    usdPerCount: 1,
    dailyGoalValue: 0,
    streakEnabled: true,
    streakCadence: "daily",
    badgeEnabled: true,
    badgeMilestones: [3, 7, 30],
  };

  const badgeMilestonesInput = Array.isArray(formData.badgeMilestones)
    ? formData.badgeMilestones.join(", ")
    : "3, 7, 30";

  return `
    <section class="stack">
      <article class="panel">
        <h2>${isEditing ? "Edit Category" : "New Category"}</h2>
        <form id="category-form" class="form">
          <label class="field">
            <span>Title</span>
            <input type="text" name="title" value="${escapeHtml(formData.title)}" maxlength="40" required />
          </label>

          <div class="row-2">
            <label class="field">
              <span>Type</span>
              <select name="type">
                <option value="goodHabit" ${formData.type === "goodHabit" ? "selected" : ""}>Good Habit</option>
                <option value="quitHabit" ${formData.type === "quitHabit" ? "selected" : ""}>Quit Habit</option>
              </select>
            </label>

            <label class="field">
              <span>Unit</span>
              <select name="unit">
                <option value="time" ${formData.unit === "time" ? "selected" : ""}>Time</option>
                <option value="count" ${formData.unit === "count" ? "selected" : ""}>Count</option>
                <option value="money" ${formData.unit === "money" ? "selected" : ""}>Money</option>
              </select>
            </label>
          </div>

          <div class="row-3">
            <label class="field">
              <span>Time Mode</span>
              <select name="timeConversionMode">
                <option value="multiplier" ${formData.timeConversionMode === "multiplier" ? "selected" : ""}>Multiplier</option>
                <option value="hourlyRate" ${formData.timeConversionMode === "hourlyRate" ? "selected" : ""}>Hourly Rate</option>
              </select>
            </label>

            <label class="field">
              <span>Multiplier</span>
              <input type="number" step="0.01" min="0.01" name="multiplier" value="${toNumber(formData.multiplier, 1)}" />
            </label>

            <label class="field">
              <span>USD per Count</span>
              <input type="number" step="0.01" min="0.01" name="usdPerCount" value="${toNumber(formData.usdPerCount, 1)}" />
            </label>
          </div>

          <div class="row-2">
            <label class="field">
              <span>Hourly Rate (USD)</span>
              <input type="number" step="0.01" min="0.01" name="hourlyRateUSD" value="${toNumber(
                formData.hourlyRateUSD,
                state.settings.usdPerHour
              )}" />
            </label>

            <label class="field">
              <span>Daily Goal</span>
              <input type="number" step="1" min="0" name="dailyGoalValue" value="${toNumber(formData.dailyGoalValue, 0)}" />
            </label>
          </div>

          <div class="row-3">
            <label class="checkbox">
              <input type="checkbox" name="streakEnabled" ${formData.streakEnabled ? "checked" : ""} />
              Track Streak
            </label>

            <label class="field">
              <span>Streak Cadence</span>
              <select name="streakCadence">
                <option value="daily" ${formData.streakCadence === "daily" ? "selected" : ""}>Daily</option>
                <option value="weekly" ${formData.streakCadence === "weekly" ? "selected" : ""}>Weekly</option>
                <option value="monthly" ${formData.streakCadence === "monthly" ? "selected" : ""}>Monthly</option>
              </select>
            </label>

            <label class="checkbox">
              <input type="checkbox" name="badgeEnabled" ${formData.badgeEnabled ? "checked" : ""} />
              Badge Awards
            </label>
          </div>

          <label class="field">
            <span>Badge Milestones</span>
            <input
              type="text"
              name="badgeMilestonesInput"
              value="${escapeHtml(badgeMilestonesInput)}"
              placeholder="3, 7, 30"
            />
          </label>
          <p class="muted">Comma-separated milestones (for example: 3, 7, 30).</p>

          <div class="actions">
            <button type="submit" class="button strong">${isEditing ? "Save Category" : "Add Category"}</button>
            ${isEditing ? `<button type="button" class="button" data-action="category-cancel-edit">Cancel</button>` : ""}
          </div>

          ${isEditing ? `<input type="hidden" name="categoryId" value="${editingCategory.id}" />` : ""}
        </form>
      </article>

      <article class="panel">
        <h2>Your Categories</h2>
        ${state.categories.length === 0
          ? `<p class="muted">No categories yet.</p>`
          : `<ul class="list">
              ${state.categories
                .map(
                  (category) => `
                    <li>
                      <div>
                        <p><strong>${escapeHtml(category.title)}</strong></p>
                        <p class="muted">${category.type} · ${category.unit} · ${category.streakCadence || "daily"} cadence · goal ${toNumber(
                          category.dailyGoalValue,
                          0
                        )}</p>
                      </div>
                      <div class="actions">
                        <button type="button" class="button" data-action="category-edit" data-id="${category.id}">Edit</button>
                        <button type="button" class="button danger" data-action="category-delete" data-id="${category.id}">Delete</button>
                      </div>
                    </li>
                  `
                )
                .join("")}
            </ul>`}
      </article>
    </section>
  `;
}

function renderHistory(state) {
  const categoriesById = new Map(state.categories.map((category) => [category.id, category]));
  const entries = store.getEntriesFiltered({ manualOnly: uiState.manualOnly });

  return `
    <section class="stack">
      <article class="panel">
        <h2>History</h2>
        <div class="row-wrap">
          <label class="checkbox">
            <input type="checkbox" id="manual-only-toggle" ${uiState.manualOnly ? "checked" : ""} />
            Manual only
          </label>

          <div class="actions">
            <button type="button" class="button" data-action="history-export-json">Export JSON</button>
            <label class="button">
              Import JSON
              <input type="file" id="history-import-input" accept="application/json,.json,text/plain" hidden />
            </label>
            <select id="history-import-policy">
              <option value="replaceExisting" ${uiState.importPolicy === "replaceExisting" ? "selected" : ""}>Replace Existing</option>
              <option value="keepExisting" ${uiState.importPolicy === "keepExisting" ? "selected" : ""}>Keep Existing</option>
            </select>
          </div>
        </div>
      </article>

      <article class="panel">
        <h2>Entries (${entries.length})</h2>
        ${entries.length === 0
          ? `<p class="muted">No entries yet.</p>`
          : `<ul class="list">
              ${entries
                .map((entry) => {
                  const category = categoriesById.get(entry.categoryId);
                  return `
                    <li>
                      <div>
                        <p><strong>${escapeHtml(category?.title || "Unknown")}</strong> · ${formatCurrency(entry.amountUSD)}</p>
                        <p class="muted">${formatDateTime(entry.timestamp)} · ${entry.isManual ? "Manual" : "Timer"} · ${escapeHtml(
                          entry.note || "No note"
                        )}</p>
                      </div>
                      <button type="button" class="button danger" data-action="entry-delete" data-id="${entry.id}">Delete</button>
                    </li>
                  `;
                })
                .join("")}
            </ul>`}
      </article>
    </section>
  `;
}

function renderSettings(state) {
  return `
    <section class="stack">
      <article class="panel">
        <h2>Settings</h2>
        <form id="settings-form" class="form">
          <label class="field">
            <span>USD per Hour</span>
            <input type="number" name="usdPerHour" step="0.01" min="0.01" value="${state.settings.usdPerHour}" required />
          </label>
          <button type="submit" class="button strong">Save Settings</button>
        </form>
      </article>

      <article class="panel">
        <h2>Maintenance</h2>
        <p class="muted">Session timer and data are stored in this browser only.</p>
        <div class="actions">
          <button type="button" class="button" data-action="settings-clear-session">Clear Active Session</button>
          <button type="button" class="button danger" data-action="settings-reset-all">Reset All Data</button>
        </div>
      </article>

      <article class="panel">
        <h2>Future Cloud Upgrade</h2>
        <p class="muted">
          This app already uses a storage adapter boundary. Replace <code>LocalStorageAdapter</code> with a cloud adapter later
          (Supabase/Firebase/etc.) without rewriting core screen logic.
        </p>
      </article>
    </section>
  `;
}

function updateTimerDisplays() {
  if (!latestState?.activeSession) {
    return;
  }

  const session = latestState.activeSession;
  const category = latestState.categories.find((item) => item.id === session.categoryId);
  if (!category) {
    return;
  }

  const elapsedSeconds = store.getElapsedSeconds();
  const elapsedText = formatDuration(elapsedSeconds);

  const elapsedNodes = document.querySelectorAll("[data-elapsed]");
  for (const node of elapsedNodes) {
    node.textContent = elapsedText;
  }

  const liveAmountUSD = amountUSDForCategory({
    category,
    quantity: elapsedSeconds / 60,
    usdPerHour: latestState.settings.usdPerHour,
  });

  const amountNodes = document.querySelectorAll("[data-live-amount]");
  for (const node of amountNodes) {
    node.textContent = formatCurrency(liveAmountUSD);
  }
}

function syncTimerLoop() {
  if (timerDisplayIntervalID) {
    clearInterval(timerDisplayIntervalID);
    timerDisplayIntervalID = null;
  }

  if (!latestState?.activeSession) {
    return;
  }

  timerDisplayIntervalID = window.setInterval(() => {
    updateTimerDisplays();
  }, 1000);
}

function triggerDownload(filename, text) {
  const blob = new Blob([text], { type: "application/json;charset=utf-8" });
  const url = URL.createObjectURL(blob);

  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.append(link);
  link.click();
  link.remove();

  URL.revokeObjectURL(url);
}

async function handleRootClick(event) {
  const tabButton = event.target.closest("[data-tab]");
  if (tabButton) {
    uiState.activeTab = tabButton.dataset.tab;
    render();
    return;
  }

  const actionButton = event.target.closest("[data-action]");
  if (!actionButton) {
    return;
  }

  const { action, id } = actionButton.dataset;

  if (action === "flash-clear") {
    clearFlash();
    return;
  }

  if (action === "session-start") {
    const result = await store.startSession(uiState.sessionCategoryId);
    if (!result.ok) {
      setFlash("error", result.error);
      return;
    }
    uiState.sessionNote = "";
    setFlash("success", "Session started.");
    return;
  }

  if (action === "session-pause") {
    const result = await store.pauseSession();
    if (!result.ok) {
      setFlash("error", result.error);
      return;
    }
    setFlash("success", "Session paused.");
    return;
  }

  if (action === "session-resume") {
    const result = await store.resumeSession();
    if (!result.ok) {
      setFlash("error", result.error);
      return;
    }
    setFlash("success", "Session resumed.");
    return;
  }

  if (action === "session-stop-save") {
    const note = document.querySelector("#session-note")?.value || uiState.sessionNote || "";
    const result = await store.stopSessionAndSave({ note });
    if (!result.ok) {
      setFlash("error", result.error);
      return;
    }
    uiState.sessionNote = "";
    const badgeSuffix =
      result.newAwards && result.newAwards.length > 0 ? ` + ${result.newAwards.length} new badge(s)` : "";
    setFlash("success", `Session saved (${formatCurrency(result.entry.amountUSD)})${badgeSuffix}.`);
    return;
  }

  if (action === "category-edit" && id) {
    uiState.editingCategoryId = id;
    render();
    return;
  }

  if (action === "category-cancel-edit") {
    uiState.editingCategoryId = null;
    render();
    return;
  }

  if (action === "category-delete" && id) {
    const confirmed = window.confirm("Delete this category and its entries?");
    if (!confirmed) {
      return;
    }

    const result = await store.deleteCategory(id);
    if (!result.ok) {
      setFlash("error", result.error);
      return;
    }

    if (uiState.editingCategoryId === id) {
      uiState.editingCategoryId = null;
    }

    setFlash("success", "Category deleted.");
    return;
  }

  if (action === "entry-delete" && id) {
    const confirmed = window.confirm("Delete this entry?");
    if (!confirmed) {
      return;
    }

    const result = await store.deleteEntry(id);
    if (!result.ok) {
      setFlash("error", result.error);
      return;
    }

    setFlash("success", "Entry deleted.");
    return;
  }

  if (action === "settings-clear-session") {
    await store.clearActiveSession();
    uiState.sessionNote = "";
    setFlash("success", "Active session cleared.");
    return;
  }

  if (action === "settings-reset-all") {
    const confirmed = window.confirm("Reset all data? This cannot be undone.");
    if (!confirmed) {
      return;
    }

    await store.resetAllData();
    uiState.editingCategoryId = null;
    uiState.manualOnly = false;
    uiState.sessionNote = "";
    setFlash("success", "All data reset.");
    return;
  }

  if (action === "history-export-json") {
    const payload = store.exportHistoryPayload({
      manualOnlyFilter: uiState.manualOnly,
      dateRangeFilter: "all",
    });

    const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-");
    triggerDownload(`grind-n-chill-history-${stamp}.json`, JSON.stringify(payload, null, 2));
    setFlash("success", "History exported.");
  }
}

async function handleRootSubmit(event) {
  const form = event.target.closest("form");
  if (!form) {
    return;
  }

  event.preventDefault();

  if (form.id === "category-form") {
    const data = new FormData(form);
    const input = {
      title: data.get("title"),
      type: data.get("type"),
      unit: data.get("unit"),
      timeConversionMode: data.get("timeConversionMode"),
      multiplier: data.get("multiplier"),
      hourlyRateUSD: data.get("hourlyRateUSD"),
      usdPerCount: data.get("usdPerCount"),
      dailyGoalValue: data.get("dailyGoalValue"),
      streakEnabled: data.get("streakEnabled") === "on",
      streakCadence: data.get("streakCadence"),
      badgeEnabled: data.get("badgeEnabled") === "on",
      badgeMilestonesInput: data.get("badgeMilestonesInput"),
    };

    const categoryID = data.get("categoryId");
    const result = categoryID ? await store.updateCategory(categoryID, input) : await store.createCategory(input);

    if (!result.ok) {
      setFlash("error", result.error);
      return;
    }

    uiState.editingCategoryId = null;
    setFlash("success", categoryID ? "Category updated." : "Category created.");
    return;
  }

  if (form.id === "manual-entry-form") {
    const data = new FormData(form);

    const result = await store.addManualEntry({
      categoryId: uiState.sessionCategoryId,
      quantity: data.get("quantity"),
      note: data.get("note"),
    });

    if (!result.ok) {
      setFlash("error", result.error);
      return;
    }

    const badgeSuffix =
      result.newAwards && result.newAwards.length > 0 ? ` + ${result.newAwards.length} new badge(s)` : "";
    setFlash("success", `Entry saved (${formatCurrency(result.entry.amountUSD)})${badgeSuffix}.`);
    return;
  }

  if (form.id === "settings-form") {
    const data = new FormData(form);
    const usdPerHour = data.get("usdPerHour");
    await store.setUsdPerHour(usdPerHour);
    setFlash("success", "Settings saved.");
  }
}

async function handleRootChange(event) {
  const target = event.target;
  if (!(target instanceof HTMLElement)) {
    return;
  }

  if (target.id === "session-category-select") {
    uiState.sessionCategoryId = target.value;
    render();
    return;
  }

  if (target.id === "session-note") {
    uiState.sessionNote = target.value;
    return;
  }

  if (target.id === "manual-only-toggle") {
    uiState.manualOnly = target.checked;
    render();
    return;
  }

  if (target.id === "history-import-policy") {
    uiState.importPolicy = target.value === "keepExisting" ? "keepExisting" : "replaceExisting";
    return;
  }

  if (target.id === "history-import-input") {
    const file = target.files?.[0];
    if (!file) {
      return;
    }

    try {
      const content = await file.text();
      const payload = JSON.parse(content);
      const result = await store.importHistoryPayload(payload, {
        conflictPolicy: uiState.importPolicy,
      });

      if (!result.ok) {
        setFlash("error", result.error);
        return;
      }

      const report = result.report;
      setFlash(
        "success",
        `Import finished. created=${report.createdEntries}, updated=${report.updatedEntries}, skipped=${report.skippedEntries}, categories=${report.createdCategories}.`
      );
    } catch (error) {
      setFlash("error", `Import failed: ${error instanceof Error ? error.message : "Unknown error"}`);
    } finally {
      target.value = "";
    }
  }
}

function handleRootInput(event) {
  const target = event.target;
  if (!(target instanceof HTMLElement)) {
    return;
  }

  if (target.id === "session-note") {
    uiState.sessionNote = target.value;
  }
}

function registerServiceWorker() {
  if (!("serviceWorker" in navigator)) {
    return;
  }

  window.addEventListener("load", () => {
    navigator.serviceWorker.register("./sw.js").catch((error) => {
      console.warn("Service worker registration failed:", error);
    });
  });
}

root.addEventListener("click", (event) => {
  handleRootClick(event).catch((error) => {
    setFlash("error", `Unexpected error: ${error instanceof Error ? error.message : "unknown"}`);
  });
});

root.addEventListener("submit", (event) => {
  handleRootSubmit(event).catch((error) => {
    setFlash("error", `Unexpected error: ${error instanceof Error ? error.message : "unknown"}`);
  });
});

root.addEventListener("change", (event) => {
  handleRootChange(event).catch((error) => {
    setFlash("error", `Unexpected error: ${error instanceof Error ? error.message : "unknown"}`);
  });
});

root.addEventListener("input", (event) => {
  handleRootInput(event);
});

(async function bootstrap() {
  latestState = await store.init();
  store.subscribe((state) => {
    latestState = state;
    render();
  });
  registerServiceWorker();
})();
