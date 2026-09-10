import { useEffect, useMemo, useRef, useState } from "react";
import { useVirtualizer } from "@tanstack/react-virtual";
import { Link, Video, MoreHorizontal, FolderOpen } from "lucide-react";
import { useTranslation } from "react-i18next";
import { invoke } from "@tauri-apps/api/core";
import {
  useLibrary,
  patch,
  select,
  attempt,
  addFolder,
  mark,
} from "../lib/store";
import { Photo, Stars, Modal } from "./Common";
import type { MediaFile } from "../lib/types";
import { bytes } from "../lib/format";
export default function Grid({ files }: { files: MediaFile[] }) {
  const { t } = useTranslation();
  const parent = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(800);
  const [menu, setMenu] = useState<MediaFile | null>(null);
  const selected = useLibrary((s) => s.selected),
    size = useLibrary((s) => s.thumbnail),
    marks = useLibrary((s) => s.database.marks),
    pairs = useLibrary((s) => s.pairs),
    scanning = useLibrary((s) => s.scanning),
    total = useLibrary((s) => s.files.length);
  useEffect(() => {
    if (!parent.current) return;
    const observer = new ResizeObserver((entries) =>
      setWidth(entries[0].contentRect.width),
    );
    observer.observe(parent.current);
    return () => observer.disconnect();
  }, []);
  const columns = Math.max(1, Math.floor((width - 32) / (size + 12)));
  const cellWidth = (width - 32 - 12 * (columns - 1)) / columns;
  const height = cellWidth * 0.77 + 62;
  const virtual = useVirtualizer({
    count: Math.ceil(files.length / columns),
    getScrollElement: () => parent.current,
    estimateSize: () => height,
    overscan: 2,
  });
  useEffect(() => {
    virtual.measure();
  }, [height, virtual]);
  const indices = useMemo(
    () => new Map(files.map((f, i) => [f.path, i])),
    [files],
  );
  useEffect(() => {
    const path = [...selected].at(-1);
    const index = path ? indices.get(path) : undefined;
    if (index !== undefined)
      virtual.scrollToIndex(Math.floor(index / columns), { align: "auto" });
  }, [selected, indices, columns, virtual]);
  return (
    <div
      className="grid-scroll"
      ref={parent}
      data-testid="grid"
      role="listbox"
      aria-label={t("all")}
      aria-multiselectable="true"
    >
      {files.length === 0 ? (
        <div className="empty">
          <FolderOpen size={48} />
          <h2>
            {t(total ? "noResults" : scanning ? "scanning" : "emptyTitle")}
          </h2>
          {!total && !scanning && (
            <>
              <p>{t("emptyBody")}</p>
              <button className="primary" onClick={() => void addFolder()}>
                <FolderOpen size={16} />
                {t("openFolder")}
              </button>
            </>
          )}
        </div>
      ) : (
        <div
          style={{
            height: virtual.getTotalSize(),
            position: "relative",
            margin: "16px",
          }}
        >
          {virtual.getVirtualItems().map((row) => (
            <div
              className="grid-row"
              key={row.key}
              style={{
                position: "absolute",
                top: 0,
                left: 0,
                width: "100%",
                height: row.size,
                transform: `translateY(${row.start}px)`,
                gridTemplateColumns: `repeat(${columns},minmax(0,1fr))`,
              }}
            >
              {files
                .slice(row.index * columns, (row.index + 1) * columns)
                .map((file) => (
                  <article
                    key={file.path}
                    className={`tile ${selected.has(file.path) ? "selected" : ""}`}
                    role="option"
                    aria-selected={selected.has(file.path)}
                    aria-label={file.name}
                    tabIndex={-1}
                    onClick={(e) =>
                      select(file, files, e.ctrlKey || e.metaKey, e.shiftKey)
                    }
                    onDoubleClick={() => patch({ preview: file.path })}
                    onContextMenu={(e) => {
                      e.preventDefault();
                      if (!selected.has(file.path)) select(file, files);
                      setMenu(file);
                    }}
                  >
                    <div className="tile-image">
                      <Photo file={file} px={Math.round(size * 2)} />
                      <span className="format-tag">
                        {file.is_video && <Video size={11} />}{" "}
                        {file.ext.toUpperCase()}
                      </span>
                      {pairs[file.path] && (
                        <span className="pair-tag">
                          <Link size={13} />
                          {pairs[file.path].length + 1}
                        </span>
                      )}
                      <button
                        className="tile-menu"
                        aria-label={t("more")}
                        onClick={(e) => {
                          e.stopPropagation();
                          if (!selected.has(file.path)) select(file, files);
                          setMenu(file);
                        }}
                      >
                        <MoreHorizontal size={17} />
                      </button>
                    </div>
                    <div className="tile-title">
                      <span title={file.name}>{file.name}</span>
                      {marks[file.key]?.label &&
                        marks[file.key].label !== "none" && (
                          <i
                            style={{
                              background: `var(--${marks[file.key].label})`,
                            }}
                          />
                        )}
                    </div>
                    <div className="tile-meta">
                      <span>{file.volume_name}</span>
                      <span>{bytes(file.file_size)}</span>
                    </div>
                    {(marks[file.key]?.rating ?? 0) > 0 && (
                      <div className="tile-stars">
                        {"★".repeat(marks[file.key].rating)}
                      </div>
                    )}
                  </article>
                ))}
            </div>
          ))}
        </div>
      )}
      {menu && (
        <Modal title={menu.name} onClose={() => setMenu(null)}>
          <div className="action-list">
            {[
              "preview",
              "edit",
              "reveal",
              "open",
              "copyName",
              "copyPath",
              "delete",
            ].map((action) => (
              <button
                key={action}
                onClick={() => {
                  const file = menu;
                  setMenu(null);
                  if (action === "preview") patch({ preview: file.path });
                  else if (action === "edit") patch({ editor: file.path });
                  else if (action === "delete") patch({ modal: "delete" });
                  else if (action === "copyName" || action === "copyPath")
                    void attempt(() =>
                      navigator.clipboard.writeText(
                        action === "copyName" ? file.name : file.path,
                      ),
                    );
                  else
                    void attempt(() =>
                      invoke("open_path", { path: file.path, action }),
                    );
                }}
              >
                {t(action)}
              </button>
            ))}
            <Stars
              value={marks[menu.key]?.rating ?? 0}
              onChange={(rating) =>
                void mark([...useLibrary.getState().selected], { rating })
              }
            />
          </div>
        </Modal>
      )}
    </div>
  );
}
