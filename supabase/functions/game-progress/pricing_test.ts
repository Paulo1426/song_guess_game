import {
  allowedInstrumentPrices,
  canPurchaseInstrument,
  maxPurchasedInstruments,
  selectMelodyInstrument,
  selectNextInstrumentPrice,
  totalInstrumentBudget,
} from "./pricing.ts";

const instruments = ["bateria", "acordeon", "bajo", "guitarra"];

Deno.test("each purchase price keeps the final three purchases at 1000000", () => {
  for (const firstPrice of allowedInstrumentPrices) {
    for (
      const secondChoice of firstPrice === 300000 ? [0, 1] : [0]
    ) {
      const first = selectNextInstrumentPrice([], () =>
        firstPrice === 300000 ? 0 : 1
      );
      const second = selectNextInstrumentPrice([first], () => secondChoice);
      const third = selectNextInstrumentPrice([first, second]);

      if (
        !allowedInstrumentPrices.includes(
          first as typeof allowedInstrumentPrices[number],
        ) ||
        !allowedInstrumentPrices.includes(
          second as typeof allowedInstrumentPrices[number],
        ) ||
        !allowedInstrumentPrices.includes(
          third as typeof allowedInstrumentPrices[number],
        ) ||
        first + second + third !== totalInstrumentBudget
      ) {
        throw new Error("Three sequential purchases must total 1000000");
      }
    }
  }
});

Deno.test("the second and third prices follow the remaining budget", () => {
  if (
    selectNextInstrumentPrice([400000]) !== 300000 ||
    selectNextInstrumentPrice([300000], () => 0) !== 300000 ||
    selectNextInstrumentPrice([300000], () => 1) !== 400000 ||
    selectNextInstrumentPrice([300000, 300000]) !== 400000 ||
    selectNextInstrumentPrice([300000, 400000]) !== 300000 ||
    selectNextInstrumentPrice([400000, 300000]) !== 300000
  ) {
    throw new Error("Price choices must match the remaining budget");
  }
});

Deno.test("melody is unpurchased for seven of ten outcomes", () => {
  const purchased = instruments.slice(0, 3);
  for (let roll = 0; roll < 7; roll++) {
    const melody = selectMelodyInstrument(instruments, purchased, () => roll);
    if (purchased.includes(melody)) {
      throw new Error("Seven of ten outcomes must select the unpurchased stem");
    }
  }
});

Deno.test("melody is purchased for three of ten outcomes", () => {
  const purchased = instruments.slice(0, 3);
  for (let index = 0; index < 3; index++) {
    const choices = [7 + index, index];
    const melody = selectMelodyInstrument(
      instruments,
      purchased,
      () => choices.shift()!,
    );
    if (melody !== purchased[index]) {
      throw new Error("The remaining three outcomes must select a purchased stem");
    }
  }
});

Deno.test("three-instrument levels allow all three purchases", () => {
  if (
    !canPurchaseInstrument(maxPurchasedInstruments - 1) ||
    canPurchaseInstrument(maxPurchasedInstruments)
  ) {
    throw new Error("A player can purchase three instruments, but not four");
  }
});

Deno.test("invalid purchase histories and melody sets are rejected", () => {
  const invalidPurchaseHistories = [
    [300000, 300000, 300000],
    [200000],
    [300000, 400000, 300000],
  ];
  for (const history of invalidPurchaseHistories) {
    let rejected = false;
    try {
      selectNextInstrumentPrice(history);
    } catch (error) {
      rejected = error instanceof RangeError;
    }
    if (!rejected) throw new Error("Invalid purchase histories must be rejected");
  }

  let rejected = false;
  try {
    selectMelodyInstrument(instruments, ["bateria", "acordeon"]);
  } catch (error) {
    rejected = error instanceof RangeError;
  }
  if (!rejected) throw new Error("Melody needs exactly three purchased stems");
});
