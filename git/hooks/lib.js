"use strict";

const fs = require("fs");
const path = require("path");
const os = require("os");
const { execSync } = require("child_process");

const dataHome = process.env.XDG_DATA_HOME || path.join(os.homedir(), ".local", "share");
const DEBUG_LOG = path.join(dataHome, "opencode", "git-hook-debug.log");
const COMMIT_AUDITOR_LOG = path.join(dataHome, "opencode", "commit-auditor.jsonl");

const ASCII_REPLACEMENTS = new Map([
    ["\u2014", "---"],
    ["\u2013", "-"],
    ["\u2212", "-"],
    ["\u2026", "..."],
    ["\u2018", "'"],
    ["\u2019", "'"],
    ["\u201A", "'"],
    ["\u201B", "'"],
    ["\u2032", "'"],
    ["\u201C", '"'],
    ["\u201D", '"'],
    ["\u201E", '"'],
    ["\u201F", '"'],
    ["\u2033", '"'],
    ["\u2192", "->"],
    ["\u2190", "<-"],
    ["\u2194", "<->"],
    ["\u21D2", "=>"],
    ["\u21D0", "<="],
    ["\u21D4", "<=>"],
    ["\u2022", "*"],
    ["\u00B7", "*"],
    ["\u25CF", "*"],
    ["\u00A9", "(c)"],
    ["\u00AE", "(R)"],
    ["\u2122", "(TM)"],
]);

const ZERO_WIDTH_RE = /[\uFEFF\u200B\u200C\u200D\u2060]/g;
const SPACE_VARIANTS_RE = /[\u00A0\u2000-\u200A\u202F\u205F\u3000]/g;

let anyAsciiPromise = null;
function loadAnyAscii() {
    if (!anyAsciiPromise) {
        anyAsciiPromise = import("any-ascii").then((m) => m.default).catch(() => null);
    }
    return anyAsciiPromise;
}

async function sanitizeToAscii(text) {
    if (typeof text !== "string" || text.length === 0) return { text: text || "", changed: false };

    let s = text.replace(ZERO_WIDTH_RE, "");
    s = s.replace(SPACE_VARIANTS_RE, " ");

    let mapped = "";
    for (const ch of s) {
        const repl = ASCII_REPLACEMENTS.get(ch);
        mapped += repl !== undefined ? repl : ch;
    }
    s = mapped;

    if (/[^\x00-\x7F]/.test(s)) {
        const anyAscii = await loadAnyAscii();
        if (anyAscii) {
            s = anyAscii(s);
        }
    }

    if (/[^\x00-\x7F]/.test(s)) {
        s = s.replace(/[^\x00-\x7F]/g, "?");
    }

    s = s.replace(/[ \t]+\n/g, "\n");

    return { text: s, changed: s !== text };
}

function makeDebug(hookTag) {
    return function debug(msg) {
        if (process.env.OPENCODE_GIT_HOOK_DEBUG !== "1") return;
        try {
            fs.mkdirSync(path.dirname(DEBUG_LOG), { recursive: true });
            fs.appendFileSync(DEBUG_LOG, `${new Date().toISOString()} ${hookTag} ${msg}\n`);
        } catch {}
    };
}

// Append one JSONL record per commit-auditor invocation to
// $XDG_DATA_HOME/opencode/commit-auditor.jsonl (default
// ~/.local/share/opencode/commit-auditor.jsonl).
//
// Telemetry surface for the commit-msg hook: captures every audit outcome
// (APPROVE / REWRITE / REJECT / UNKNOWN) so the auditor's editing behavior
// is reconstructable without scraping per-session OpenCode logs.
//
// `record` is a plain object; a `timestamp` field is injected if absent.
// Write failures are swallowed: telemetry must never block a commit.
function appendAuditLog(record) {
    try {
        const entry = { timestamp: new Date().toISOString(), ...record };
        fs.mkdirSync(path.dirname(COMMIT_AUDITOR_LOG), { recursive: true });
        fs.appendFileSync(COMMIT_AUDITOR_LOG, JSON.stringify(entry) + "\n");
    } catch {}
}

function gitOutput(args, opts = {}) {
    try {
        return execSync(`git ${args}`, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], ...opts }).trim();
    } catch {
        return "";
    }
}

function withTimeout(promise, ms, label) {
    return Promise.race([
        promise,
        new Promise((_, reject) => setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms)),
    ]);
}

async function httpJson(method, urlStr, body) {
    const headers = { "Content-Type": "application/json" };
    if (process.env.OPENCODE_SERVER_PASSWORD) {
        const user = process.env.OPENCODE_SERVER_USERNAME || "";
        const pass = process.env.OPENCODE_SERVER_PASSWORD;
        headers["Authorization"] = "Basic " + Buffer.from(`${user}:${pass}`).toString("base64");
    }
    const init = { method, headers };
    if (body !== undefined) init.body = JSON.stringify(body);
    const res = await fetch(urlStr, init);
    const text = await res.text();
    let data = null;
    try {
        data = text ? JSON.parse(text) : null;
    } catch {}
    return { status: res.status, ok: res.ok, text, data };
}

module.exports = { makeDebug, appendAuditLog, gitOutput, withTimeout, httpJson, sanitizeToAscii };
