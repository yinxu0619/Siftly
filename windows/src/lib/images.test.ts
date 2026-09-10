import { expect, test, vi } from "vitest";
import { ImageQueue, type Lane } from "./images";
import type { MediaFile } from "./types";
function file(path: string): MediaFile {
  return { path, modified_nanos: "1", file_size: 10 } as MediaFile;
}
function harness() {
  const calls: { path: string; lane: Lane; resolve: (s: string) => void }[] =
    [];
  const cancel = vi.fn();
  const queue = new ImageQueue(
    (f, _px, lane) =>
      new Promise((resolve) => calls.push({ path: f.path, lane, resolve })),
    cancel,
  );
  return { queue, calls, cancel };
}
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
test("an explicit preview starts while grid and prefetch lanes are saturated", () => {
  const { queue, calls } = harness();
  for (let i = 0; i < 30; i++)
    queue.request(file(`neighbor${i}`), 2400, "prefetch");
  for (let i = 0; i < 30; i++) queue.request(file(`grid${i}`), 360, "grid");
  queue.request(file("current"), 2400, "preview");
  expect(calls.filter((c) => c.lane === "prefetch")).toHaveLength(1);
  expect(calls.filter((c) => c.lane === "grid")).toHaveLength(4);
  expect(calls.at(-1)?.path).toBe("current");
});
test("a cancelled request is not reused when the same photo is selected again", async () => {
  const { queue, calls, cancel } = harness();
  const first = queue.request(file("a"), 2400, "preview");
  first.release();
  expect(cancel).toHaveBeenCalledOnce();
  const next = queue.request(file("a"), 2400, "preview");
  expect(calls).toHaveLength(2);
  calls[0].resolve("old");
  await flush();
  calls[1].resolve("fresh");
  expect(await next.promise).toBe("fresh");
  expect(await first.promise).toBeNull();
});
test("multiple consumers share decoding and a released queued photo never decodes", async () => {
  const { queue, calls, cancel } = harness();
  const first = queue.request(file("a"), 2400, "prefetch");
  const second = queue.request(file("a"), 2400, "prefetch");
  first.release();
  expect(cancel).not.toHaveBeenCalled();
  const abandoned = queue.request(file("b"), 2400, "prefetch");
  abandoned.release();
  calls[0].resolve("data");
  expect(await second.promise).toBe("data");
  await flush();
  expect(calls).toHaveLength(1);
  expect(await queue.request(file("a"), 2400, "preview").promise).toBe("data");
});
