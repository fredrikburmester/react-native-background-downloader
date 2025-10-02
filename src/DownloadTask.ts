import NativeRNBackgroundDownloader from "./NativeRNBackgroundDownloader";
import { TaskInfo } from "./index.d";

function validateHandler(handler: any) {
  const type = typeof handler;

  if (type !== "function") {
    throw new TypeError(
      `[RNBackgroundDownloader] expected argument to be a function, got: ${type}`
    );
  }
}

export default class DownloadTask {
  id = "";
  state: "PENDING" | "DOWNLOADING" | "PAUSED" | "DONE" | "FAILED" | "STOPPED" =
    "PENDING";
  metadata: any = {};

  bytesDownloaded = 0;
  bytesTotal = 0;

  beginHandler?: (params: any) => void;
  progressHandler?: (params: any) => void;
  doneHandler?: (params: any) => void;
  errorHandler?: (params: any) => void;

  constructor(taskInfo: TaskInfo, originalTask?: DownloadTask) {
    this.id = taskInfo.id;
    this.bytesDownloaded = taskInfo.bytesDownloaded ?? 0;
    this.bytesTotal = taskInfo.bytesTotal ?? 0;

    const metadata = this.tryParseJson(taskInfo.metadata);
    if (metadata) {
      this.metadata = metadata;
    }

    if (originalTask) {
      this.beginHandler = originalTask.beginHandler;
      this.progressHandler = originalTask.progressHandler;
      this.doneHandler = originalTask.doneHandler;
      this.errorHandler = originalTask.errorHandler;
    }
  }

  begin(handler: (params: any) => void) {
    validateHandler(handler);
    this.beginHandler = handler;
    return this;
  }

  progress(handler: (params: any) => void) {
    validateHandler(handler);
    this.progressHandler = handler;
    return this;
  }

  done(handler: (params: any) => void) {
    validateHandler(handler);
    this.doneHandler = handler;
    return this;
  }

  error(handler: (params: any) => void) {
    validateHandler(handler);
    this.errorHandler = handler;
    return this;
  }

  onBegin(params: any) {
    this.state = "DOWNLOADING";
    if (this.beginHandler) {
      this.beginHandler(params);
    }
  }

  onProgress({
    bytesDownloaded,
    bytesTotal,
  }: {
    bytesDownloaded: number;
    bytesTotal: number;
  }) {
    this.bytesDownloaded = bytesDownloaded;
    this.bytesTotal = bytesTotal;
    if (this.progressHandler) {
      this.progressHandler({ bytesDownloaded, bytesTotal });
    }
  }

  onDone(params: any) {
    this.state = "DONE";
    this.bytesDownloaded = params.bytesDownloaded;
    this.bytesTotal = params.bytesTotal;

    if (this.doneHandler) {
      try {
        this.doneHandler(params);
      } catch (error) {
        console.error(
          `[RNBackgroundDownloader] Error in doneHandler for id: ${this.id}:`,
          error
        );
      }
    }
  }

  onError(params: any) {
    this.state = "FAILED";
    if (this.errorHandler) {
      this.errorHandler(params);
    }
  }

  pause() {
    this.state = "PAUSED";
    NativeRNBackgroundDownloader.pauseDownload(this.id);
  }

  resume() {
    this.state = "DOWNLOADING";
    NativeRNBackgroundDownloader.resumeDownload(this.id);
  }

  stop() {
    this.state = "STOPPED";
    NativeRNBackgroundDownloader.cancelDownload(this.id);
  }

  tryParseJson(element: any) {
    try {
      if (typeof element === "string") {
        element = JSON.parse(element);
      }
      return element;
    } catch (e) {
      console.warn("DownloadTask tryParseJson", e);
      return null;
    }
  }
}
