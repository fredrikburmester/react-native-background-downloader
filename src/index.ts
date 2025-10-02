import { NativeEventEmitter, Platform } from "react-native";
import DownloadTask from "./DownloadTask";
import NativeRNBackgroundDownloader from "./NativeRNBackgroundDownloader";
import { DownloadOptions } from "./index.d";

const MIN_PROGRESS_INTERVAL = 250;
const tasksMap = new Map<string, DownloadTask>();

const config = {
  headers: {} as Record<string, string>,
  progressInterval: 1000,
  progressMinBytes: 1024 * 1024,
  isLogsEnabled: false,
};

function log(...args: any[]) {
  if (config.isLogsEnabled) {
    console.log("[RNBackgroundDownloader]", ...args);
  }
}

// Create event emitter for the TurboModule
const eventEmitter = new NativeEventEmitter(
  NativeRNBackgroundDownloader as any
);

// Register event listeners
eventEmitter.addListener("downloadBegin", ({ id, ...rest }) => {
  log("downloadBegin event received", id);
  const task = tasksMap.get(id);
  if (task) {
    task.onBegin(rest);
  }
});

eventEmitter.addListener("downloadProgress", (events) => {
  log("downloadProgress event received");
  const eventArray = Array.isArray(events) ? events : [events];

  for (const event of eventArray) {
    const { id, ...rest } = event;
    const task = tasksMap.get(id);
    if (task) {
      task.onProgress(rest);
    }
  }
});

eventEmitter.addListener("downloadComplete", ({ id, ...rest }) => {
  log("downloadComplete event received", id);
  const task = tasksMap.get(id);
  if (task) {
    task.onDone(rest);
  }
  tasksMap.delete(id);
});

eventEmitter.addListener("downloadFailed", ({ id, ...rest }) => {
  log("downloadFailed event received", id);
  const task = tasksMap.get(id);
  if (task) {
    task.onError(rest);
  }
  tasksMap.delete(id);
});

// Notify native that we're listening to events (required for New Architecture)
if (NativeRNBackgroundDownloader.addListener) {
  NativeRNBackgroundDownloader.addListener("downloadBegin");
  NativeRNBackgroundDownloader.addListener("downloadProgress");
  NativeRNBackgroundDownloader.addListener("downloadComplete");
  NativeRNBackgroundDownloader.addListener("downloadFailed");
}

export function setConfig({
  headers,
  progressInterval,
  progressMinBytes,
  isLogsEnabled,
}: {
  headers?: Record<string, string>;
  progressInterval?: number;
  progressMinBytes?: number;
  isLogsEnabled?: boolean;
}) {
  if (typeof headers === "object") {
    config.headers = headers;
  }

  if (progressInterval != null) {
    if (
      typeof progressInterval === "number" &&
      progressInterval >= MIN_PROGRESS_INTERVAL
    ) {
      config.progressInterval = progressInterval;
    } else {
      console.warn(
        `[RNBackgroundDownloader] progressInterval must be a number >= ${MIN_PROGRESS_INTERVAL}`
      );
    }
  }

  if (progressMinBytes != null) {
    if (typeof progressMinBytes === "number" && progressMinBytes >= 0) {
      config.progressMinBytes = progressMinBytes;
    } else {
      console.warn(
        `[RNBackgroundDownloader] progressMinBytes must be a number >= 0`
      );
    }
  }

  if (typeof isLogsEnabled === "boolean") {
    config.isLogsEnabled = isLogsEnabled;
  }
}

export async function checkForExistingDownloads(): Promise<DownloadTask[]> {
  log("checkForExistingDownloads");

  try {
    const foundTasks =
      await NativeRNBackgroundDownloader.checkForExistingDownloads();
    log("checkForExistingDownloads found", foundTasks.length, "tasks");

    return foundTasks
      .map((taskInfo) => {
        const existingTask = tasksMap.get(taskInfo.id);
        const task = new DownloadTask(taskInfo, existingTask);

        // Map native states to our state names
        if (taskInfo.state === 0) {
          task.state = "DOWNLOADING";
        } else if (taskInfo.state === 1) {
          task.state = "PAUSED";
        } else if (taskInfo.state === 2) {
          return null; // Canceling
        } else if (taskInfo.state === 3) {
          if (
            taskInfo.bytesTotal <= 0 ||
            taskInfo.bytesDownloaded === taskInfo.bytesTotal
          ) {
            task.state = "DONE";
          } else {
            return null;
          }
        }

        tasksMap.set(taskInfo.id, task);
        return task;
      })
      .filter((task): task is DownloadTask => task !== null);
  } catch (error) {
    console.error(
      "[RNBackgroundDownloader] Error in checkForExistingDownloads:",
      error
    );
    return [];
  }
}

export async function ensureDownloadsAreRunning() {
  log("ensureDownloadsAreRunning");
  const tasks = await checkForExistingDownloads();
  for (const task of tasks) {
    if (task.state === "DOWNLOADING") {
      task.pause();
      task.resume();
    }
  }
}

export function completeHandler(jobId: string) {
  try {
    return NativeRNBackgroundDownloader.completeHandler(jobId);
  } catch (error) {
    console.error("[RNBackgroundDownloader] Error in completeHandler:", error);
  }
}

export function download(options: DownloadOptions): DownloadTask {
  log("download called", options.id);

  if (!options.id || !options.url || !options.destination) {
    throw new Error(
      "[RNBackgroundDownloader] id, url and destination are required"
    );
  }

  const headers: Record<string, string> = {};
  Object.entries({ ...config.headers, ...options.headers }).forEach(
    ([key, value]) => {
      if (value != null) {
        headers[key] = value;
      }
    }
  );

  const metadata =
    options.metadata && typeof options.metadata === "object"
      ? options.metadata
      : {};

  const destination = options.destination.replace("file://", "");

  const isAllowedOverRoaming = options.isAllowedOverRoaming ?? true;
  const isAllowedOverMetered = options.isAllowedOverMetered ?? true;
  const isNotificationVisible = options.isNotificationVisible ?? false;

  const task = new DownloadTask({
    id: options.id,
    metadata: metadata,
    bytesDownloaded: 0,
    bytesTotal: 0,
  });

  tasksMap.set(options.id, task);

  try {
    NativeRNBackgroundDownloader.downloadFile(
      options.url,
      destination,
      options.id,
      headers as Object,
      JSON.stringify(metadata),
      config.progressInterval,
      config.progressMinBytes,
      isAllowedOverRoaming,
      isAllowedOverMetered,
      isNotificationVisible,
      options.notificationTitle || ""
    );
  } catch (error: any) {
    console.error("[RNBackgroundDownloader] Error in download:", error);
    task.onError({ error: error.message || "Download failed to start" });
  }

  return task;
}

export const directories = {
  documents: Platform.select({
    ios: "/tmp/documents",
    android: "/tmp/documents",
    default: "/tmp/documents",
  }),
};

export default {
  download,
  checkForExistingDownloads,
  ensureDownloadsAreRunning,
  completeHandler,
  setConfig,
  directories,
};
