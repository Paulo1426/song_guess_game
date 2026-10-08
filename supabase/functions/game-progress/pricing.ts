export const allowedInstrumentPrices = [300000, 400000] as const;
export const maxPurchasedInstruments = 3;
export const totalInstrumentBudget = 1000000;

function secureRandomIndex(maxExclusive: number): number {
  const range = 0x100000000;
  const cutoff = range - (range % maxExclusive);
  let value: number;
  do {
    value = crypto.getRandomValues(new Uint32Array(1))[0];
  } while (value >= cutoff);
  return value % maxExclusive;
}

function checkedRandomIndex(
  maxExclusive: number,
  chooseIndex: (limit: number) => number,
): number {
  const selected = chooseIndex(maxExclusive);
  if (
    !Number.isInteger(selected) || selected < 0 || selected >= maxExclusive
  ) {
    throw new RangeError("Random index is outside the allowed range");
  }
  return selected;
}

export function selectNextInstrumentPrice(
  purchasedPrices: number[],
  chooseIndex: (maxExclusive: number) => number = secureRandomIndex,
): number {
  if (
    purchasedPrices.length >= maxPurchasedInstruments ||
    purchasedPrices.some((price) => !allowedInstrumentPrices.includes(
      price as typeof allowedInstrumentPrices[number],
    ))
  ) {
    throw new RangeError("Purchased instrument prices are invalid");
  }

  const remainingBudget = totalInstrumentBudget -
    purchasedPrices.reduce((sum, price) => sum + price, 0);
  if (purchasedPrices.length === 0) {
    return allowedInstrumentPrices[
      checkedRandomIndex(allowedInstrumentPrices.length, chooseIndex)
    ];
  }
  if (purchasedPrices.length === 1 && purchasedPrices[0] === 300000) {
    return allowedInstrumentPrices[
      checkedRandomIndex(allowedInstrumentPrices.length, chooseIndex)
    ];
  }
  if (purchasedPrices.length === 1 && purchasedPrices[0] === 400000) {
    return 300000;
  }
  if (purchasedPrices.length === 2) {
    if (!allowedInstrumentPrices.includes(
      remainingBudget as typeof allowedInstrumentPrices[number],
    )) {
      throw new RangeError("Remaining budget cannot fund the next purchase");
    }
    return remainingBudget;
  }
  throw new RangeError("Purchased instrument prices are invalid");
}

export function selectMelodyInstrument(
  instrumentTypes: string[],
  purchasedInstrumentTypes: string[],
  chooseIndex: (maxExclusive: number) => number = secureRandomIndex,
): string {
  if (
    new Set(instrumentTypes).size !== instrumentTypes.length ||
    (instrumentTypes.length !== 4 && instrumentTypes.length !== 3) ||
    purchasedInstrumentTypes.length !==
      (instrumentTypes.length === 4 ? maxPurchasedInstruments : 3) ||
    new Set(purchasedInstrumentTypes).size !==
      purchasedInstrumentTypes.length ||
    purchasedInstrumentTypes.some((type) => !instrumentTypes.includes(type))
  ) {
    throw new RangeError("Melody requires four instruments and three purchases");
  }

  const unpurchased = instrumentTypes.filter((type) =>
    !purchasedInstrumentTypes.includes(type)
  );
  if (unpurchased.length === 0) {
    return purchasedInstrumentTypes[
      checkedRandomIndex(purchasedInstrumentTypes.length, chooseIndex)
    ];
  }
  return checkedRandomIndex(10, chooseIndex) < 7
    ? unpurchased[0]
    : purchasedInstrumentTypes[
      checkedRandomIndex(purchasedInstrumentTypes.length, chooseIndex)
    ];
}

export function canPurchaseInstrument(purchasedCount: number): boolean {
  return purchasedCount < maxPurchasedInstruments;
}
