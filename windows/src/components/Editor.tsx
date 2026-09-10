import { setCloseGuard } from "../lib/lifecycle";
import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { save } from "@tauri-apps/plugin-dialog";
import { useTranslation } from "react-i18next";
import {
  X,
  RotateCcw,
  RotateCw,
  FlipHorizontal,
  Download,
  Undo2,
  Redo2,
  LoaderCircle,
  Crop,
} from "lucide-react";
import { useLibrary, patch, mark, fail } from "../lib/store";
import { identity, type Adjustments, type ImageReply } from "../lib/types";
import { IconButton, Modal } from "./Common";
import { errorText } from "../lib/format";
type NumericKey = {
  [K in keyof Adjustments]: Adjustments[K] extends number ? K : never;
}[keyof Adjustments];
const sections: { title: string; keys: NumericKey[] }[] = [
  {
    title: "light",
    keys: [
      "exposure",
      "brightness",
      "contrast",
      "highlights",
      "shadows",
      "hdr",
    ],
  },
  { title: "color", keys: ["saturation", "vibrance", "temperature", "tint"] },
  { title: "detail", keys: ["sharpen", "vignette"] },
];
function Curve({
  points,
  onChange,
}: {
  points: [number, number][];
  onChange: (p: [number, number][]) => void;
}) {
  const { t } = useTranslation();
  const active = useRef<number | null>(null);
  function coords(
    e: React.PointerEvent<SVGSVGElement> | React.MouseEvent<SVGSVGElement>,
  ): [number, number] {
    const r = e.currentTarget.getBoundingClientRect();
    return [
      Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)),
      Math.max(0, Math.min(1, 1 - (e.clientY - r.top) / r.height)),
    ];
  }
  return (
    <>
      <svg
        className="curve"
        viewBox="0 0 200 200"
        onDoubleClick={(e) => {
          if (points.length >= 16) return;
          const point = coords(e);
          if (points.some((p) => Math.abs(p[0] - point[0]) < 0.025)) return;
          onChange([...points, point].sort((a, b) => a[0] - b[0]));
        }}
        onPointerDown={(e) => {
          const p = coords(e);
          const index = points.findIndex(
            (v) => Math.hypot(v[0] - p[0], v[1] - p[1]) < 0.07,
          );
          if (index >= 0) {
            active.current = index;
            e.currentTarget.setPointerCapture(e.pointerId);
          }
        }}
        onPointerMove={(e) => {
          const i = active.current;
          if (i === null) return;
          const p = coords(e);
          p[0] =
            i === 0
              ? 0
              : i === points.length - 1
                ? 1
                : Math.max(
                    points[i - 1][0] + 0.01,
                    Math.min(points[i + 1][0] - 0.01, p[0]),
                  );
          onChange(points.map((v, index) => (index === i ? p : v)));
        }}
        onPointerUp={() => {
          active.current = null;
        }}
        onContextMenu={(e) => {
          e.preventDefault();
          const p = coords(e);
          onChange(
            points.filter(
              (v, i) =>
                i === 0 ||
                i === points.length - 1 ||
                Math.hypot(v[0] - p[0], v[1] - p[1]) > 0.07,
            ),
          );
        }}
      >
        {[50, 100, 150].map((n) => (
          <path key={n} d={`M ${n} 0 V 200 M 0 ${n} H 200`} stroke="#373c3e" />
        ))}
        <path d="M 0 200 L 200 0" stroke="#596063" strokeDasharray="4 4" />
        <polyline
          points={points
            .map(([x, y]) => `${x * 200},${(1 - y) * 200}`)
            .join(" ")}
          fill="none"
          stroke="var(--accent)"
          strokeWidth={2}
        />
        {points.map(([x, y], i) => (
          <circle
            key={i}
            cx={x * 200}
            cy={(1 - y) * 200}
            r={4}
            fill="var(--accent)"
          />
        ))}
      </svg>
      <small className="muted">{t("curveHint")}</small>
    </>
  );
}
export default function Editor() {
  const s = useLibrary(),
    { t } = useTranslation();
  const file = s.files.find((f) => f.path === s.editor)!;
  const [a, setA] = useState<Adjustments>(() =>
    structuredClone(s.database.marks[file.key]?.adjustments ?? identity),
  );
  const [history, setHistory] = useState<Adjustments[]>([]),
    [future, setFuture] = useState<Adjustments[]>([]);
  const [rendered, setRendered] = useState<ImageReply | null>(null);
  const [renderError, setRenderError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [compare, setCompare] = useState(false);
  const [crop, setCrop] = useState(false);
  const [ratio, setRatio] = useState(0);
  const [exporting, setExporting] = useState(false),
    [exportDialog, setExportDialog] = useState(false);
  const [format, setFormat] = useState("jpeg"),
    [quality, setQuality] = useState(92),
    [edge, setEdge] = useState(0);
  const imageRef = useRef<HTMLDivElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const [stageSize, setStageSize] = useState({ width: 800, height: 600 });
  useEffect(() => {
    if (!stageRef.current) return;
    const observer = new ResizeObserver(([entry]) =>
      setStageSize({
        width: entry.contentRect.width,
        height: entry.contentRect.height,
      }),
    );
    observer.observe(stageRef.current);
    return () => observer.disconnect();
  }, []);
  const start = useRef<[number, number] | null>(null);
  const current = useRef(a);
  current.current = a;
  const historyStamp = useRef(0);
  useEffect(
    () =>
      setCloseGuard(() => mark([file.path], { adjustments: current.current })),
    [file.path],
  );
  function change(next: Partial<Adjustments>) {
    if (Date.now() - historyStamp.current > 350) {
      setHistory((h) => [...h.slice(-49), current.current]);
      historyStamp.current = Date.now();
    }
    setFuture([]);
    setA({ ...current.current, ...next });
  }
  function undo() {
    const previous = history.at(-1);
    if (previous) {
      setFuture((f) => [a, ...f]);
      setA(previous);
      setHistory((h) => h.slice(0, -1));
      historyStamp.current = 0;
    }
  }
  function redo() {
    if (future.length) {
      setHistory((h) => [...h, a]);
      setA(future[0]);
      setFuture((f) => f.slice(1));
      historyStamp.current = 0;
    }
  }
  useEffect(() => {
    const timer = setTimeout(() => {
      void mark([file.path], { adjustments: a });
    }, 450);
    return () => clearTimeout(timer);
  }, [a, file.path]);
  async function close() {
    if (exporting) return;
    if (await mark([file.path], { adjustments: current.current }))
      patch({ editor: null });
  }
  useEffect(() => {
    const id = crypto.randomUUID();
    let alive = true;
    const timer = setTimeout(() => {
      setLoading(true);
      setRenderError(null);
      void invoke<ImageReply>("render_preview", {
        path: file.path,
        adjustments: compare ? identity : a,
        includeCrop: !crop,
        id,
      })
        .then((value) => {
          if (alive) setRendered(value);
        })
        .catch((error) => {
          if (alive && String(error) !== "cancelled")
            setRenderError(errorText(error));
        })
        .finally(() => {
          if (alive) setLoading(false);
        });
    }, 120);
    return () => {
      alive = false;
      clearTimeout(timer);
      void invoke("cancel", { id }).catch(() => {});
    };
  }, [a, file.path, compare, crop]);
  useEffect(() => {
    function key(e: KeyboardEvent) {
      if (
        exportDialog ||
        e.target instanceof HTMLInputElement ||
        e.target instanceof HTMLSelectElement
      )
        return;
      if (e.key === "Escape") {
        e.preventDefault();
        void close();
      }
      if ((e.ctrlKey || e.metaKey) && e.key === "z") {
        e.preventDefault();
        if (e.shiftKey) redo();
        else undo();
      }
    }
    document.addEventListener("keydown", key);
    return () => document.removeEventListener("keydown", key);
  }, [exportDialog, history, future, a, exporting]);
  function cropPoint(e: React.PointerEvent): [number, number] {
    const r = imageRef.current!.getBoundingClientRect();
    return [
      Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)),
      Math.max(0, Math.min(1, (e.clientY - r.top) / r.height)),
    ];
  }
  async function exportFile() {
    const ext = format === "jpeg" ? "jpg" : format === "tiff" ? "tif" : "png";
    try {
      const destination = await save({
        defaultPath: `${file.base_name}-edited.${ext}`,
        filters: [{ name: format.toUpperCase(), extensions: [ext] }],
      });
      if (!destination) return;
      setExporting(true);
      patch({ busy: true });
      await invoke("export_image", {
        path: file.path,
        destination,
        adjustments: a,
        settings: { format, quality, max_edge: edge || null },
      });
      setExportDialog(false);
      patch({ notice: t("exported") });
    } catch (error) {
      fail(error);
    } finally {
      setExporting(false);
      patch({ busy: false });
    }
  }
  return (
    <div
      className="full-overlay editor"
      role="dialog"
      aria-modal="true"
      aria-label={t("edit")}
    >
      <header className="viewer-header">
        <div>
          <strong>{file.name}</strong>
          <small>{t("readOnly")}</small>
        </div>
        <div className="button-row">
          <IconButton
            title={t("undo")}
            disabled={!history.length}
            onClick={undo}
          >
            <Undo2 size={17} />
          </IconButton>
          <IconButton
            title={t("redo")}
            disabled={!future.length}
            onClick={redo}
          >
            <Redo2 size={17} />
          </IconButton>
          <button
            onPointerDown={(e) => {
              e.currentTarget.setPointerCapture(e.pointerId);
              setCompare(true);
            }}
            onPointerUp={() => setCompare(false)}
            onPointerCancel={() => setCompare(false)}
            onLostPointerCapture={() => setCompare(false)}
          >
            {t("compare")}
          </button>
          <button onClick={() => change(structuredClone(identity))}>
            {t("reset")}
          </button>
          <button
            className="primary"
            disabled={!!renderError || exporting}
            onClick={() => setExportDialog(true)}
          >
            <Download size={16} />
            {t("export")}
          </button>
          <IconButton
            title={t("close")}
            disabled={exporting}
            onClick={() => void close()}
          >
            <X size={20} />
          </IconButton>
        </div>
      </header>
      <div className="editor-body">
        <div className="editor-stage" ref={stageRef}>
          {renderError ? (
            <div className="empty">
              <h3>{t("unsupportedEdit")}</h3>
              <p>{renderError}</p>
            </div>
          ) : rendered ? (
            <div
              className="edited-image"
              data-testid="edited-image"
              ref={imageRef}
              style={{
                width: Math.min(
                  stageSize.width,
                  (stageSize.height * rendered.width) / rendered.height,
                ),
                height: Math.min(
                  stageSize.height,
                  (stageSize.width * rendered.height) / rendered.width,
                ),
                aspectRatio: `${rendered.width}/${rendered.height}`,
              }}
              onPointerDown={(e) => {
                if (!crop) return;
                start.current = cropPoint(e);
                e.currentTarget.setPointerCapture(e.pointerId);
              }}
              onPointerMove={(e) => {
                if (!crop || !start.current) return;
                const [sx, sy] = start.current,
                  [ex, ey] = cropPoint(e);
                let w = Math.abs(ex - sx),
                  h = Math.abs(ey - sy);
                if (ratio) {
                  const imageRatio = rendered.width / rendered.height;
                  h = (w * imageRatio) / ratio;
                  h = Math.min(h, ey >= sy ? 1 - sy : sy);
                  w = (h * ratio) / imageRatio;
                }
                const x = ex >= sx ? sx : sx - w,
                  y = ey >= sy ? sy : sy - h;
                if (w > 0.005 && h > 0.005) change({ crop_rect: [x, y, w, h] });
              }}
              onPointerUp={() => {
                start.current = null;
              }}
            >
              <img src={rendered.data} alt={file.name} draggable={false} />
              {crop && a.crop_rect && (
                <div
                  className="crop-rectangle"
                  style={{
                    left: `${a.crop_rect[0] * 100}%`,
                    top: `${a.crop_rect[1] * 100}%`,
                    width: `${a.crop_rect[2] * 100}%`,
                    height: `${a.crop_rect[3] * 100}%`,
                  }}
                >
                  <i />
                  <i />
                </div>
              )}
            </div>
          ) : (
            <LoaderCircle className="spin" size={32} />
          )}
          {loading && (
            <div className="render-status">
              <LoaderCircle className="spin" size={14} />
              {t("loadingPhoto")}
            </div>
          )}
        </div>
        <aside className="editor-controls">
          {sections.map((section) => (
            <section key={section.title}>
              <h3>{t(section.title)}</h3>
              {section.keys.map((key) => (
                <label className="slider-control" key={key}>
                  <span>
                    {t(key)}
                    <output>{a[key]}</output>
                  </span>
                  <input
                    type="range"
                    aria-label={t(key)}
                    min={
                      ["hdr", "sharpen", "vignette"].includes(key) ? 0 : -100
                    }
                    max={100}
                    value={a[key]}
                    onChange={(e) => change({ [key]: Number(e.target.value) })}
                    onDoubleClick={() => change({ [key]: 0 })}
                  />
                </label>
              ))}
            </section>
          ))}
          <section>
            <h3>{t("toneCurve")}</h3>
            <Curve points={a.curve} onChange={(curve) => change({ curve })} />
          </section>
          <section>
            <h3>{t("geometry")}</h3>
            <div className="button-row">
              <IconButton
                title={t("rotateLeft")}
                onClick={() =>
                  change({
                    rotation_quarters: a.rotation_quarters - 1,
                    crop_rect: null,
                  })
                }
              >
                <RotateCcw size={17} />
              </IconButton>
              <IconButton
                title={t("rotateRight")}
                onClick={() =>
                  change({
                    rotation_quarters: a.rotation_quarters + 1,
                    crop_rect: null,
                  })
                }
              >
                <RotateCw size={17} />
              </IconButton>
              <IconButton
                title={t("flip")}
                onClick={() => change({ flip_horizontal: !a.flip_horizontal })}
              >
                <FlipHorizontal size={17} />
              </IconButton>
              <button
                className={crop ? "active" : ""}
                onClick={() => setCrop(!crop)}
              >
                <Crop size={16} />
                {t("crop")}
              </button>
            </div>
            <label className="slider-control">
              <span>
                {t("straighten")}
                <output>{a.straighten}°</output>
              </span>
              <input
                type="range"
                min={-45}
                max={45}
                step={0.5}
                value={a.straighten}
                aria-label={t("straighten")}
                onChange={(e) =>
                  change({
                    straighten: Number(e.target.value),
                    crop_rect: null,
                  })
                }
              />
            </label>
            {crop && (
              <>
                <select
                  aria-label={t("crop")}
                  value={ratio}
                  onChange={(e) => {
                    setRatio(Number(e.target.value));
                    change({ crop_rect: null });
                  }}
                >
                  <option value={0}>{t("freeCrop")}</option>
                  {[1, 3 / 2, 4 / 3, 16 / 9, 2 / 3, 3 / 4].map((r) => (
                    <option value={r} key={r}>
                      {r === 1
                        ? "1:1"
                        : r === 1.5
                          ? "3:2"
                          : r === 4 / 3
                            ? "4:3"
                            : r === 16 / 9
                              ? "16:9"
                              : r === 2 / 3
                                ? "2:3"
                                : "3:4"}
                    </option>
                  ))}
                </select>
                <button onClick={() => change({ crop_rect: null })}>
                  {t("resetCrop")}
                </button>
                <p className="muted">{t("dragCrop")}</p>
              </>
            )}
          </section>
        </aside>
      </div>
      {exportDialog && (
        <Modal
          title={t("exportTitle")}
          onClose={() => {
            if (!exporting) setExportDialog(false);
          }}
        >
          <div className="modal-body">
            <label>
              {t("format")}
              <select
                value={format}
                disabled={exporting}
                onChange={(e) => setFormat(e.target.value)}
              >
                <option value="jpeg">JPEG</option>
                <option value="png">PNG</option>
                <option value="tiff">TIFF</option>
              </select>
            </label>
            {format === "jpeg" && (
              <label className="slider-control">
                <span>
                  {t("quality")}
                  <output>{quality}</output>
                </span>
                <input
                  type="range"
                  min={1}
                  max={100}
                  value={quality}
                  disabled={exporting}
                  onChange={(e) => setQuality(Number(e.target.value))}
                />
              </label>
            )}
            <label>
              {t("resize")}
              <select
                value={edge}
                disabled={exporting}
                onChange={(e) => setEdge(Number(e.target.value))}
              >
                <option value={0}>{t("originalSize")}</option>
                {[1280, 1920, 2560, 3840, 6000].map((n) => (
                  <option key={n} value={n}>
                    {n} px
                  </option>
                ))}
              </select>
            </label>
            <p className="muted">{t("exportHint")}</p>
            <footer>
              <button
                className="primary"
                disabled={exporting}
                onClick={() => void exportFile()}
              >
                {exporting ? (
                  <>
                    <LoaderCircle className="spin" size={16} />
                    {t("working")}
                  </>
                ) : (
                  t("saveAs")
                )}
              </button>
            </footer>
          </div>
        </Modal>
      )}
    </div>
  );
}
