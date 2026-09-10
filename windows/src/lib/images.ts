import { invoke } from "@tauri-apps/api/core";
import type { ImageReply, MediaFile } from "./types";
export type Lane = "grid" | "preview" | "prefetch";
type Entry = {
  key: string;
  file: MediaFile;
  px: number;
  lane: Lane;
  refs: number;
  id: string;
  started: boolean;
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
      invoke<ImageReply>("image", { path: file.path, px, lane, id }).then(
        (r) => r.data,
      ),
    private canceller = (id: string) => {
      void invoke("cancel", { id }).catch(() => {});
    },
  ) {}
  request(file: MediaFile, px: number, lane: Lane) {
    const key = `${file.path}|${file.fingerprint}|${file.modified_nanos}|${file.file_size}|${px}`;
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
        if (entry.refs === 0) {
          if (this.jobs.get(entry.key) === entry) this.jobs.delete(entry.key);
          if (entry.started) this.canceller(entry.id);
          entry.resolve(null);
        }
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
            if (next.refs === 0) {
              next.resolve(null);
              return;
            }
            this.cost -= (this.cache.get(next.key)?.length ?? 0) * 2;
            this.cache.set(next.key, data);
            this.cost += data.length * 2;
            while (this.cost > 96 * 1024 * 1024 && this.cache.size > 1) {
              const first = this.cache.entries().next().value!;
              this.cost -= first[1].length * 2;
              this.cache.delete(first[0]);
            }
            next.resolve(data);
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
