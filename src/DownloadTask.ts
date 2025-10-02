import { NativeModules } from "react-native";
import { TaskInfo } from "./index.d";

const { RNBackgroundDownloader } = NativeModules;

function validateHandler(handler) {
  const type = typeof handler;

  if (type !== "function")
    throw new TypeError(
      `[RNBackgroundDownloader] expected argument to be a function, got: ${type}`
    );
}

export default class DownloadTask {
  id = "";
  state = "PENDING";
  metadata = {};

  bytesDownloaded = 0;
  bytesTotal = 0;

  beginHandler;
  progressHandler;
  doneHandler;
  errorHandler;

  constructor(taskInfo: TaskInfo, originalTask?: TaskInfo) {
    this.id = taskInfo.id;
    this.bytesDownloaded = taskInfo.bytesDownloaded ?? 0;
    this.bytesTotal = taskInfo.bytesTotal ?? 0;

    const metadata = this.tryParseJson(taskInfo.metadata);
    if (metadata) this.metadata = metadata;

    if (originalTask) {
      this.beginHandler = originalTask.beginHandler;
      this.progressHandler = originalTask.progressHandler;
      this.doneHandler = originalTask.doneHandler;
      this.errorHandler = originalTask.errorHandler;
    }
  }

  begin(handler) {
    validateHandler(handler);
    this.beginHandler = handler;
    return this;
  }

  progress(handler) {
    validateHandler(handler);
    this.progressHandler = handler;
    return this;
  }

  done(handler) {
    validateHandler(handler);
    console.log(
      `[RNBackgroundDownloader] [DownloadTask] done() handler registered for id: ${this.id}`
    );
    this.doneHandler = handler;
    return this;
  }

  error(handler) {
    validateHandler(handler);
    this.errorHandler = handler;
    return this;
  }

  onBegin(params) {
    console.log(
      `[RNBackgroundDownloader] [DownloadTask] onBegin called for id: ${
        this.id
      }, hasHandler: ${!!this.beginHandler}`
    );
    this.state = "DOWNLOADING";
    if (this.beginHandler) {
      console.log(
        `[RNBackgroundDownloader] [DownloadTask] Invoking beginHandler for id: ${this.id}`
      );
      this.beginHandler(params);
      console.log(
        `[RNBackgroundDownloader] [DownloadTask] beginHandler invoked successfully for id: ${this.id}`
      );
    } else {
      console.log(
        `[RNBackgroundDownloader] [DownloadTask] No beginHandler registered for id: ${this.id}`
      );
    }
  }

  onProgress({ bytesDownloaded, bytesTotal }) {
    this.bytesDownloaded = bytesDownloaded;
    this.bytesTotal = bytesTotal;
    if (this.progressHandler) {
      this.progressHandler({ bytesDownloaded, bytesTotal });
    }
  }

  onDone(params) {
    console.log(
      `[RNBackgroundDownloader] [DownloadTask] ===== onDone CALLED =====`
    );
    console.log(`[RNBackgroundDownloader] [DownloadTask] Task ID: ${this.id}`);
    console.log(
      `[RNBackgroundDownloader] [DownloadTask] Current state: ${this.state}`
    );
    console.log(`[RNBackgroundDownloader] [DownloadTask] Params:`, {
      bytesDownloaded: params.bytesDownloaded,
      bytesTotal: params.bytesTotal,
      location: params.location,
      hasHeaders: !!params.headers,
    });
    console.log(
      `[RNBackgroundDownloader] [DownloadTask] Has doneHandler: ${!!this
        .doneHandler}`
    );
    console.log(
      `[RNBackgroundDownloader] [DownloadTask] doneHandler type: ${typeof this
        .doneHandler}`
    );

    this.state = "DONE";
    this.bytesDownloaded = params.bytesDownloaded;
    this.bytesTotal = params.bytesTotal;

    if (this.doneHandler) {
      console.log(
        `[RNBackgroundDownloader] [DownloadTask] ✅ INVOKING doneHandler for id: ${this.id}`
      );
      try {
        this.doneHandler(params);
        console.log(
          `[RNBackgroundDownloader] [DownloadTask] ✅ doneHandler COMPLETED SUCCESSFULLY for id: ${this.id}`
        );
      } catch (error) {
        console.error(
          `[RNBackgroundDownloader] [DownloadTask] ❌ ERROR in doneHandler for id: ${this.id}:`,
          error
        );
      }
    } else {
      console.warn(
        `[RNBackgroundDownloader] [DownloadTask] ❌ No doneHandler registered for id: ${this.id} - callback will NOT be invoked`
      );
    }
    console.log(
      `[RNBackgroundDownloader] [DownloadTask] ===== onDone COMPLETE =====`
    );
  }

  onError(params) {
    console.log(
      `[RNBackgroundDownloader] [DownloadTask] onError called for id: ${
        this.id
      }, error: ${params.error}, hasHandler: ${!!this.errorHandler}`
    );
    this.state = "FAILED";
    if (this.errorHandler) {
      console.log(
        `[RNBackgroundDownloader] [DownloadTask] Invoking errorHandler for id: ${this.id}`
      );
      this.errorHandler(params);
      console.log(
        `[RNBackgroundDownloader] [DownloadTask] errorHandler invoked successfully for id: ${this.id}`
      );
    } else {
      console.log(
        `[RNBackgroundDownloader] [DownloadTask] No errorHandler registered for id: ${this.id}`
      );
    }
  }

  pause() {
    this.state = "PAUSED";
    RNBackgroundDownloader.pauseTask(this.id);
  }

  resume() {
    this.state = "DOWNLOADING";
    RNBackgroundDownloader.resumeTask(this.id);
  }

  stop() {
    this.state = "STOPPED";
    RNBackgroundDownloader.stopTask(this.id);
  }

  tryParseJson(element) {
    try {
      if (typeof element === "string") element = JSON.parse(element);

      return element;
    } catch (e) {
      console.warn("DownloadTask tryParseJson", e);
      return null;
    }
  }
}
