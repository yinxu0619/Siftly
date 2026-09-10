use std::{mem::size_of, path::Path};
use windows::{
    core::PCWSTR,
    Win32::{
        Foundation::SIZE,
        Graphics::Gdi::*,
        System::Com::{CoInitializeEx, CoUninitialize, COINIT_APARTMENTTHREADED},
        UI::{
            Shell::{
                IShellItemImageFactory, SHCreateItemFromParsingName, ShellExecuteW,
                SIIGBF_THUMBNAILONLY,
            },
            WindowsAndMessaging::SW_SHOWNORMAL,
        },
    },
};
struct Com(bool);
impl Drop for Com {
    fn drop(&mut self) {
        if self.0 {
            unsafe { CoUninitialize() }
        }
    }
}
struct Bitmap(HBITMAP);
impl Drop for Bitmap {
    fn drop(&mut self) {
        unsafe {
            let _ = DeleteObject(HGDIOBJ(self.0 .0));
        }
    }
}
struct Dc(HDC);
impl Drop for Dc {
    fn drop(&mut self) {
        unsafe {
            ReleaseDC(None, self.0);
        }
    }
}
fn shell_path(path: &str) -> String {
    if let Some(unc) = path.strip_prefix("\\\\?\\UNC\\") {
        format!("\\\\{unc}")
    } else {
        path.strip_prefix("\\\\?\\").unwrap_or(path).to_owned()
    }
}
fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(Some(0)).collect()
}
pub fn thumbnail(path: &Path, px: u32) -> Result<image::DynamicImage, String> {
    unsafe {
        let _com = Com(CoInitializeEx(None, COINIT_APARTMENTTHREADED).is_ok());
        let path = wide(&shell_path(&path.to_string_lossy()));
        let factory: IShellItemImageFactory =
            SHCreateItemFromParsingName(PCWSTR(path.as_ptr()), None).map_err(|e| e.to_string())?;
        let bitmap = Bitmap(
            factory
                .GetImage(
                    SIZE {
                        cx: px as i32,
                        cy: px as i32,
                    },
                    SIIGBF_THUMBNAILONLY,
                )
                .map_err(|e| e.to_string())?,
        );
        let dc = Dc(GetDC(None));
        if dc.0 .0.is_null() {
            return Err("thumbnail_dc_failed".into());
        }
        let mut info = BITMAPINFO::default();
        info.bmiHeader.biSize = size_of::<BITMAPINFOHEADER>() as u32;
        if GetDIBits(dc.0, bitmap.0, 0, 0, None, &mut info, DIB_RGB_COLORS) == 0 {
            return Err("thumbnail_dimensions_failed".into());
        }
        let width = info.bmiHeader.biWidth.unsigned_abs();
        let height = info.bmiHeader.biHeight.unsigned_abs();
        if width == 0 || height == 0 || width > 8192 || height > 8192 {
            return Err("invalid_thumbnail_size".into());
        }
        info.bmiHeader.biWidth = width as i32;
        info.bmiHeader.biHeight = -(height as i32);
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        info.bmiHeader.biCompression = BI_RGB.0;
        let mut pixels = vec![0u8; (width * height * 4) as usize];
        if GetDIBits(
            dc.0,
            bitmap.0,
            0,
            height,
            Some(pixels.as_mut_ptr().cast()),
            &mut info,
            DIB_RGB_COLORS,
        ) != height as i32
        {
            return Err("thumbnail_read_failed".into());
        }
        for pixel in pixels.as_chunks_mut::<4>().0 {
            pixel.swap(0, 2);
            pixel[3] = 255;
        }
        image::RgbaImage::from_raw(width, height, pixels)
            .map(image::DynamicImage::ImageRgba8)
            .ok_or("thumbnail_failed".into())
    }
}
pub fn open(path: &str, reveal: bool) -> Result<(), String> {
    if reveal {
        std::process::Command::new("explorer.exe")
            .arg(format!("/select,{}", shell_path(path)))
            .spawn()
            .map_err(|e| e.to_string())?;
        return Ok(());
    }
    let target = wide(&shell_path(path));
    let verb = wide("open");
    let result = unsafe {
        ShellExecuteW(
            None,
            PCWSTR(verb.as_ptr()),
            PCWSTR(target.as_ptr()),
            PCWSTR::null(),
            PCWSTR::null(),
            SW_SHOWNORMAL,
        )
    };
    if result.0 as isize <= 32 {
        return Err(format!("shell_open_failed: {}", result.0 as isize));
    }
    Ok(())
}

use std::sync::{Arc, Mutex};
use windows::{
    core::{implement, Ref, HRESULT},
    Win32::{
        Foundation::E_ABORT,
        System::Com::{CoCreateInstance, CLSCTX_ALL},
        UI::Shell::*,
    },
};
#[implement(IFileOperationProgressSink)]
struct RecycleSink {
    result: Arc<Mutex<Option<HRESULT>>>,
    recycled_id: Arc<Mutex<Option<String>>>,
}
#[allow(non_snake_case)]
impl IFileOperationProgressSink_Impl for RecycleSink_Impl {
    fn StartOperations(&self) -> windows::core::Result<()> {
        Ok(())
    }
    fn FinishOperations(&self, hrresult: HRESULT) -> windows::core::Result<()> {
        hrresult.ok()
    }
    fn PreRenameItem(
        &self,
        dwflags: u32,
        _psiitem: Ref<'_, IShellItem>,
        _psznewname: &PCWSTR,
    ) -> windows::core::Result<()> {
        let _ = dwflags;
        Err(E_ABORT.into())
    }
    fn PostRenameItem(
        &self,
        dwflags: u32,
        _psiitem: Ref<'_, IShellItem>,
        _psznewname: &PCWSTR,
        _hrrename: HRESULT,
        _psinewlycreated: Ref<'_, IShellItem>,
    ) -> windows::core::Result<()> {
        let _ = dwflags;
        Err(E_ABORT.into())
    }
    fn PreMoveItem(
        &self,
        dwflags: u32,
        _psiitem: Ref<'_, IShellItem>,
        _psidestinationfolder: Ref<'_, IShellItem>,
        _psznewname: &PCWSTR,
    ) -> windows::core::Result<()> {
        let _ = dwflags;
        Err(E_ABORT.into())
    }
    fn PostMoveItem(
        &self,
        dwflags: u32,
        _psiitem: Ref<'_, IShellItem>,
        _psidestinationfolder: Ref<'_, IShellItem>,
        _psznewname: &PCWSTR,
        _hrmove: HRESULT,
        _psinewlycreated: Ref<'_, IShellItem>,
    ) -> windows::core::Result<()> {
        let _ = dwflags;
        Err(E_ABORT.into())
    }
    fn PreCopyItem(
        &self,
        dwflags: u32,
        _psiitem: Ref<'_, IShellItem>,
        _psidestinationfolder: Ref<'_, IShellItem>,
        _psznewname: &PCWSTR,
    ) -> windows::core::Result<()> {
        let _ = dwflags;
        Err(E_ABORT.into())
    }
    fn PostCopyItem(
        &self,
        dwflags: u32,
        _psiitem: Ref<'_, IShellItem>,
        _psidestinationfolder: Ref<'_, IShellItem>,
        _psznewname: &PCWSTR,
        _hrcopy: HRESULT,
        _psinewlycreated: Ref<'_, IShellItem>,
    ) -> windows::core::Result<()> {
        let _ = dwflags;
        Err(E_ABORT.into())
    }
    fn PreDeleteItem(
        &self,
        dwflags: u32,
        _psiitem: Ref<'_, IShellItem>,
    ) -> windows::core::Result<()> {
        if dwflags & TSF_DELETE_RECYCLE_IF_POSSIBLE.0 as u32 == 0 {
            return Err(windows::core::Error::new(
                E_ABORT,
                "Recycling is unavailable; permanent deletion was blocked",
            ));
        }
        Ok(())
    }
    fn PostDeleteItem(
        &self,
        dwflags: u32,
        _psiitem: Ref<'_, IShellItem>,
        hrdelete: HRESULT,
        psinewlycreated: Ref<'_, IShellItem>,
    ) -> windows::core::Result<()> {
        let _ = dwflags;
        *self.result.lock().unwrap() = Some(hrdelete);
        hrdelete.ok()?;
        if let Some(item) = psinewlycreated.as_ref() {
            unsafe {
                let value = item.GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING)?;
                let id = value.to_string();
                windows::Win32::System::Com::CoTaskMemFree(Some(value.0.cast()));
                *self.recycled_id.lock().unwrap() = Some(id?);
            }
        }
        Ok(())
    }
    fn PreNewItem(
        &self,
        dwflags: u32,
        _psidestinationfolder: Ref<'_, IShellItem>,
        _psznewname: &PCWSTR,
    ) -> windows::core::Result<()> {
        let _ = dwflags;
        Err(E_ABORT.into())
    }
    fn PostNewItem(
        &self,
        dwflags: u32,
        _psidestinationfolder: Ref<'_, IShellItem>,
        _psznewname: &PCWSTR,
        _psztemplatename: &PCWSTR,
        _dwfileattributes: u32,
        _hrnew: HRESULT,
        _psinewitem: Ref<'_, IShellItem>,
    ) -> windows::core::Result<()> {
        let _ = dwflags;
        Err(E_ABORT.into())
    }
    fn UpdateProgress(&self, _iworktotal: u32, _iworksofar: u32) -> windows::core::Result<()> {
        Ok(())
    }
    fn ResetTimer(&self) -> windows::core::Result<()> {
        Ok(())
    }
    fn PauseTimer(&self) -> windows::core::Result<()> {
        Ok(())
    }
    fn ResumeTimer(&self) -> windows::core::Result<()> {
        Ok(())
    }
}
pub fn recycle(path: &Path) -> Result<crate::model::RecycledFile, String> {
    unsafe {
        let _com = Com(CoInitializeEx(None, COINIT_APARTMENTTHREADED).is_ok());
        let operation: IFileOperation = CoCreateInstance(&FileOperation, None, CLSCTX_ALL)
            .map_err(|e| format!("recycle_create_operation: {e}"))?;
        operation
            .SetOperationFlags(
                FOF_NO_UI | FOF_WANTNUKEWARNING | FOFX_RECYCLEONDELETE | FOFX_EARLYFAILURE,
            )
            .map_err(|e| e.to_string())?;
        let original = path.to_string_lossy().to_string();
        let path = wide(&shell_path(&original));
        let item: IShellItem = SHCreateItemFromParsingName(PCWSTR(path.as_ptr()), None)
            .map_err(|e| format!("recycle_create_item: {e}"))?;
        let result = Arc::new(Mutex::new(None));
        let recycled_id = Arc::new(Mutex::new(None));
        let sink: IFileOperationProgressSink = RecycleSink {
            result: result.clone(),
            recycled_id: recycled_id.clone(),
        }
        .into();
        operation
            .DeleteItem(&item, &sink)
            .map_err(|e| e.to_string())?;
        operation
            .PerformOperations()
            .map_err(|e| format!("recycle_perform: {e}"))?;
        if operation
            .GetAnyOperationsAborted()
            .map_err(|e| e.to_string())?
            .as_bool()
        {
            return Err("recycle_unavailable".into());
        }
        let status = *result.lock().unwrap();
        status
            .ok_or("recycle_not_completed")?
            .ok()
            .map_err(|e| e.to_string())?;
        let id = recycled_id
            .lock()
            .unwrap()
            .take()
            .ok_or("recycle_receipt_unavailable")?;
        Ok(crate::model::RecycledFile { id, path: original })
    }
}
pub fn restore(item: &crate::model::RecycledFile) -> Result<(), String> {
    unsafe {
        let destination = Path::new(&item.path);
        if destination.symlink_metadata().is_ok() {
            return Err("destination_exists".into());
        }
        let _com = Com(CoInitializeEx(None, COINIT_APARTMENTTHREADED).is_ok());
        let operation: IFileOperation =
            CoCreateInstance(&FileOperation, None, CLSCTX_ALL).map_err(|e| e.to_string())?;
        // A racing file creation must never replace the user's new file.
        operation
            .SetOperationFlags(FOF_NO_UI | FOF_RENAMEONCOLLISION | FOFX_EARLYFAILURE)
            .map_err(|e| e.to_string())?;
        let id = wide(&item.id);
        let source: IShellItem =
            SHCreateItemFromParsingName(PCWSTR(id.as_ptr()), None).map_err(|e| e.to_string())?;
        let folder = wide(&shell_path(
            &destination
                .parent()
                .ok_or("invalid_restore_path")?
                .to_string_lossy(),
        ));
        let folder: IShellItem = SHCreateItemFromParsingName(PCWSTR(folder.as_ptr()), None)
            .map_err(|e| e.to_string())?;
        let name = wide(
            &destination
                .file_name()
                .ok_or("invalid_restore_path")?
                .to_string_lossy(),
        );
        operation
            .MoveItem(&source, &folder, PCWSTR(name.as_ptr()), None)
            .map_err(|e| e.to_string())?;
        operation.PerformOperations().map_err(|e| e.to_string())?;
        if operation
            .GetAnyOperationsAborted()
            .map_err(|e| e.to_string())?
            .as_bool()
            || !destination.is_file()
        {
            return Err("restore_not_completed".into());
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn shell_paths_handle_drive_and_unc_prefixes() {
        assert_eq!(
            shell_path(r"\\?\C:\Photos\image.jpg"),
            r"C:\Photos\image.jpg"
        );
        assert_eq!(
            shell_path(r"\\?\UNC\server\share\image.jpg"),
            r"\\server\share\image.jpg"
        );
        assert_eq!(shell_path(r"C:\Photos\image.jpg"), r"C:\Photos\image.jpg");
    }
}
