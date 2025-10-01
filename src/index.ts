import { NativeModules, NativeEventEmitter } from "react-native";
import DownloadTask from "./DownloadTask";
import NativeRNBackgroundDownloader from "./NativeRNBackgroundDownloader";
import { DownloadOptions } from "./index.d";

const { RNBackgroundDownloader } = NativeModules;

// CRITICAL FIX: Use RNBackgroundDownloader (from NativeModules) for event emitter
// This is the actual module that emits events, not the TurboModule spec
let RNBackgroundDownloaderEmitter;
try {
  // Try NativeRNBackgroundDownloader first (new arch), fallback to RNBackgroundDownloader (old arch)
  const nativeModule = NativeRNBackgroundDownloader || RNBackgroundDownloader;

  if (nativeModule) {
    console.log(
      "[RNBackgroundDownloader] Creating event emitter from native module"
    );
    RNBackgroundDownloaderEmitter = new NativeEventEmitter(nativeModule);
    console.log("[RNBackgroundDownloader] Event emitter created successfully");
  } else {
    console.warn(
      "[RNBackgroundDownloader] Native module not available for event emitter, using mock"
    );
    // Create a mock event emitter to prevent crashes
    RNBackgroundDownloaderEmitter = {
      addListener: () => ({ remove: () => {} }),
      removeAllListeners: () => {},
      removeSubscription: () => {},
    };
  }
} catch (error) {
  console.warn(
    "[RNBackgroundDownloader] Failed to create event emitter:",
    error.message || error
  );
  // Create a mock event emitter as fallback
  RNBackgroundDownloaderEmitter = {
    addListener: () => ({ remove: () => {} }),
    removeAllListeners: () => {},
    removeSubscription: () => {},
  };
}

const MIN_PROGRESS_INTERVAL = 250;
const tasksMap = new Map();

const config = {
  headers: {},
  progressInterval: 1000,
  progressMinBytes: 1024 * 1024, // 1MB default
  isLogsEnabled: false,
};

function log(...args) {
  if (config.isLogsEnabled) console.log("[RNBackgroundDownloader]", ...args);
}

console.log("[RNBackgroundDownloader] Registering downloadBegin listener");
RNBackgroundDownloaderEmitter.addListener(
  "downloadBegin",
  ({ id, ...rest }) => {
    log("[RNBackgroundDownloader] downloadBegin event received", {
      id,
      hasTask: tasksMap.has(id),
      totalTasks: tasksMap.size,
    });
    const task = tasksMap.get(id);
    if (task) {
      task.onBegin(rest);
    } else {
      console.warn(
        `[RNBackgroundDownloader] downloadBegin: No task found for id "${id}". ` +
          `This might happen if the download started before JS initialized. ` +
          `Current tasks in map: [${Array.from(tasksMap.keys()).join(", ")}]`
      );
    }
  }
);
console.log("[RNBackgroundDownloader] downloadBegin listener registered");

console.log("[RNBackgroundDownloader] Registering downloadProgress listener");
RNBackgroundDownloaderEmitter.addListener("downloadProgress", (events) => {
  log("[RNBackgroundDownloader] downloadProgress event received", {
    isArray: Array.isArray(events),
    eventCount: Array.isArray(events) ? events.length : "not an array",
    totalTasks: tasksMap.size,
  });

  // Ensure events is always an array
  const eventArray = Array.isArray(events) ? events : [events];

  for (const event of eventArray) {
    const { id, ...rest } = event;
    const task = tasksMap.get(id);
    if (task) {
      log("[RNBackgroundDownloader] Firing progress for task", id, rest);
      task.onProgress(rest);
    } else {
      log(
        `[RNBackgroundDownloader] downloadProgress: No task found for id "${id}"`
      );
    }
  }
});
console.log("[RNBackgroundDownloader] downloadProgress listener registered");

console.log("[RNBackgroundDownloader] Registering downloadComplete listener");
RNBackgroundDownloaderEmitter.addListener(
  "downloadComplete",
  ({ id, ...rest }) => {
    log("[RNBackgroundDownloader] downloadComplete event received", {
      id,
      hasTask: tasksMap.has(id),
      totalTasks: tasksMap.size,
    });
    const task = tasksMap.get(id);
    if (task) {
      task.onDone(rest);
    } else {
      console.warn(
        `[RNBackgroundDownloader] downloadComplete: No task found for id "${id}". ` +
          `This might happen if the download completed before JS initialized or after task was removed.`
      );
    }

    tasksMap.delete(id);
  }
);
console.log("[RNBackgroundDownloader] downloadComplete listener registered");

console.log("[RNBackgroundDownloader] Registering downloadFailed listener");
RNBackgroundDownloaderEmitter.addListener(
  "downloadFailed",
  ({ id, ...rest }) => {
    log("[RNBackgroundDownloader] downloadFailed event received", {
      id,
      hasTask: tasksMap.has(id),
      error: rest.error,
    });
    const task = tasksMap.get(id);
    if (task) {
      task.onError(rest);
    } else {
      console.warn(
        `[RNBackgroundDownloader] downloadFailed: No task found for id "${id}". Error: ${rest.error}`
      );
    }

    tasksMap.delete(id);
  }
);
console.log("[RNBackgroundDownloader] downloadFailed listener registered");
console.log(
  "[RNBackgroundDownloader] All event listeners registered successfully"
);

export function setConfig({
  headers,
  progressInterval,
  progressMinBytes,
  isLogsEnabled,
}) {
  if (typeof headers === "object") config.headers = headers;

  if (progressInterval != null)
    if (
      typeof progressInterval === "number" &&
      progressInterval >= MIN_PROGRESS_INTERVAL
    )
      config.progressInterval = progressInterval;
    else
      console.warn(
        `[RNBackgroundDownloader] progressInterval must be a number >= ${MIN_PROGRESS_INTERVAL}. You passed ${progressInterval}`
      );

  if (progressMinBytes != null)
    if (typeof progressMinBytes === "number" && progressMinBytes >= 0)
      config.progressMinBytes = progressMinBytes;
    else
      console.warn(
        `[RNBackgroundDownloader] progressMinBytes must be a number >= 0. You passed ${progressMinBytes}`
      );

  if (typeof isLogsEnabled === "boolean") config.isLogsEnabled = isLogsEnabled;
}

export async function checkForExistingDownloads() {
  log("[RNBackgroundDownloader] checkForExistingDownloads-1");

  // Validate that the native module is available
  if (!NativeRNBackgroundDownloader) {
    console.warn(
      "[RNBackgroundDownloader] Native module not available, returning empty array"
    );
    return [];
  }

  if (
    typeof NativeRNBackgroundDownloader.checkForExistingDownloads !== "function"
  ) {
    console.warn(
      "[RNBackgroundDownloader] checkForExistingDownloads method not available on native module, returning empty array"
    );
    return [];
  }

  try {
    const foundTasks =
      await NativeRNBackgroundDownloader.checkForExistingDownloads();
    log("[RNBackgroundDownloader] checkForExistingDownloads-2", foundTasks);

    // Ensure foundTasks is an array
    if (!Array.isArray(foundTasks)) {
      console.warn(
        "[RNBackgroundDownloader] checkForExistingDownloads returned non-array, returning empty array:",
        foundTasks
      );
      return [];
    }

    return foundTasks
      .map((taskInfo) => {
        // SECOND ARGUMENT RE-ASSIGNS EVENT HANDLERS
        const task = new DownloadTask(taskInfo, tasksMap.get(taskInfo.id));
        log("[RNBackgroundDownloader] checkForExistingDownloads-3", taskInfo);

        if (taskInfo.state === RNBackgroundDownloader.TaskRunning) {
          task.state = "DOWNLOADING";
        } else if (taskInfo.state === RNBackgroundDownloader.TaskSuspended) {
          task.state = "PAUSED";
        } else if (taskInfo.state === RNBackgroundDownloader.TaskCanceling) {
          task.stop();
          return null;
        } else if (taskInfo.state === RNBackgroundDownloader.TaskCompleted) {
          if (taskInfo.bytesDownloaded === taskInfo.bytesTotal)
            task.state = "DONE";
          // IOS completed the download but it was not done.
          else return null;
        }
        tasksMap.set(taskInfo.id, task);
        return task;
      })
      .filter((task) => !!task);
  } catch (error) {
    console.error(
      "[RNBackgroundDownloader] Error in checkForExistingDownloads:",
      error
    );
    return [];
  }
}

export async function ensureDownloadsAreRunning() {
  log("[RNBackgroundDownloader] ensureDownloadsAreRunning");
  const tasks = await checkForExistingDownloads();
  for (const task of tasks)
    if (task.state === "DOWNLOADING") {
      task.pause();
      task.resume();
    }
}

export function completeHandler(jobId: string) {
  if (!NativeRNBackgroundDownloader) {
    console.warn(
      "[RNBackgroundDownloader] Native module not available for completeHandler"
    );
    return;
  }

  try {
    const result = NativeRNBackgroundDownloader.completeHandler(jobId);
    if (result instanceof Promise) return result;
    return Promise.resolve(result);
  } catch (error) {
    console.error("[RNBackgroundDownloader] Error in completeHandler:", error);
  }
}

export function download(options: DownloadOptions) {
  log("[RNBackgroundDownloader] download called", {
    id: options.id,
    url: options.url?.substring(0, 50) + "...",
  });

  if (!options.id || !options.url || !options.destination)
    throw new Error(
      "[RNBackgroundDownloader] id, url and destination are required"
    );

  options.headers = { ...config.headers, ...options.headers };

  if (!(options.metadata && typeof options.metadata === "object"))
    options.metadata = {};

  options.destination = options.destination.replace("file://", "");

  if (options.isAllowedOverRoaming == null) options.isAllowedOverRoaming = true;
  if (options.isAllowedOverMetered == null) options.isAllowedOverMetered = true;
  if (options.isNotificationVisible == null)
    options.isNotificationVisible = false;

  const task = new DownloadTask({
    id: options.id,
    metadata: options.metadata,
  });

  log("[RNBackgroundDownloader] Registering task in tasksMap", {
    id: options.id,
    mapSize: tasksMap.size,
  });
  tasksMap.set(options.id, task);

  if (!NativeRNBackgroundDownloader) {
    console.error(
      "[RNBackgroundDownloader] Native module not available for download"
    );
    task.onError({ error: "Native module not available" });
    return task;
  }

  if (typeof NativeRNBackgroundDownloader.download !== "function") {
    console.error(
      "[RNBackgroundDownloader] download method not available on native module"
    );
    task.onError({ error: "Download method not available" });
    return task;
  }

  try {
    log("[RNBackgroundDownloader] Calling native download method", {
      id: options.id,
    });
    NativeRNBackgroundDownloader.download({
      ...options,
      metadata: JSON.stringify(options.metadata),
      progressInterval: config.progressInterval,
      progressMinBytes: config.progressMinBytes,
    });
    log("[RNBackgroundDownloader] Native download method called successfully", {
      id: options.id,
      taskInMap: tasksMap.has(options.id),
    });
  } catch (error) {
    console.error("[RNBackgroundDownloader] Error in download:", error);
    task.onError({ error: error.message || "Download failed to start" });
  }

  return task;
}

export const directories = {
  documents: RNBackgroundDownloader?.documents || "/tmp/documents",
};

export const storageInfo = {
  isMMKVAvailable: RNBackgroundDownloader?.isMMKVAvailable || false,
  storageType: RNBackgroundDownloader?.storageType || "Unknown",
};

export default {
  download,
  checkForExistingDownloads,
  ensureDownloadsAreRunning,
  completeHandler,

  setConfig,

  directories,
  storageInfo,
};
