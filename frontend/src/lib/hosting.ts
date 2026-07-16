export function isSharedIpfsPathGateway(pathname: string): boolean {
  let decodedPath = pathname;

  // A gateway or intermediary may decode the path before routing it. Decode a small,
  // bounded number of layers so encoded separators/casing cannot bypass the guard.
  for (let pass = 0; pass < 3; pass += 1) {
    let next: string;
    try {
      next = decodeURIComponent(decodedPath);
    } catch {
      // A malformed path is not a safe origin on which to enable wallet behavior.
      return true;
    }
    if (next === decodedPath) break;
    decodedPath = next;
  }

  return decodedPath
    .split(/\/+/)
    .some((segment) => segment.toLowerCase() === "ipfs" || segment.toLowerCase() === "ipns");
}
