import type { TurboModule } from "react-native";
import { TurboModuleRegistry } from "react-native";

export interface Spec extends TurboModule {
  // Download management methods
  downloadFile(
    url: string,
    destinationPath: string,
    id: string,
    headers?: Object,
    metadata?: string,
    progressInterval?: number,
    progressMinBytes?: number,
    isAllowedOverRoaming?: boolean,
    isAllowedOverMetered?: boolean,
    isNotificationVisible?: boolean,
    notificationTitle?: string
  ): Promise<void>;

  cancelDownload(id: string): void;
  pauseDownload(id: string): void;
  resumeDownload(id: string): void;

  checkForExistingDownloads(): Promise<
    Array<{
      id: string;
      metadata: string;
      state: number;
      bytesDownloaded: number;
      bytesTotal: number;
    }>
  >;

  completeHandler(jobId: string): Promise<void>;

  // Event listener management (required for New Architecture)
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>("RNBackgroundDownloader");
