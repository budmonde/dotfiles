import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import { pathToFileURL } from "node:url";

import {
    MonitorSession,
    NotificationState,
    buildNotification,
    buildPushNotifierInvocation,
    isMainModule,
} from "./notification-monitor.mjs";

const tick = () => new Promise((resolve) => setImmediate(resolve));

test("main-module detection resolves a symlinked entrypoint", () => {
    const entryPath = path.resolve("installed", "notification-monitor.mjs");
    const sourcePath = path.resolve("source", "notification-monitor.mjs");
    const sourceUrl = pathToFileURL(sourcePath).href;
    const resolvedPaths = [];

    assert.equal(
        isMainModule(entryPath, sourceUrl, (candidate) => {
            resolvedPaths.push(candidate);
            return sourcePath;
        }),
        true,
    );
    assert.deepEqual(resolvedPaths, [entryPath]);
});

test("main-module detection tolerates a non-file argv entry", () => {
    assert.equal(
        isMainModule("-", import.meta.url, () => {
            throw new Error("not a filesystem entry");
        }),
        false,
    );
});

test("notification invocation passes multiline payloads as safe ASCII arguments", async () => {
    const invocation = await buildPushNotifierInvocation(
        {
            title: "dötfiles & café",
            message: "Session: “Résumé” — work\nEvent: Task completed!",
            sound: "Windows Exclamation",
        },
        "C:\\Windows\\System32\\cmd.exe",
    );

    assert.deepEqual(invocation, {
        filePath: "C:\\Windows\\System32\\cmd.exe",
        argumentsList: [
            "/d",
            "/s",
            "/c",
            "push-notify.cmd",
            "--sound",
            "Windows Exclamation",
            "dotfiles cafe",
            "Session: Resume --- work",
            "Event: Task completed",
        ],
    });
    assert.doesNotMatch(invocation.argumentsList.join(""), /[^\x00-\x7F]/);
});

async function startSession() {
    const outbound = [];
    const notifications = [];
    const logs = [];
    const session = new MonitorSession({
        send: (message) => outbound.push(message),
        notify: (notification) => notifications.push(notification),
        log: (level, message) => logs.push({ level, message }),
        state: new NotificationState(),
    });

    const started = session.start();
    await tick();
    assert.deepEqual(outbound[0], {
        method: "initialize",
        id: 1,
        params: {
            clientInfo: {
                name: "dotfiles_notification_monitor",
                title: "Dotfiles Notification Monitor",
                version: "1.0.0",
            },
            capabilities: {
                experimentalApi: true,
                requestAttestation: false,
            },
        },
    });

    session.handleMessage({ id: 1, result: {} });
    await tick();
    assert.deepEqual(outbound[1], { method: "initialized", params: {} });
    assert.deepEqual(outbound[2], {
        method: "thread/loaded/list",
        id: 2,
        params: {},
    });

    session.handleMessage({
        id: 2,
        result: { data: ["thread-1"], nextCursor: null },
    });
    await tick();
    assert.deepEqual(outbound[3], {
        method: "thread/resume",
        id: 3,
        params: { threadId: "thread-1", excludeTurns: true },
    });

    session.handleMessage({
        id: 3,
        result: {
            sandbox: {
                type: "readOnly",
                networkAccess: false,
            },
            thread: {
                id: "thread-1",
                cwd: "C:\\src\\widget",
                gitInfo: { branch: "main" },
                name: "Widget work",
                preview: "Fallback preview",
            },
        },
    });
    await tick();
    assert.deepEqual(outbound[4], {
        method: "thread/settings/update",
        id: 4,
        params: {
            threadId: "thread-1",
            sandboxPolicy: {
                type: "workspaceWrite",
                writableRoots: [],
                networkAccess: false,
                excludeTmpdirEnvVar: false,
                excludeSlashTmp: false,
            },
        },
    });
    session.handleMessage({ id: 4, result: {} });
    await started;

    return { session, outbound, notifications, logs };
}

test("startup subscribes and normalizes the managed sandbox", async () => {
    const { outbound, logs } = await startSession();
    assert.deepEqual(
        outbound.map(({ method }) => method),
        [
            "initialize",
            "initialized",
            "thread/loaded/list",
            "thread/resume",
            "thread/settings/update",
        ],
    );
    assert.ok(
        logs.some(
            ({ level, message }) =>
                level === "info" && message === "Subscribed to thread thread-1",
        ),
    );
    assert.ok(
        logs.some(
            ({ level, message }) =>
                level === "info" &&
                message === "Applied managed sandbox policy to thread thread-1",
        ),
    );
});

test("successful notification delivery is logged", async () => {
    const { session, logs } = await startSession();

    session.handleMessage({
        method: "turn/completed",
        params: {
            threadId: "thread-1",
            turn: { id: "turn-ok", status: "completed", error: null },
        },
    });
    await tick();

    assert.ok(
        logs.some(
            ({ level, message }) =>
                level === "info" &&
                message === "Notification delivered for thread thread-1: Event: Task completed",
        ),
    );
});

test("server requests notify once and never produce a response", async () => {
    const { session, outbound, notifications } = await startSession();
    const outboundCount = outbound.length;
    const request = {
        method: "item/commandExecution/requestApproval",
        id: 41,
        params: {
            threadId: "thread-1",
            turnId: "turn-1",
            itemId: "item-1",
            command: "Get-ChildItem",
        },
    };

    session.handleMessage(request);
    session.handleMessage(request);

    assert.equal(outbound.length, outboundCount);
    assert.equal(notifications.length, 1);
    assert.deepEqual(notifications[0], {
        title: "widget : main",
        message: "Session: Widget work\nEvent: Permission required",
        sound: "Windows Exclamation",
    });

    session.handleMessage({
        method: "serverRequest/resolved",
        params: { threadId: "thread-1", requestId: 41 },
    });
    assert.equal(session.pendingRequestCount, 0);
    assert.equal(outbound.length, outboundCount);
});

test("input requests notify while auto-review events remain silent", async () => {
    const { session, notifications } = await startSession();

    session.handleMessage({
        method: "item/autoApprovalReview/started",
        params: { threadId: "thread-1", turnId: "turn-1" },
    });
    session.handleMessage({
        method: "item/autoApprovalReview/completed",
        params: { threadId: "thread-1", turnId: "turn-1" },
    });
    session.handleMessage({
        method: "item/tool/requestUserInput",
        id: "request-1",
        params: {
            threadId: "thread-1",
            turnId: "turn-1",
            itemId: "item-1",
            questions: [],
        },
    });
    session.handleMessage({
        method: "mcpServer/elicitation/request",
        id: "request-2",
        params: {
            threadId: "thread-1",
            turnId: "turn-1",
            serverName: "example",
            mode: "form",
            message: "Choose a value",
        },
    });

    assert.deepEqual(
        notifications.map(({ message }) => message),
        ["Event: Input required", "Event: Input required"],
    );
});

test("terminal turn notifications are deduplicated and interruptions are silent", async () => {
    const { session, notifications } = await startSession();

    session.handleMessage({
        method: "turn/completed",
        params: {
            threadId: "thread-1",
            turn: { id: "turn-ok", status: "completed", error: null },
        },
    });
    session.handleMessage({
        method: "turn/completed",
        params: {
            threadId: "thread-1",
            turn: { id: "turn-ok", status: "completed", error: null },
        },
    });
    session.handleMessage({
        method: "turn/completed",
        params: {
            threadId: "thread-1",
            turn: { id: "turn-stop", status: "interrupted", error: null },
        },
    });
    session.handleMessage({
        method: "error",
        params: {
            threadId: "thread-1",
            turnId: "turn-fail",
            willRetry: false,
            error: { message: "tool failed" },
        },
    });
    session.handleMessage({
        method: "turn/completed",
        params: {
            threadId: "thread-1",
            turn: {
                id: "turn-fail",
                status: "failed",
                error: { message: "tool failed" },
            },
        },
    });

    assert.deepEqual(
        notifications.map(({ message }) => message),
        [
            "Session: Widget work\nEvent: Task completed",
            "Session: Widget work\nEvent: Error - tool failed",
        ],
    );
    assert.equal(notifications[1].sound, "Windows Critical Stop");
});

test("retrying errors and malformed or unknown messages do not terminate the session", async () => {
    const { session, notifications, logs } = await startSession();

    assert.doesNotThrow(() => {
        session.handleMessage({
            method: "error",
            params: {
                threadId: "thread-1",
                turnId: "turn-1",
                willRetry: true,
                error: { message: "temporary" },
            },
        });
        session.handleMessage({ method: "turn/completed", params: {} });
        session.handleMessage({ method: "future/event", params: { value: 1 } });
    });

    assert.equal(notifications.length, 0);
    assert.ok(logs.some(({ level }) => level === "warn"));
});

test("notification formatting is bounded", () => {
    const notification = buildNotification({
        metadata: {
            cwd: "C:\\src\\widget",
            gitInfo: { branch: "feature/notifications" },
            name: "A".repeat(300),
        },
        summary: `Event: Error - ${"B".repeat(500)}`,
        sound: "Windows Exclamation",
    });

    assert.ok(notification.title.length <= 100);
    assert.ok(notification.message.length <= 240);
    assert.doesNotMatch(notification.title, /[^\x00-\x7F]/);
    assert.doesNotMatch(notification.message, /[^\x00-\x7F]/);
});

test("client requests time out when an endpoint stops answering", async () => {
    const outbound = [];
    const session = new MonitorSession({
        send: (message) => outbound.push(message),
        notify: () => {},
        log: () => {},
        state: new NotificationState(),
        requestTimeoutMs: 5,
    });

    await assert.rejects(session.start({ discover: false }), /timed out/);
    assert.equal(outbound.length, 1);
});
