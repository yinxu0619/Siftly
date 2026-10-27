import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import type { MediaFile, ThumbReply } from "./types";
export type Lane = "grid" | "preview" | "prefetch";
const thumbnailSizes = [256, 384, 512, 768];
// A few fixed sizes keep the slider and window resizes on cached thumbnails.
export function thumbnailPx(
  width: number,
  ratio = globalThis.devicePixelRatio || 1,
) {
  const needed = width * ratio;
  return thumbnailSizes.find((px) => px >= needed) ?? thumbnailSizes.at(-1)!;
}
type Entry = {
  key: string;
  file: MediaFile;
  px: number;
  lane: Lane;
  refs: number;
  id: string;
  started: boolean;
  dropped: boolean;
  resolve: (value: string | null) => void;
  promise: Promise<string | null>;
};
export class ImageQueue {
  private jobs = new Map<string, Entry>();
  private cache = new Map<string, string>();
  private cost = 0;
  private active: Record<Lane, number> = { grid: 0, preview: 0, prefetch: 0 };
  constructor(
    private fetcher = (file: MediaFile, px: number, lane: Lane, id: string) =>
      invoke<ThumbReply>("image", { path: file.path, px, lane, id }).then(
        (r) => r.data ?? convertFileSrc(r.name!, "thumb"),
      ),
    private canceller = (id: string) => {
      void invoke("cancel", { id }).catch(() => {});
    },
  ) {}
  key(file: MediaFile, px: number) {
    return `${file.path}|${file.fingerprint}|${file.modified_nanos}|${file.file_size}|${px}`;
  }
  evict(file: MediaFile, px: number) {
    const key = this.key(file, px);
    this.cost -= (this.cache.get(key)?.length ?? 0) * 2;
    this.cache.delete(key);
  }
  request(file: MediaFile, px: number, lane: Lane) {
    const key = this.key(file, px);
    const cached = this.cache.get(key);
    if (cached) {
      this.cache.delete(key);
      this.cache.set(key, cached);
      return { promise: Promise.resolve(cached), release: () => {} };
    }
    let job = this.jobs.get(key);
    if (!job) {
      let resolve!: (s: string | null) => void;
      const promise = new Promise<string | null>((r) => {
        resolve = r;
      });
      job = {
        key,
        file,
        px,
        lane,
        refs: 0,
        id: crypto.randomUUID(),
        started: false,
        dropped: false,
        resolve,
        promise,
      };
      this.jobs.set(key, job);
    }
    if (!job.started && lane === "preview") job.lane = "preview";
    job.refs++;
    this.drain();
    let released = false;
    const entry = job;
    return {
      promise: job.promise,
      release: () => {
        if (released) return;
        released = true;
        entry.refs--;
        // Defer the drop so a consumer that asks for the same image in the same
        // React commit (the preview stepping onto a prefetched neighbor) keeps it.
        if (entry.refs === 0)
          queueMicrotask(() => {
            if (entry.refs > 0 || entry.dropped) return;
            entry.dropped = true;
            if (this.jobs.get(entry.key) === entry) this.jobs.delete(entry.key);
            if (entry.started) this.canceller(entry.id);
            entry.resolve(null);
          });
      },
    };
  }
  private drain() {
    for (const lane of ["preview", "grid", "prefetch"] as const) {
      const limit = lane === "grid" ? 4 : lane === "preview" ? 2 : 1;
      while (this.active[lane] < limit) {
        const next = [...this.jobs.values()]
          .reverse()
          .find((j) => !j.started && j.refs > 0 && j.lane === lane);
        if (!next) break;
        next.started = true;
        this.active[lane]++;
        void this.fetcher(next.file, next.px, lane, next.id)
          .then((data) => {
            // Finished work is cached even when nobody waits for it any more.
            this.cost -= (this.cache.get(next.key)?.length ?? 0) * 2;
            this.cache.set(next.key, data);
            this.cost += data.length * 2;
            while (
              (this.cost > 96 * 1024 * 1024 || this.cache.size > 2000) &&
              this.cache.size > 1
            ) {
              const first = this.cache.entries().next().value!;
              this.cost -= first[1].length * 2;
              this.cache.delete(first[0]);
            }
            next.resolve(next.refs > 0 ? data : null);
          })
          .catch(() => next.resolve(null))
          .finally(() => {
            if (this.jobs.get(next.key) === next) this.jobs.delete(next.key);
            this.active[lane]--;
            this.drain();
          });
      }
    }
  }
}
export const images = new ImageQueue();
