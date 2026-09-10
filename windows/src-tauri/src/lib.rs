mod cache;
mod commands;
mod files;
mod imaging;
mod model;
#[cfg(windows)]
mod shell;
mod store;
#[cfg(test)]
mod tests;
mod volumes;
mod xmp;
use tauri::Manager;
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let data = app.path().app_data_dir()?;
            let cache = app.path().app_cache_dir()?;
            let state = commands::AppData::new(&data, &cache).map_err(std::io::Error::other)?;
            app.manage(std::sync::Arc::new(state));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::bootstrap,
            commands::list_volumes,
            commands::add_folder,
            commands::scan,
            commands::cancel,
            commands::compute_pairs,
            commands::image,
            commands::read_exif,
            commands::plan_deletion,
            commands::delete_files,
            commands::undo_delete,
            commands::set_marks,
            commands::save_preferences,
            commands::render_preview,
            commands::export_image,
            commands::plan_import,
            commands::perform_import,
            commands::open_path
        ])
        .run(tauri::generate_context!())
        .expect("Unable to start Siftly");
}
