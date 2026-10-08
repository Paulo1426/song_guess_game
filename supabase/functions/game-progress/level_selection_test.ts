import {
  levelsPerDifficulty,
  selectDifficultyLevels,
} from "./level_selection.ts";

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
