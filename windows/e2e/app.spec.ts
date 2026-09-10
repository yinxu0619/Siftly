import { test, expect, type Page } from "@playwright/test";
async function mock(page: Page, count = 1200) {
  await page.addInitScript(
    ({ count }) => {
      const w = window as any;
      w.isTauri = true;
      let id = 0;
      const callbacks = new Map();
      const listeners = new Map();
      w.__TAURI_EVENT_PLUGIN_INTERNALS__ = {
        unregisterListener: (_event: string, id: number) =>
          listeners.delete(id),
      };
      w.requestClose = async () => {
        for (const [eventId, listener] of [...listeners]) {
          if (listener.event === "tauri://close-requested")
            await callbacks.get(listener.handler)({
              event: listener.event,
              id: eventId,
              payload: null,
            });
        }
      };
      const volume = {
        id: "card",
        name: "EOS_DIGITAL",
        path: "E:\\",
        total: 64 * 1024 ** 3,
        free: 40 * 1024 ** 3,
        manual: false,
      };
      const adjustments = {
        exposure: 0,
        brightness: 0,
        contrast: 0,
        highlights: 0,
        shadows: 0,
        hdr: 0,
        saturation: 0,
        vibrance: 0,
        temperature: 0,
        tint: 0,
        sharpen: 0,
        vignette: 0,
        curve: [
          [0, 0],
          [1, 1],
        ],
        rotation_quarters: 0,
        straighten: 0,
        flip_horizontal: false,
        crop_rect: null,
      };
      const files = Array.from({ length: count }, (_, i) => {
        const name = `IMG_${String(Math.floor(i / 2)).padStart(4, "0")}.${i % 2 ? "JPG" : "CR3"}`;
        return {
          path: `E:\\DCIM\\${name}`,
          name,
          base_name: name.split(".")[0],
          ext: i % 2 ? "jpg" : "cr3",
          directory: "E:\\DCIM",
          file_size: 24000000 + i,
          modified: 1700000000 + i,
          modified_nanos: 1700000000000 + i,
          volume_id: "card",
          volume_name: "EOS_DIGITAL",
          volume_path: "E:\\",
          key: `card::${name}`,
          is_raw: i % 2 === 0,
          is_video: false,
        };
      });
      const database = {
        marks: {} as Record<string, any>,
        preferences: {
          language: "en",
          prefetch: 3,
          write_xmp: false,
          show_exif: true,
        },
      };
      w.calls = [];
      let current = files;
      const picture = (path: string) => {
        const index = files.findIndex((f) => f.path === path);
        return (
          "data:image/svg+xml;base64," +
          btoa(
            `<svg xmlns="http://www.w3.org/2000/svg" width="800" height="530"><defs><linearGradient id="s" x2="0" y2="1"><stop stop-color="${index % 3 ? "#6b8e98" : "#c6a080"}"/><stop offset="1" stop-color="#d9cbb0"/></linearGradient></defs><rect width="800" height="530" fill="url(#s)"/><circle cx="620" cy="120" r="38" fill="#e2d7b7"/><path d="M0 430 L180 180 310 350 430 230 800 470 V530 H0" fill="#3f5550"/><path d="M0 530 L300 330 500 440 670 260 800 400 V530" fill="#243c36"/></svg>`,
          )
        );
      };
      w.__TAURI_INTERNALS__ = {
        metadata: { currentWindow: { label: "main" } },
        transformCallback: (cb: any) => {
          callbacks.set(++id, cb);
          return id;
        },
        unregisterCallback: (id: number) => callbacks.delete(id),
        invoke: async (cmd: string, args: any = {}) => {
          w.calls.push({ cmd, args: JSON.parse(JSON.stringify(args)) });
          switch (cmd) {
            case "plugin:event|listen":
              listeners.set(++id, args);
              return id;
            case "plugin:event|unlisten":
              listeners.delete(args.eventId);
              return;
            case "plugin:window|destroy":
              return;
            case "bootstrap":
              return { database, volumes: [volume], can_undo: false };
            case "list_volumes":
              return [volume];
            case "scan":
              args.onEvent.onmessage({ kind: "batch", files: current });
              args.onEvent.onmessage({ kind: "done", count: current.length });
              return;
            case "compute_pairs":
              return Object.fromEntries(
                current.map((f, i) => [
                  f.path,
                  [current[i % 2 ? i - 1 : i + 1]?.path].filter(Boolean),
                ]),
              );
            case "image":
            case "render_preview":
              return { data: picture(args.path), width: 800, height: 530 };
            case "read_exif":
              return {
                camera: "Canon EOS R5",
                lens: "RF 24-70mm F2.8 L IS USM",
                iso: "ISO 100",
                aperture: "f/8",
                shutter: "1/250 s",
                focal: "35 mm",
                width: 8192,
                height: 5464,
              };
            case "set_marks":
              for (const update of args.updates) {
                const f = files.find((f) => f.path === update.path)!;
                database.marks[f.key] = update.mark;
              }
              return database;
            case "save_preferences":
              database.preferences = args.preferences;
              return database;
            case "plan_deletion":
              return {
                id: "delete-plan",
                selected: current.filter((f) => args.selected.includes(f.path)),
                paired: current.filter(
                  (f) =>
                    !args.selected.includes(f.path) &&
                    args.selected.some(
                      (p: string) => p.split(".")[0] === f.path.split(".")[0],
                    ),
                ),
                total_bytes: 48000000,
              };
            case "delete_files":
              throw new Error("Test must never execute destructive commands");
            case "plugin:dialog|open":
              return "C:\\Pictures";
            case "plan_import":
              return {
                id: "import-plan",
                settings: args.settings,
                items: args.selected.map((path: string) => ({
                  source: files.find((f) => f.path === path),
                  destination: "C:\\Pictures\\new.jpg",
                })),
                skipped: [],
                total_bytes: 48000000,
                free_bytes: 40000000000,
              };
            case "perform_import":
              return {
                completed: [],
                skipped: [],
                failures: [],
                cancelled: false,
              };
            case "cancel":
              return;
            case "plugin:dialog|save":
              return "C:\\Pictures\\edited.jpg";
            case "export_image":
              return;
            default:
              throw new Error(`Unmocked command ${cmd}`);
          }
        },
      };
      w.adjustments = adjustments;
    },
    { count },
  );
}
const errors = new WeakMap<Page, string[]>();
test.afterEach(async ({ page }) => {
  expect(errors.get(page) ?? []).toEqual([]);
});
test.beforeEach(async ({ page }) => {
  const messages: string[] = [];
  errors.set(page, messages);
  page.on("pageerror", (error) => messages.push(error.message));
  await mock(page);
  await page.goto("/");
  await expect(
    page.getByTestId("grid").getByRole("option").first(),
  ).toBeVisible();
});
test("virtualized library supports filtering, keyboard selection and pairing review", async ({
  page,
}) => {
  await expect(page.getByTestId("grid").getByRole("option")).not.toHaveCount(
    1200,
  );
  expect(
    await page.getByTestId("grid").getByRole("option").count(),
  ).toBeLessThan(60);
  await page.getByPlaceholder("Search filenames…").fill("IMG_0010");
  await expect(page.getByTestId("grid").getByRole("option")).toHaveCount(2);
  await page
    .getByTestId("grid")
    .getByRole("option", { name: "IMG_0010.JPG" })
    .click();
  await page.keyboard.press("4");
  await expect(
    page.getByRole("button", { name: "4 Rating", exact: true }),
  ).toHaveClass("lit");
  await page.keyboard.press("Delete");
  const modal = page.getByRole("dialog");
  await expect(modal).toContainText("Paired companions");
  await expect(modal).toContainText("IMG_0010.CR3");
  await expect(
    modal.getByRole("checkbox", { name: "Delete permanently" }),
  ).not.toBeChecked();
  await modal.getByRole("button", { name: "Cancel", exact: true }).click();
  expect(
    await page.evaluate(() =>
      (window as any).calls.some((x: any) => x.cmd === "delete_files"),
    ),
  ).toBe(false);
});
test("preview navigation, editor controls and export preserve the source", async ({
  page,
}) => {
  await page.getByTestId("grid").getByRole("option").first().dblclick();
  await expect(
    page.getByRole("dialog", { name: "Preview", exact: true }),
  ).toBeVisible();
  await page.keyboard.press("ArrowRight");
  await page
    .getByRole("dialog", { name: "Preview", exact: true })
    .getByRole("button", { name: "Edit photo", exact: true })
    .click();
  await expect(
    page.getByRole("dialog", { name: "Edit photo", exact: true }),
  ).toBeVisible();
  await page.getByRole("slider", { name: "Exposure", exact: true }).fill("30");
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          (window as any).calls
            .filter((c: any) => c.cmd === "render_preview")
            .at(-1)?.args.adjustments.exposure,
      ),
    )
    .toBe(30);
  await page
    .getByRole("button", { name: "Export a new file", exact: true })
    .click();
  await page.getByRole("button", { name: "Save as…", exact: true }).click();
  await expect(page.getByText("Export complete")).toBeVisible();
  const call = await page.evaluate(() =>
    (window as any).calls.find((c: any) => c.cmd === "export_image"),
  );
  expect(call.args.destination).not.toBe(call.args.path);
  expect(call.args.adjustments.exposure).toBe(30);
});
test("import requires destination planning and leaves source cleanup opt-in", async ({
  page,
}) => {
  await page.getByTestId("grid").getByRole("option").first().click();
  await page.getByRole("button", { name: "Import", exact: true }).click();
  const modal = page.getByRole("dialog");
  await expect(
    modal.getByRole("button", { name: "Confirm", exact: true }),
  ).toBeDisabled();
  await modal
    .getByRole("button", { name: "Choose folder", exact: true })
    .click();
  await expect(
    modal.getByRole("checkbox", {
      name: "Move originals to Recycle Bin after verified import",
    }),
  ).not.toBeChecked();
  await modal.getByRole("button", { name: "Confirm", exact: true }).click();
  await expect(
    modal.getByRole("button", { name: "Start import", exact: true }),
  ).toBeEnabled();
  expect(
    await page.evaluate(() =>
      (window as any).calls.some((x: any) => x.cmd === "perform_import"),
    ),
  ).toBe(false);
});
test("language switch and minimum window layout", async ({ page }) => {
  await page.getByRole("button", { name: "Settings", exact: true }).click();
  await page
    .getByRole("combobox", { name: "Language", exact: true })
    .selectOption("zh-Hans");
  await expect(
    page.getByRole("heading", { name: "设置", exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "关闭", exact: true }).click();
  await page.setViewportSize({ width: 1040, height: 680 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(
    1040,
  );
  await page.screenshot({ path: "test-results/library-1040.png" });
  await page.setViewportSize({ width: 1440, height: 920 });
  await page.getByTestId("grid").getByRole("option").first().click();
  await page.screenshot({ path: "test-results/library-1440.png" });
});

test("closing the native window flushes the latest editor values before destroy", async ({
  page,
}) => {
  await page.getByTestId("grid").getByRole("option").first().click();
  await page.getByRole("button", { name: "Edit photo", exact: true }).click();
  await page.getByRole("slider", { name: "Exposure", exact: true }).fill("47");
  await page.evaluate(() => (window as any).requestClose());
  const calls = await page.evaluate(() => (window as any).calls);
  const destroy = calls.findIndex(
    (c: any) => c.cmd === "plugin:window|destroy",
  );
  expect(destroy).toBeGreaterThan(0);
  expect(
    calls
      .slice(0, destroy)
      .filter((c: any) => c.cmd === "set_marks")
      .at(-1).args.updates[0].mark.adjustments.exposure,
  ).toBe(47);
});

test("editor image bounds preserve aspect ratio for accurate crop coordinates", async ({
  page,
}) => {
  await page.setViewportSize({ width: 1040, height: 920 });
  await page.getByTestId("grid").getByRole("option").first().click();
  await page.getByRole("button", { name: "Edit photo", exact: true }).click();
  const image = page.getByTestId("edited-image");
  await expect(image).toBeVisible();
  const rect = await image.boundingBox();
  expect(rect).not.toBeNull();
  expect(rect!.width / rect!.height).toBeCloseTo(800 / 530, 2);
  await page.screenshot({ path: "test-results/editor-1040.png" });
});
