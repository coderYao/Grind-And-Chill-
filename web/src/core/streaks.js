import { dateKey, round2, toNumber } from "./utils.js";

const DEFAULT_MILESTONES = [3, 7, 30];

function asDate(dateLike = Date.now()) {
  return dateLike instanceof Date ? dateLike : new Date(dateLike);
}

function startOfDay(dateLike) {
  const date = asDate(dateLike);
  date.setHours(0, 0, 0, 0);
  return date;
}

function startOfWeek(dateLike) {
  const date = startOfDay(dateLike);
  const dayOfWeek = date.getDay(); // 0 = Sunday
  date.setDate(date.getDate() - dayOfWeek);
  return date;
}

function startOfMonth(dateLike) {
  const date = asDate(dateLike);
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

function addCadence(dateLike, cadence, delta) {
  const date = asDate(dateLike);

  if (cadence === "daily") {
    date.setDate(date.getDate() + delta);
    return startOfDay(date);
  }

  if (cadence === "weekly") {
    date.setDate(date.getDate() + delta * 7);
    return startOfWeek(date);
  }

  date.setMonth(date.getMonth() + delta);
  return startOfMonth(date);
}

function isoWeekString(dateLike) {
  const date = asDate(dateLike);
  const temp = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const dayNum = temp.getUTCDay() || 7;
  temp.setUTCDate(temp.getUTCDate() + 4 - dayNum);
  const year = temp.getUTCFullYear();
  const yearStart = new Date(Date.UTC(year, 0, 1));
  const week = Math.ceil((((temp - yearStart) / 86400000) + 1) / 7);
  return `${year}-W${String(week).padStart(2, "0")}`;
}

function isoMonthString(dateLike) {
  const date = asDate(dateLike);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

function formatByUnit(value, unit) {
  if (unit === "time") {
    return `${Math.max(0, Math.floor(toNumber(value, 0)))}m`;
  }

  if (unit === "count") {
    return new Intl.NumberFormat(undefined, {
      maximumFractionDigits: 2,
    }).format(toNumber(value, 0));
  }

  return new Intl.NumberFormat(undefined, {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 2,
  }).format(toNumber(value, 0));
}

function progressValue(entry, category) {
  if (entry?.bonusKey) {
    return 0;
  }

  if (category.unit === "time") {
    return Math.max(0, toNumber(entry.durationMinutes, 0));
  }

  if (category.unit === "count") {
    if (entry.unit === "count") {
      return Math.max(0, toNumber(entry.quantity, 0));
    }
    return Math.max(0, toNumber(entry.durationMinutes, 0));
  }

  const amount = toNumber(entry.amountUSD, 0);
  return amount < 0 ? amount * -1 : amount;
}

export function resolveCadence(rawCadence) {
  if (["daily", "weekly", "monthly"].includes(rawCadence)) {
    return rawCadence;
  }
  return "daily";
}

export function resolveMilestones(rawMilestones, defaults = DEFAULT_MILESTONES) {
  const source = Array.isArray(rawMilestones)
    ? rawMilestones
    : String(rawMilestones || "")
        .split(/[\s,]+/)
        .filter(Boolean);

  const parsed = source
    .map((value) => Number.parseInt(String(value), 10))
    .filter((value) => Number.isFinite(value) && value > 0);

  const normalized = Array.from(new Set(parsed)).sort((a, b) => a - b);
  if (normalized.length > 0) {
    return normalized;
  }

  return [...defaults];
}

export function cadenceShortSuffix(cadence) {
  const resolved = resolveCadence(cadence);
  if (resolved === "weekly") {
    return "w";
  }
  if (resolved === "monthly") {
    return "m";
  }
  return "d";
}

export function cadenceProgressLabel(cadence) {
  const resolved = resolveCadence(cadence);
  if (resolved === "weekly") {
    return "this week";
  }
  if (resolved === "monthly") {
    return "this month";
  }
  return "today";
}

export function cadenceUnitLabel(cadence) {
  const resolved = resolveCadence(cadence);
  if (resolved === "weekly") {
    return "week";
  }
  if (resolved === "monthly") {
    return "month";
  }
  return "day";
}

export function periodAnchor(dateLike, cadence) {
  const resolved = resolveCadence(cadence);

  if (resolved === "weekly") {
    return startOfWeek(dateLike);
  }

  if (resolved === "monthly") {
    return startOfMonth(dateLike);
  }

  return startOfDay(dateLike);
}

export function periodRange(dateLike, cadence) {
  const start = periodAnchor(dateLike, cadence);
  const end = addCadence(start, resolveCadence(cadence), 1);
  return { start, end };
}

function previousPeriodAnchor(dateLike, cadence) {
  return addCadence(periodAnchor(dateLike, cadence), resolveCadence(cadence), -1);
}

function sameAnchor(a, b) {
  return a.getTime() === b.getTime();
}

function categoryEntries(category, entries) {
  return entries.filter((entry) => entry.categoryId === category.id);
}

function goodHabitStreak(category, entries, now) {
  const cadence = resolveCadence(category.streakCadence);
  const goal = Math.max(0, toNumber(category.dailyGoalValue, 0));
  if (goal <= 0) {
    return 0;
  }

  const totalsByAnchor = new Map();
  for (const entry of entries) {
    const anchor = periodAnchor(entry.timestamp, cadence).getTime();
    totalsByAnchor.set(anchor, (totalsByAnchor.get(anchor) || 0) + progressValue(entry, category));
  }

  const currentAnchor = periodAnchor(now, cadence);
  const currentTotal = totalsByAnchor.get(currentAnchor.getTime()) || 0;
  let cursor = currentTotal >= goal ? currentAnchor : previousPeriodAnchor(currentAnchor, cadence);

  if (!cursor) {
    return 0;
  }

  let streak = 0;
  while ((totalsByAnchor.get(cursor.getTime()) || 0) >= goal) {
    streak += 1;
    const prev = previousPeriodAnchor(cursor, cadence);
    if (!prev || sameAnchor(prev, cursor)) {
      break;
    }
    cursor = prev;
  }

  return streak;
}

function quitHabitStreak(categoryEntriesList, cadence, now) {
  if (categoryEntriesList.length === 0) {
    return 0;
  }

  const sorted = [...categoryEntriesList].sort(
    (a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()
  );

  const lastDate = asDate(sorted[0].timestamp);
  const start = periodAnchor(lastDate, cadence);
  const end = periodAnchor(now, cadence);

  if (end.getTime() <= start.getTime()) {
    return 0;
  }

  if (cadence === "daily") {
    return Math.max(0, Math.floor((end.getTime() - start.getTime()) / 86_400_000));
  }

  if (cadence === "weekly") {
    return Math.max(0, Math.floor((end.getTime() - start.getTime()) / 604_800_000));
  }

  return Math.max(
    0,
    (end.getFullYear() - start.getFullYear()) * 12 + (end.getMonth() - start.getMonth())
  );
}

export function totalProgressForCategory(category, entries, on = Date.now()) {
  const range = periodRange(on, resolveCadence(category.streakCadence));

  return round2(
    entries
      .filter((entry) => {
        if (entry.categoryId !== category.id) {
          return false;
        }

        const timestamp = new Date(entry.timestamp).getTime();
        return timestamp >= range.start.getTime() && timestamp < range.end.getTime();
      })
      .reduce((sum, entry) => sum + progressValue(entry, category), 0)
  );
}

export function streakForCategory(category, entries, now = Date.now()) {
  if (category.streakEnabled === false) {
    return 0;
  }

  const cadence = resolveCadence(category.streakCadence);
  const scopedEntries = categoryEntries(category, entries);

  if (category.type === "quitHabit") {
    return quitHabitStreak(scopedEntries, cadence, now);
  }

  return goodHabitStreak(category, scopedEntries, now);
}

export function cadencePeriodKey(cadence, now = Date.now()) {
  const resolved = resolveCadence(cadence);

  if (resolved === "weekly") {
    return `w${isoWeekString(now)}`;
  }

  if (resolved === "monthly") {
    return `m${isoMonthString(now)}`;
  }

  return dateKey(now);
}

export function progressTextForCategory(category, entries, now = Date.now()) {
  const progress = totalProgressForCategory(category, entries, now);
  const goal = Math.max(0, toNumber(category.dailyGoalValue, 0));
  const thresholdText = formatByUnit(goal, category.unit);
  const label = cadenceProgressLabel(category.streakCadence);

  if (category.type === "quitHabit") {
    if (progress === 0) {
      return `No relapses ${label} - Target < ${thresholdText}`;
    }
    return `${formatByUnit(progress, category.unit)} logged ${label} - Target < ${thresholdText}`;
  }

  return `${formatByUnit(progress, category.unit)}/${thresholdText} ${label}`;
}

export function streakHighlight(categories, entries, now = Date.now()) {
  const candidates = categories
    .map((category) => {
      const streak = streakForCategory(category, entries, now);
      if (streak <= 0) {
        return null;
      }

      const cadence = resolveCadence(category.streakCadence);
      return {
        categoryId: category.id,
        title: category.title,
        type: category.type,
        unit: category.unit,
        cadence,
        streak,
        progressText: progressTextForCategory(category, entries, now),
      };
    })
    .filter(Boolean);

  candidates.sort((a, b) => {
    if (a.streak !== b.streak) {
      return b.streak - a.streak;
    }

    if (a.type !== b.type) {
      return a.type === "goodHabit" ? -1 : 1;
    }

    return a.title.localeCompare(b.title);
  });

  return candidates[0] || null;
}

export function streakRiskAlerts(categories, entries, now = Date.now()) {
  const alerts = [];

  for (const category of categories) {
    if (category.streakEnabled === false) {
      continue;
    }

    const goal = Math.max(0, toNumber(category.dailyGoalValue, 0));
    const progress = totalProgressForCategory(category, entries, now);

    if (category.type === "goodHabit") {
      const streak = streakForCategory(category, entries, now);
      if (streak <= 0 || goal <= 0 || progress >= goal) {
        continue;
      }

      const remaining = round2(goal - progress);
      const ratio = goal <= 0 ? 0 : remaining / goal;
      const severity = ratio <= 0.25 ? 3 : 2;

      alerts.push({
        id: category.id,
        categoryId: category.id,
        title: category.title,
        type: "goodHabit",
        severity,
        message: `Needs ${formatByUnit(remaining, category.unit)} ${cadenceProgressLabel(
          category.streakCadence
        )} to protect ${streak}${cadenceShortSuffix(category.streakCadence)} streak.`,
      });
      continue;
    }

    if (goal <= 0 || progress <= 0) {
      continue;
    }

    const threshold70 = goal * 0.7;
    let severity = 0;
    let message = "";

    if (progress >= goal) {
      severity = 3;
      message = `Target exceeded ${cadenceProgressLabel(category.streakCadence)}: ${formatByUnit(
        progress,
        category.unit
      )} / ${formatByUnit(goal, category.unit)}.`;
    } else if (progress >= threshold70) {
      severity = 2;
      message = `Close to limit ${cadenceProgressLabel(category.streakCadence)}: ${formatByUnit(
        progress,
        category.unit
      )} / ${formatByUnit(goal, category.unit)}.`;
    }

    if (severity > 0) {
      alerts.push({
        id: category.id,
        categoryId: category.id,
        title: category.title,
        type: "quitHabit",
        severity,
        message,
      });
    }
  }

  alerts.sort((a, b) => {
    if (a.severity !== b.severity) {
      return b.severity - a.severity;
    }

    if (a.type !== b.type) {
      return a.type === "goodHabit" ? -1 : 1;
    }

    return a.title.localeCompare(b.title);
  });

  return alerts;
}

export function badgeLabelFromAward(award) {
  const milestone = Number(award?.milestone);
  if (!Number.isFinite(milestone) || milestone <= 0) {
    return String(award?.awardKey || "Badge");
  }

  const unit = cadenceUnitLabel(award.cadence);
  return `${milestone}-${unit} streak`;
}
