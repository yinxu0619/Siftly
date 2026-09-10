use crate::{files::*, imaging, model::*, store::Store, xmp};
use std::{
    fs,
    path::Path,
    sync::atomic::{AtomicBool, Ordering},
};
fn media(root: &Path, name: &str, data: &[u8]) -> MediaFile {
    let path = root.join(name);
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(&path, data).unwrap();
    read_media(
        &path.canonicalize().unwrap(),
        &crate::volumes::folder(root).unwrap(),
    )
    .unwrap()
}
fn settings(root: &Path) -> ImportSettings {
    ImportSettings {
        destination: root.to_string_lossy().into(),
        organization: "flat".into(),
        include_paired: true,
        delete_after: false,
    }
}
#[test]
fn pairing_is_scoped_and_cross_card_is_explicit() {
    let temp = tempfile::tempdir().unwrap();
    let a = media(temp.path(), "card-a/DCIM/DSC_1.ARW", b"raw");
    let b = media(temp.path(), "card-a/DCIM/dsc_1.JPG", b"jpg");
    let c = media(temp.path(), "card-b/DCIM/DSC_1.MP4", b"video");
    let files = vec![a.clone(), b.clone(), c.clone()];
    let normal = pair(&files, &Rule::default());
    assert_eq!(normal[&a.path], vec![b.path.clone()]);
    assert!(!normal.contains_key(&c.path));
    let cross = pair(
        &files,
        &Rule {
            cross_location: true,
            ..Rule::default()
        },
    );
    assert_eq!(cross[&a.path].len(), 2);
    let plan = deletion_plan(&files, &[a.path.clone(), b.path.clone()], &Rule::default());
    assert_eq!(plan.selected.len(), 2);
    assert!(plan.paired.is_empty());
    assert_eq!(plan.total_bytes, 6)
}
#[test]
fn deletion_plan_contains_companions_once() {
    let root = tempfile::tempdir().unwrap();
    let raw = media(root.path(), "A.NEF", b"123");
    let jpg = media(root.path(), "a.jpg", b"4567");
    let other = media(root.path(), "B.jpg", b"89");
    let plan = deletion_plan(
        &[raw.clone(), jpg, other],
        &[raw.path.clone(), raw.path],
        &Rule::default(),
    );
    assert_eq!(plan.selected.len(), 1);
    assert_eq!(plan.paired.len(), 1);
    assert_eq!(plan.total_bytes, 7)
}
#[test]
fn import_never_overwrites_and_skips_identical() {
    let source = tempfile::tempdir().unwrap();
    let target = tempfile::tempdir().unwrap();
    let a = media(source.path(), "a.jpg", b"new");
    let b = media(source.path(), "b.jpg", b"same");
    fs::write(target.path().join("a.jpg"), b"old").unwrap();
    fs::write(target.path().join("b.jpg"), b"same").unwrap();
    let plan = plan_import(&[a, b], settings(target.path()), &AtomicBool::new(false)).unwrap();
    assert_eq!(plan.items.len(), 1);
    assert!(plan.items[0].destination.ends_with("a-1.jpg"));
    assert_eq!(plan.skipped.len(), 1);
    copy_verified(
        Path::new(&plan.items[0].source.path),
        Path::new(&plan.items[0].destination),
        &AtomicBool::new(false),
        |_| {},
    )
    .unwrap();
    assert_eq!(fs::read(target.path().join("a.jpg")).unwrap(), b"old");
    assert_eq!(fs::read(target.path().join("a-1.jpg")).unwrap(), b"new")
}
#[test]
fn copy_commit_rejects_a_file_created_after_planning() {
    let root = tempfile::tempdir().unwrap();
    let src = root.path().join("source");
    let dst = root.path().join("target");
    fs::write(&src, vec![1; 100]).unwrap();
    assert!(copy_verified(&src, &dst, &AtomicBool::new(false), |_| {
        fs::write(&dst, b"external").unwrap()
    })
    .is_err());
    assert_eq!(fs::read(&dst).unwrap(), b"external");
    assert_eq!(fs::read_dir(root.path()).unwrap().count(), 2)
}
#[test]
fn cancelled_copy_cleans_staging() {
    let root = tempfile::tempdir().unwrap();
    let src = root.path().join("source");
    let dst = root.path().join("target");
    fs::write(&src, vec![1; 1000]).unwrap();
    let cancel = AtomicBool::new(false);
    assert_eq!(
        copy_verified(&src, &dst, &cancel, |_| cancel
            .store(true, Ordering::Relaxed))
        .unwrap_err(),
        "cancelled"
    );
    assert!(!dst.exists());
    assert_eq!(fs::read_dir(root.path()).unwrap().count(), 1)
}
#[test]
fn changed_file_is_detected() {
    let root = tempfile::tempdir().unwrap();
    let file = media(root.path(), "a.jpg", b"old");
    assert!(unchanged(&file));
    fs::write(&file.path, b"newer").unwrap();
    assert!(!unchanged(&file))
}
#[test]
fn marks_survive_restart_and_do_not_collide_between_volumes() {
    let a = tempfile::tempdir().unwrap();
    let b = tempfile::tempdir().unwrap();
    let db = tempfile::tempdir().unwrap();
    let one = media(a.path(), "a.jpg", b"one");
    let two = media(b.path(), "a.jpg", b"two");
    assert_ne!(one.key, two.key);
    let mut store = Store::open(db.path()).unwrap();
    store.data.marks.insert(
        one.key.clone(),
        FileMark {
            rating: 4,
            ..FileMark::default()
        },
    );
    store.save().unwrap();
    let store = Store::open(db.path()).unwrap();
    assert_eq!(store.data.marks[&one.key].rating, 4);
    assert!(!store.data.marks.contains_key(&two.key))
}
#[test]
fn corrupt_database_is_not_silently_replaced() {
    let root = tempfile::tempdir().unwrap();
    fs::write(root.path().join("library.json"), b"broken").unwrap();
    assert!(Store::open(root.path()).is_err());
    assert_eq!(
        fs::read(root.path().join("library.json")).unwrap(),
        b"broken"
    )
}
#[test]
fn xmp_preserves_unrelated_attributes_elements_and_nested_rating() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("a.nef");
    let side = source.with_extension("xmp");
    let original=br#"<x:xmpmeta xmlns:x="adobe:ns:meta/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:q="http://ns.adobe.com/xap/1.0/" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"><rdf:RDF><rdf:Description rdf:about="" q:Rating="2" crs:Exposure2012="+1.0"><q:Label>Blue</q:Label><crs:Mask><rdf:Description q:Rating="1"/></crs:Mask></rdf:Description><rdf:Description rdf:about="other" q:Rating="5"/></rdf:RDF></x:xmpmeta>"#;
    fs::write(&side, original).unwrap();
    let mark = FileMark {
        rating: 4,
        label: "red".into(),
        ..FileMark::default()
    };
    xmp::write(&source, &mark).unwrap();
    let first = fs::read_to_string(&side).unwrap();
    assert!(first.contains("crs:Exposure2012=\"+1.0\""));
    assert!(first.contains("q:Rating=\"4\""));
    assert!(first.contains("q:Rating=\"1\""));
    assert!(first.contains("q:Rating=\"5\""));
    assert!(!first.contains("<q:Label>"));
    xmp::write(&source, &mark).unwrap();
    assert_eq!(fs::read_to_string(side).unwrap(), first)
}
#[test]
fn malformed_xmp_is_not_overwritten() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("a.jpg");
    let side = source.with_extension("xmp");
    fs::write(&side, b"<rdf:RDF><broken>").unwrap();
    assert!(xmp::write(&source, &FileMark::default()).is_err());
    assert_eq!(fs::read(side).unwrap(), b"<rdf:RDF><broken>")
}
#[test]
fn identity_edit_and_normalized_crop() {
    let source = image::DynamicImage::ImageRgba8(image::RgbaImage::from_fn(20, 10, |x, y| {
        image::Rgba([x as u8 * 10, y as u8 * 20, 80, 255])
    }));
    assert_eq!(
        imaging::render(&source, &Adjustments::default(), true).unwrap(),
        source
    );
    let a = Adjustments {
        crop_rect: Some([0.25, 0.2, 0.5, 0.6]),
        ..Adjustments::default()
    };
    let edited = imaging::render(&source, &a, true).unwrap();
    assert_eq!((edited.width(), edited.height()), (10, 6));
    assert_eq!(
        edited.to_rgba8().get_pixel(0, 0),
        source.to_rgba8().get_pixel(5, 2)
    );
    let invalid = Adjustments {
        crop_rect: Some([0.9, 0.2, 0.5, 0.6]),
        ..a
    };
    assert!(imaging::render(&source, &invalid, true).is_err())
}
#[test]
fn export_has_correct_format_and_protects_existing_output() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("source.png");
    image::RgbaImage::from_pixel(40, 20, image::Rgba([100, 70, 30, 255]))
        .save(&source)
        .unwrap();
    for (name, format, expected) in [
        ("output.jpg", "jpeg", image::ImageFormat::Jpeg),
        ("output.png", "png", image::ImageFormat::Png),
        ("output.tif", "tiff", image::ImageFormat::Tiff),
    ] {
        let destination = root.path().join(name);
        let settings = imaging::ExportSettings {
            format: format.into(),
            quality: 90,
            max_edge: Some(20),
        };
        imaging::export(&source, &destination, &Adjustments::default(), &settings).unwrap();
        let bytes = fs::read(&destination).unwrap();
        assert_eq!(image::guess_format(&bytes).unwrap(), expected);
        assert_eq!(image::load_from_memory(&bytes).unwrap().width(), 20);
        assert!(
            imaging::export(&source, &destination, &Adjustments::default(), &settings).is_err()
        );
        assert_eq!(fs::read(destination).unwrap(), bytes)
    }
}
#[test]
fn scanner_streams_supported_files_and_ignores_hidden_folders() {
    let root = tempfile::tempdir().unwrap();
    for i in 0..300 {
        media(root.path(), &format!("DCIM/{i}.jpg"), b"photo");
    }
    media(root.path(), ".hidden/a.jpg", b"hidden");
    media(root.path(), "DCIM/ignore.txt", b"text");
    let mut batches = vec![];
    scan(
        &crate::volumes::folder(root.path()).unwrap(),
        &AtomicBool::new(false),
        |files| batches.push(files.len()),
        |e| panic!("{e}"),
    )
    .unwrap();
    assert_eq!(batches, vec![256, 44])
}
#[cfg(unix)]
#[test]
fn scanner_does_not_follow_symlinks() {
    let root = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    let file = media(outside.path(), "outside.jpg", b"secret");
    std::os::unix::fs::symlink(&file.path, root.path().join("link.jpg")).unwrap();
    let mut count = 0;
    scan(
        &crate::volumes::folder(root.path()).unwrap(),
        &AtomicBool::new(false),
        |files| count += files.len(),
        |e| panic!("{e}"),
    )
    .unwrap();
    assert_eq!(count, 0)
}

#[test]
fn replacing_a_file_with_matching_size_and_timestamp_is_detected() {
    let root = tempfile::tempdir().unwrap();
    let file = media(root.path(), "a.jpg", b"old");
    let modified =
        filetime::FileTime::from_last_modification_time(&fs::metadata(&file.path).unwrap());
    fs::rename(&file.path, root.path().join("original.jpg")).unwrap();
    fs::write(&file.path, b"new").unwrap();
    filetime::set_file_mtime(&file.path, modified).unwrap();
    assert!(!unchanged(&file));
}
#[cfg(windows)]
#[test]
fn windows_recycle_and_restore_round_trip() {
    let root = tempfile::tempdir().unwrap();
    let file = media(root.path(), "Siftly-recycle-test.jpg", b"round trip");
    let item = crate::shell::recycle(Path::new(&file.path)).unwrap();
    assert!(!Path::new(&file.path).exists());
    assert!(!item.id.is_empty());
    fs::write(&file.path, b"new occupant").unwrap();
    assert!(crate::shell::restore(&item).is_err());
    assert_eq!(fs::read(&file.path).unwrap(), b"new occupant");
    fs::remove_file(&file.path).unwrap();
    crate::shell::restore(&item).unwrap();
    assert_eq!(fs::read(&file.path).unwrap(), b"round trip");
}
#[cfg(windows)]
#[test]
fn windows_shell_thumbnail() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("test.jpg");
    image::RgbImage::from_pixel(80, 40, image::Rgb([200, 100, 50]))
        .save(&source)
        .unwrap();
    let preview = crate::shell::thumbnail(&source.canonicalize().unwrap(), 128).unwrap();
    assert!(preview.width() > 0 && preview.width() <= 128);
    assert!(preview.height() > 0)
}
