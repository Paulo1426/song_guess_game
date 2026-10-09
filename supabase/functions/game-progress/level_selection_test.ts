import {
  canonicalDifficulty,
  levelsPerDifficulty,
  selectDifficultyLevels,
} from "./level_selection.ts";

Deno.test("normalizes the Firestore labels used for medium and hard levels", () => {
  if (
    canonicalDifficulty("media") !== "medio" ||
    canonicalDifficulty("DIFÍCIL") !== "avanzado"
  ) {
    throw new Error("Legacy difficulty labels must map to canonical IDs");
  }
  const levels = [
    {
      id: "media-01",
      numero: 1,
      dificultad: "media",
      published: true,
    },
    {
      id: "dificil-01",
      numero: 1,
      dificultad: "difícil",
      published: true,
    },
  ];
  if (
    selectDifficultyLevels(levels, "medio").map((level) => level.id).join() !==
      "media-01" ||
    selectDifficultyLevels(levels, "avanzado").map((level) => level.id).join() !==
      "dificil-01"
  ) {
    throw new Error("Legacy levels must appear in their canonical difficulties");
  }
});

Deno.test("limits every difficulty to its first five numbered published levels", () => {
  const levels = Array.from({ length: 8 }, (_, index) => ({
    id: `facil-${index + 1}`,
    numero: index + 1,
    dificultad: "facil",
    published: true,
  }));
  levels.push({
    id: "medio-01",
    numero: 1,
    dificultad: "medio",
    published: true,
  });
  levels.push({
    id: "facil-09-draft",
    numero: 9,
    dificultad: "facil",
    published: false,
  });

  const selected = selectDifficultyLevels(levels, "facil");
  if (selected.length !== levelsPerDifficulty) {
    throw new Error("Expected exactly five active levels");
  }
  if (selected.some((level, index) => level.numero !== index + 1)) {
    throw new Error("Old levels beyond number five must not be selected");
  }
});

Deno.test("requires exactly five published levels before a difficulty is complete", () => {
  const fourLevels = Array.from({ length: 4 }, (_, index) => ({
    id: `facil-${index + 1}`,
    numero: index + 1,
    dificultad: "facil",
    published: true,
  }));
  const fiveLevels = [
    ...fourLevels,
    {
      id: "facil-05",
      numero: 5,
      dificultad: "facil",
      published: true,
    },
  ];

  if (
    selectDifficultyLevels(fourLevels, "facil").length === levelsPerDifficulty
  ) {
    throw new Error("Four published levels must not satisfy the requirement");
  }
  if (
    selectDifficultyLevels(fiveLevels, "facil").length !== levelsPerDifficulty
  ) {
    throw new Error("Five published levels should satisfy the requirement");
  }
});
