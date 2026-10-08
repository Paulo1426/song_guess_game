export const levelsPerDifficulty = 5;

export interface PublishedLevel {
  id: string;
  numero: number;
  dificultad: string;
  published: boolean;
}

export function selectDifficultyLevels(
  levels: PublishedLevel[],
  difficulty: string,
): PublishedLevel[] {
  return levels
    .filter((level) =>
      level.dificultad.trim() === difficulty &&
      level.published &&
      Number.isInteger(level.numero)
    )
    .sort((first, second) =>
      first.numero - second.numero || first.id.localeCompare(second.id)
    )
    .slice(0, levelsPerDifficulty);
}
