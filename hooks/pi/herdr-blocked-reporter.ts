/**
 * Herdr blocked-state reporter for Pi.
 *
 * When running inside Herdr (HERDR_ENV=1 with HERDR_BIN_PATH and HERDR_PANE_ID
 * set), reports state=blocked to Herdr whenever the ask_user_question tool is
 * invoked, so the sidebar shows the agent as waiting on the user.
 *
 * Fire-and-forget: never blocks the agent turn; failures are ignored.
 *
 * Usage:
 *   pi -e ./hooks/pi/herdr-blocked-reporter.ts
 * or copy/symlink into ~/.pi/agent/extensions/.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawn } from "node:child_process";

const HERDR_ENV = process.env.HERDR_ENV === "1";
const HERDR_BIN_PATH = process.env.HERDR_BIN_PATH?.trim() ?? "";
const HERDR_PANE_ID = process.env.HERDR_PANE_ID?.trim() ?? "";

export default function herdrBlockedReporter(pi: ExtensionAPI) {
  // No-op outside Herdr.
  if (!HERDR_ENV || !HERDR_BIN_PATH || !HERDR_PANE_ID) {
    return;
  }

  pi.on("tool_call", (event) => {
    if (event.toolName !== "ask_user_question") {
      return;
    }

    try {
      const child = spawn(
        HERDR_BIN_PATH,
        [
          "pane",
          "report-agent",
          HERDR_PANE_ID,
          "--source",
          "pi",
          "--agent",
          "pi",
          "--state",
          "blocked",
          "--message",
          "Approval: ⚡ ACT",
          "--seq",
          String(Date.now()),
        ],
        { stdio: "ignore", detached: false },
      );

      const timer = setTimeout(() => {
        try {
          child.kill();
        } catch {
          // ignore
        }
      }, 2000);

      child.on("exit", () => clearTimeout(timer));
      child.on("error", () => {
        // ignore failures so the agent is never slowed down
      });
      child.unref();
    } catch {
      // ignore
    }
  });
}
