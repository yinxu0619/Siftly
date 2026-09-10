import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useTranslation } from "react-i18next";
import { SlidersHorizontal, ScanEye, FileImage } from "lucide-react";
import { useLibrary, mark, patch } from "../lib/store";
import { emptyMark, type Exif, type MediaFile } from "../lib/types";
import { bytes, date } from "../lib/format";
import { Photo, Stars, Labels } from "./Common";
export function Details({ file }: { file: MediaFile }) {
  const { t } = useTranslation();
  const [exif, setExif] = useState<Exif | null>(null);
  useEffect(() => {
    let alive = true;
    setExif(null);
    void invoke<Exif>("read_exif", { path: file.path })
      .then((value) => {
        if (alive) setExif(value);
      })
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, [file.path]);
  const rows: [string, string | number | null | undefined][] = [
    ["filename", file.name],
    ["size", bytes(file.file_size)],
    ["modified", date(file.modified)],
    ["location", file.directory],
    [
      "dimensions",
      exif?.width && exif.height ? `${exif.width} × ${exif.height}` : null,
    ],
    ...(
      [
        "camera",
        "lens",
        "iso",
        "aperture",
        "shutter",
        "focal",
        "captured",
      ] as const
    ).map((key) => [key, exif?.[key]] as [string, string | null | undefined]),
  ];
  return (
    <dl className="details">
      {rows
        .filter(([, value]) => value)
        .map(([key, value]) => (
          <div key={key}>
            <dt>{t(key)}</dt>
            <dd title={String(value)}>{value}</dd>
          </div>
        ))}
    </dl>
  );
}
export default function Inspector() {
  const { t } = useTranslation();
  const s = useLibrary();
  const file = s.files.find((f) => f.path === [...s.selected].at(-1));
  const value = file
    ? (s.database.marks[file.key] ?? emptyMark())
    : emptyMark();
  return (
    <aside className="inspector">
      <div className="section-heading">
        {t("inspector")}
        <FileImage size={15} />
      </div>
      {file ? (
        <>
          <div className="inspector-photo">
            <Photo file={file} px={560} />
          </div>
          <h3 title={file.name}>{file.name}</h3>
          <span className="muted">
            {file.ext.toUpperCase()} · {bytes(file.file_size)}
          </span>
          <div className="mark-controls">
            <Stars
              value={value.rating}
              onChange={(rating) => void mark([...s.selected], { rating })}
            />
            <Labels
              value={value.label || "none"}
              onChange={(label) => void mark([...s.selected], { label })}
            />
          </div>
          <div className="button-row">
            <button onClick={() => patch({ preview: file.path })}>
              <ScanEye size={15} />
              {t("preview")}
            </button>
            <button
              disabled={file.is_video}
              onClick={() => patch({ editor: file.path })}
            >
              <SlidersHorizontal size={15} />
              {t("edit")}
            </button>
          </div>
          <Details file={file} />
        </>
      ) : (
        <div className="empty small">
          <FileImage size={32} />
          <p>{t("pickPhoto")}</p>
        </div>
      )}
    </aside>
  );
}
