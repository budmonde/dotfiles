import { spawn } from "node:child_process";
import { realpathSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

import gitHookHelpers from "../../git/hooks/lib.js";

const { sanitizeToAscii } = gitHookHelpers;

const APPROVAL_METHODS = new Set([
    "item/commandExecution/requestApproval",
    "item/fileChange/requestApproval",
    "item/permissions/requestApproval",
]);
const INPUT_METHODS = new Set([
    "item/tool/requestUserInput",
    "mcpServer/elicitation/request",
]);
const AUTO_REVIEW_METHODS = new Set([
    "item/autoApprovalReview/started",
    "item/autoApprovalReview/completed",
]);
const ALLOWED_REQUEST_METHODS = new Set([
    "initialize",
    "thread/loaded/list",
    "thread/resume",
    "thread/settings/update",
]);
const MANAGED_SANDBOX_POLICY = {
    type: "workspaceWrite",
    writableRoots: [],
    networkAccess: false,
    excludeTmpdirEnvVar: false,
    excludeSlashTmp: false,
};
const DEFAULT_ENDPOINT = "ws://127.0.0.1:4500";
const CLIENT_INFO = {
    name: "dotfiles_notification_monitor",
    title: "Dotfiles Notification Monitor",
    version: "1.0.0",
};

function compactText(value) {
    return String(value ?? "").replace(/\s+/g, " ").trim();
}

function truncate(value, limit) {
    const text = compactText(value);
    return text.length <= limit ? text : `${text.slice(0, limit - 3)}...`;
}

function truncateLines(value, limit) {
    const text = String(value ?? "")
        .replace(/\r\n?/g, "\n")
        .split("\n")
        .map((line) => compactText(line))
        .filter(Boolean)
        .join("\n");
    return text.length <= limit ? text : `${text.slice(0, limit - 3)}...`;
}

function threadLabel(metadata) {
    return truncate(metadata?.name || metadata?.preview || "unknown", 100);
}

function errorMessage(error) {
    if (typeof error === "string") {
        return error;
    }
    return error?.message || error?.additionalDetails || "Unknown failure";
}

function errorSummary(error) {
    const message = compactText(errorMessage(error));
    const bounded = message.length > 80 ? `${message.slice(0, 80)}...` : message;
    return `Event: Error - ${bounded}`;
}

export function buildNotification({ metadata = {}, summary, sound, includeSession = true }) {
    const cwd = metadata.cwd || "";
    const directory = path.basename(cwd) || "Codex";
    const branch = metadata.gitInfo?.branch;
    const title = truncate(branch ? `${directory} : ${branch}` : directory, 100);
    const message = truncateLines(
        includeSession ? `Session: ${threadLabel(metadata)}\n${summary}` : summary,
        240,
    );
    return { title, message, ...(sound ? { sound } : {}) };
}

export class NotificationState {
    constructor() {
        this.terminalTurns = new Set();
        this.threadMetadata = new Map();
    }
}

export class MonitorSession {
    constructor({ send, notify, log, state, requestTimeoutMs = 10000 }) {
        this.send = send;
        this.notify = notify;
        this.log = log;
        this.state = state;
        this.nextRequestId = 1;
        this.pendingClientRequests = new Map();
        this.pendingServerRequests = new Map();
        this.seenServerRequests = new Set();
        this.subscribedThreads = new Set();
        this.discoveryPromise = null;
        this.closed = false;
        this.requestTimeoutMs = requestTimeoutMs;
    }

    get pendingRequestCount() {
        return this.pendingServerRequests.size;
    }

    async start({ discover = true } = {}) {
        await this.request("initialize", {
            clientInfo: CLIENT_INFO,
            capabilities: {
                experimentalApi: true,
                requestAttestation: false,
            },
        });
        this.sendInitialized();
        if (discover) {
            await this.discoverLoadedThreads();
        }
    }

    request(method, params) {
        if (!ALLOWED_REQUEST_METHODS.has(method)) {
            throw new Error(`Passive monitor cannot send request method ${method}`);
        }
        if (this.closed) {
            return Promise.reject(new Error("Connection is closed"));
        }

        const id = this.nextRequestId++;
        const response = new Promise((resolve, reject) => {
            const timeout = setTimeout(() => {
                this.pendingClientRequests.delete(String(id));
                reject(new Error(`${method}: timed out waiting for App Server response`));
            }, this.requestTimeoutMs);
            this.pendingClientRequests.set(String(id), { resolve, reject, method, timeout });
        });
        this.send({ method, id, params });
        return response;
    }

    sendInitialized() {
        if (this.closed) {
            throw new Error("Connection is closed");
        }
        this.send({ method: "initialized", params: {} });
    }

    async discoverLoadedThreads() {
        if (this.discoveryPromise) {
            return this.discoveryPromise;
        }

        this.discoveryPromise = this.discoverLoadedThreadsInternal().finally(() => {
            this.discoveryPromise = null;
        });
        return this.discoveryPromise;
    }

    async discoverLoadedThreadsInternal() {
        let cursor = null;
        do {
            const params = cursor ? { cursor } : {};
            const result = await this.request("thread/loaded/list", params);
            if (!Array.isArray(result?.data)) {
                throw new Error("thread/loaded/list returned malformed data");
            }
            await Promise.all(result.data.map((threadId) => this.subscribe(threadId)));
            cursor = result.nextCursor || null;
        } while (cursor);
    }

    async subscribe(threadId) {
        if (typeof threadId !== "string" || this.subscribedThreads.has(threadId)) {
            return;
        }

        this.subscribedThreads.add(threadId);
        try {
            const result = await this.request("thread/resume", {
                threadId,
                excludeTurns: true,
            });
            if (result?.thread?.id) {
                if (result.sandbox?.type !== "workspaceWrite") {
                    await this.request("thread/settings/update", {
                        threadId,
                        sandboxPolicy: MANAGED_SANDBOX_POLICY,
                    });
                    this.log("info", `Applied managed sandbox policy to thread ${threadId}`);
                }
                this.state.threadMetadata.set(result.thread.id, result.thread);
                this.log("info", `Subscribed to thread ${result.thread.id}`);
            } else {
                this.log("warn", `thread/resume returned no metadata for ${threadId}`);
            }
        } catch (error) {
            this.subscribedThreads.delete(threadId);
            throw error;
        }
    }

    handleRawMessage(rawMessage) {
        try {
            this.handleMessage(JSON.parse(rawMessage));
        } catch (error) {
            this.log("warn", `Skipped malformed App Server message: ${error.message}`);
        }
    }

    handleMessage(message) {
        if (!message || typeof message !== "object") {
            this.log("warn", "Skipped non-object App Server message");
            return;
        }

        if (message.method && Object.hasOwn(message, "id")) {
            this.handleServerRequest(message);
            return;
        }
        if (Object.hasOwn(message, "id")) {
            this.handleClientResponse(message);
            return;
        }
        if (typeof message.method === "string") {
            this.handleNotification(message);
            return;
        }
        this.log("warn", "Skipped unrecognized App Server message shape");
    }

    handleClientResponse(message) {
        const pending = this.pendingClientRequests.get(String(message.id));
        if (!pending) {
            this.log("debug", `Ignored response for unknown request ${message.id}`);
            return;
        }

        this.pendingClientRequests.delete(String(message.id));
        clearTimeout(pending.timeout);
        if (message.error) {
            pending.reject(new Error(`${pending.method}: ${errorMessage(message.error)}`));
        } else {
            pending.resolve(message.result);
        }
    }

    handleServerRequest(message) {
        const requestKey = String(message.id);
        if (this.seenServerRequests.has(requestKey)) {
            return;
        }
        this.seenServerRequests.add(requestKey);

        const params = message.params;
        if (!params || typeof params.threadId !== "string") {
            this.log("warn", `Skipped malformed server request ${message.method}`);
            return;
        }

        let summary;
        let includeSession = true;
        if (APPROVAL_METHODS.has(message.method)) {
            summary = "Event: Permission required";
        } else if (INPUT_METHODS.has(message.method)) {
            summary = "Event: Input required";
            includeSession = false;
        } else {
            this.log("debug", `Observed unsupported server request ${message.method}`);
            return;
        }

        this.pendingServerRequests.set(requestKey, {
            threadId: params.threadId,
            turnId: params.turnId || null,
            itemId: params.itemId || null,
        });
        this.dispatch(params.threadId, summary, "Windows Exclamation", includeSession);
    }

    handleNotification(message) {
        if (AUTO_REVIEW_METHODS.has(message.method)) {
            return;
        }

        switch (message.method) {
            case "serverRequest/resolved":
                this.handleResolvedRequest(message.params);
                break;
            case "turn/completed":
                this.handleTurnCompleted(message.params);
                break;
            case "error":
                this.handleError(message.params);
                break;
            case "thread/name/updated":
                this.handleThreadNameUpdated(message.params);
                break;
            default:
                break;
        }
    }

    handleResolvedRequest(params) {
        if (!params || !Object.hasOwn(params, "requestId")) {
            this.log("warn", "Skipped malformed serverRequest/resolved notification");
            return;
        }
        this.pendingServerRequests.delete(String(params.requestId));
    }

    handleTurnCompleted(params) {
        const threadId = params?.threadId;
        const turn = params?.turn;
        if (typeof threadId !== "string" || typeof turn?.id !== "string" || !turn.status) {
            this.log("warn", "Skipped malformed turn/completed notification");
            return;
        }

        const turnKey = `${threadId}:${turn.id}`;
        if (this.state.terminalTurns.has(turnKey)) {
            return;
        }
        this.state.terminalTurns.add(turnKey);

        if (turn.status === "completed") {
            this.dispatch(threadId, "Event: Task completed");
        } else if (turn.status === "failed") {
            this.dispatch(
                threadId,
                errorSummary(turn.error),
                "Windows Critical Stop",
            );
        } else if (turn.status !== "interrupted") {
            this.log("warn", `Unknown terminal turn status ${turn.status}`);
        }
    }

    handleError(params) {
        if (
            typeof params?.threadId !== "string" ||
            typeof params?.turnId !== "string" ||
            !params.error
        ) {
            this.log("warn", "Skipped malformed error notification");
            return;
        }
        if (params.willRetry) {
            this.log("info", `Turn ${params.turnId} reported a retryable error`);
            return;
        }

        const turnKey = `${params.threadId}:${params.turnId}`;
        if (this.state.terminalTurns.has(turnKey)) {
            return;
        }
        this.state.terminalTurns.add(turnKey);
        this.dispatch(
            params.threadId,
            errorSummary(params.error),
            "Windows Critical Stop",
        );
    }

    handleThreadNameUpdated(params) {
        if (typeof params?.threadId !== "string") {
            return;
        }
        const current = this.state.threadMetadata.get(params.threadId) || {
            id: params.threadId,
        };
        this.state.threadMetadata.set(params.threadId, {
            ...current,
            name: params.threadName || null,
        });
    }

    dispatch(threadId, summary, sound, includeSession = true) {
        const metadata = this.state.threadMetadata.get(threadId) || {};
        const notification = buildNotification({ metadata, summary, sound, includeSession });
        Promise.resolve(this.notify(notification))
            .then(() => {
                this.log("info", `Notification delivered for thread ${threadId}: ${summary}`);
            })
            .catch((error) => {
                this.log("error", `push-notify failed: ${error.message}`);
            });
    }

    close(error = new Error("Connection closed")) {
        if (this.closed) {
            return;
        }
        this.closed = true;
        for (const pending of this.pendingClientRequests.values()) {
            clearTimeout(pending.timeout);
            pending.reject(error);
        }
        this.pendingClientRequests.clear();
        this.pendingServerRequests.clear();
        this.seenServerRequests.clear();
        this.subscribedThreads.clear();
    }
}

function createLogger() {
    return (level, message) => {
        process.stdout.write(`${new Date().toISOString()} ${level.toUpperCase()} ${message}\n`);
    };
}

function shellSafeText(value) {
    return compactText(value)
        .replace(/[^\x20-\x7E]|[%!"^&|<>()]/g, " ")
        .replace(/\s+/g, " ")
        .trim();
}

export async function buildPushNotifierInvocation(
    { title, message, sound },
    comSpec = process.env.ComSpec || "cmd.exe",
) {
    const argumentsList = ["/d", "/s", "/c", "push-notify.cmd"];
    if (sound) {
        const normalizedSound = await sanitizeToAscii(String(sound));
        argumentsList.push("--sound", shellSafeText(normalizedSound.text));
    }
    const [normalizedTitle, normalizedMessage] = await Promise.all([
        sanitizeToAscii(String(title ?? "")),
        sanitizeToAscii(String(message ?? "")),
    ]);
    const messageLines = normalizedMessage.text
        .split(/\r?\n/)
        .map((line) => shellSafeText(line))
        .filter(Boolean);
    argumentsList.push(shellSafeText(normalizedTitle.text), ...messageLines);
    return { filePath: comSpec, argumentsList };
}

function createPushNotifier(log) {
    return async (notification) => {
        const invocation = await buildPushNotifierInvocation(notification);
        return new Promise((resolve, reject) => {
            const child = spawn(invocation.filePath, invocation.argumentsList, {
                windowsHide: true,
                stdio: "ignore",
            });
            child.once("error", reject);
            child.once("exit", (code) => {
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

function connectWebSocket(endpoint, timeoutMs = 5000) {
    return new Promise((resolve, reject) => {
        const socket = new WebSocket(endpoint);
        const timeout = setTimeout(() => {
            socket.close();
            reject(new Error(`Timed out connecting to ${endpoint}`));
        }, timeoutMs);
        socket.addEventListener(
            "open",
            () => {
                clearTimeout(timeout);
                resolve(socket);
            },
            { once: true },
        );
        socket.addEventListener(
            "error",
            () => {
                clearTimeout(timeout);
                reject(new Error(`WebSocket connection failed for ${endpoint}`));
            },
            { once: true },
        );
    });
}

function rawMessageText(data) {
    if (typeof data === "string") {
        return Promise.resolve(data);
    }
    if (data instanceof Blob) {
        return data.text();
    }
    if (data instanceof ArrayBuffer) {
        return Promise.resolve(Buffer.from(data).toString("utf8"));
    }
    return Promise.resolve(String(data));
}

async function createLiveSession(
    endpoint,
    state,
    notify,
    log,
    discover,
    requestTimeoutMs = 10000,
) {
    const socket = await connectWebSocket(endpoint);
    const session = new MonitorSession({
        send: (message) => socket.send(JSON.stringify(message)),
        notify,
        log,
        state,
        requestTimeoutMs,
    });
    const closed = new Promise((resolve) => {
        socket.addEventListener(
            "close",
            () => {
                session.close();
                resolve();
            },
            { once: true },
        );
    });
    socket.addEventListener("message", (event) => {
        rawMessageText(event.data)
            .then((text) => session.handleRawMessage(text))
            .catch((error) => log("warn", `Could not read App Server message: ${error.message}`));
    });
    await session.start({ discover });
    return { socket, session, closed };
}

export async function runProbe(endpoint = DEFAULT_ENDPOINT) {
    if (typeof WebSocket !== "function") {
        throw new Error("The installed Node runtime does not provide WebSocket");
    }
    const log = () => {};
    const live = await createLiveSession(
        endpoint,
        new NotificationState(),
        () => {},
        log,
        false,
        3000,
    );
    live.socket.close(1000, "probe complete");
    await live.closed;
}

function delay(milliseconds) {
    return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

export async function runMonitor({
    endpoint = DEFAULT_ENDPOINT,
    discoveryIntervalMs = 500,
    signal = null,
} = {}) {
    if (typeof WebSocket !== "function") {
        throw new Error("The installed Node runtime does not provide WebSocket");
    }

    const log = createLogger();
    const notify = createPushNotifier(log);
    const state = new NotificationState();
    let reconnectAttempt = 0;

    while (!signal?.aborted) {
        let pollTimer;
        try {
            const live = await createLiveSession(endpoint, state, notify, log, true);
            reconnectAttempt = 0;
            log("info", `Connected to Codex App Server at ${endpoint}`);
            const abortHandler = () => live.socket.close(1000, "monitor stopping");
            signal?.addEventListener("abort", abortHandler, { once: true });
            pollTimer = setInterval(() => {
                live.session.discoverLoadedThreads().catch((error) => {
                    log("warn", `Thread discovery failed: ${error.message}`);
                });
            }, discoveryIntervalMs);
            await live.closed;
            signal?.removeEventListener("abort", abortHandler);
            clearInterval(pollTimer);
            if (signal?.aborted) {
                break;
            }
            log("warn", "Codex App Server connection closed");
        } catch (error) {
            if (pollTimer) {
                clearInterval(pollTimer);
            }
            if (signal?.aborted) {
                break;
            }
            log("warn", error.message);
        }

        const baseDelay = Math.min(30000, 1000 * 2 ** reconnectAttempt++);
        const jitter = Math.floor(Math.random() * Math.min(1000, baseDelay / 4));
        await delay(baseDelay + jitter);
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
    if (options.check) {
        if (typeof WebSocket !== "function") {
            throw new Error("The installed Node runtime does not provide WebSocket");
        }
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

const isMain = isMainModule(process.argv[1], import.meta.url);
if (isMain) {
    main().catch((error) => {
        process.stderr.write(`${error.message}\n`);
        process.exitCode = 1;
    });
}
