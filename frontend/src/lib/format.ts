import { formatEther } from "viem";

export function formatPls(value: bigint | null | undefined): string {
  if (value === null || value === undefined) return "-";
  const [whole, fraction = ""] = formatEther(value).split(".");
  const trimmedFraction = fraction.replace(/0+$/, "").slice(0, 6);
  return `${whole}${trimmedFraction ? `.${trimmedFraction}` : ""} PLS`;
}

export function toHexChainId(chainId: number): `0x${string}` {
  return `0x${chainId.toString(16)}`;
}

export function formatShortHash(hash: string | null): string {
  if (!hash) return "-";
  if (hash.length <= 16) return hash;
  return `${hash.slice(0, 10)}…${hash.slice(-6)}`;
}
