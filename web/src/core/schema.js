import { resolveCadence, resolveMilestones } from "./streaks.js";
import { deepClone } from "./utils.js";

export const CURRENT_SCHEMA_VERSION = 2;

export const DEFAULT_STATE = {
  schemaVersion: CURRENT_SCHEMA_VERSION,
  settings: {
    usdPerHour: 18,
  },
  categories: [],
  entries: [],
  badgeAwards: [],
  activeSession: null,
};

export function createDefaultState() {
  return deepClone(DEFAULT_STATE);
}

function asBool(value, fallback = false) {
  if (typeof value === "boolean") {
    return value;
  }
  if (value === "true" || value === "1") {
    return true;
  }
  if (value === "false" || value === "0") {
    return false;
  }
  return fallback;
}

function normalizeCategory(rawCategory) {
  if (!rawCategory || typeof rawCategory !== "object") {
    return null;
  }

  const id = String(rawCategory.id || "").trim();
  const title = String(rawCategory.title || "").trim();

  if (!id || !title) {
    return null;
  }

  const type = rawCategory.type === "quitHabit" ? "quitHabit" : "goodHabit";
  const unit = ["time", "count", "money"].includes(rawCategory.unit) ? rawCategory.unit : "time";
  const timeConversionMode = rawCategory.timeConversionMode === "hourlyRate" ? "hourlyRate" : "multiplier";

  return {
    id,
    title,
    type,
    unit,
    multiplier: Number.isFinite(Number(rawCategory.multiplier)) ? Number(rawCategory.multiplier) : 1,
    timeConversionMode,
    hourlyRateUSD:
      rawCategory.hourlyRateUSD === null || rawCategory.hourlyRateUSD === undefined
        ? null
        : Number(rawCategory.hourlyRateUSD),
    usdPerCount:
      rawCategory.usdPerCount === null || rawCategory.usdPerCount === undefined
        ? null
        : Number(rawCategory.usdPerCount),
    dailyGoalValue: Number.isFinite(Number(rawCategory.dailyGoalValue)) ? Number(rawCategory.dailyGoalValue) : 0,
    streakEnabled: asBool(rawCategory.streakEnabled, true),
    streakCadence: resolveCadence(rawCategory.streakCadence),
    badgeEnabled: asBool(rawCategory.badgeEnabled, true),
    badgeMilestones: resolveMilestones(rawCategory.badgeMilestones),
    createdAt: rawCategory.createdAt || new Date().toISOString(),
    updatedAt: rawCategory.updatedAt || new Date().toISOString(),
  };
}

function normalizeEntry(rawEntry) {
  if (!rawEntry || typeof rawEntry !== "object") {
    return null;
  }

  const id = String(rawEntry.id || "").trim();
  const categoryId = String(rawEntry.categoryId || "").trim();

  if (!id || !categoryId) {
    return null;
  }

  return {
    id,
    timestamp: rawEntry.timestamp || new Date().toISOString(),
    categoryId,
    durationMinutes: Number.isFinite(Number(rawEntry.durationMinutes))
      ? Math.max(0, Number(rawEntry.durationMinutes))
      : 0,
    quantity: Number.isFinite(Number(rawEntry.quantity)) ? Math.max(0, Number(rawEntry.quantity)) : 0,
    unit: ["time", "count", "money"].includes(rawEntry.unit) ? rawEntry.unit : "time",
    amountUSD: Number.isFinite(Number(rawEntry.amountUSD)) ? Number(rawEntry.amountUSD) : 0,
    note: String(rawEntry.note || ""),
    bonusKey: rawEntry.bonusKey ? String(rawEntry.bonusKey) : null,
    isManual: Boolean(rawEntry.isManual),
    createdAt: rawEntry.createdAt || new Date().toISOString(),
    updatedAt: rawEntry.updatedAt || new Date().toISOString(),
  };
}

function normalizeBadgeAward(rawAward) {
  if (!rawAward || typeof rawAward !== "object") {
    return null;
  }

  const awardKey = String(rawAward.awardKey || "").trim();
  if (!awardKey) {
    return null;
  }

  const cadence = resolveCadence(rawAward.cadence);
  const milestone = Number.parseInt(String(rawAward.milestone || ""), 10);

  return {
    id: String(rawAward.id || `${awardKey}:${rawAward.dateAwarded || ""}`),
    awardKey,
    dateAwarded: rawAward.dateAwarded || new Date().toISOString(),
    categoryId: rawAward.categoryId ? String(rawAward.categoryId) : null,
    milestone: Number.isFinite(milestone) && milestone > 0 ? milestone : null,
    cadence,
  };
}

function normalizeSession(rawSession) {
  if (!rawSession || typeof rawSession !== "object") {
    return null;
  }

  const categoryId = String(rawSession.categoryId || "").trim();
  const startTime = rawSession.startTime || null;

  if (!categoryId || !startTime) {
    return null;
  }

  return {
    categoryId,
    startTime,
    isPaused: Boolean(rawSession.isPaused),
    accumulatedElapsedSeconds: Number.isFinite(Number(rawSession.accumulatedElapsedSeconds))
      ? Math.max(0, Number(rawSession.accumulatedElapsedSeconds))
      : 0,
    runningSegmentStartTime: rawSession.runningSegmentStartTime || null,
  };
}

export function normalizeState(rawState) {
  const base = createDefaultState();
  if (!rawState || typeof rawState !== "object") {
    return base;
  }

  const normalizedCategories = Array.isArray(rawState.categories)
    ? rawState.categories.map(normalizeCategory).filter(Boolean)
    : [];

  const categoryIdSet = new Set(normalizedCategories.map((category) => category.id));

  const normalizedEntries = Array.isArray(rawState.entries)
    ? rawState.entries
        .map(normalizeEntry)
        .filter((entry) => entry && categoryIdSet.has(entry.categoryId))
    : [];

  const normalizedSession = normalizeSession(rawState.activeSession);

  const normalizedAwards = Array.isArray(rawState.badgeAwards)
    ? rawState.badgeAwards
        .map(normalizeBadgeAward)
        .filter((award) => award && (!award.categoryId || categoryIdSet.has(award.categoryId)))
    : [];

  normalizedAwards.sort((a, b) => new Date(b.dateAwarded).getTime() - new Date(a.dateAwarded).getTime());

  return {
    schemaVersion: CURRENT_SCHEMA_VERSION,
    settings: {
      usdPerHour: Number.isFinite(Number(rawState.settings?.usdPerHour))
        ? Math.max(0.01, Number(rawState.settings.usdPerHour))
        : base.settings.usdPerHour,
    },
    categories: normalizedCategories,
    entries: normalizedEntries,
    badgeAwards: normalizedAwards,
    activeSession:
      normalizedSession && categoryIdSet.has(normalizedSession.categoryId) ? normalizedSession : null,
  };
}
