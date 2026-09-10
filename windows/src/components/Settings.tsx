import { useTranslation } from "react-i18next";
import { invoke } from "@tauri-apps/api/core";
import { useLibrary, patch, preferences, attempt } from "../lib/store";
import { Modal } from "./Common";
export default function Settings() {
  const s = useLibrary(),
    { t } = useTranslation(),
    p = s.database.preferences;
  return (
    <Modal
      title={t(s.modal === "settings" ? "settings" : "about")}
      onClose={() => patch({ modal: null })}
    >
      {s.modal === "settings" ? (
        <div className="modal-body settings-form">
          <label>
            {t("language")}
            <select
              value={p.language}
              onChange={(e) =>
                void preferences({ ...p, language: e.target.value })
              }
            >
              <option value="system">{t("system")}</option>
              <option value="zh-Hans">简体中文</option>
              <option value="en">English</option>
            </select>
          </label>
          <label>
            {t("prefetch")}
            <input
              type="number"
              min={0}
              max={20}
              value={p.prefetch}
              onChange={(e) =>
                void preferences({
                  ...p,
                  prefetch: Math.max(0, Math.min(20, Number(e.target.value))),
                })
              }
            />
          </label>
          <p className="muted">{t("prefetchHint")}</p>
          <label className="check">
            <input
              type="checkbox"
              checked={p.write_xmp}
              onChange={(e) =>
                void preferences({ ...p, write_xmp: e.target.checked })
              }
            />
            {t("xmp")}
          </label>
          <p className="muted">{t("xmpHint")}</p>
        </div>
      ) : (
        <div className="modal-body about">
          <img className="app-icon" src="/AppIcon-square.png" alt="Siftly" />
          <h1>Siftly</h1>
          <p className="muted">{t("version")}</p>
          <p>{t("aboutBody")}</p>
          <h3>{t("sponsor")}</h3>
          <div className="qr-row">
            <figure>
              <img src="/sponsor-wechat.png" alt={t("wechat")} />
              <figcaption>{t("wechat")}</figcaption>
            </figure>
            <figure>
              <img src="/sponsor-alipay.png" alt={t("alipay")} />
              <figcaption>{t("alipay")}</figcaption>
            </figure>
          </div>
          <button
            onClick={() =>
              void attempt(() =>
                invoke("open_path", { path: "", action: "paypal" }),
              )
            }
          >
            {t("paypal")}
          </button>
        </div>
      )}
    </Modal>
  );
}
