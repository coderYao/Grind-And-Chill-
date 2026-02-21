import { amountUSDForCategory } from "./core/ledger.js";
import { AppStore } from "./core/store.js";
import {
  dateKey,
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
  historyCategoryId: "all",
  historyType: "all",
  historyQuery: "",
  editingCategoryId: null,
  showNewCategoryForm: false,
  importPolicy: "replaceExisting",
  sessionNote: "",
};

let latestState = null;
let flashMessage = null;
let flashTimeoutID = null;
let timerDisplayIntervalID = null;

const CATEGORY_DEFAULT_EMOJI = {
  goodHabit: "💪",
  quitHabit: "🧊",
};

const CATEGORY_EMOJI_OPTIONS = [
  "💪",
  "📚",
  "🏃",
  "🧠",
  "🧘",
  "🎯",
  "🔥",
  "⚡",
  "🧊",
  "📵",
  "🚭",
  "🍬",
  "🍺",
  "🎮",
  "😴",
  "🛑",
];

const HISTORY_TREND_CHART_LIMIT = 14;

const CHART_COLORS = {
  gain: "#0d7a58",
  spent: "#b02a4b",
  net: "#1f6feb",
  grid: "rgba(15, 32, 39, 0.14)",
  axis: "rgba(15, 32, 39, 0.5)",
};

const GRIND_PIE_COLORS = ["#0d7a58", "#2f9e44", "#37b24d", "#74c69d", "#95d5b2", "#b7e4c7"];
const CHILL_PIE_COLORS = ["#b02a4b", "#c92a2a", "#e03131", "#f06595", "#ff8fab", "#ffb3c1"];
const MANUAL_QUICK_ACTIONS = {
  time: [5, 15, 30, 60],
  count: [1, 3, 5, 10],
  money: [1, 5, 10, 20],
};

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

function ensureHistoryFilters(state) {
  if (!state) {
    return;
  }

  if (
    uiState.historyCategoryId !== "all" &&
    !state.categories.some((category) => category.id === uiState.historyCategoryId)
  ) {
    uiState.historyCategoryId = "all";
  }

  if (!["all", "goodHabit", "quitHabit"].includes(uiState.historyType)) {
    uiState.historyType = "all";
  }
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

function categoryTypeLabel(type) {
  return type === "quitHabit" ? "Chill" : "Grind";
}

function normalizeCategoryType(type) {
  return type === "quitHabit" ? "quitHabit" : "goodHabit";
}

function categoryEmoji(category) {
  const type = normalizeCategoryType(category?.type);
  const rawEmoji = String(category?.emoji || "").trim();
  return rawEmoji || CATEGORY_DEFAULT_EMOJI[type];
}

function categoryDisplayText(category) {
  if (!category) {
    return "Unknown";
  }
  return `${categoryEmoji(category)} ${category.title}`;
}

function renderCategoryTitle(category, useStrong = true) {
  const emoji = category ? categoryEmoji(category) : "❔";
  const title = category?.title || "Unknown";
  const titleNode = useStrong ? `<strong>${escapeHtml(title)}</strong>` : `<span>${escapeHtml(title)}</span>`;
  return `<span class="category-title"><span class="category-emoji">${escapeHtml(emoji)}</span>${titleNode}</span>`;
}

function formatDateShort(dateLike) {
  const date = new Date(dateLike);
  return new Intl.DateTimeFormat(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  }).format(date);
}

function filterHistoryEntries(state) {
  const categoriesById = new Map(state.categories.map((category) => [category.id, category]));
  const query = uiState.historyQuery.trim().toLowerCase();

  return store.getEntriesFiltered({ manualOnly: uiState.manualOnly }).filter((entry) => {
    if (uiState.historyCategoryId !== "all" && entry.categoryId !== uiState.historyCategoryId) {
      return false;
    }

    const category = categoriesById.get(entry.categoryId);
    if (
      uiState.historyType !== "all" &&
      normalizeCategoryType(category?.type) !== uiState.historyType
    ) {
      return false;
    }

    if (!query) {
      return true;
    }

    const title = String(category?.title || "").toLowerCase();
    const note = String(entry.note || "").toLowerCase();
    return title.includes(query) || note.includes(query);
  });
}

function getBackupReminderDetails(state, now = Date.now()) {
  const shouldShow = store.shouldShowBackupReminder(now);
  if (!shouldShow) {
    return null;
  }

  const lastBackup = state.settings?.lastFullBackupAt || null;
  return {
    lastBackup,
  };
}

function render() {
  if (!latestState) {
    return;
  }

  ensureUISelections(latestState);
  ensureHistoryFilters(latestState);
  const dashboard = store.computeDashboard();
  const selectedCategory = getSelectedSessionCategory(latestState);
  const editingCategory = getEditingCategory(latestState);
  const backupReminder = getBackupReminderDetails(latestState);

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

      ${backupReminder ? renderBackupReminder(backupReminder) : ""}
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

function renderBackupReminder(details) {
  return `
    <section class="backup-reminder">
      <div>
        <p><strong>Backup reminder:</strong> export a full backup this week.</p>
        <p class="muted">${
          details.lastBackup
            ? `Last full backup: ${escapeHtml(formatDateShort(details.lastBackup))}.`
            : "No full backup exported yet on this device."
        }</p>
      </div>
      <div class="actions">
        <button type="button" class="button strong" data-action="backup-reminder-export">Export Now</button>
        <button type="button" class="button" data-action="backup-reminder-dismiss">Remind Tomorrow</button>
      </div>
    </section>
  `;
}

function renderDashboard(dashboard) {
  const balanceTone = dashboard.balanceUSD < 0 ? "negative" : "positive";
  const todayTone = dashboard.today.ledgerChange < 0 ? "negative" : "positive";
  const highlight = dashboard.streakHighlight;
  const alerts = dashboard.streakRiskAlerts || [];
  const badges = dashboard.latestBadges || [];
  const categoriesById = new Map((latestState?.categories || []).map((category) => [category.id, category]));
  const highlightCategory = highlight ? categoriesById.get(highlight.categoryId) || highlight : null;

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

      ${renderDashboardCharts(categoriesById)}

      <article class="panel panel-wide">
        <h2>Active Session</h2>
        ${dashboard.activeSession
          ? `
            <p class="metric category-heading">${renderCategoryTitle(dashboard.activeSession.category)}</p>
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
            <p>${renderCategoryTitle(highlightCategory)} · ${categoryTypeLabel(highlight.type)}</p>
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
                  (alert) => {
                    const alertCategory = categoriesById.get(alert.categoryId) || alert;
                    return `
                    <li>
                      <div>
                        <p>${renderCategoryTitle(alertCategory)} · ${categoryTypeLabel(alert.type)}</p>
                        <p class="muted">${escapeHtml(alert.message)}</p>
                      </div>
                      <span class="pill ${alert.severity >= 3 ? "pill-danger" : "pill-watch"}">${alert.severity >= 3 ? "High" : "Watch"}</span>
                    </li>
                  `;
                  }
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
                        ${escapeHtml(categoryDisplayText(category))} (${category.unit})
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
              <p>${renderCategoryTitle(activeCategory)}</p>
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

  const quickValues = MANUAL_QUICK_ACTIONS[selectedCategory.unit] || [];
  const quickButtons = quickValues
    .map((value) => {
      if (selectedCategory.unit === "time") {
        return `<button type="button" class="quick-chip" data-action="manual-quick-add" data-delta="${value}">+${value}m</button>`;
      }
      if (selectedCategory.unit === "money") {
        return `<button type="button" class="quick-chip" data-action="manual-quick-add" data-delta="${value}">+$${value}</button>`;
      }
      return `<button type="button" class="quick-chip" data-action="manual-quick-add" data-delta="${value}">+${value}</button>`;
    })
    .join("");

  return `
    <form id="manual-entry-form" class="form">
      <label class="field">
        <span>${label}</span>
        <input id="manual-quantity" name="quantity" type="number" step="0.01" min="0" value="${defaultValue}" placeholder="${placeholder}" required />
      </label>
      <div class="quick-row" role="group" aria-label="Quick add values">
        ${quickButtons}
      </div>
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
  const shouldShowCreateForm = uiState.showNewCategoryForm && !isEditing;
  const shouldShowForm = isEditing || shouldShowCreateForm;
  const formData = editingCategory || {
    title: "",
    emoji: CATEGORY_DEFAULT_EMOJI.goodHabit,
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

  const formType = normalizeCategoryType(formData.type);
  const formEmoji = String(formData.emoji || "").trim() || CATEGORY_DEFAULT_EMOJI[formType];
  const badgeMilestonesInput = Array.isArray(formData.badgeMilestones)
    ? formData.badgeMilestones.join(", ")
    : "3, 7, 30";

  return `
    <section class="stack">
      <article class="panel">
        <div class="panel-head">
          <div>
            <h2>${isEditing ? "Edit Category" : "Category Builder"}</h2>
            <p class="muted">${
              isEditing
                ? "Update this category."
                : shouldShowCreateForm
                  ? "Create a category with title, emoji, and rules."
                  : "Tap New Category to add one."
            }</p>
          </div>
          ${isEditing
            ? `<button type="button" class="button" data-action="category-cancel-edit">Back</button>`
            : shouldShowCreateForm
              ? `<button type="button" class="button" data-action="category-hide-new">Close</button>`
              : `<button type="button" class="button strong" data-action="category-show-new">+ New Category</button>`}
        </div>

        ${shouldShowForm
          ? `
            <form id="category-form" class="form">
              <div class="row-2">
                <label class="field">
                  <span>Title</span>
                  <input type="text" name="title" value="${escapeHtml(formData.title)}" maxlength="40" required />
                </label>

                <label class="field">
                  <span>Emoji</span>
                  <input type="text" name="emoji" value="${escapeHtml(formEmoji)}" maxlength="16" placeholder="${
                    CATEGORY_DEFAULT_EMOJI[formType]
                  }" required />
                </label>
              </div>

              <div class="emoji-picker">
                ${CATEGORY_EMOJI_OPTIONS.map(
                  (emoji) => `
                    <button
                      type="button"
                      class="emoji-chip ${formEmoji === emoji ? "is-active" : ""}"
                      data-action="category-emoji-pick"
                      data-emoji="${escapeHtml(emoji)}"
                    >
                      ${escapeHtml(emoji)}
                    </button>
                  `
                ).join("")}
              </div>

              <div class="row-2">
                <label class="field">
                  <span>Type</span>
                  <select name="type">
                    <option value="goodHabit" ${formData.type === "goodHabit" ? "selected" : ""}>Grind</option>
                    <option value="quitHabit" ${formData.type === "quitHabit" ? "selected" : ""}>Chill</option>
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
                <button
                  type="button"
                  class="button"
                  data-action="${isEditing ? "category-cancel-edit" : "category-hide-new"}"
                >
                  Cancel
                </button>
              </div>

              ${isEditing ? `<input type="hidden" name="categoryId" value="${editingCategory.id}" />` : ""}
            </form>
          `
          : ""}
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
                        <p>${renderCategoryTitle(category)}</p>
                        <p class="muted">${categoryTypeLabel(category.type)} · ${category.unit} · ${category.streakCadence || "daily"} cadence · goal ${toNumber(
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

function renderDashboardCharts(categoriesById) {
  const allEntries = Array.isArray(latestState?.entries) ? latestState.entries : [];
  const recentTrendPoints = buildHistoryChartPoints(allEntries, 7);
  const todayKey = dateKey(Date.now());
  const todayEntries = allEntries.filter((entry) => dateKey(entry.timestamp) === todayKey);
  const breakdown = buildCategoryBreakdown(todayEntries, categoriesById);
  const grindSlices = addSliceColors(
    breakdown.grind.slices,
    GRIND_PIE_COLORS,
    breakdown.grind.totalAmount
  );
  const chillSlices = addSliceColors(
    breakdown.chill.slices,
    CHILL_PIE_COLORS,
    breakdown.chill.totalAmount
  );
  const hasBreakdown = grindSlices.length > 0 || chillSlices.length > 0;

  return `
    <article class="panel panel-wide">
      <h2>Charts</h2>
      <div class="stack">
        <section>
          <h3 class="subheading">Last 7 Days Trend</h3>
          ${renderHistoryTrendChart(recentTrendPoints)}
        </section>

        <section>
          <h3 class="subheading">Today Category Breakdown</h3>
          ${hasBreakdown
            ? `
              <div class="chart-donut-grid">
                ${grindSlices.length
                  ? renderDonutCard({
                      title: "Grind Today",
                      tone: "grind",
                      slices: grindSlices,
                      totalAmount: breakdown.grind.totalAmount,
                    })
                  : ""}
                ${chillSlices.length
                  ? renderDonutCard({
                      title: "Chill Today",
                      tone: "chill",
                      slices: chillSlices,
                      totalAmount: breakdown.chill.totalAmount,
                    })
                  : ""}
              </div>
            `
            : `<p class="muted">No category money movement yet today.</p>`}
        </section>
      </div>
    </article>
  `;
}

function compactCurrency(value) {
  const normalized = toNumber(value, 0);
  const sign = normalized < 0 ? "-" : "";
  const absolute = Math.abs(normalized);

  if (absolute >= 1_000_000) {
    return `${sign}$${(absolute / 1_000_000).toFixed(1)}M`;
  }

  if (absolute >= 1_000) {
    return `${sign}$${(absolute / 1_000).toFixed(1)}K`;
  }

  if (absolute >= 100) {
    return `${sign}$${absolute.toFixed(0)}`;
  }

  return `${sign}$${absolute.toFixed(2)}`;
}

function dayLabelFromKey(dayKeyValue) {
  const dayDate = new Date(`${dayKeyValue}T00:00:00`);
  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
  }).format(dayDate);
}

function buildHistoryChartPoints(entries, limit = HISTORY_TREND_CHART_LIMIT) {
  const byDay = new Map();

  for (const entry of entries) {
    const key = dateKey(entry.timestamp);
    if (!byDay.has(key)) {
      byDay.set(key, {
        dayKey: key,
        gain: 0,
        spent: 0,
        net: 0,
      });
    }

    const amount = toNumber(entry.amountUSD, 0);
    const bucket = byDay.get(key);
    if (amount >= 0) {
      bucket.gain += amount;
    } else {
      bucket.spent += amount * -1;
    }
    bucket.net += amount;
  }

  const points = Array.from(byDay.values())
    .sort((a, b) => a.dayKey.localeCompare(b.dayKey))
    .slice(-Math.max(1, limit))
    .map((point) => ({
      ...point,
      label: dayLabelFromKey(point.dayKey),
    }));

  return points;
}

function renderHistoryTrendChart(points) {
  if (points.length === 0) {
    return `<p class="muted">No data to chart yet for current filters.</p>`;
  }

  const width = 860;
  const height = 290;
  const paddingLeft = 46;
  const paddingRight = 16;
  const paddingTop = 14;
  const paddingBottom = 38;
  const plotWidth = width - paddingLeft - paddingRight;
  const plotHeight = height - paddingTop - paddingBottom;
  const centerY = paddingTop + plotHeight / 2;
  const amplitude = Math.max(18, plotHeight / 2 - 8);
  const slotWidth = plotWidth / points.length;
  const barWidth = Math.min(14, Math.max(4, slotWidth * 0.24));
  const labelEvery = Math.max(1, Math.ceil(points.length / 6));
  const maxAbs = Math.max(
    1,
    ...points.map((point) => Math.max(point.gain, point.spent, Math.abs(point.net)))
  );

  function yFor(value) {
    return centerY - (value / maxAbs) * amplitude;
  }

  const barsMarkup = points
    .map((point, index) => {
      const xCenter = paddingLeft + slotWidth * (index + 0.5);
      const gainY = yFor(point.gain);
      const gainHeight = Math.max(0, centerY - gainY);
      const spentY = yFor(point.spent * -1);
      const spentHeight = Math.max(0, spentY - centerY);

      return `
        <g>
          <title>${escapeHtml(
            `${point.label}: Gain ${formatCurrency(point.gain)}, Spent ${formatCurrency(
              point.spent
            )}, Net ${formatCurrency(point.net)}`
          )}</title>
          ${
            gainHeight > 0.35
              ? `<rect x="${(xCenter - barWidth - 1).toFixed(2)}" y="${gainY.toFixed(2)}" width="${barWidth.toFixed(
                  2
                )}" height="${gainHeight.toFixed(2)}" fill="${CHART_COLORS.gain}" rx="2"></rect>`
              : ""
          }
          ${
            spentHeight > 0.35
              ? `<rect x="${(xCenter + 1).toFixed(2)}" y="${centerY.toFixed(2)}" width="${barWidth.toFixed(
                  2
                )}" height="${spentHeight.toFixed(2)}" fill="${CHART_COLORS.spent}" rx="2"></rect>`
              : ""
          }
        </g>
      `;
    })
    .join("");

  const linePoints = points.map((point, index) => {
    const xCenter = paddingLeft + slotWidth * (index + 0.5);
    return {
      x: xCenter,
      y: yFor(point.net),
      point,
      index,
    };
  });

  const netPath = linePoints
    .map((point, index) => `${index === 0 ? "M" : "L"} ${point.x.toFixed(2)} ${point.y.toFixed(2)}`)
    .join(" ");

  const netDots = linePoints
    .map(
      (point) => `
        <circle cx="${point.x.toFixed(2)}" cy="${point.y.toFixed(2)}" r="3.2" fill="${CHART_COLORS.net}">
          <title>${escapeHtml(`${point.point.label}: Net ${formatCurrency(point.point.net)}`)}</title>
        </circle>
      `
    )
    .join("");

  const xLabels = linePoints
    .map((point) => {
      if (point.index % labelEvery !== 0 && point.index !== linePoints.length - 1) {
        return "";
      }
      return `<text x="${point.x.toFixed(2)}" y="${(height - 10).toFixed(
        2
      )}" class="chart-axis-label" text-anchor="middle">${escapeHtml(point.point.label)}</text>`;
    })
    .join("");

  return `
    <div class="chart-shell">
      <svg class="combo-chart" viewBox="0 0 ${width} ${height}" preserveAspectRatio="none" role="img" aria-label="Daily gain, spent, and net chart">
        <line x1="${paddingLeft}" y1="${(centerY - amplitude).toFixed(2)}" x2="${(width - paddingRight).toFixed(
          2
        )}" y2="${(centerY - amplitude).toFixed(2)}" stroke="${CHART_COLORS.grid}" stroke-dasharray="4 4" />
        <line x1="${paddingLeft}" y1="${centerY.toFixed(2)}" x2="${(width - paddingRight).toFixed(
          2
        )}" y2="${centerY.toFixed(2)}" stroke="${CHART_COLORS.axis}" />
        <line x1="${paddingLeft}" y1="${(centerY + amplitude).toFixed(2)}" x2="${(width - paddingRight).toFixed(
          2
        )}" y2="${(centerY + amplitude).toFixed(2)}" stroke="${CHART_COLORS.grid}" stroke-dasharray="4 4" />

        <text x="4" y="${(centerY - amplitude + 4).toFixed(2)}" class="chart-axis-label">${escapeHtml(
    compactCurrency(maxAbs)
  )}</text>
        <text x="4" y="${(centerY + 4).toFixed(2)}" class="chart-axis-label">$0</text>
        <text x="4" y="${(centerY + amplitude + 4).toFixed(2)}" class="chart-axis-label">${escapeHtml(
    compactCurrency(maxAbs * -1)
  )}</text>

        ${barsMarkup}

        <path d="${netPath}" fill="none" stroke="${CHART_COLORS.net}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" />
        ${netDots}
        ${xLabels}
      </svg>

      <div class="chart-legend">
        <span class="legend-item"><span class="legend-dot gain"></span>Gain</span>
        <span class="legend-item"><span class="legend-dot spent"></span>Spent</span>
        <span class="legend-item"><span class="legend-dot net"></span>Net</span>
      </div>
    </div>
  `;
}

function buildCategoryBreakdown(entries, categoriesById) {
  const grindMap = new Map();
  const chillMap = new Map();

  for (const entry of entries) {
    const category = categoriesById.get(entry.categoryId);
    if (!category) {
      continue;
    }

    const type = normalizeCategoryType(category.type);
    const signedAmount = toNumber(entry.amountUSD, 0);
    const amount = type === "goodHabit" ? Math.max(0, signedAmount) : Math.abs(signedAmount);
    if (amount <= 0) {
      continue;
    }

    const targetMap = type === "goodHabit" ? grindMap : chillMap;
    const existing = targetMap.get(category.id) || {
      categoryId: category.id,
      title: category.title,
      emoji: categoryEmoji(category),
      type,
      totalAmount: 0,
      entryCount: 0,
    };

    existing.totalAmount += amount;
    existing.entryCount += 1;
    targetMap.set(category.id, existing);
  }

  const grind = Array.from(grindMap.values()).sort((a, b) => b.totalAmount - a.totalAmount);
  const chill = Array.from(chillMap.values()).sort((a, b) => b.totalAmount - a.totalAmount);

  return {
    grind: {
      slices: grind,
      totalAmount: grind.reduce((sum, item) => sum + item.totalAmount, 0),
    },
    chill: {
      slices: chill,
      totalAmount: chill.reduce((sum, item) => sum + item.totalAmount, 0),
    },
  };
}

function addSliceColors(slices, palette, totalAmount) {
  return slices.map((slice, index) => {
    const percentage = totalAmount > 0 ? (slice.totalAmount / totalAmount) * 100 : 0;
    return {
      ...slice,
      color: palette[index % palette.length],
      percentage,
    };
  });
}

function donutGradient(slices) {
  if (!slices.length) {
    return "conic-gradient(#dfe8ed 0 100%)";
  }

  let cursor = 0;
  const segments = [];
  for (const slice of slices) {
    const next = cursor + slice.percentage;
    segments.push(`${slice.color} ${cursor.toFixed(2)}% ${next.toFixed(2)}%`);
    cursor = next;
  }

  if (cursor < 100) {
    segments.push(`#dfe8ed ${cursor.toFixed(2)}% 100%`);
  }

  return `conic-gradient(${segments.join(", ")})`;
}

function renderDonutCard({ title, tone, slices, totalAmount }) {
  const rows = slices
    .slice(0, 5)
    .map(
      (slice) => `
        <li class="slice-row">
          <span class="slice-meta">
            <span class="slice-swatch" style="background:${slice.color}"></span>
            ${renderCategoryTitle(
              {
                title: slice.title,
                emoji: slice.emoji,
                type: slice.type,
              },
              false
            )}
          </span>
          <span class="slice-amount ${tone === "grind" ? "positive" : "negative"}">
            ${formatCurrency(slice.totalAmount)}
            <small>(${slice.entryCount})</small>
          </span>
        </li>
      `
    )
    .join("");

  return `
    <article class="donut-card">
      <div class="donut-head">
        <h4>${escapeHtml(title)}</h4>
        <p class="${tone === "grind" ? "positive" : "negative"}">${formatCurrency(totalAmount)}</p>
      </div>

      <div class="donut-visual" style="background:${donutGradient(slices)}">
        <div class="donut-hole">
          <span>${escapeHtml(title)}</span>
          <strong>${formatCurrency(totalAmount)}</strong>
        </div>
      </div>

      <ul class="slice-list">${rows}</ul>
      ${slices.length > 5 ? `<p class="muted">+${slices.length - 5} more categories</p>` : ""}
    </article>
  `;
}

function renderHistoryCharts(entries, categoriesById) {
  const points = buildHistoryChartPoints(entries);
  const breakdown = buildCategoryBreakdown(entries, categoriesById);
  const grindSlices = addSliceColors(
    breakdown.grind.slices,
    GRIND_PIE_COLORS,
    breakdown.grind.totalAmount
  );
  const chillSlices = addSliceColors(
    breakdown.chill.slices,
    CHILL_PIE_COLORS,
    breakdown.chill.totalAmount
  );
  const hasBreakdown = grindSlices.length > 0 || chillSlices.length > 0;

  return `
    <article class="panel">
      <h2>Charts</h2>

      <div class="stack">
        <section>
          <h3 class="subheading">Daily Ledger Trend</h3>
          ${renderHistoryTrendChart(points)}
        </section>

        <section>
          <h3 class="subheading">Category Breakdown (Money)</h3>
          ${hasBreakdown
            ? `
              <div class="chart-donut-grid">
                ${grindSlices.length
                  ? renderDonutCard({
                      title: "Grind",
                      tone: "grind",
                      slices: grindSlices,
                      totalAmount: breakdown.grind.totalAmount,
                    })
                  : ""}
                ${chillSlices.length
                  ? renderDonutCard({
                      title: "Chill",
                      tone: "chill",
                      slices: chillSlices,
                      totalAmount: breakdown.chill.totalAmount,
                    })
                  : ""}
              </div>
            `
            : `<p class="muted">No category money data for current filters.</p>`}
        </section>
      </div>
    </article>
  `;
}

function renderHistory(state) {
  const categoriesById = new Map(state.categories.map((category) => [category.id, category]));
  const entries = filterHistoryEntries(state);
  const queryLabel = uiState.historyQuery.trim();

  return `
    <section class="stack">
      <article class="panel">
        <h2>History</h2>
        <div class="stack">
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

          <div class="history-filter-grid">
            <label class="field">
              <span>Category</span>
              <select id="history-category-filter">
                <option value="all" ${uiState.historyCategoryId === "all" ? "selected" : ""}>All Categories</option>
                ${state.categories
                  .map(
                    (category) => `
                      <option value="${category.id}" ${uiState.historyCategoryId === category.id ? "selected" : ""}>
                        ${escapeHtml(categoryDisplayText(category))}
                      </option>
                    `
                  )
                  .join("")}
              </select>
            </label>

            <label class="field">
              <span>Type</span>
              <select id="history-type-filter">
                <option value="all" ${uiState.historyType === "all" ? "selected" : ""}>All</option>
                <option value="goodHabit" ${uiState.historyType === "goodHabit" ? "selected" : ""}>Grind</option>
                <option value="quitHabit" ${uiState.historyType === "quitHabit" ? "selected" : ""}>Chill</option>
              </select>
            </label>

            <label class="field">
              <span>Search note/title</span>
              <input
                id="history-search"
                type="text"
                maxlength="80"
                value="${escapeHtml(uiState.historyQuery)}"
                placeholder="Try: reading, game, coffee..."
              />
            </label>
          </div>

          <p class="muted">
            Showing ${entries.length} entr${entries.length === 1 ? "y" : "ies"}${queryLabel ? ` matching "${escapeHtml(queryLabel)}"` : ""}.
          </p>
        </div>
      </article>

      ${renderHistoryCharts(entries, categoriesById)}

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
                        <p>${renderCategoryTitle(category)} · ${formatCurrency(entry.amountUSD)}</p>
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
  const restorePoints = Array.isArray(state.restorePoints) ? state.restorePoints : [];
  const lastBackupAt = state.settings?.lastFullBackupAt || null;

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
        <p class="muted">
          ${lastBackupAt ? `Last full backup: ${escapeHtml(formatDateTime(lastBackupAt))}.` : "No full backup exported yet."}
        </p>
        <div class="actions">
          <button type="button" class="button" data-action="settings-export-backup">Export Full Backup</button>
          <label class="button">
            Import Full Backup
            <input
              type="file"
              id="settings-import-backup-input"
              accept="application/json,.json,text/plain"
              hidden
            />
          </label>
          <button type="button" class="button" data-action="settings-clear-session">Clear Active Session</button>
          <button type="button" class="button danger" data-action="settings-reset-all">Reset All Data</button>
        </div>
        <p class="muted">Full backup includes settings, categories, entries, badges, and active session state.</p>
      </article>

      <article class="panel">
        <h2>Restore Points</h2>
        <p class="muted">Auto-saved before delete/reset/import actions. Keeps the latest 3 snapshots.</p>
        ${restorePoints.length === 0
          ? `<p class="muted">No restore points yet.</p>`
          : `
            <ul class="list restore-list">
              ${restorePoints
                .map(
                  (point) => `
                    <li>
                      <div>
                        <p><strong>${escapeHtml(point.reason || "Restore point")}</strong></p>
                        <p class="muted">${escapeHtml(formatDateTime(point.createdAt))} · ${escapeHtml(point.summary || "")}</p>
                      </div>
                      <div class="actions">
                        <button type="button" class="button" data-action="restore-point-apply" data-id="${point.id}">Restore</button>
                        <button type="button" class="button danger" data-action="restore-point-delete" data-id="${point.id}">Delete</button>
                      </div>
                    </li>
                  `
                )
                .join("")}
            </ul>
          `}
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

async function exportFullBackupNow() {
  await store.markFullBackupExported();
  const payload = store.exportFullBackup();
  const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-");
  triggerDownload(`grind-n-chill-full-backup-${stamp}.json`, JSON.stringify(payload, null, 2));
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

  if (action === "manual-quick-add") {
    const quantityInput = document.querySelector("#manual-quantity");
    const delta = toNumber(actionButton.dataset.delta, 0);
    if (!(quantityInput instanceof HTMLInputElement) || delta <= 0) {
      return;
    }

    const current = toNumber(quantityInput.value, 0);
    const next = Math.max(0, Math.round((current + delta) * 100) / 100);
    quantityInput.value = String(next);
    quantityInput.focus();
    return;
  }

  if (action === "backup-reminder-export") {
    await exportFullBackupNow();
    setFlash("success", "Full backup exported.");
    return;
  }

  if (action === "backup-reminder-dismiss") {
    await store.dismissBackupReminder();
    setFlash("success", "Backup reminder dismissed until tomorrow.");
    return;
  }

  if (action === "category-show-new") {
    uiState.editingCategoryId = null;
    uiState.showNewCategoryForm = true;
    render();
    return;
  }

  if (action === "category-hide-new") {
    uiState.showNewCategoryForm = false;
    render();
    return;
  }

  if (action === "category-emoji-pick") {
    const selectedEmoji = String(actionButton.dataset.emoji || "").trim();
    const form = document.querySelector("#category-form");
    const emojiInput = form?.querySelector('input[name="emoji"]');

    if (selectedEmoji && emojiInput instanceof HTMLInputElement) {
      emojiInput.value = selectedEmoji;

      for (const chip of form.querySelectorAll(".emoji-chip")) {
        chip.classList.remove("is-active");
      }
      actionButton.classList.add("is-active");
    }
    return;
  }

  if (action === "category-edit" && id) {
    uiState.showNewCategoryForm = false;
    uiState.editingCategoryId = id;
    render();
    return;
  }

  if (action === "category-cancel-edit") {
    uiState.editingCategoryId = null;
    uiState.showNewCategoryForm = false;
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

  if (action === "restore-point-apply" && id) {
    const confirmed = window.confirm("Restore this snapshot and replace current local data?");
    if (!confirmed) {
      return;
    }

    const result = await store.restoreFromPoint(id);
    if (!result.ok) {
      setFlash("error", result.error);
      return;
    }

    uiState.editingCategoryId = null;
    uiState.showNewCategoryForm = false;
    uiState.sessionNote = "";
    setFlash(
      "success",
      `Restore complete. categories=${result.report.categories}, entries=${result.report.entries}, badges=${result.report.badges}.`
    );
    return;
  }

  if (action === "restore-point-delete" && id) {
    const result = await store.deleteRestorePoint(id);
    if (!result.ok) {
      setFlash("error", result.error);
      return;
    }
    setFlash("success", "Restore point deleted.");
    return;
  }

  if (action === "settings-clear-session") {
    await store.clearActiveSession();
    uiState.sessionNote = "";
    setFlash("success", "Active session cleared.");
    return;
  }

  if (action === "settings-export-backup") {
    await exportFullBackupNow();
    setFlash("success", "Full backup exported.");
    return;
  }

  if (action === "settings-reset-all") {
    const confirmed = window.confirm("Reset all data? This cannot be undone.");
    if (!confirmed) {
      return;
    }

    await store.resetAllData();
    uiState.editingCategoryId = null;
    uiState.showNewCategoryForm = false;
    uiState.manualOnly = false;
    uiState.historyCategoryId = "all";
    uiState.historyType = "all";
    uiState.historyQuery = "";
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
      emoji: data.get("emoji"),
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
    uiState.showNewCategoryForm = false;
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

  if (target.matches('#category-form select[name="type"]')) {
    const form = target.closest("#category-form");
    const emojiInput = form?.querySelector('input[name="emoji"]');
    if (emojiInput instanceof HTMLInputElement && !emojiInput.value.trim()) {
      const nextType = normalizeCategoryType(target.value);
      emojiInput.value = CATEGORY_DEFAULT_EMOJI[nextType];
    }
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

  if (target.id === "history-category-filter") {
    uiState.historyCategoryId = target.value || "all";
    render();
    return;
  }

  if (target.id === "history-type-filter") {
    uiState.historyType = target.value || "all";
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

  if (target.id === "settings-import-backup-input") {
    const file = target.files?.[0];
    if (!file) {
      return;
    }

    try {
      const content = await file.text();
      const payload = JSON.parse(content);

      const confirmed = window.confirm(
        "Restore this full backup and replace current local data on this device?"
      );
      if (!confirmed) {
        target.value = "";
        return;
      }

      const result = await store.importFullBackup(payload);
      if (!result.ok) {
        setFlash("error", result.error);
        return;
      }

      uiState.editingCategoryId = null;
      uiState.showNewCategoryForm = false;
      uiState.manualOnly = false;
      uiState.historyCategoryId = "all";
      uiState.historyType = "all";
      uiState.historyQuery = "";
      uiState.sessionNote = "";

      const report = result.report;
      const sessionNote = report.hasActiveSession ? " active session restored." : " no active session.";
      setFlash(
        "success",
        `Backup restored. categories=${report.categories}, entries=${report.entries}, badges=${report.badges},${sessionNote}`
      );
    } catch (error) {
      setFlash("error", `Backup restore failed: ${error instanceof Error ? error.message : "Unknown error"}`);
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
    return;
  }

  if (target.id === "history-search") {
    uiState.historyQuery = target.value || "";
    render();
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
