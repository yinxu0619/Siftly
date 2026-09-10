import { useEffect, useState } from "react";
import { Channel, invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import { useTranslation } from "react-i18next";
import { FolderOpen, ShieldCheck, AlertTriangle } from "lucide-react";
import { useLibrary, patch, fail, refresh } from "../lib/store";
import type {
  DeletionPlan,
  ImportPlan,
  ImportSettings,
  Outcome,
  Progress,
  MediaFile,
} from "../lib/types";
import { bytes } from "../lib/format";
import { Modal } from "./Common";
function FileList({ files }: { files: MediaFile[] }) {
  return (
    <ul className="file-list">
      {files.map((f) => (
        <li key={f.path}>
          <span title={f.path}>
            {f.name}
            <small>
              {f.volume_name} · {f.directory}
            </small>
          </span>
          <span>{bytes(f.file_size)}</span>
        </li>
      ))}
    </ul>
  );
}
export default function Operations() {
  const s = useLibrary(),
    { t } = useTranslation();
  const [deletion, setDeletion] = useState<DeletionPlan | null>(null);
  const [plan, setPlan] = useState<ImportPlan | null>(null);
  const [permanent, setPermanent] = useState(false);
  const [settings, setSettings] = useState<ImportSettings>({
    destination: "",
    organization: "date",
    include_paired: true,
    delete_after: false,
  });
  const [working, setWorking] = useState(false);
  const [progress, setProgress] = useState<Progress | null>(null);
  const [operation, setOperation] = useState<string | null>(null);
  const [result, setResult] = useState<Outcome | null>(null);
  const close = () => {
    if (working) {
      if (operation) void invoke("cancel", { id: operation });
      return;
    }
    patch({ modal: null });
  };
  useEffect(() => {
    let alive = true;
    if (s.modal === "delete")
      void invoke<DeletionPlan>("plan_deletion", {
        selected: [...s.selected],
        rule: s.rule,
      })
        .then((value) => {
          if (alive) setDeletion(value);
        })
        .catch(fail);
    return () => {
      alive = false;
    };
  }, []);
  async function buildPlan() {
    const id = crypto.randomUUID();
    setOperation(id);
    setWorking(true);
    patch({ busy: true });
    try {
      setPlan(
        await invoke<ImportPlan>("plan_import", {
          selected: [...s.selected],
          rule: s.rule,
          settings,
          id,
        }),
      );
    } catch (error) {
      if (String(error) !== "cancelled") fail(error);
    } finally {
      setWorking(false);
      setOperation(null);
      patch({ busy: false });
    }
  }
  async function run() {
    const id = crypto.randomUUID();
    setOperation(id);
    setWorking(true);
    patch({ busy: true });
    const channel = new Channel<Progress>();
    channel.onmessage = setProgress;
    try {
      const outcome = await invoke<Outcome>(
        s.modal === "delete" ? "delete_files" : "perform_import",
        {
          planId: s.modal === "delete" ? deletion!.id : plan!.id,
          permanent,
          id,
          onEvent: channel,
        },
      );
      setResult(outcome);
      if (s.modal === "delete" && !permanent && outcome.completed.length)
        patch({ canUndo: true });
      patch({ busy: false });
      await refresh();
    } catch (error) {
      fail(error);
      patch({ modal: null });
    } finally {
      setWorking(false);
      patch({ busy: false });
      setOperation(null);
    }
  }
  const change = (next: Partial<ImportSettings>) => {
    setSettings({ ...settings, ...next });
    setPlan(null);
  };
  return (
    <Modal
      title={t(s.modal === "delete" ? "deleteTitle" : "importTitle")}
      onClose={close}
      wide
    >
      {result ? (
        <div className="modal-body">
          <ShieldCheck className="accent" size={34} />
          <h3>
            {t(result.cancelled ? "cancelled" : "completed", {
              count: result.completed.length,
            })}
          </h3>
          {result.skipped.length > 0 && (
            <p>{t("skipped", { count: result.skipped.length })}</p>
          )}
          {result.failures.length > 0 && (
            <>
              <p className="warning">{t("operationFailed")}</p>
              <pre>{result.failures.join("\n")}</pre>
            </>
          )}
          <footer>
            <button className="primary" onClick={close}>
              {t("done")}
            </button>
          </footer>
        </div>
      ) : working ? (
        <div className="modal-body">
          <h3>{t(progress ? "working" : "planning")}</h3>
          <progress max={progress?.total || 1} value={progress?.done || 0} />
          <p className="muted">{progress?.name}</p>
          <p>
            {progress
              ? `${progress.done} / ${progress.total} · ${bytes(progress.bytes)}`
              : ""}
          </p>
          <footer>
            <button onClick={close}>{t("cancel")}</button>
          </footer>
        </div>
      ) : s.modal === "delete" ? (
        <div className="modal-body">
          {deletion ? (
            <>
              <h3>
                {t("direct")}{" "}
                <span className="count">{deletion.selected.length}</span>
              </h3>
              <FileList files={deletion.selected} />
              {deletion.paired.length > 0 && (
                <>
                  <h3>
                    {t("companions")}{" "}
                    <span className="count">{deletion.paired.length}</span>
                  </h3>
                  <FileList files={deletion.paired} />
                </>
              )}
              {s.rule.cross_location && deletion.paired.length > 0 && (
                <p className="warning">
                  <AlertTriangle size={16} />
                  {t("crossWarning")}
                </p>
              )}
              <label className="check">
                <input
                  type="checkbox"
                  checked={permanent}
                  onChange={(e) => setPermanent(e.target.checked)}
                />
                {t("permanent")}
              </label>
              <p className="muted">
                {t(permanent ? "permanentHint" : "trashHint")}
              </p>
              <footer>
                <span>
                  {t("total")}{" "}
                  {deletion.selected.length + deletion.paired.length} ·{" "}
                  {bytes(deletion.total_bytes)}
                </span>
                <button onClick={close}>{t("cancel")}</button>
                <button
                  className="danger"
                  disabled={!deletion.selected.length}
                  onClick={() => void run()}
                >
                  {t(permanent ? "permanent" : "trash")}
                </button>
              </footer>
            </>
          ) : (
            <p>{t("loading")}</p>
          )}
        </div>
      ) : (
        <div className="modal-body">
          <p className="muted">{t("importBody")}</p>
          <label>{t("destination")}</label>
          <div className="button-row">
            <input
              readOnly
              value={settings.destination}
              placeholder={t("choose")}
            />
            <button
              onClick={() =>
                void open({ directory: true, multiple: false })
                  .then((path) => {
                    if (typeof path === "string") change({ destination: path });
                  })
                  .catch(fail)
              }
            >
              <FolderOpen size={16} />
              {t("choose")}
            </button>
          </div>
          <label>
            {t("organization")}
            <select
              value={settings.organization}
              onChange={(e) => change({ organization: e.target.value })}
            >
              {[
                ["flat", "flat"],
                ["date", "byDate"],
                ["month", "byMonth"],
                ["kind", "byKind"],
              ].map(([value, key]) => (
                <option key={value} value={value}>
                  {t(key)}
                </option>
              ))}
            </select>
          </label>
          <label className="check">
            <input
              type="checkbox"
              checked={settings.include_paired}
              onChange={(e) => change({ include_paired: e.target.checked })}
            />
            {t("includePaired")}
          </label>
          <label className="check">
            <input
              type="checkbox"
              checked={settings.delete_after}
              onChange={(e) => change({ delete_after: e.target.checked })}
            />
            {t("deleteAfter")}
          </label>
          <p className="verified">
            <ShieldCheck size={17} />
            {t("verifyAlways")}
          </p>
          {plan && (
            <div className="import-plan">
              <strong>
                {t("copyCount", {
                  count: plan.items.length,
                  size: bytes(plan.total_bytes),
                })}
              </strong>
              <p>
                {t("free", { size: bytes(plan.free_bytes) })} ·{" "}
                {t("skipped", { count: plan.skipped.length })}
              </p>
              <FileList files={plan.items.map((i) => i.source)} />
            </div>
          )}
          <footer>
            <button onClick={close}>{t("cancel")}</button>
            <button
              className="primary"
              disabled={
                !settings.destination ||
                (!!plan &&
                  (!plan.items.length || plan.total_bytes > plan.free_bytes))
              }
              onClick={() => void (plan ? run() : buildPlan())}
            >
              {t(plan ? "startImport" : "confirm")}
            </button>
          </footer>
        </div>
      )}
    </Modal>
  );
}
