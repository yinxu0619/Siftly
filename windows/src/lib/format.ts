import i18n from "../i18n";
export function bytes(n: number) {
  if (n <= 0) return "0 B";
  const i = Math.min(Math.floor(Math.log(n) / Math.log(1024)), 4);
  return `${new Intl.NumberFormat(i18n.language, { maximumFractionDigits: i ? 1 : 0 }).format(n / 1024 ** i)} ${["B", "KB", "MB", "GB", "TB"][i]}`;
}
export function date(n: number) {
  return n
    ? new Intl.DateTimeFormat(i18n.language, {
        dateStyle: "medium",
        timeStyle: "short",
      }).format(n * 1000)
    : "—";
}
export function errorText(error: unknown) {
  const message = String(error);
  return i18n.exists(message) ? i18n.t(message) : message;
}
