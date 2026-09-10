import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  ChevronLeft,
  ChevronRight,
  X,
  ZoomIn,
  ZoomOut,
  Maximize,
  SlidersHorizontal,
  Info,
  ExternalLink,
} from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { useLibrary, patch, mark, attempt } from "../lib/store";
import type { MediaFile } from "../lib/types";
import { images } from "../lib/images";
import { Photo, IconButton, Stars, Labels } from "./Common";
import { Details } from "./Inspector";
export default function Preview({ files }: { files: MediaFile[] }) {
  const s = useLibrary(),
    { t } = useTranslation();
  const file = s.files.find((f) => f.path === s.preview);
  const [zoom, setZoom] = useState(1);
  const [showInfo, setShowInfo] = useState(s.database.preferences.show_exif);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const index = files.findIndex((f) => f.path === file?.path);
  function move(step: number) {
    const next = files[index + step];
    if (next)
      patch({
        preview: next.path,
        selected: new Set([next.path]),
        anchor: next.path,
      });
  }
  useEffect(() => {
    setZoom(1);
    setPan({ x: 0, y: 0 });
  }, [file?.path]);
  useEffect(() => {
    const tickets: ReturnType<typeof images.request>[] = [];
    for (let i = 1; i <= s.database.preferences.prefetch; i++)
      for (const step of [-i, i]) {
        const next = files[index + step];
        if (next) tickets.push(images.request(next, 2400, "prefetch"));
      }
    return () => tickets.forEach((ticket) => ticket.release());
  }, [files, index, s.database.preferences.prefetch]);
  useEffect(() => {
    function key(e: KeyboardEvent) {
      if (e.target instanceof HTMLInputElement) return;
      if (e.key === "Escape" || e.key === " ") {
        e.preventDefault();
        patch({ preview: null });
      } else if (e.key === "ArrowLeft") {
        e.preventDefault();
        move(-1);
      } else if (e.key === "ArrowRight") {
        e.preventDefault();
        move(1);
      } else if (/^[0-5]$/.test(e.key) && file)
        void mark([file.path], { rating: Number(e.key) });
      else if (e.key === "Delete" && file) {
        patch({
          preview: null,
          selected: new Set([file.path]),
          modal: "delete",
        });
      }
    }
    document.addEventListener("keydown", key);
    return () => document.removeEventListener("keydown", key);
  }, [index, files, file]);
  if (!file) return null;
  const value = s.database.marks[file.key];
  return (
    <div
      className="full-overlay"
      role="dialog"
      aria-modal="true"
      aria-label={t("preview")}
    >
      <header className="viewer-header">
        <div>
          <strong>{file.name}</strong>
          <small>
            {index + 1} / {files.length} · {file.volume_name}
          </small>
        </div>
        <div className="button-row">
          <IconButton
            title={t("zoomOut")}
            onClick={() => setZoom((z) => Math.max(0.25, z / 1.25))}
          >
            <ZoomOut size={18} />
          </IconButton>
          <button
            onClick={() => {
              setZoom(1);
              setPan({ x: 0, y: 0 });
            }}
          >
            {Math.round(zoom * 100)}%
          </button>
          <IconButton
            title={t("zoomIn")}
            onClick={() => setZoom((z) => Math.min(8, z * 1.25))}
          >
            <ZoomIn size={18} />
          </IconButton>
          <IconButton
            title={t("fit")}
            onClick={() => {
              setZoom(1);
              setPan({ x: 0, y: 0 });
            }}
          >
            <Maximize size={17} />
          </IconButton>
          <IconButton
            title={t("showExif")}
            onClick={() => setShowInfo(!showInfo)}
          >
            <Info size={18} />
          </IconButton>
          <button
            disabled={file.is_video}
            onClick={() => patch({ preview: null, editor: file.path })}
          >
            <SlidersHorizontal size={16} />
            {t("edit")}
          </button>
          <IconButton
            title={t("close")}
            onClick={() => patch({ preview: null })}
          >
            <X size={21} />
          </IconButton>
        </div>
      </header>
      <div className="viewer-body">
        <div
          className="viewer-stage"
          onWheel={(e) =>
            setZoom((z) =>
              Math.max(0.25, Math.min(8, z * (e.deltaY > 0 ? 0.9 : 1.1))),
            )
          }
          onPointerDown={(e) => {
            if (e.target instanceof HTMLButtonElement) return;
            e.currentTarget.setPointerCapture(e.pointerId);
          }}
          onPointerMove={(e) => {
            if (e.currentTarget.hasPointerCapture(e.pointerId) && zoom > 1)
              setPan((p) => ({ x: p.x + e.movementX, y: p.y + e.movementY }));
          }}
          onPointerUp={(e) => {
            if (e.currentTarget.hasPointerCapture(e.pointerId))
              e.currentTarget.releasePointerCapture(e.pointerId);
          }}
          onDoubleClick={() => {
            setZoom((z) => (z === 1 ? 2 : 1));
            setPan({ x: 0, y: 0 });
          }}
        >
          <Photo
            file={file}
            px={2400}
            lane="preview"
            className="preview-image"
            style={{
              transform: `translate(${pan.x}px,${pan.y}px) scale(${zoom})`,
            }}
          />
          <button
            className="nav-arrow left"
            disabled={index <= 0}
            aria-label={t("previous")}
            onClick={() => move(-1)}
          >
            <ChevronLeft />
          </button>
          <button
            className="nav-arrow right"
            disabled={index >= files.length - 1}
            aria-label={t("next")}
            onClick={() => move(1)}
          >
            <ChevronRight />
          </button>
          {file.is_video && (
            <button
              className="video-open"
              onClick={() =>
                void attempt(() =>
                  invoke("open_path", { path: file.path, action: "open" }),
                )
              }
            >
              <ExternalLink size={16} />
              {t("open")}
            </button>
          )}
        </div>
        {showInfo && (
          <aside className="preview-details">
            <Details file={file} />
          </aside>
        )}
      </div>
      <footer className="viewer-footer">
        <Stars
          value={value?.rating ?? 0}
          onChange={(rating) => void mark([file.path], { rating })}
        />
        <Labels
          value={value?.label || "none"}
          onChange={(label) => void mark([file.path], { label })}
        />
        <span className="muted">← → · 0–5 · Delete</span>
      </footer>
    </div>
  );
}
