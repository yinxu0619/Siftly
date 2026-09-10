import { isTauri } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { flushMarks, useLibrary, patch, fail } from "./store";
import i18n from "../i18n";
let closeGuard: (() => Promise<boolean>) | null = null;
export function setCloseGuard(guard: () => Promise<boolean>) {
  closeGuard = guard;
  return () => {
    if (closeGuard === guard) closeGuard = null;
  };
}
export function installCloseHandler() {
  if (!isTauri()) return () => {};
  let disposed = false;
  let unlisten: (() => void) | undefined;
  const window = getCurrentWindow();
  void window
    .onCloseRequested(async (event) => {
      event.preventDefault();
      if (useLibrary.getState().busy) {
        patch({ notice: i18n.t("working") });
        return;
      }
      const saved = closeGuard ? await closeGuard() : await flushMarks();
      if (saved) await window.destroy().catch(fail);
    })
    .then((fn) => {
      if (disposed) fn();
      else unlisten = fn;
    })
    .catch(fail);
  return () => {
    disposed = true;
    unlisten?.();
  };
}
