import { spawn } from "node:child_process";
import { realpathSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

import gitHookHelpers from "../../git/hooks/lib.js";

const { sanitizeToAscii } = gitHookHelpers;
const CLIENT_INFO = {
    name: "dotfiles_notification_monitor",
    title: "Dotfiles Notification Monitor",
    version: "1.0.0",
};

export const DEFAULT_ENDPOINT = "ws://127.0.0.1:4500";

function clean(value, limit = Infinity) {
    const text = String(value ?? "").replace(/\s+/g, " ").trim();
    return text.length <= limit ? text : `${text.slice(0, limit - 3)}...`;
}

function errorText(error) {
    return typeof error === "string"
        ? error
        : error?.message || error?.additionalDetails || "Unknown error";
}

function isEligibleThread(thread) {
    return Boolean(
        thread?.id &&
            thread.parentThreadId == null &&
            thread.threadSource === "user",
    );
}

function waitingFlags(status) {
    return status?.type === "active" && Array.isArray(status.activeFlags)
        ? new Set(status.activeFlags)
        : new Set();
}

export function buildNotification({ event, metadata = {}, detail = "" }) {
    const directory = path.basename(metadata.cwd || "") || "Codex";
    const branch = metadata.gitInfo?.branch;
    const session = clean(metadata.name || metadata.preview || "Codex", 100);
    const title = clean(branch ? `${directory} : ${branch}` : directory, 100);
    let summary;
    let sound;

    if (event === "interaction") {
        summary = `Interaction required${detail ? `: ${detail}` : ""}`;
        sound = "Windows Exclamation";
    } else if (event === "idle") {
        summary = "Codex is idle";
        sound = "Windows Notify";
    } else {
        throw new Error(`Unsupported notification event: ${event}`);
    }

    return {
        event,
        title,
        message: clean(`Session: ${session}\n${summary}`, 240),
        sound,
    };
}

export class NotificationState {
    constructor() {
        this.metadata = new Map();
        this.statuses = new Map();
        this.waiting = new Map();
        this.idleTimers = new Map();
    }
}

export class MonitorSession {
    constructor({
        send,
        notify,
        log,
        state,
        idleDelayMs = 500,
        requestTimeoutMs = 10000,
    }) {
        this.send = send;
        this.notify = notify;
        this.log = log;
        this.state = state;
        this.idleDelayMs = idleDelayMs;
        this.requestTimeoutMs = requestTimeoutMs;
        this.nextId = 1;
        this.requests = new Map();
        this.pendingStatuses = new Map();
        this.inspections = new Map();
        this.closed = false;
    }

    async start({ discover = true } = {}) {
        await this.request("initialize", {
            clientInfo: CLIENT_INFO,
            capabilities: { experimentalApi: true, requestAttestation: false },
        });
        this.send({ method: "initialized", params: {} });
        if (discover) {
            await this.discover();
        }
    }

    request(method, params) {
        if (this.closed) {
            return Promise.reject(new Error("Connection is closed"));
        }
        const id = this.nextId++;
        const response = new Promise((resolve, reject) => {
            const timeout = setTimeout(() => {
                this.requests.delete(String(id));
                reject(new Error(`${method}: timed out waiting for App Server`));
            }, this.requestTimeoutMs);
            this.requests.set(String(id), { method, resolve, reject, timeout });
        });
        this.send({ method, id, params });
        return response;
    }

    async discover() {
        let cursor = null;
        do {
            const result = await this.request(
                "thread/loaded/list",
                cursor ? { cursor } : {},
            );
            if (!Array.isArray(result?.data)) {
                throw new Error("thread/loaded/list returned malformed data");
            }
            await Promise.all(result.data.map((threadId) => this.inspect(threadId)));
            cursor = result.nextCursor || null;
        } while (cursor);
    }

    inspect(threadId) {
        if (typeof threadId !== "string") {
            return Promise.resolve();
        }
        if (this.inspections.has(threadId)) {
            return this.inspections.get(threadId);
        }
        const inspection = this.request("thread/read", {
            threadId,
            includeTurns: false,
        })
            .then((result) => {
                const thread = result?.thread;
                if (!thread?.id) {
                    throw new Error(`thread/read returned no metadata for ${threadId}`);
                }
                this.state.metadata.set(thread.id, thread);
                const queued = this.pendingStatuses.get(thread.id) || [];
                this.pendingStatuses.delete(thread.id);
                if (isEligibleThread(thread)) {
                    for (const status of queued.length ? queued : [thread.status]) {
                        this.applyStatus(thread.id, status);
                    }
                }
            })
            .finally(() => this.inspections.delete(threadId));
        this.inspections.set(threadId, inspection);
        return inspection;
    }

    handleRawMessage(rawMessage) {
        try {
            this.handleMessage(JSON.parse(rawMessage));
        } catch (error) {
            this.log("warn", `Skipped App Server message: ${errorText(error)}`);
        }
    }

    handleMessage(message) {
        if (!message || typeof message !== "object") {
            return;
        }
        if (message.method && Object.hasOwn(message, "id")) {
            return;
        }
        if (Object.hasOwn(message, "id")) {
            const pending = this.requests.get(String(message.id));
            if (!pending) {
                return;
            }
            this.requests.delete(String(message.id));
            clearTimeout(pending.timeout);
            if (message.error) {
                pending.reject(new Error(`${pending.method}: ${errorText(message.error)}`));
            } else {
                pending.resolve(message.result);
            }
            return;
        }
        this.handleNotification(message.method, message.params);
    }

    handleNotification(method, params) {
        if (method === "thread/started" && params?.thread?.id) {
            const thread = params.thread;
            this.state.metadata.set(thread.id, thread);
            if (isEligibleThread(thread)) {
                this.applyStatus(thread.id, thread.status);
            }
        } else if (method === "thread/status/changed" && params?.status?.type) {
            const metadata = this.state.metadata.get(params.threadId);
            if (metadata && isEligibleThread(metadata)) {
                this.applyStatus(params.threadId, params.status);
            } else if (!metadata && typeof params.threadId === "string") {
                const queued = this.pendingStatuses.get(params.threadId) || [];
                queued.push(params.status);
                this.pendingStatuses.set(params.threadId, queued.slice(-8));
                void this.inspect(params.threadId).catch((error) =>
                    this.log("warn", `Thread inspection failed: ${errorText(error)}`),
                );
            }
        } else if (
            ["thread/closed", "thread/archived", "thread/deleted"].includes(method)
        ) {
            this.prune(params?.threadId);
        }
    }

    applyStatus(threadId, status) {
        if (!status?.type) {
            return;
        }
        const previous = this.state.statuses.get(threadId);
        const flags = waitingFlags(status);
        const isWaiting = flags.size > 0;
        const wasWaiting = this.state.waiting.get(threadId) || false;
        this.state.statuses.set(threadId, status);
        this.state.waiting.set(threadId, isWaiting);

        if (status.type !== "idle") {
            this.cancelIdle(threadId);
        }
        if (isWaiting && !wasWaiting) {
            const detail = flags.has("waitingOnUserInput")
                ? "Input required"
                : "Permission required";
            this.emit(threadId, "interaction", detail);
        }
        if (status.type === "idle" && previous?.type === "active") {
            this.cancelIdle(threadId);
            const timer = setTimeout(() => {
                this.state.idleTimers.delete(threadId);
                if (this.state.statuses.get(threadId)?.type === "idle") {
                    this.emit(threadId, "idle");
                }
            }, this.idleDelayMs);
            this.state.idleTimers.set(threadId, timer);
        }
    }

    emit(threadId, event, detail = "") {
        const notification = buildNotification({
            event,
            detail,
            metadata: this.state.metadata.get(threadId),
        });
        Promise.resolve()
            .then(() => this.notify(notification))
            .catch((error) =>
                this.log("error", `push-notify failed: ${errorText(error)}`),
            );
    }

    cancelIdle(threadId) {
        const timer = this.state.idleTimers.get(threadId);
        if (timer) {
            clearTimeout(timer);
            this.state.idleTimers.delete(threadId);
        }
    }

    prune(threadId) {
        this.cancelIdle(threadId);
        this.state.metadata.delete(threadId);
        this.state.statuses.delete(threadId);
        this.state.waiting.delete(threadId);
        this.pendingStatuses.delete(threadId);
    }

    close(error = new Error("Connection closed")) {
        if (this.closed) {
            return;
        }
        this.closed = true;
        for (const pending of this.requests.values()) {
            clearTimeout(pending.timeout);
            pending.reject(error);
        }
        this.requests.clear();
        for (const threadId of this.state.idleTimers.keys()) {
            this.cancelIdle(threadId);
        }
    }
}

function shellSafe(value) {
    return clean(value).replace(/[^\x20-\x7E]|[%!"^&|<>()]/g, " ");
}

export async function buildPushNotifierInvocation(
    { title, message, sound },
    comSpec = process.env.ComSpec || "cmd.exe",
) {
    const [safeTitle, safeMessage] = await Promise.all([
        sanitizeToAscii(String(title ?? "")),
        sanitizeToAscii(String(message ?? "")),
    ]);
    const argumentsList = ["/d", "/s", "/c", "push-notify.cmd"];
    if (sound) {
        argumentsList.push("--sound", shellSafe(sound));
    }
    argumentsList.push(
        shellSafe(safeTitle.text),
        ...safeMessage.text.split(/\r?\n/).map(shellSafe).filter(Boolean),
    );
    return { filePath: comSpec, argumentsList };
}

function createPushNotifier(log) {
    return async (notification) => {
        const command = await buildPushNotifierInvocation(notification);
        return new Promise((resolve, reject) => {
            const child = spawn(command.filePath, command.argumentsList, {
                windowsHide: true,
                stdio: "ignore",
            });
            const timeout = setTimeout(() => {
                child.kill();
                reject(new Error("push-notify process timed out"));
            }, 10000);
            child.once("error", (error) => {
                clearTimeout(timeout);
                reject(error);
            });
            child.once("exit", (code) => {
                clearTimeout(timeout);
                if (code === 0) {
                    resolve();
                } else {
                    const error = new Error(`push-notify exited with code ${code}`);
                    log("error", error.message);
                    reject(error);
                }
            });
        });
    };
}

function connect(endpoint, timeoutMs = 5000) {
    return new Promise((resolve, reject) => {
        const socket = new WebSocket(endpoint);
        const timeout = setTimeout(() => {
            socket.close();
            reject(new Error(`Timed out connecting to ${endpoint}`));
        }, timeoutMs);
        socket.addEventListener("open", () => {
            clearTimeout(timeout);
            resolve(socket);
        }, { once: true });
        socket.addEventListener("error", () => {
            clearTimeout(timeout);
            reject(new Error(`WebSocket connection failed for ${endpoint}`));
        }, { once: true });
    });
}

async function messageText(data) {
    if (typeof data === "string") {
        return data;
    }
    if (data instanceof Blob) {
        return data.text();
    }
    return Buffer.from(data).toString("utf8");
}

async function openSession(endpoint, state, notify, log, discover) {
    const socket = await connect(endpoint);
    const session = new MonitorSession({
        send: (message) => socket.send(JSON.stringify(message)),
        notify,
        log,
        state,
    });
    const closed = new Promise((resolve) => socket.addEventListener("close", () => {
        session.close();
        resolve();
    }, { once: true }));
    socket.addEventListener("message", (event) => {
        void messageText(event.data)
            .then((text) => session.handleRawMessage(text))
            .catch((error) => log("warn", `Could not read message: ${errorText(error)}`));
    });
    try {
        await session.start({ discover });
        return { socket, closed };
    } catch (error) {
        session.close(error);
        socket.close();
        await closed;
        throw error;
    }
}

export async function runProbe(endpoint = DEFAULT_ENDPOINT) {
    const live = await openSession(
        endpoint,
        new NotificationState(),
        () => {},
        () => {},
        false,
    );
    live.socket.close(1000, "probe complete");
    await live.closed;
}

function delay(milliseconds, signal) {
    return new Promise((resolve) => {
        if (signal?.aborted) {
            resolve();
            return;
        }
        const timer = setTimeout(resolve, milliseconds);
        signal?.addEventListener("abort", () => {
            clearTimeout(timer);
            resolve();
        }, { once: true });
    });
}

export async function runMonitor({ endpoint = DEFAULT_ENDPOINT, signal = null } = {}) {
    const log = (level, message) =>
        process.stdout.write(`${new Date().toISOString()} ${level.toUpperCase()} ${message}\n`);
    const state = new NotificationState();
    const notify = createPushNotifier(log);
    let reconnectAttempt = 0;

    while (!signal?.aborted) {
        try {
            const live = await openSession(endpoint, state, notify, log, true);
            reconnectAttempt = 0;
            log("info", `Connected to Codex App Server at ${endpoint}`);
            const stop = () => live.socket.close(1000, "monitor stopping");
            signal?.addEventListener("abort", stop, { once: true });
            await live.closed;
            signal?.removeEventListener("abort", stop);
        } catch (error) {
            if (!signal?.aborted) {
                log("warn", errorText(error));
            }
        }
        if (!signal?.aborted) {
            await delay(Math.min(30000, 1000 * 2 ** reconnectAttempt++), signal);
        }
    }
}

function parseArguments(argumentsList) {
    const options = { endpoint: DEFAULT_ENDPOINT, probe: false, check: false };
    for (let index = 0; index < argumentsList.length; index++) {
        const argument = argumentsList[index];
        if (argument === "--endpoint") {
            options.endpoint = argumentsList[++index];
        } else if (argument.startsWith("--endpoint=")) {
            options.endpoint = argument.slice("--endpoint=".length);
        } else if (argument === "--probe") {
            options.probe = true;
        } else if (argument === "--check") {
            options.check = true;
        } else {
            throw new Error(`Unknown argument ${argument}`);
        }
    }
    return options;
}

async function main() {
    const options = parseArguments(process.argv.slice(2));
    if (typeof WebSocket !== "function") {
        throw new Error("The installed Node runtime does not provide WebSocket");
    }
    if (options.check) {
        return;
    }
    if (options.probe) {
        await runProbe(options.endpoint);
        return;
    }
    const controller = new AbortController();
    process.once("SIGINT", () => controller.abort());
    process.once("SIGTERM", () => controller.abort());
    await runMonitor({ endpoint: options.endpoint, signal: controller.signal });
}

export function isMainModule(entryPath, moduleUrl, resolvePath = realpathSync) {
    if (!entryPath) {
        return false;
    }
    try {
        return pathToFileURL(resolvePath(entryPath)).href === moduleUrl;
    } catch {
        return false;
    }
}

if (isMainModule(process.argv[1], import.meta.url)) {
    main().catch((error) => {
        process.stderr.write(`${errorText(error)}\n`);
        process.exitCode = 1;
    });
}
