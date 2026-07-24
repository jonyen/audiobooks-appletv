const VALUES: Array<[number, string]> = [
  [1000, "M"], [900, "CM"], [500, "D"], [400, "CD"],
  [100, "C"], [90, "XC"], [50, "L"], [40, "XL"],
  [10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"],
];

/**
 * Parses a Roman numeral (case-insensitive). Returns null if the string
 * contains non-numeral characters or is not consumable greedily.
 */
export function parseRoman(s: string): number | null {
  const upper = s.toUpperCase();
  if (upper.length === 0 || ![...upper].every((c) => "MDCLXVI".includes(c))) return null;
  let total = 0;
  let index = 0;
  for (const [value, symbol] of VALUES) {
    while (upper.startsWith(symbol, index)) {
      total += value;
      index += symbol.length;
      if (index === upper.length) return total;
    }
  }
  return index === upper.length ? total : null;
}
