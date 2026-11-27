import { isSharedIpfsPathGateway } from "./lib/hosting.ts";

const root = document.getElementById("root");

const framed = window.top !== window.self;
const sharedIpfsOrigin = isSharedIpfsPathGateway(window.location.pathname);

if (framed || sharedIpfsOrigin) {
  if (root) {
    const heading = document.createElement("h1");
    heading.textContent = framed ? "Embedded interface blocked" : "Shared IPFS gateway origin blocked";

    const explanation = document.createElement("p");
    explanation.textContent = framed
      ? "Open the verified PulseTensor interface in a top-level browser tab before connecting a wallet."
      : "Wallet code is disabled on /ipfs/ and /ipns/ path gateways because unrelated CIDs share one browser origin. Use a verified CID-subdomain gateway, dedicated origin, or local build.";

    root.replaceChildren(heading, explanation);
  }
} else {
  void import("./main.tsx");
}
