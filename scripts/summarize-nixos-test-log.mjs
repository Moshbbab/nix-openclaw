#!/usr/bin/env node
import fs from "node:fs";

function usage() {
  process.stderr.write(`Usage:
  scripts/summarize-nixos-test-log.mjs [--label <label>] [--limit <count>] [--summary-file <path>] <log>
`);
}

function parseArgs(argv) {
  const args = {
    label: "nixos-test",
    limit: 32,
    summaryFile: process.env.GITHUB_STEP_SUMMARY || null,
    logPath: null,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--label") {
      args.label = requireValue(argv, ++i, arg);
    } else if (arg === "--limit") {
      args.limit = Number(requireValue(argv, ++i, arg));
      if (!Number.isInteger(args.limit) || args.limit < 1) {
        throw new Error("--limit must be a positive integer");
      }
    } else if (arg === "--summary-file") {
      args.summaryFile = requireValue(argv, ++i, arg);
    } else if (arg.startsWith("-")) {
      throw new Error(`Unknown option: ${arg}`);
    } else if (!args.logPath) {
      args.logPath = arg;
    } else {
      throw new Error(`Unexpected argument: ${arg}`);
    }
  }

  if (!args.logPath) {
    throw new Error("Missing log path");
  }
  return args;
}

function requireValue(argv, index, flag) {
  const value = argv[index];
  if (!value) {
    throw new Error(`Missing value for ${flag}`);
  }
  return value;
}

function parseLog(text) {
  const finished = [];
  const gatewayEvents = [];

  for (const rawLine of text.split(/\r?\n/)) {
    const line = stripAnsi(rawLine);

    const finishedMatch = line.match(/\(finished: (.+), in ([0-9]+(?:\.[0-9]+)?) seconds\)/);
    if (finishedMatch) {
      finished.push({
        step: finishedMatch[1],
        seconds: Number(finishedMatch[2]),
      });
    }

    const gatewayMatch = line.match(/\[gateway\] (.+)$/);
    if (gatewayMatch && /\b(ready|http server listening|starting HTTP server|loading configuration)\b/.test(gatewayMatch[1])) {
      gatewayEvents.push(gatewayMatch[1]);
    }
  }

  return { finished, gatewayEvents };
}

function stripAnsi(value) {
  return value.replace(/\x1B\[[0-9;?]*[ -/]*[@-~]/g, "");
}

function render({ label, limit, finished, gatewayEvents }) {
  const lines = [`### NixOS Test Timing: ${label}`, ""];

  if (finished.length === 0 && gatewayEvents.length === 0) {
    lines.push("No NixOS test timing lines found.");
    return `${lines.join("\n")}\n`;
  }

  if (finished.length > 0) {
    lines.push(
      "Reported test-driver timings can nest; treat them as phase attribution, not a sum.",
      "",
      "| Step | Seconds |",
      "| --- | ---: |",
    );
    for (const item of finished.slice(0, limit)) {
      lines.push(`| ${markdownCell(item.step)} | ${formatSeconds(item.seconds)} |`);
    }
    if (finished.length > limit) {
      lines.push(`| ${formatCount(finished.length - limit)} more | - |`);
    }

    const slowest = [...finished]
      .sort((left, right) => right.seconds - left.seconds || left.step.localeCompare(right.step))
      .slice(0, Math.min(5, limit));
    lines.push("", `Slowest: ${slowest.map((item) => `${item.step} ${formatSeconds(item.seconds)}s`).join(", ")}.`);
  }

  if (gatewayEvents.length > 0) {
    lines.push("", "Gateway events:");
    for (const event of gatewayEvents.slice(-limit)) {
      lines.push(`- ${event}`);
    }
  }

  return `${lines.join("\n")}\n`;
}

function markdownCell(value) {
  return String(value).replace(/\|/g, "\\|").replace(/\r?\n/g, " ");
}

function formatSeconds(value) {
  if (!Number.isFinite(value)) {
    return "-";
  }
  return value.toFixed(value >= 10 ? 1 : 2);
}

function formatCount(value) {
  return new Intl.NumberFormat("en-US").format(value);
}

try {
  const args = parseArgs(process.argv.slice(2));
  const parsed = parseLog(fs.readFileSync(args.logPath, "utf8"));
  const markdown = render({ label: args.label, limit: args.limit, ...parsed });

  process.stdout.write(markdown);
  if (args.summaryFile) {
    fs.appendFileSync(args.summaryFile, `\n${markdown}`);
  }
} catch (error) {
  usage();
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
}
