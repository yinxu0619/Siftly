import { create } from "zustand";
import { Channel, invoke, isTauri } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import { language } from "../i18n";
import {
  emptyMark,
  type Database,
  type MediaFile,
  type Volume,
  type Pairs,
  type Rule,
  type FileMark,
  type ScanEvent,
  type Preferences,
} from "./types";
import { errorText } from "./format";
export type Modal = "settings" | "about" | "delete" | "import" | null;
export interface Filters {
  type: string;
  pair: string;
  rating: number;
  label: string;
  search: string;
  sort: string;
  desc: boolean;
}
export const defaultFilters: Filters = {
  type: "all",
  pair: "all",
  rating: 0,
  label: "all",
  search: "",
  sort: "date",
  desc: true,
};
interface Library {
  volumes: Volume[];
  files: MediaFile[];
  volume: string;
  database: Database;
  pairs: Pairs;
  rule: Rule;
  filters: Filters;
  selected: Set<string>;
  anchor: string | null;
  scanning: boolean;
  busy: boolean;
  error: string | null;
  notice: string | null;
  modal: Modal;
  preview: string | null;
  editor: string | null;
  thumbnail: number;
  canUndo: boolean;
  booted: boolean;
}
export const useLibrary = create<Library>(() => ({
  volumes: [],
  files: [],
  volume: "all",
  database: {
    marks: {},
    preferences: {
      language: "system",
      prefetch: 3,
      write_xmp: false,
      show_exif: true,
    },
  },
  pairs: {},
  rule: { preset: "universal", cross_location: false },
  filters: defaultFilters,
  selected: new Set(),
  anchor: null,
  scanning: false,
  busy: false,
  error: null,
  notice: null,
  modal: null,
  preview: null,
  editor: null,
  thumbnail: 180,
  canUndo: false,
  booted: false,
}));
export const patch = useLibrary.setState;
export function fail(error: unknown) {
  patch({ error: errorText(error) });
}
export async function attempt<T>(fn: () => Promise<T>): Promise<T | undefined> {
  try {
    return await fn();
  } catch (error) {
    fail(error);
  }
}
let scanId: string | null = null;
let pairVersion = 0;
export async function recompute() {
  const version = ++pairVersion;
  const pairs = await invoke<Pairs>("compute_pairs", {
    rule: useLibrary.getState().rule,
  });
  if (version === pairVersion) patch({ pairs });
}
export async function refresh() {
  if (useLibrary.getState().busy) return;
  if (scanId) await invoke("cancel", { id: scanId });
  const id = crypto.randomUUID();
  scanId = id;
  patch({
    scanning: true,
    files: [],
    selected: new Set(),
    pairs: {},
    anchor: null,
  });
  try {
    const volumes = await invoke<Volume[]>("list_volumes");
    if (scanId !== id) return;
    patch({ volumes });
    const channel = new Channel<ScanEvent>();
    let pending: MediaFile[] = [];
    let timer: ReturnType<typeof setTimeout> | undefined;
    const flush = () => {
      if (scanId !== id) return;
      if (pending.length) {
        const batch = pending;
        pending = [];
        patch((s) => ({ files: [...s.files, ...batch] }));
      }
    };
    const warnings: string[] = [];
    channel.onmessage = (event) => {
      if (scanId !== id) return;
      if (event.kind === "batch") {
        pending.push(...event.files);
        if (!timer)
          timer = setTimeout(() => {
            timer = undefined;
            flush();
          }, 100);
      } else if (event.kind === "warning") warnings.push(event.message);
    };
    try {
      await invoke("scan", {
        ids: volumes.map((v) => v.id),
        id,
        onEvent: channel,
      });
    } finally {
      clearTimeout(timer);
      flush();
    }
    if (scanId === id) {
      await recompute();
      if (warnings.length) patch({ error: warnings.slice(0, 10).join("\n") });
    }
  } catch (error) {
    if (scanId === id && String(error) !== "cancelled") fail(error);
  } finally {
    if (scanId === id) {
      scanId = null;
      patch({ scanning: false });
    }
  }
}
export async function boot() {
  if (useLibrary.getState().booted) return;
  patch({ booted: true });
  if (!isTauri()) {
    patch({ error: errorText("desktopOnly") });
    return;
  }
  await attempt(async () => {
    const data = await invoke<{
      database: Database;
      volumes: Volume[];
      can_undo: boolean;
    }>("bootstrap");
    patch({
      database: data.database,
      volumes: data.volumes,
      canUndo: data.can_undo,
    });
    language(data.database.preferences.language);
    await refresh();
  });
}
export async function addFolder() {
  if (useLibrary.getState().busy) return;
  await attempt(async () => {
    const path = await open({ directory: true, multiple: false });
    if (typeof path === "string") {
      await invoke("add_folder", { path });
      patch({ volume: "all" });
      await refresh();
    }
  });
}
export function filtered(s: Library): MediaFile[] {
  const f = s.filters;
  const search = f.search.trim().toLocaleLowerCase();
  return s.files
    .filter((file) => {
      const mark = s.database.marks[file.key];
      return (
        (s.volume === "all" || s.volume === file.volume_id) &&
        (!search || file.name.toLocaleLowerCase().includes(search)) &&
        (f.type === "all" ||
          (f.type === "raw"
            ? file.is_raw
            : f.type === "video"
              ? file.is_video
              : ["jpg", "jpeg"].includes(file.ext))) &&
        (f.pair === "all" ||
          (f.pair === "paired" ? !!s.pairs[file.path] : !s.pairs[file.path])) &&
        (!f.rating || (mark?.rating ?? 0) >= f.rating) &&
        (f.label === "all" || (mark?.label || "none") === f.label)
      );
    })
    .sort((a, b) => {
      const n =
        f.sort === "name"
          ? a.name.localeCompare(b.name, undefined, { numeric: true })
          : f.sort === "size"
            ? a.file_size - b.file_size
            : f.sort === "rating"
              ? (s.database.marks[a.key]?.rating ?? 0) -
                (s.database.marks[b.key]?.rating ?? 0)
              : a.modified - b.modified;
      return (n || a.path.localeCompare(b.path)) * (f.desc ? -1 : 1);
    });
}
export function select(
  file: MediaFile,
  ordered: MediaFile[],
  ctrl = false,
  shift = false,
) {
  const s = useLibrary.getState();
  const next = ctrl ? new Set(s.selected) : new Set<string>();
  if (shift && s.anchor) {
    const from = ordered.findIndex((f) => f.path === s.anchor),
      to = ordered.findIndex((f) => f.path === file.path);
    if (from >= 0 && to >= 0)
      for (const f of ordered.slice(Math.min(from, to), Math.max(from, to) + 1))
        next.add(f.path);
    else next.add(file.path);
  } else if (ctrl && next.has(file.path)) next.delete(file.path);
  else next.add(file.path);
  patch({ selected: next, anchor: shift ? s.anchor : file.path });
}
let markQueue = Promise.resolve();
let marksSaved = true;
export async function flushMarks() {
  await markQueue;
  return marksSaved;
}
export function mark(paths: string[], change: Partial<FileMark>) {
  const task = markQueue.then(async () => {
    const s = useLibrary.getState();
    const updates = paths
      .map((path) => {
        const file = s.files.find((f) => f.path === path);
        return file
          ? {
              path,
              mark: {
                ...(s.database.marks[file.key] ?? emptyMark()),
                ...change,
              },
            }
          : null;
      })
      .filter((x) => x !== null);
    if (!updates.length) return true;
    try {
      const database = await invoke<Database>("set_marks", { updates });
      patch({ database });
      return true;
    } catch (error) {
      fail(error);
      await attempt(async () => {
        const data = await invoke<{ database: Database }>("bootstrap");
        patch({ database: data.database });
      });
      return false;
    }
  });
  markQueue = task.then((saved) => {
    marksSaved = saved;
  });
  return task;
}
export async function preferences(value: Preferences) {
  await attempt(async () => {
    const database = await invoke<Database>("save_preferences", {
      preferences: value,
    });
    patch({ database });
    language(value.language);
  });
}
