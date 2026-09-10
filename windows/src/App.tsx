import { installCloseHandler } from "./lib/lifecycle";
import { useEffect, useMemo } from "react";
import { useTranslation } from "react-i18next";
import { invoke, isTauri } from "@tauri-apps/api/core";
import {
  Camera,
  HardDrive,
  FolderPlus,
  RefreshCw,
  Settings as SettingsIcon,
  Info,
  Search,
  ArrowDownUp,
  Trash2,
  Download,
  Undo2,
  Link,
  LoaderCircle,
} from "lucide-react";
import {
  useLibrary,
  patch,
  boot,
  refresh,
  addFolder,
  filtered,
  defaultFilters,
  attempt,
  recompute,
  select,
  mark,
} from "./lib/store";
import { labels, type Outcome, type Volume } from "./lib/types";
import { bytes } from "./lib/format";
import Grid from "./components/Grid";
import Inspector from "./components/Inspector";
import Settings from "./components/Settings";
import Operations from "./components/Operations";
import Preview from "./components/Preview";
import Editor from "./components/Editor";
import { IconButton, Modal } from "./components/Common";
export default function App() {
  const s = useLibrary(),
    { t } = useTranslation();
  const files = useMemo(
    () => filtered(s),
    [s.files, s.filters, s.volume, s.database.marks, s.pairs],
  );
  useEffect(() => {
    void boot();
    return installCloseHandler();
  }, []);
  useEffect(() => {
    if (!isTauri()) return;
    const timer = setInterval(() => {
      const state = useLibrary.getState();
      if (
        state.busy ||
        state.scanning ||
        state.modal ||
        state.editor ||
        state.preview
      )
        return;
      void invoke<Volume[]>("list_volumes")
        .then((volumes) => {
          if (
            volumes.map((v) => v.id).join("|") !==
            state.volumes.map((v) => v.id).join("|")
          )
            void refresh();
        })
        .catch(() => {});
    }, 4000);
    return () => clearInterval(timer);
  }, []);
  useEffect(() => {
    function key(event: KeyboardEvent) {
      const state = useLibrary.getState();
      if (
        state.modal ||
        state.preview ||
        state.editor ||
        state.error ||
        state.busy ||
        event.target instanceof HTMLInputElement ||
        event.target instanceof HTMLSelectElement ||
        event.target instanceof HTMLTextAreaElement
      )
        return;
      const ctrl = event.ctrlKey || event.metaKey;
      const current = [...state.selected].at(-1);
      if (ctrl && event.key.toLowerCase() === "a") {
        event.preventDefault();
        patch({
          selected: new Set(files.map((f) => f.path)),
          anchor: files[0]?.path ?? null,
        });
      } else if (event.key === "Escape") patch({ selected: new Set() });
      else if (event.key === " " && current) {
        event.preventDefault();
        patch({ preview: current });
      } else if (
        event.key === "Delete" &&
        state.selected.size &&
        !state.scanning
      ) {
        event.preventDefault();
        patch({ modal: "delete" });
      } else if (/^[0-5]$/.test(event.key) && current) {
        void mark([...state.selected], { rating: Number(event.key) });
      } else if (event.key.startsWith("Arrow") && files.length) {
        event.preventDefault();
        const index = files.findIndex((f) => f.path === current);
        const step =
          event.key === "ArrowLeft" || event.key === "ArrowUp" ? -1 : 1;
        select(
          files[Math.max(0, Math.min(files.length - 1, index + step))],
          files,
          ctrl,
          event.shiftKey,
        );
      }
    }
    document.addEventListener("keydown", key);
    return () => document.removeEventListener("keydown", key);
  }, [files]);
  const filter = (next: Partial<typeof s.filters>) =>
    patch({ filters: { ...s.filters, ...next } });
  const locked = s.scanning || s.busy;
  async function undo() {
    patch({ busy: true });
    try {
      const result = await invoke<Outcome>("undo_delete");
      patch({
        canUndo: result.failures.length > 0,
        notice: t("completed", { count: result.completed.length }),
        error: result.failures.join("\n") || null,
      });
    } finally {
      patch({ busy: false });
      await refresh();
    }
  }
  return (
    <>
      <div
        className="app-shell"
        inert={!!(s.preview || s.editor)}
        aria-hidden={!!(s.preview || s.editor)}
      >
        <header className="topbar">
          <div className="brand">
            <img src="/AppIcon-square.png" alt="" />
            <strong>Siftly</strong>
            <span>WINDOWS</span>
          </div>
          <span className="tagline">{t("tagline")}</span>
          <div className="top-actions">
            <IconButton
              title={t("undo")}
              disabled={!s.canUndo || locked}
              onClick={() => void attempt(undo)}
            >
              <Undo2 size={17} />
            </IconButton>
            <IconButton
              title={t("settings")}
              onClick={() => patch({ modal: "settings" })}
            >
              <SettingsIcon size={18} />
            </IconButton>
            <IconButton
              title={t("about")}
              onClick={() => patch({ modal: "about" })}
            >
              <Info size={18} />
            </IconButton>
          </div>
        </header>
        <div className="workspace">
          <aside className="sidebar">
            <div className="section-heading">
              {t("library")}
              <IconButton
                title={t("refresh")}
                disabled={locked}
                onClick={() => void refresh()}
              >
                <RefreshCw size={14} className={s.scanning ? "spin" : ""} />
              </IconButton>
            </div>
            <button
              className={`nav-item ${s.volume === "all" ? "active" : ""}`}
              onClick={() => patch({ volume: "all" })}
            >
              <Camera size={18} />
              {t("allCards")}
              <span>{s.files.length}</span>
            </button>
            <div className="section-heading storage-heading">{t("cards")}</div>
            {s.volumes.map((v) => (
              <button
                key={v.id}
                className={`volume ${s.volume === v.id ? "active" : ""}`}
                onClick={() => patch({ volume: v.id })}
              >
                <HardDrive size={20} />
                <div>
                  <strong>{v.name}</strong>
                  <small title={v.path}>{v.path}</small>
                  <div className="disk-meter">
                    <i
                      style={{
                        width: `${v.total ? Math.max(0, 100 - (v.free / v.total) * 100) : 0}%`,
                      }}
                    />
                  </div>
                  <small>{t("free", { size: bytes(v.free) })}</small>
                </div>
              </button>
            ))}
            <button
              className="add-folder"
              disabled={locked}
              onClick={() => void addFolder()}
            >
              <FolderPlus size={16} />
              {t("addFolder")}
            </button>
            <div className="pair-settings">
              <div className="section-heading">
                <Link size={14} />
                {t("pairing")}
              </div>
              <select
                aria-label={t("pairing")}
                value={s.rule.preset}
                disabled={locked}
                onChange={(e) => {
                  patch({ rule: { ...s.rule, preset: e.target.value } });
                  void attempt(recompute);
                }}
              >
                {["universal", "sony", "canon", "nikon", "fuji"].map(
                  (value) => (
                    <option key={value} value={value}>
                      {t(value)}
                    </option>
                  ),
                )}
              </select>
              <label className="check">
                <input
                  type="checkbox"
                  checked={s.rule.cross_location}
                  disabled={locked}
                  onChange={(e) => {
                    patch({
                      rule: { ...s.rule, cross_location: e.target.checked },
                    });
                    void attempt(recompute);
                  }}
                />
                {t("crossCard")}
              </label>
            </div>
            <div className="sidebar-bottom">
              <span className="status-dot" />
              {s.scanning ? t("scanning") : t("ready")}
            </div>
          </aside>
          <main className="main-panel">
            <div className="library-heading">
              <div>
                <p className="eyebrow">
                  {s.volume === "all"
                    ? "SIFTLY LIBRARY"
                    : s.volumes.find((v) => v.id === s.volume)?.name}
                </p>
                <h1>{t(s.filters.type === "all" ? "all" : s.filters.type)}</h1>
              </div>
              <div className="library-actions">
                <button
                  disabled={!s.selected.size || locked}
                  onClick={() => patch({ modal: "delete" })}
                >
                  <Trash2 size={16} />
                  {t("delete")}
                </button>
                <button
                  className="primary"
                  disabled={!s.selected.size || locked}
                  onClick={() => patch({ modal: "import" })}
                >
                  <Download size={16} />
                  {t("import")}
                </button>
              </div>
            </div>
            <div className="filter-toolbar">
              <div className="type-tabs">
                {["all", "raw", "jpg", "video"].map((type) => (
                  <button
                    key={type}
                    className={s.filters.type === type ? "active" : ""}
                    onClick={() => filter({ type })}
                  >
                    {t(type)}
                  </button>
                ))}
              </div>
              <div className="search-box">
                <Search size={15} />
                <input
                  aria-label={t("search")}
                  placeholder={t("search")}
                  value={s.filters.search}
                  onChange={(e) => filter({ search: e.target.value })}
                />
              </div>
            </div>
            <div className="secondary-toolbar">
              <select
                aria-label={t("paired")}
                value={s.filters.pair}
                onChange={(e) => filter({ pair: e.target.value })}
              >
                <option value="all">{t("pairing")}</option>
                <option value="paired">{t("paired")}</option>
                <option value="unpaired">{t("unpaired")}</option>
              </select>
              <select
                aria-label={t("rating")}
                value={s.filters.rating}
                onChange={(e) => filter({ rating: Number(e.target.value) })}
              >
                <option value={0}>{t("anyRating")}</option>
                {[1, 2, 3, 4, 5].map((n) => (
                  <option key={n} value={n}>
                    {"★".repeat(n)} +
                  </option>
                ))}
              </select>
              <select
                aria-label={t("label")}
                value={s.filters.label}
                onChange={(e) => filter({ label: e.target.value })}
              >
                <option value="all">{t("label")}</option>
                {labels.map((label) => (
                  <option key={label} value={label}>
                    {t(label)}
                  </option>
                ))}
              </select>
              <button
                className="text-button"
                title={t("clearFilters")}
                onClick={() => patch({ filters: defaultFilters })}
              >
                ×
              </button>
              <span className="spacer" />
              <select
                aria-label={t("sort")}
                value={s.filters.sort}
                onChange={(e) => filter({ sort: e.target.value })}
              >
                {["date", "name", "size", "rating"].map((key) => (
                  <option key={key} value={key}>
                    {t(key)}
                  </option>
                ))}
              </select>
              <IconButton
                title={t(s.filters.desc ? "descending" : "ascending")}
                onClick={() => filter({ desc: !s.filters.desc })}
              >
                <ArrowDownUp size={15} />
              </IconButton>
              <input
                className="size-range"
                type="range"
                aria-label={t("thumbnailSize")}
                min={130}
                max={260}
                value={s.thumbnail}
                onChange={(e) => patch({ thumbnail: Number(e.target.value) })}
              />
            </div>
            <Grid files={files} />
            <footer className="statusbar">
              <span>
                {s.scanning && <LoaderCircle size={13} className="spin" />}
                {t("shown", { shown: files.length, total: s.files.length })}
              </span>
              <span>
                {s.selected.size
                  ? t("selected", { count: s.selected.size })
                  : t("shortcuts")}
              </span>
            </footer>
          </main>
          <Inspector />
        </div>
      </div>
      {(s.modal === "settings" || s.modal === "about") && <Settings />}
      {(s.modal === "delete" || s.modal === "import") && <Operations />}
      {s.preview && <Preview files={files} />}
      {s.editor && <Editor key={s.editor} />}
      {s.error && (
        <Modal title={t("error")} onClose={() => patch({ error: null })}>
          <div className="modal-body">
            <pre>{s.error}</pre>
            <footer>
              <button
                className="primary"
                onClick={() => patch({ error: null })}
              >
                {t("dismiss")}
              </button>
            </footer>
          </div>
        </Modal>
      )}
      {s.notice && (
        <button className="toast" onClick={() => patch({ notice: null })}>
          {s.notice} ×
        </button>
      )}
    </>
  );
}
