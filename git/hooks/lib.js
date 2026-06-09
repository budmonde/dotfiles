"use strict";

const fs = require("fs");
const path = require("path");
const os = require("os");
const { execSync } = require("child_process");

const dataHome = process.env.XDG_DATA_HOME || path.join(os.homedir(), ".local", "share");
const DEBUG_LOG = path.join(dataHome, "opencode", "git-hook-debug.log");

function makeDebug(hookTag) {
    return function debug(msg) {
        if (process.env.OPENCODE_GIT_HOOK_DEBUG !== "1") return;
        try {
            fs.mkdirSync(path.dirname(DEBUG_LOG), { recursive: true });
            fs.appendFileSync(DEBUG_LOG, `${new Date().toISOString()} ${hookTag} ${msg}\n`);
        } catch {}
    };
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

module.exports = { makeDebug, gitOutput, withTimeout, httpJson };
