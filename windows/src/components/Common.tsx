import { useEffect, useRef, useState, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { X, Star, ImageOff, LoaderCircle } from "lucide-react";
import { images } from "../lib/images";
import { type MediaFile, labels } from "../lib/types";
export function IconButton({
  title,
  children,
  onClick,
  disabled = false,
}: {
  title: string;
  children: ReactNode;
  onClick: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      className="icon-button"
      title={title}
      aria-label={title}
      disabled={disabled}
      onClick={onClick}
    >
      {children}
    </button>
  );
}
export function Modal({
  title,
  children,
  onClose,
  wide = false,
}: {
  title: string;
  children: ReactNode;
  onClose: () => void;
  wide?: boolean;
}) {
  const { t } = useTranslation();
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    dialog?.showModal();
    return () => dialog?.close();
  }, []);
  return (
    <dialog
      ref={ref}
      className={wide ? "modal wide" : "modal"}
      onCancel={(e) => {
        e.preventDefault();
        onClose();
      }}
    >
      <header>
        <h2>{title}</h2>
        <IconButton title={t("close")} onClick={onClose}>
          <X size={20} />
        </IconButton>
      </header>
      {children}
    </dialog>
  );
}
export function Stars({
  value,
  onChange,
}: {
  value: number;
  onChange: (n: number) => void;
}) {
  const { t } = useTranslation();
  return (
    <div className="stars" aria-label={t("rating")}>
      {[1, 2, 3, 4, 5].map((n) => (
        <button
          key={n}
          title={`${n} ${t("rating")}`}
          aria-label={`${n} ${t("rating")}`}
          className={n <= value ? "lit" : ""}
          onClick={() => onChange(n === value ? 0 : n)}
        >
          <Star size={17} fill={n <= value ? "currentColor" : "none"} />
        </button>
      ))}
    </div>
  );
}
export function Labels({
  value,
  onChange,
}: {
  value: string;
  onChange: (n: string) => void;
}) {
  const { t } = useTranslation();
  return (
    <div className="labels">
      {labels.map((label) => (
        <button
          key={label}
          title={t(label)}
          aria-label={t(label)}
          className={`swatch ${value === label ? "chosen" : ""}`}
          style={{
            background: label === "none" ? "transparent" : `var(--${label})`,
          }}
          onClick={() => onChange(label)}
        >
          {label === "none" ? "×" : ""}
        </button>
      ))}
    </div>
  );
}
export function Photo({
  file,
  px = 360,
  lane = "grid",
  className = "",
  style,
}: {
  file: MediaFile;
  px?: number;
  lane?: "grid" | "preview" | "prefetch";
  className?: string;
  style?: React.CSSProperties;
}) {
  const [data, setData] = useState<string | null>(null);
  const [loaded, setLoaded] = useState(false);
  useEffect(() => {
    setData(null);
    setLoaded(false);
    let alive = true;
    const ticket = images.request(file, px, lane);
    void ticket.promise.then((reply) => {
      if (alive) {
        setData(reply ?? null);
        setLoaded(true);
      }
    });
    return () => {
      alive = false;
      ticket.release();
    };
  }, [file.path, file.fingerprint, file.modified_nanos, px, lane]);
  return data ? (
    <img
      draggable={false}
      className={className}
      style={style}
      src={data}
      alt={file.name}
    />
  ) : (
    <span className="photo-placeholder">
      {loaded ? (
        <ImageOff size={28} />
      ) : (
        <LoaderCircle className="spin" size={22} />
      )}
    </span>
  );
}
