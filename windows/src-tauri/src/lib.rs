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
        // Thumbnails are served from the disk cache instead of as base64 over IPC.
        .register_asynchronous_uri_scheme_protocol("thumb", |ctx, request, responder| {
            let state = ctx
                .app_handle()
                .try_state::<std::sync::Arc<commands::AppData>>()
                .map(|s| s.inner().clone());
            let name = request.uri().path().trim_start_matches('/').to_owned();
            tauri::async_runtime::spawn_blocking(move || {
                use tauri::http::{header, Response};
                let response = match state.and_then(|s| s.thumbnail(&name)) {
                    Some(bytes) => Response::builder()
                        .header(header::CONTENT_TYPE, "image/jpeg")
                        .header(header::CACHE_CONTROL, "max-age=31536000, immutable")
                        .body(bytes),
                    None => Response::builder().status(404).body(Vec::new()),
                };
                responder.respond(response.unwrap());
            });
        })
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
