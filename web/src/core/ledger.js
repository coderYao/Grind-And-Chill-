import { round2 } from "./utils.js";

export function resolveType(category) {
  return category?.type === "quitHabit" ? "quitHabit" : "goodHabit";
}

export function resolveUnit(category) {
  if (["time", "count", "money"].includes(category?.unit)) {
    return category.unit;
  }
  return "time";
}

export function resolveTimeMode(category) {
  return category?.timeConversionMode === "hourlyRate" ? "hourlyRate" : "multiplier";
}

export function amountUSDForCategory({ category, quantity, usdPerHour }) {
  if (!category) {
    return 0;
  }

  const safeQuantity = Math.max(0, Number(quantity) || 0);
  if (safeQuantity <= 0) {
    return 0;
  }

  const unit = resolveUnit(category);
  let rawAmount = 0;

  if (unit === "time") {
    const hours = safeQuantity / 60;
    const mode = resolveTimeMode(category);

    if (mode === "hourlyRate") {
      const customRate = Number(category.hourlyRateUSD);
      rawAmount = hours * (Number.isFinite(customRate) && customRate > 0 ? customRate : usdPerHour);
    } else {
      const multiplier = Number(category.multiplier);
      rawAmount = hours * usdPerHour * (Number.isFinite(multiplier) && multiplier > 0 ? multiplier : 1);
    }
  }

  if (unit === "count") {
    const usdPerCount = Number(category.usdPerCount);
    rawAmount = safeQuantity * (Number.isFinite(usdPerCount) && usdPerCount > 0 ? usdPerCount : 1);
  }

  if (unit === "money") {
    rawAmount = safeQuantity;
  }

  const signed = resolveType(category) === "quitHabit" ? rawAmount * -1 : rawAmount;
  return round2(signed);
}

export function totalBalance(entries) {
  return round2(entries.reduce((sum, entry) => sum + (Number(entry.amountUSD) || 0), 0));
}

export function dailyLedgerSummary(entries, dayTimestamp) {
  const date = new Date(dayTimestamp);
  date.setHours(0, 0, 0, 0);
  const start = date.getTime();
  const end = start + 24 * 60 * 60 * 1000;

  let ledgerChange = 0;
  let gain = 0;
  let spent = 0;
  let count = 0;

  for (const entry of entries) {
    const entryTime = new Date(entry.timestamp).getTime();
    if (entryTime < start || entryTime >= end) {
      continue;
    }

    count += 1;
    const amount = Number(entry.amountUSD) || 0;
    ledgerChange += amount;

    if (amount >= 0) {
      gain += amount;
    } else {
      spent += amount * -1;
    }
  }

  return {
    ledgerChange: round2(ledgerChange),
    gain: round2(gain),
    spent: round2(spent),
    count,
  };
}
