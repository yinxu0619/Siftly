export interface Volume {
  id: string;
  name: string;
  path: string;
  total: number;
  free: number;
  manual: boolean;
}
export interface MediaFile {
  path: string;
  name: string;
  base_name: string;
  ext: string;
  directory: string;
  file_size: number;
  modified: number;
  modified_nanos: string;
  fingerprint: string;
  volume_id: string;
  volume_name: string;
  volume_path: string;
  key: string;
  is_raw: boolean;
  is_video: boolean;
}
export interface Adjustments {
  exposure: number;
  brightness: number;
  contrast: number;
  highlights: number;
  shadows: number;
  hdr: number;
  saturation: number;
  vibrance: number;
  temperature: number;
  tint: number;
  sharpen: number;
  vignette: number;
  curve: [number, number][];
  rotation_quarters: number;
  straighten: number;
  flip_horizontal: boolean;
  crop_rect: [number, number, number, number] | null;
}
export const identity: Adjustments = {
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
export interface FileMark {
  rating: number;
  label: string;
  adjustments: Adjustments;
}
export const emptyMark = (): FileMark => ({
  rating: 0,
  label: "none",
  adjustments: structuredClone(identity),
});
export const labels = [
  "none",
  "red",
  "orange",
  "yellow",
  "green",
  "blue",
  "purple",
  "gray",
];
export interface Preferences {
  language: string;
  prefetch: number;
  write_xmp: boolean;
  show_exif: boolean;
}
export interface Database {
  marks: Record<string, FileMark>;
  preferences: Preferences;
}
export interface Rule {
  preset: string;
  cross_location: boolean;
}
export type Pairs = Record<string, string[]>;
export interface DeletionPlan {
  id: string;
  selected: MediaFile[];
  paired: MediaFile[];
  total_bytes: number;
}
export interface Outcome {
  completed: string[];
  skipped: string[];
  failures: string[];
  cancelled: boolean;
}
export interface Progress {
  id: string;
  done: number;
  total: number;
  name: string;
  bytes: number;
}
export interface ImageReply {
  data: string;
  width: number;
  height: number;
}
export interface Exif {
  width: number | null;
  height: number | null;
  camera: string | null;
  lens: string | null;
  iso: string | null;
  aperture: string | null;
  shutter: string | null;
  focal: string | null;
  captured: string | null;
}
export interface ImportSettings {
  destination: string;
  organization: string;
  include_paired: boolean;
  delete_after: boolean;
}
export interface ImportPlan {
  id: string;
  settings: ImportSettings;
  items: { source: MediaFile; destination: string }[];
  skipped: string[];
  total_bytes: number;
  free_bytes: number;
}
export type ScanEvent =
  | { kind: "batch"; files: MediaFile[] }
  | { kind: "warning"; message: string }
  | { kind: "done"; count: number };
