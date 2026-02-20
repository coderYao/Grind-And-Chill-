import { amountUSDForCategory, dailyLedgerSummary, totalBalance } from "./ledger.js";
import { createDefaultState, normalizeState } from "./schema.js";
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

function compareEntriesDesc(a, b) {
  const dateDiff = new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime();
  if (dateDiff !== 0) {
    return dateDiff;
  }
  return String(b.id).localeCompare(String(a.id));
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
    const title = String(input?.title || "").trim();
    if (!title) {
      return { ok: false, error: "Category title is required." };
    }

    const nowISO = toISOString();
    const type = normalizeType(input?.type);
    const unit = normalizeUnit(input?.unit);
    const mode = normalizeMode(input?.timeConversionMode);

    const category = {
      id: uuid(),
      title,
      type,
      unit,
      multiplier: unit === "time" ? Math.max(0.01, toNumber(input?.multiplier, 1)) : 1,
      timeConversionMode: unit === "time" ? mode : "multiplier",
      hourlyRateUSD:
        unit === "time" && mode === "hourlyRate"
          ? Math.max(0.01, toNumber(input?.hourlyRateUSD, this.state.settings.usdPerHour))
          : null,
      usdPerCount: unit === "count" ? Math.max(0.01, toNumber(input?.usdPerCount, 1)) : null,
      dailyGoalValue: Math.max(0, toInt(input?.dailyGoalValue, 0)),
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

    const title = String(patch?.title ?? category.title).trim();
    if (!title) {
      return { ok: false, error: "Category title is required." };
    }

    const type = normalizeType(patch?.type ?? category.type);
    const unit = normalizeUnit(patch?.unit ?? category.unit);
    const mode = normalizeMode(patch?.timeConversionMode ?? category.timeConversionMode);

    category.title = title;
    category.type = type;
    category.unit = unit;
    category.multiplier = unit === "time" ? Math.max(0.01, toNumber(patch?.multiplier ?? category.multiplier, 1)) : 1;
    category.timeConversionMode = unit === "time" ? mode : "multiplier";
    category.hourlyRateUSD =
      unit === "time" && mode === "hourlyRate"
        ? Math.max(
            0.01,
            toNumber(
              patch?.hourlyRateUSD ?? category.hourlyRateUSD ?? this.state.settings.usdPerHour,
              this.state.settings.usdPerHour
            )
          )
        : null;
    category.usdPerCount =
      unit === "count" ? Math.max(0.01, toNumber(patch?.usdPerCount ?? category.usdPerCount ?? 1, 1)) : null;
    category.dailyGoalValue = Math.max(0, toInt(patch?.dailyGoalValue ?? category.dailyGoalValue, 0));
    category.updatedAt = toISOString();

    // Keep historical entries intact, but update unit pointer for future entries.
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
      isManual: true,
      createdAt: toISOString(),
      updatedAt: toISOString(),
    };

    this.state.entries.push(entry);
    this.state.entries.sort(compareEntriesDesc);

    await this._persistAndEmit();
    return { ok: true, entry: deepClone(entry) };
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
      isManual: false,
      createdAt: toISOString(),
      updatedAt: toISOString(),
    };

    this.state.entries.push(entry);
    this.state.entries.sort(compareEntriesDesc);
    this.state.activeSession = null;

    await this._persistAndEmit();
    return { ok: true, entry: deepClone(entry) };
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

    return {
      balanceUSD: totalBalance(entries),
      today,
      activeSession,
      totalEntries: entries.length,
      totalCategories: categories.length,
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
      const durationMinutes = Math.max(
        0,
        toInt(item?.durationMinutes, unit === "time" ? Math.round(quantity) : 0)
      );
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
