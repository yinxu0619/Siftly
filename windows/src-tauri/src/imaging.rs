use crate::model::*;
use image::{imageops::FilterType, DynamicImage, GenericImageView, ImageBuffer, Rgba};
use lru::LruCache;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::{fs::File, io::BufReader, num::NonZeroUsize, path::Path, sync::Arc};

pub struct Images {
    sources: Mutex<LruCache<String, Arc<DynamicImage>>>,
}
impl Default for Images {
    fn default() -> Self {
        Self {
            sources: Mutex::new(LruCache::new(NonZeroUsize::new(2).unwrap())),
        }
    }
}
impl Images {
    pub fn editor_source(&self, file: &MediaFile) -> Result<Arc<DynamicImage>, String> {
        let key = format!("{}|{}|{}", file.path, file.fingerprint, file.modified_nanos);
        if let Some(image) = self.sources.lock().get(&key) {
            return Ok(image.clone());
        }
        let source = decode(Path::new(&file.path), false)?;
        let image = Arc::new(source.resize(1800, 1800, FilterType::Triangle));
        self.sources.lock().put(key, image.clone());
        Ok(image)
    }
}
pub fn decode(path: &Path, embedded: bool) -> Result<DynamicImage, String> {
    let ext = path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or_default()
        .to_lowercase();
    if RAW.contains(&ext.as_str()) {
        let source = rawler::rawsource::RawSource::new(path).map_err(|e| e.to_string())?;
        let decoder = rawler::get_decoder(&source).map_err(|e| e.to_string())?;
        let params = rawler::decoders::RawDecodeParams::default();
        if embedded {
            if let Ok(Some(image)) = decoder.full_image(&source, &params) {
                return Ok(orient(image, orientation(path)));
            }
        }
        static RAW_DEVELOP: Mutex<()> = Mutex::new(());
        let _guard = RAW_DEVELOP.lock();
        let raw = decoder
            .raw_image(&source, &params, false)
            .map_err(|e| e.to_string())?;
        let result = rawler::imgop::develop::RawDevelop::default()
            .develop_intermediate(&raw)
            .map_err(|e| e.to_string())?;
        return result
            .to_dynamic_image()
            .map(|i| orient(i, raw.orientation.to_u16() as u32))
            .ok_or("raw_decode_failed".into());
    }
    let mut reader = image::ImageReader::open(path)
        .map_err(|e| e.to_string())?
        .with_guessed_format()
        .map_err(|e| e.to_string())?;
    let mut limits = image::Limits::default();
    limits.max_alloc = Some(768 * 1024 * 1024);
    reader.limits(limits);
    reader
        .decode()
        .map(|i| orient(i, orientation(path)))
        .map_err(|e| e.to_string())
}
fn orientation(path: &Path) -> u32 {
    File::open(path)
        .ok()
        .and_then(|f| {
            exif::Reader::new()
                .read_from_container(&mut BufReader::new(f))
                .ok()
        })
        .and_then(|e| {
            e.get_field(exif::Tag::Orientation, exif::In::PRIMARY)
                .and_then(|f| f.value.get_uint(0))
        })
        .unwrap_or(1)
}
fn orient(image: DynamicImage, orientation: u32) -> DynamicImage {
    match orientation {
        2 => image.fliph(),
        3 => image.rotate180(),
        4 => image.flipv(),
        5 => image.rotate90().fliph(),
        6 => image.rotate90(),
        7 => image.rotate270().fliph(),
        8 => image.rotate270(),
        _ => image,
    }
}
pub fn jpeg(image: &DynamicImage, quality: u8) -> Result<Vec<u8>, String> {
    let mut output = vec![];
    image::codecs::jpeg::JpegEncoder::new_with_quality(&mut output, quality)
        .encode_image(&DynamicImage::ImageRgb8(image.to_rgb8()))
        .map_err(|e| e.to_string())?;
    Ok(output)
}
#[derive(Clone, Default, Serialize)]
pub struct Exif {
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub camera: Option<String>,
    pub lens: Option<String>,
    pub iso: Option<String>,
    pub aperture: Option<String>,
    pub shutter: Option<String>,
    pub focal: Option<String>,
    pub captured: Option<String>,
}
pub fn exif_info(path: &Path) -> Exif {
    let mut info = Exif::default();
    if let Ok((w, h)) = image::image_dimensions(path) {
        info.width = Some(w);
        info.height = Some(h)
    }
    if let Ok(file) = File::open(path) {
        if let Ok(exif) = exif::Reader::new().read_from_container(&mut BufReader::new(file)) {
            let value = |tag| {
                exif.get_field(tag, exif::In::PRIMARY)
                    .map(|f| f.display_value().with_unit(&exif).to_string())
            };
            info.camera = value(exif::Tag::Model);
            info.lens = value(exif::Tag::LensModel);
            info.iso = value(exif::Tag::PhotographicSensitivity);
            info.aperture = value(exif::Tag::FNumber);
            info.shutter = value(exif::Tag::ExposureTime);
            info.focal = value(exif::Tag::FocalLength);
            info.captured = value(exif::Tag::DateTimeOriginal);
            if info.width.is_none() {
                info.width = exif
                    .get_field(exif::Tag::PixelXDimension, exif::In::PRIMARY)
                    .and_then(|f| f.value.get_uint(0));
                info.height = exif
                    .get_field(exif::Tag::PixelYDimension, exif::In::PRIMARY)
                    .and_then(|f| f.value.get_uint(0));
            }
        }
    }
    info
}
fn curve(value: f32, points: &[[f32; 2]]) -> f32 {
    if points.len() < 2 {
        return value;
    }
    if value <= points[0][0] {
        return points[0][1];
    }
    for segment in points.windows(2) {
        if value <= segment[1][0] {
            let t = (value - segment[0][0]) / (segment[1][0] - segment[0][0]).max(0.00001);
            return segment[0][1] + t * (segment[1][1] - segment[0][1]);
        }
    }
    points.last().unwrap()[1]
}
pub fn render(
    source: &DynamicImage,
    a: &Adjustments,
    include_crop: bool,
) -> Result<DynamicImage, String> {
    let numbers = [
        a.exposure,
        a.brightness,
        a.contrast,
        a.highlights,
        a.shadows,
        a.hdr,
        a.saturation,
        a.vibrance,
        a.temperature,
        a.tint,
        a.sharpen,
        a.vignette,
        a.straighten,
    ];
    if numbers.iter().any(|v| !v.is_finite())
        || a.curve.len() > 128
        || a.curve.iter().flatten().any(|v| !v.is_finite())
    {
        return Err("invalid_adjustments".into());
    }
    let mut points = a.curve.clone();
    for p in &mut points {
        p[0] = p[0].clamp(0., 1.);
        p[1] = p[1].clamp(0., 1.)
    }
    points.sort_by(|a, b| a[0].total_cmp(&b[0]));
    points.dedup_by(|a, b| a[0] == b[0]);
    let exposure = 2f32.powf(a.exposure.clamp(-100., 100.) / 50.);
    let hdr = a.hdr.clamp(0., 100.) / 100.;
    let mut pixels = source.to_rgba8();
    let (w, h) = pixels.dimensions();
    for (x, y, p) in pixels.enumerate_pixels_mut() {
        let mut rgb = [p[0] as f32 / 255., p[1] as f32 / 255., p[2] as f32 / 255.];
        for c in &mut rgb {
            *c *= exposure
        }
        let lum = rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
        let shadow = (a.shadows / 100. + hdr * 0.6).clamp(-1., 1.);
        let highlight = (a.highlights / 100. * 0.8 - hdr * 0.5).clamp(-1., 1.);
        for c in &mut rgb {
            *c += shadow * (1. - lum.clamp(0., 1.)).powi(2) * 0.32
                + highlight * lum.clamp(0., 1.).powi(2) * 0.4;
        }
        rgb[0] *=
            1. + a.temperature.clamp(-100., 100.) * 0.0015 + a.tint.clamp(-100., 100.) * 0.0005;
        rgb[2] *= 1. - a.temperature.clamp(-100., 100.) * 0.0015;
        rgb[1] *= 1. - a.tint.clamp(-100., 100.) * 0.001;
        let gray = rgb.iter().sum::<f32>() / 3.;
        let saturation = 1. + a.saturation.clamp(-100., 100.) / 100.;
        let chroma = rgb.iter().cloned().fold(f32::MIN, f32::max)
            - rgb.iter().cloned().fold(f32::MAX, f32::min);
        let vibrance = 1. + a.vibrance.clamp(-100., 100.) / 100. * (1. - chroma.clamp(0., 1.));
        let radius =
            ((x as f32 / w as f32 - 0.5).powi(2) + (y as f32 / h as f32 - 0.5).powi(2)) * 2.;
        let vignette = 1. - a.vignette.clamp(0., 100.) / 100. * radius.powi(2) * 0.8;
        for i in 0..3 {
            let color = gray + (rgb[i] - gray) * saturation * vibrance;
            let color = (color - 0.5) * (1. + a.contrast.clamp(-100., 100.) / 200.)
                + 0.5
                + a.brightness.clamp(-100., 100.) / 100. * 0.3;
            p[i] =
                (curve(color.clamp(0., 1.), &points).clamp(0., 1.) * vignette * 255.).round() as u8;
        }
    }
    let mut image = DynamicImage::ImageRgba8(pixels);
    let scale = (w.max(h) as f32 / 4000.).max(0.1);
    if hdr > 0. {
        image = image.unsharpen(12. * scale, ((1. - hdr * 0.8) * 12.) as i32);
    }
    if a.sharpen > 0. {
        image = image.unsharpen(scale, (12. - a.sharpen.clamp(0., 100.) / 10.) as i32);
    }
    image = match a.rotation_quarters.rem_euclid(4) {
        1 => image.rotate90(),
        2 => image.rotate180(),
        3 => image.rotate270(),
        _ => image,
    };
    if a.flip_horizontal {
        image = image.fliph()
    }
    if a.straighten.abs() > 0.001 {
        image = straighten(&image, a.straighten.clamp(-45., 45.));
    }
    if include_crop {
        if let Some([x, y, width, height]) = a.crop_rect {
            if [x, y, width, height].iter().any(|v| !v.is_finite())
                || x < 0.
                || y < 0.
                || width <= 0.
                || height <= 0.
                || x + width > 1.0001
                || y + height > 1.0001
            {
                return Err("invalid_crop".into());
            }
            let (w, h) = image.dimensions();
            let left = (x * w as f32) as u32;
            let top = (y * h as f32) as u32;
            if left >= w || top >= h {
                return Err("invalid_crop".into());
            }
            image = image.crop_imm(
                left,
                top,
                ((width * w as f32).round() as u32).max(1).min(w - left),
                ((height * h as f32).round() as u32).max(1).min(h - top),
            );
        }
    }
    Ok(image)
}
fn straighten(image: &DynamicImage, angle: f32) -> DynamicImage {
    let (w, h) = image.dimensions();
    let theta = angle.to_radians();
    let (sin, cos) = theta.sin_cos();
    // Uniformly inscribe an axis-aligned rectangle, excluding transparent corners.
    let scale = (w as f32 / (w as f32 * cos.abs() + h as f32 * sin.abs()))
        .min(h as f32 / (h as f32 * cos.abs() + w as f32 * sin.abs()));
    let out_w = (w as f32 * scale).floor().max(1.) as u32;
    let out_h = (h as f32 * scale).floor().max(1.) as u32;
    let input = image.to_rgba8();
    let out = ImageBuffer::from_fn(out_w, out_h, |x, y| {
        let dx = x as f32 + 0.5 - out_w as f32 / 2.;
        let dy = y as f32 + 0.5 - out_h as f32 / 2.;
        let sx = (cos * dx + sin * dy + w as f32 / 2. - 0.5).clamp(0., w as f32 - 1.);
        let sy = (-sin * dx + cos * dy + h as f32 / 2. - 0.5).clamp(0., h as f32 - 1.);
        let x0 = sx.floor() as u32;
        let y0 = sy.floor() as u32;
        let fx = sx - x0 as f32;
        let fy = sy - y0 as f32;
        let mut p = [0u8; 4];
        for (c, channel) in p.iter_mut().enumerate() {
            let top = input.get_pixel(x0, y0)[c] as f32 * (1. - fx)
                + input.get_pixel((x0 + 1).min(w - 1), y0)[c] as f32 * fx;
            let bottom = input.get_pixel(x0, (y0 + 1).min(h - 1))[c] as f32 * (1. - fx)
                + input.get_pixel((x0 + 1).min(w - 1), (y0 + 1).min(h - 1))[c] as f32 * fx;
            *channel = (top * (1. - fy) + bottom * fy).round() as u8;
        }
        Rgba(p)
    });
    DynamicImage::ImageRgba8(out)
}
#[derive(Clone, Deserialize)]
pub struct ExportSettings {
    pub format: String,
    pub quality: u8,
    pub max_edge: Option<u32>,
}
pub fn export(
    source: &Path,
    destination: &Path,
    a: &Adjustments,
    settings: &ExportSettings,
) -> Result<(), String> {
    if destination.symlink_metadata().is_ok() {
        return Err("destination_exists".into());
    }
    let full = decode(source, false)?;
    let mut output = render(&full, a, true)?;
    if let Some(edge) = settings.max_edge {
        let edge = edge.clamp(1, 16000);
        if output.width().max(output.height()) > edge {
            output = output.resize(edge, edge, FilterType::Lanczos3)
        }
    }
    let parent = destination.parent().ok_or("invalid_destination")?;
    std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    let mut temp = tempfile::NamedTempFile::new_in(parent).map_err(|e| e.to_string())?;
    match settings.format.as_str() {
        "jpeg" => {
            use std::io::Write;
            temp.write_all(&jpeg(&output, settings.quality.clamp(1, 100))?)
                .map_err(|e| e.to_string())?;
        }
        "png" => output
            .write_to(temp.as_file_mut(), image::ImageFormat::Png)
            .map_err(|e| e.to_string())?,
        "tiff" => output
            .write_to(temp.as_file_mut(), image::ImageFormat::Tiff)
            .map_err(|e| e.to_string())?,
        _ => return Err("unsupported_export".into()),
    }
    temp.as_file().sync_all().map_err(|e| e.to_string())?;
    temp.persist_noclobber(destination)
        .map_err(|e| e.to_string())?;
    Ok(())
}
