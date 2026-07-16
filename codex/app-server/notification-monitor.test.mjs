import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
    DEFAULT_ENDPOINT,
    MonitorSession,
    NotificationState,
    buildNotification,
    buildPushNotifierInvocation,
} from "./notification-monitor.mjs";

const delay = (milliseconds) =>
    new Promise((resolve) => setTimeout(resolve, milliseconds));

function rootThread(status = { type: "idle" }) {
    return {
        id: "thread-1",
        parentThreadId: null,
        threadSource: "user",
        cwd: "C:\\src\\widget",
        gitInfo: { branch: "main" },
        name: "Widget work",
        status,
    };
}

async function createSession({ discover = false, idleDelayMs = 5, notify = null } = {}) {
    const outbound = [];
    const notifications = [];
    const logs = [];
    let session;
    session = new MonitorSession({
        send: (message) => {
            outbound.push(message);
            queueMicrotask(() => {
                if (message.method === "initialize") {
                    session.handleMessage({ id: message.id, result: {} });
                } else if (message.method === "thread/loaded/list") {
                    session.handleMessage({
                        id: message.id,
                        result: { data: ["thread-1"], nextCursor: null },
                    });
                } else if (message.method === "thread/read") {
                    session.handleMessage({
                        id: message.id,
                        result: { thread: rootThread() },
                    });
                }
            });
        },
        notify: notify || ((notification) => notifications.push(notification)),
        log: (level, message) => logs.push({ level, message }),
        state: new NotificationState(),
        idleDelayMs,
        requestTimeoutMs: 100,
    });
    await session.start({ discover });
    return { session, outbound, notifications, logs };
}

test("the monitor uses the loopback WebSocket endpoint", () => {
    assert.equal(DEFAULT_ENDPOINT, "ws://127.0.0.1:4500");
});

test("startup performs one passive discovery and establishes idle as baseline", async () => {
    const { session, outbound, notifications } = await createSession({ discover: true });
    assert.deepEqual(
        outbound.map(({ method }) => method),
        ["initialize", "initialized", "thread/loaded/list", "thread/read"],
    );
    assert.equal(notifications.length, 0);
    session.close();
});

test("a waiting epoch emits one interaction notification", async () => {
    const { session, notifications } = await createSession();
    session.handleMessage({
        method: "thread/started",
        params: { thread: rootThread({ type: "active", activeFlags: [] }) },
    });
    for (let count = 0; count < 2; count++) {
        session.handleMessage({
            method: "thread/status/changed",
            params: {
                threadId: "thread-1",
                status: { type: "active", activeFlags: ["waitingOnApproval"] },
            },
        });
    }
    await delay(1);
    assert.deepEqual(notifications.map(({ event }) => event), ["interaction"]);

    session.handleMessage({
        method: "thread/status/changed",
        params: {
            threadId: "thread-1",
            status: { type: "active", activeFlags: [] },
        },
    });
    session.handleMessage({
        method: "thread/status/changed",
        params: {
            threadId: "thread-1",
            status: { type: "active", activeFlags: ["waitingOnUserInput"] },
        },
    });
    await delay(1);
    assert.deepEqual(
        notifications.map(({ event }) => event),
        ["interaction", "interaction"],
    );
    session.close();
});

test("active to idle emits one idle notification", async () => {
    const { session, notifications } = await createSession();
    session.handleMessage({
        method: "thread/started",
        params: { thread: rootThread({ type: "active", activeFlags: [] }) },
    });
    for (let count = 0; count < 2; count++) {
        session.handleMessage({
            method: "thread/status/changed",
            params: { threadId: "thread-1", status: { type: "idle" } },
        });
    }
    await delay(10);
    assert.deepEqual(notifications.map(({ event }) => event), ["idle"]);
    session.close();
});

test("a new active transition cancels a pending idle notification", async () => {
    const { session, notifications } = await createSession({ idleDelayMs: 15 });
    session.handleMessage({
        method: "thread/started",
        params: { thread: rootThread({ type: "active", activeFlags: [] }) },
    });
    session.handleMessage({
        method: "thread/status/changed",
        params: { threadId: "thread-1", status: { type: "idle" } },
    });
    session.handleMessage({
        method: "thread/status/changed",
        params: {
            threadId: "thread-1",
            status: { type: "active", activeFlags: [] },
        },
    });
    await delay(20);
    assert.equal(notifications.length, 0);
    session.close();
});

test("unknown child-thread status is inspected and ignored", async () => {
    const { session, outbound, notifications } = await createSession();
    session.handleMessage({
        method: "thread/status/changed",
        params: {
            threadId: "child-1",
            status: { type: "active", activeFlags: ["waitingOnApproval"] },
        },
    });
    const read = outbound.at(-1);
    assert.equal(read.method, "thread/read");
    session.handleMessage({
        id: read.id,
        result: {
            thread: {
                ...rootThread(),
                id: "child-1",
                parentThreadId: "thread-1",
                threadSource: "subagent",
            },
        },
    });
    await delay(1);
    assert.equal(notifications.length, 0);
    session.close();
});

test("server requests are ignored", async () => {
    const { session, outbound, notifications } = await createSession();
    const outboundCount = outbound.length;
    session.handleMessage({
        id: 41,
        method: "item/commandExecution/requestApproval",
        params: { threadId: "thread-1" },
    });
    assert.equal(outbound.length, outboundCount);
    assert.equal(notifications.length, 0);
    session.close();
});

test("notifier failure is logged outside status dispatch", async () => {
    const { session, logs } = await createSession({
        notify: () => {
            throw new Error("toast unavailable");
        },
    });
    session.handleMessage({
        method: "thread/started",
        params: { thread: rootThread({ type: "active", activeFlags: [] }) },
    });
    assert.doesNotThrow(() => session.handleMessage({
        method: "thread/status/changed",
        params: {
            threadId: "thread-1",
            status: { type: "active", activeFlags: ["waitingOnApproval"] },
        },
    }));
    await delay(1);
    assert.ok(logs.some(({ level, message }) =>
        level === "error" && message.includes("toast unavailable"),
    ));
    session.close();
});

test("notification formatting supports exactly interaction and idle", () => {
    const interaction = buildNotification({
        event: "interaction",
        metadata: rootThread(),
        detail: "Permission required",
    });
    const idle = buildNotification({ event: "idle", metadata: rootThread() });
    assert.match(interaction.message, /Interaction required: Permission required/);
    assert.match(idle.message, /Codex is idle/);
    assert.throws(() => buildNotification({ event: "failed" }), /Unsupported/);
    assert.ok(interaction.title.length <= 100);
    assert.ok(interaction.message.length <= 240);
});

test("notifier arguments are bounded to safe ASCII command arguments", async () => {
    const invocation = await buildPushNotifierInvocation({
        title: "Widget & branch",
        message: "Interaction required: approve (now)",
        sound: "Windows Exclamation",
    });
    assert.equal(invocation.argumentsList[0], "/d");
    assert.equal(invocation.argumentsList[3], "push-notify.cmd");
    assert.doesNotMatch(invocation.argumentsList.join(" "), /[&()]/);
});

test("the implementation has no subscription, history, goal, health, or proxy machinery", async () => {
    const source = await readFile(new URL("./notification-monitor.mjs", import.meta.url), "utf8");
    for (const forbidden of [
        "thread/resume",
        "thread/unsubscribe",
        "thread/turns/list",
        "thread/goal",
        "thread/settings/update",
        "ProxiedWebSocket",
        "healthFile",
    ]) {
        assert.doesNotMatch(source, new RegExp(forbidden.replace("/", "\\/")));
    }
});
