import { formatEther } from "viem";

const DISPLAY_PRECISION_WEI = 1_000_000_000_000n;

export function formatPls(value: bigint | null | undefined): string {
  if (value === null || value === undefined) return "-";
  if (value > 0n && value < DISPLAY_PRECISION_WEI) return "<0.000001 PLS";
  if (value < 0n && value > -DISPLAY_PRECISION_WEI) return ">-0.000001 PLS";
  const [whole, fraction = ""] = formatEther(value).split(".");
  const trimmedFraction = fraction.replace(/0+$/, "").slice(0, 6);
  return `${whole}${trimmedFraction ? `.${trimmedFraction}` : ""} PLS`;
}

/** Exact decimal PLS and integer wei, suitable for a tooltip/title or audit detail. */
export function formatPlsExact(value: bigint | null | undefined): string {
  if (value === null || value === undefined) return "-";
  return `${formatEther(value)} PLS (${value.toString()} wei)`;
}

export function toHexChainId(chainId: number): `0x${string}` {
  return `0x${chainId.toString(16)}`;
}

export function formatShortHash(hash: string | null): string {
  if (!hash) return "-";
  if (hash.length <= 16) return hash;
  return `${hash.slice(0, 10)}…${hash.slice(-6)}`;
}
