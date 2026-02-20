import { amountUSDForCategory, dailyLedgerSummary, totalBalance } from "./ledger.js";
import { createDefaultState, normalizeState } from "./schema.js";
import {
  badgeLabelFromAward,
  cadencePeriodKey,
  cadenceShortSuffix,
  resolveCadence,
  resolveMilestones,
  streakHighlight,
  streakRiskAlerts,
  streakForCategory,
} from "./streaks.js";
import {
  dateKey,
  deepClone,
  round2,
  startOfDayTimestamp,
  toISOString,
  toInt,
  toNumber,
  uuid,
} from "./utils.js";

const UNIT_VALUES = new Set(["time", "count", "money"]);

function categoryKey(title, type, unit) {
  return `${String(title).trim().toLowerCase()}|${type}|${unit}`;
}

function numberString(value) {
  const rounded = round2(value);
  if (Number.isInteger(rounded)) {
    return String(rounded);
  }
  return String(rounded);
}

function normalizeType(rawType) {
  return rawType === "quitHabit" ? "quitHabit" : "goodHabit";
}

function normalizeUnit(rawUnit) {
  return UNIT_VALUES.has(rawUnit) ? rawUnit : "time";
}

function normalizeMode(rawMode) {
  return rawMode === "hourlyRate" ? "hourlyRate" : "multiplier";
}

function asBool(value, fallback = false) {
  if (typeof value === "boolean") {
    return value;
  }
  if (value === "true" || value === "1" || value === "on") {
    return true;
  }
  if (value === "false" || value === "0") {
    return false;
  }
  return fallback;
}

function compareEntriesDesc(a, b) {
  const dateDiff = new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime();
  if (dateDiff !== 0) {
    return dateDiff;
  }
  return String(b.id).localeCompare(String(a.id));
}

function compareAwardsDesc(a, b) {
  const timeDiff = new Date(b.dateAwarded).getTime() - new Date(a.dateAwarded).getTime();
  if (timeDiff !== 0) {
    return timeDiff;
  }
  return String(b.awardKey).localeCompare(String(a.awardKey));
}

function normalizeCategoryPatchInput(input, fallback) {
  const streakEnabled = asBool(input?.streakEnabled, fallback?.streakEnabled ?? true);
  const badgeEnabledRaw = asBool(input?.badgeEnabled, fallback?.badgeEnabled ?? true);
  const badgeEnabled = streakEnabled ? badgeEnabledRaw : false;

  return {
    title: String(input?.title ?? fallback?.title ?? "").trim(),
    type: normalizeType(input?.type ?? fallback?.type),
    unit: normalizeUnit(input?.unit ?? fallback?.unit),
    timeConversionMode: normalizeMode(input?.timeConversionMode ?? fallback?.timeConversionMode),
    multiplier: Math.max(0.01, toNumber(input?.multiplier ?? fallback?.multiplier, 1)),
    hourlyRateUSD: Math.max(
      0.01,
      toNumber(input?.hourlyRateUSD ?? fallback?.hourlyRateUSD, fallback?.hourlyRateUSD ?? 18)
    ),
    usdPerCount: Math.max(0.01, toNumber(input?.usdPerCount ?? fallback?.usdPerCount, 1)),
    dailyGoalValue: Math.max(0, toInt(input?.dailyGoalValue ?? fallback?.dailyGoalValue, 0)),
    streakEnabled,
    streakCadence: resolveCadence(input?.streakCadence ?? fallback?.streakCadence),
    badgeEnabled,
    badgeMilestones: resolveMilestones(input?.badgeMilestonesInput ?? input?.badgeMilestones ?? fallback?.badgeMilestones),
  };
}

export class AppStore {
  constructor(adapter) {
    this.adapter = adapter;
    this.state = createDefaultState();
    this.listeners = new Set();
  }

  async init() {
    const loaded = await this.adapter.read();
    this.state = normalizeState(loaded);
    this._emit();
    return this.snapshot();
  }

  subscribe(listener) {
    this.listeners.add(listener);
    listener(this.snapshot());
    return () => {
      this.listeners.delete(listener);
    };
  }

  snapshot() {
    return deepClone(this.state);
  }

  async setUsdPerHour(value) {
    const normalized = Math.max(0.01, toNumber(value, this.state.settings.usdPerHour));
    this.state.settings.usdPerHour = round2(normalized);
    await this._persistAndEmit();
    return this.state.settings.usdPerHour;
  }

  async createCategory(input) {
    const normalized = normalizeCategoryPatchInput(input, {
      title: "",
      type: "goodHabit",
      unit: "time",
      timeConversionMode: "multiplier",
      multiplier: 1,
      hourlyRateUSD: this.state.settings.usdPerHour,
      usdPerCount: 1,
      dailyGoalValue: 0,
      streakEnabled: true,
      streakCadence: "daily",
      badgeEnabled: true,
      badgeMilestones: [3, 7, 30],
    });

    if (!normalized.title) {
      return { ok: false, error: "Category title is required." };
    }

    const nowISO = toISOString();

    const category = {
      id: uuid(),
      title: normalized.title,
      type: normalized.type,
      unit: normalized.unit,
      multiplier: normalized.unit === "time" ? normalized.multiplier : 1,
      timeConversionMode: normalized.unit === "time" ? normalized.timeConversionMode : "multiplier",
      hourlyRateUSD:
        normalized.unit === "time" && normalized.timeConversionMode === "hourlyRate"
          ? normalized.hourlyRateUSD
          : null,
      usdPerCount: normalized.unit === "count" ? normalized.usdPerCount : null,
      dailyGoalValue: normalized.dailyGoalValue,
      streakEnabled: normalized.streakEnabled,
      streakCadence: normalized.streakCadence,
      badgeEnabled: normalized.badgeEnabled,
      badgeMilestones: normalized.badgeMilestones,
      createdAt: nowISO,
      updatedAt: nowISO,
    };

    this.state.categories.push(category);
    this.state.categories.sort((a, b) => a.title.localeCompare(b.title));

    await this._persistAndEmit();
    return { ok: true, category: deepClone(category) };
  }

  async updateCategory(categoryId, patch) {
    const category = this.state.categories.find((item) => item.id === categoryId);
    if (!category) {
      return { ok: false, error: "Category not found." };
    }

    const normalized = normalizeCategoryPatchInput(patch, category);

    if (!normalized.title) {
      return { ok: false, error: "Category title is required." };
    }

    category.title = normalized.title;
    category.type = normalized.type;
    category.unit = normalized.unit;
    category.multiplier = normalized.unit === "time" ? normalized.multiplier : 1;
    category.timeConversionMode = normalized.unit === "time" ? normalized.timeConversionMode : "multiplier";
    category.hourlyRateUSD =
      normalized.unit === "time" && normalized.timeConversionMode === "hourlyRate"
        ? normalized.hourlyRateUSD
        : null;
    category.usdPerCount = normalized.unit === "count" ? normalized.usdPerCount : null;
    category.dailyGoalValue = normalized.dailyGoalValue;
    category.streakEnabled = normalized.streakEnabled;
    category.streakCadence = normalized.streakCadence;
    category.badgeEnabled = normalized.badgeEnabled;
    category.badgeMilestones = normalized.badgeMilestones;
    category.updatedAt = toISOString();

    this.state.categories.sort((a, b) => a.title.localeCompare(b.title));

    await this._persistAndEmit();
    return { ok: true, category: deepClone(category) };
  }

  async deleteCategory(categoryId) {
    const beforeCount = this.state.categories.length;
    this.state.categories = this.state.categories.filter((category) => category.id !== categoryId);
    if (this.state.categories.length === beforeCount) {
      return { ok: false, error: "Category not found." };
    }

    this.state.entries = this.state.entries.filter((entry) => entry.categoryId !== categoryId);
    this.state.badgeAwards = this.state.badgeAwards.filter((award) => award.categoryId !== categoryId);

    if (this.state.activeSession?.categoryId === categoryId) {
      this.state.activeSession = null;
    }

    await this._persistAndEmit();
    return { ok: true };
  }

  async addManualEntry(input) {
    const category = this.state.categories.find((item) => item.id === input?.categoryId);
    if (!category) {
      return { ok: false, error: "Pick a valid category first." };
    }

    const unit = category.unit;
    const rawQuantity = toNumber(input?.quantity, 0);

    if (rawQuantity <= 0) {
      return { ok: false, error: "Quantity must be greater than zero." };
    }

    if (unit === "time" && (rawQuantity < 1 || rawQuantity > 600)) {
      return { ok: false, error: "Time entries must be between 1 and 600 minutes." };
    }

    if (unit === "count" && (rawQuantity < 1 || rawQuantity > 500)) {
      return { ok: false, error: "Count entries must be between 1 and 500." };
    }

    const quantity = round2(rawQuantity);
    const timestamp = input?.timestamp ? toISOString(input.timestamp) : toISOString();
    const amountUSD = amountUSDForCategory({
      category,
      quantity,
      usdPerHour: this.state.settings.usdPerHour,
    });

    const entry = {
      id: uuid(),
      timestamp,
      categoryId: category.id,
      durationMinutes: unit === "time" ? Math.max(1, Math.round(quantity)) : 0,
      quantity,
      unit,
      amountUSD,
      note: String(input?.note || "").trim(),
      bonusKey: null,
      isManual: true,
      createdAt: toISOString(),
      updatedAt: toISOString(),
    };

    this.state.entries.push(entry);
    this.state.entries.sort(compareEntriesDesc);

    const newAwards = this._awardBadgesIfNeededForCategory(category, timestamp);

    await this._persistAndEmit();
    return { ok: true, entry: deepClone(entry), newAwards };
  }

  async deleteEntry(entryId) {
    const beforeCount = this.state.entries.length;
    this.state.entries = this.state.entries.filter((entry) => entry.id !== entryId);
    if (this.state.entries.length === beforeCount) {
      return { ok: false, error: "Entry not found." };
    }

    await this._persistAndEmit();
    return { ok: true };
  }

  async startSession(categoryId, now = Date.now()) {
    if (this.state.activeSession) {
      return { ok: false, error: "A session is already running." };
    }

    const category = this.state.categories.find((item) => item.id === categoryId);
    if (!category) {
      return { ok: false, error: "Pick a valid category before starting." };
    }

    if (category.unit !== "time") {
      return { ok: false, error: "Live timer is only available for Time categories." };
    }

    const nowISO = toISOString(now);

    this.state.activeSession = {
      categoryId,
      startTime: nowISO,
      isPaused: false,
      accumulatedElapsedSeconds: 0,
      runningSegmentStartTime: nowISO,
    };

    await this._persistAndEmit();
    return { ok: true };
  }

  getElapsedSeconds(now = Date.now()) {
    const session = this.state.activeSession;
    if (!session) {
      return 0;
    }

    if (session.isPaused) {
      return Math.max(0, Math.floor(session.accumulatedElapsedSeconds));
    }

    const runningStartTime = session.runningSegmentStartTime || session.startTime;
    const segmentStartMs = new Date(runningStartTime).getTime();
    const segmentElapsed = Math.max(0, Math.floor((new Date(now).getTime() - segmentStartMs) / 1000));

    return Math.max(0, Math.floor(session.accumulatedElapsedSeconds) + segmentElapsed);
  }

  async pauseSession(now = Date.now()) {
    const session = this.state.activeSession;
    if (!session) {
      return { ok: false, error: "No running session to pause." };
    }

    if (session.isPaused) {
      return { ok: false, error: "Session is already paused." };
    }

    session.accumulatedElapsedSeconds = this.getElapsedSeconds(now);
    session.isPaused = true;
    session.runningSegmentStartTime = null;

    await this._persistAndEmit();
    return { ok: true };
  }

  async resumeSession(now = Date.now()) {
    const session = this.state.activeSession;
    if (!session) {
      return { ok: false, error: "No paused session to resume." };
    }

    if (!session.isPaused) {
      return { ok: false, error: "Session is already running." };
    }

    session.isPaused = false;
    session.runningSegmentStartTime = toISOString(now);

    await this._persistAndEmit();
    return { ok: true };
  }

  async stopSessionAndSave(input = {}) {
    const session = this.state.activeSession;
    if (!session) {
      return { ok: false, error: "No running session to stop." };
    }

    const category = this.state.categories.find((item) => item.id === session.categoryId);
    if (!category || category.unit !== "time") {
      this.state.activeSession = null;
      await this._persistAndEmit();
      return { ok: false, error: "Active session category is missing or invalid." };
    }

    const now = input.now || Date.now();
    const elapsedSeconds = this.getElapsedSeconds(now);
    const durationMinutes = Math.max(1, Math.round(elapsedSeconds / 60));

    const entry = {
      id: uuid(),
      timestamp: toISOString(now),
      categoryId: category.id,
      durationMinutes,
      quantity: durationMinutes,
      unit: "time",
      amountUSD: amountUSDForCategory({
        category,
        quantity: durationMinutes,
        usdPerHour: this.state.settings.usdPerHour,
      }),
      note: String(input.note || "").trim(),
      bonusKey: null,
      isManual: false,
      createdAt: toISOString(),
      updatedAt: toISOString(),
    };

    this.state.entries.push(entry);
    this.state.entries.sort(compareEntriesDesc);
    this.state.activeSession = null;

    const newAwards = this._awardBadgesIfNeededForCategory(category, now);

    await this._persistAndEmit();
    return { ok: true, entry: deepClone(entry), newAwards };
  }

  async clearActiveSession() {
    this.state.activeSession = null;
    await this._persistAndEmit();
    return { ok: true };
  }

  async resetAllData() {
    this.state = createDefaultState();
    await this._persistAndEmit();
    return { ok: true };
  }

  computeDashboard(now = Date.now()) {
    const entries = this.state.entries;
    const categories = this.state.categories;
    const today = dailyLedgerSummary(entries, startOfDayTimestamp(now));

    const activeSession = this.state.activeSession
      ? {
          ...this.state.activeSession,
          elapsedSeconds: this.getElapsedSeconds(now),
          category: categories.find((category) => category.id === this.state.activeSession.categoryId) || null,
        }
      : null;

    const highlight = streakHighlight(categories, entries, now);
    const alerts = streakRiskAlerts(categories, entries, now);

    const latestBadges = [...this.state.badgeAwards]
      .sort(compareAwardsDesc)
      .slice(0, 5)
      .map((award) => ({
        ...award,
        label: badgeLabelFromAward(award),
      }));

    return {
      balanceUSD: totalBalance(entries),
      today,
      activeSession,
      totalEntries: entries.length,
      totalCategories: categories.length,
      streakHighlight: highlight
        ? {
            ...highlight,
            shortSuffix: cadenceShortSuffix(highlight.cadence),
          }
        : null,
      streakRiskAlerts: alerts,
      latestBadges,
    };
  }

  getEntriesFiltered({ manualOnly = false } = {}) {
    const entries = manualOnly ? this.state.entries.filter((entry) => entry.isManual) : [...this.state.entries];
    return entries.sort(compareEntriesDesc);
  }

  exportHistoryPayload(options = {}) {
    const manualOnlyFilter = Boolean(options.manualOnlyFilter);
    const dateRangeFilter = options.dateRangeFilter || "all";

    const categoriesById = new Map(this.state.categories.map((category) => [category.id, category]));
    const entries = this.getEntriesFiltered({ manualOnly: manualOnlyFilter });

    const exportEntries = entries
      .map((entry) => {
        const category = categoriesById.get(entry.categoryId);
        if (!category) {
          return null;
        }

        return {
          id: entry.id,
          timestamp: new Date(entry.timestamp).toISOString(),
          categoryTitle: category.title,
          categoryType: category.type,
          unit: entry.unit,
          quantity: numberString(entry.quantity),
          durationMinutes: Math.max(0, Math.round(entry.durationMinutes || 0)),
          amountUSD: numberString(entry.amountUSD),
          isManual: Boolean(entry.isManual),
          note: entry.note || "",
        };
      })
      .filter(Boolean);

    const byDate = new Map();

    for (const entry of exportEntries) {
      const key = dateKey(entry.timestamp);
      if (!byDate.has(key)) {
        byDate.set(key, {
          date: key,
          ledgerChangeUSD: 0,
          gainUSD: 0,
          spentUSD: 0,
          entryCount: 0,
        });
      }

      const target = byDate.get(key);
      const amount = toNumber(entry.amountUSD, 0);
      target.ledgerChangeUSD = round2(target.ledgerChangeUSD + amount);
      if (amount >= 0) {
        target.gainUSD = round2(target.gainUSD + amount);
      } else {
        target.spentUSD = round2(target.spentUSD + amount * -1);
      }
      target.entryCount += 1;
    }

    const dailySummaries = Array.from(byDate.values())
      .sort((a, b) => b.date.localeCompare(a.date))
      .map((summary) => ({
        ...summary,
        ledgerChangeUSD: numberString(summary.ledgerChangeUSD),
        gainUSD: numberString(summary.gainUSD),
        spentUSD: numberString(summary.spentUSD),
      }));

    return {
      exportedAt: toISOString(),
      manualOnlyFilter,
      dateRangeFilter,
      dailySummaries,
      entries: exportEntries,
    };
  }

  async importHistoryPayload(payload, options = {}) {
    const entries = Array.isArray(payload?.entries) ? payload.entries : null;
    if (!entries) {
      return { ok: false, error: "Invalid import file. Expected an entries array." };
    }

    const conflictPolicy = options.conflictPolicy === "keepExisting" ? "keepExisting" : "replaceExisting";

    const categoriesByKey = new Map(
      this.state.categories.map((category) => [categoryKey(category.title, category.type, category.unit), category])
    );

    const entriesById = new Map(this.state.entries.map((entry) => [entry.id, entry]));

    let createdEntries = 0;
    let updatedEntries = 0;
    let skippedEntries = 0;
    let createdCategories = 0;

    for (const item of entries) {
      const entryID = String(item?.id || "").trim();
      const categoryTitle = String(item?.categoryTitle || "").trim();
      const categoryType = normalizeType(item?.categoryType);
      const unit = normalizeUnit(item?.unit);

      if (!entryID || !categoryTitle) {
        skippedEntries += 1;
        continue;
      }

      const timestamp = item?.timestamp ? toISOString(item.timestamp) : toISOString();
      const quantity = Math.max(0, toNumber(item?.quantity, 0));
      const durationMinutes = Math.max(0, toInt(item?.durationMinutes, unit === "time" ? Math.round(quantity) : 0));
      const amountUSD = round2(toNumber(item?.amountUSD, 0));

      const catKey = categoryKey(categoryTitle, categoryType, unit);
      let category = categoriesByKey.get(catKey);
      if (!category) {
        const nowISO = toISOString();
        category = {
          id: uuid(),
          title: categoryTitle,
          type: categoryType,
          unit,
          multiplier: 1,
          timeConversionMode: "multiplier",
          hourlyRateUSD: null,
          usdPerCount: unit === "count" ? 1 : null,
          dailyGoalValue: 0,
          streakEnabled: true,
          streakCadence: "daily",
          badgeEnabled: true,
          badgeMilestones: [3, 7, 30],
          createdAt: nowISO,
          updatedAt: nowISO,
        };
        this.state.categories.push(category);
        categoriesByKey.set(catKey, category);
        createdCategories += 1;
      }

      const existingEntry = entriesById.get(entryID);
      if (existingEntry && conflictPolicy === "keepExisting") {
        skippedEntries += 1;
        continue;
      }

      if (existingEntry) {
        existingEntry.timestamp = timestamp;
        existingEntry.categoryId = category.id;
        existingEntry.durationMinutes = durationMinutes;
        existingEntry.quantity = round2(quantity);
        existingEntry.unit = unit;
        existingEntry.amountUSD = amountUSD;
        existingEntry.note = String(item?.note || "").trim();
        existingEntry.bonusKey = null;
        existingEntry.isManual = Boolean(item?.isManual);
        existingEntry.updatedAt = toISOString();
        updatedEntries += 1;
      } else {
        const nowISO = toISOString();
        const created = {
          id: entryID,
          timestamp,
          categoryId: category.id,
          durationMinutes,
          quantity: round2(quantity),
          unit,
          amountUSD,
          note: String(item?.note || "").trim(),
          bonusKey: null,
          isManual: Boolean(item?.isManual),
          createdAt: nowISO,
          updatedAt: nowISO,
        };
        this.state.entries.push(created);
        entriesById.set(created.id, created);
        createdEntries += 1;
      }
    }

    this.state.categories.sort((a, b) => a.title.localeCompare(b.title));
    this.state.entries.sort(compareEntriesDesc);

    await this._persistAndEmit();

    return {
      ok: true,
      report: {
        processedEntries: entries.length,
        createdEntries,
        updatedEntries,
        skippedEntries,
        createdCategories,
      },
    };
  }

  _awardBadgesIfNeededForCategory(category, now = Date.now()) {
    if (!category || category.streakEnabled === false || category.badgeEnabled === false) {
      return [];
    }

    const milestones = resolveMilestones(category.badgeMilestones);
    if (milestones.length === 0) {
      return [];
    }

    const streakValue = streakForCategory(category, this.state.entries, now);
    if (streakValue <= 0) {
      return [];
    }

    const cadence = resolveCadence(category.streakCadence);
    const periodKey = cadencePeriodKey(cadence, now);

    const newAwards = [];

    for (const milestone of milestones) {
      if (streakValue < milestone) {
        continue;
      }

      const awardKey = `streak:${category.id}:${milestone}:${periodKey}`;
      if (this.state.badgeAwards.some((award) => award.awardKey === awardKey)) {
        continue;
      }

      const award = {
        id: uuid(),
        awardKey,
        dateAwarded: toISOString(now),
        categoryId: category.id,
        milestone,
        cadence,
      };

      this.state.badgeAwards.push(award);
      newAwards.push(award);
    }

    if (newAwards.length > 0) {
      this.state.badgeAwards.sort(compareAwardsDesc);
    }

    return newAwards;
  }

  _emit() {
    const snapshot = this.snapshot();
    for (const listener of this.listeners) {
      listener(snapshot);
    }
  }

  async _persistAndEmit() {
    await this.adapter.write(this.state);
    this._emit();
  }
}
