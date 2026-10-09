export const levelsPerDifficulty = 5;

export interface PublishedLevel {
  id: string;
  numero: number;
  dificultad: string;
  published: boolean;
}

export function canonicalDifficulty(value: string): string {
  const normalized = value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .toLocaleLowerCase();
  if (normalized === "media") return "medio";
  if (normalized === "dificil") return "avanzado";
  return normalized;
}

export function selectDifficultyLevels(
  levels: PublishedLevel[],
  difficulty: string,
): PublishedLevel[] {
  return levels
    .filter((level) =>
      canonicalDifficulty(level.dificultad) === canonicalDifficulty(difficulty) &&
      level.published &&
      Number.isInteger(level.numero)
    )
    .sort((first, second) =>
      first.numero - second.numero || first.id.localeCompare(second.id)
    )
    .slice(0, levelsPerDifficulty);
}
