# Siftly for Windows

独立的 Windows 桌面客户端，使用 Tauri 2、Rust 和 React。Windows 10 / 11 x64；界面支持简体中文和英文。

## 运行和安装

GitHub Actions 的 **Windows build** 工作流会运行检查并生成 `Siftly-Windows-x64` 构建产物：

- `Siftly_*_x64-setup.exe`：普通用户安装程序，提供中英文安装界面。
- `Siftly_*_x64_en-US.msi`：MSI 安装程序。
- `Siftly-*-Windows-x64-portable.zip`：解压后运行 `Siftly.exe`。设置仍保存在用户应用数据目录。
- `Siftly-*-source.zip`：对应源码和 Rust 依赖，用于重建及重新链接 RAW 解码库。
- `SHA256SUMS.txt`：产物校验和。

安装程序会在缺少 WebView2 时下载并安装运行环境。解压版要求系统已有 Microsoft Edge WebView2。构建产物未配置代码签名。

## 已实现

- 可移动磁盘检测和插拔刷新；手动打开文件夹，记住已添加的目录。
- RAW / JPEG / 视频配对，支持相机预设；跨卡、跨目录配对需要明确开启。
- 流式扫描、虚拟化缩略图网格、搜索、类型/配对/评分/标签筛选和排序。
- 点击、Ctrl+点击、Shift+点击多选；批量评分与颜色标签。
- 预览、缩放和平移、相邻照片预取、EXIF、资源管理器定位、默认应用打开。
- 删除前分别列出选中文件和配对文件；回收站删除、当前会话撤销、单独确认的永久删除。
- SHA-256 校验导入；按日期、月份、类型整理；跳过相同文件，重名自动改名；取消清理临时副本。
- 曝光、亮度、对比度、高光、阴影、HDR、饱和度、自然饱和度、色温、色调、锐化、暗角、色调曲线、旋转、翻转、校正角度和裁剪。
- 非破坏性编辑，保存每张照片的调整；JPEG / PNG / TIFF 导出，可调质量与长边尺寸，禁止覆盖目标已有文件。
- 评分和标签可选写入 XMP；保留已有 XMP 中其他编辑器的属性和嵌套数据。

## 键盘操作

| 位置 | 快捷键 |
| --- | --- |
| 图库 | Ctrl+A 全选；方向键移动；Shift+点击范围多选；Ctrl+点击增减选择 |
| 图库 | Space 预览；Delete 打开删除确认；Esc 清除选择；0–5 评分 |
| 预览 | ← / → 切换；滚轮缩放；拖动平移；双击放大/适应；0–5 评分；Esc / Space 关闭 |
| 编辑器 | Ctrl+Z 撤销；Ctrl+Shift+Z 重做；Esc 保存调整并关闭 |

## 与 macOS 版的差异

- RAW 使用 Rawler 开发，不使用 Apple Core Image。支持的相机型号和色彩结果可能不同。
- HEIC / HEIF 与视频缩略图使用 Windows Shell，依赖系统已安装的解码扩展；视频通过默认播放器打开。当前不提供 HEIC 编辑/导出、内嵌视频播放器和自动地平线校正。
- 日期整理依据文件修改时间。复制保留修改时间；导出的新图不复制原始 EXIF / ICC / XMP。
- 当前支持写出 XMP 评分和标签，尚未提供从现有 XMP 批量导入标记的入口。编辑参数保存在本地索引。
- 标准裁剪和分段线性色调曲线已实现；不包含 macOS 版的框选、多点曲线平滑插值。
- 删除撤销只记录本次运行中最后一批回收站操作。某些可移动磁盘不支持回收；应用会报告失败，不自动转为永久删除。

## 开发环境

安装 [Node.js 22 LTS](https://nodejs.org/)、[Rust stable MSVC 工具链](https://rustup.rs/) 和 [Visual Studio 2022 Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/)。Build Tools 勾选 **使用 C++ 的桌面开发** 和 Windows SDK。详见 [Tauri Windows 前置条件](https://v2.tauri.app/start/prerequisites/#windows)。

在仓库根目录打开 PowerShell：

```powershell
./windows/scripts/dev.ps1 dev
./windows/scripts/dev.ps1 test
./windows/scripts/dev.ps1 build
```

也可以直接运行：

```powershell
cd windows
npm ci
npm run tauri -- dev
# 发布构建
npm run tauri -- build --bundles nsis,msi
```

输出位于 `windows/src-tauri/target/release/`，安装程序位于 `bundle/nsis/` 和 `bundle/msi/`。

完整验证：

```powershell
npm run format:check
npm test
npm run build
cargo fmt --manifest-path src-tauri/Cargo.toml --check
cargo clippy --manifest-path src-tauri/Cargo.toml --locked --all-targets -- -D warnings
cargo test --manifest-path src-tauri/Cargo.toml --locked --lib
npx playwright install chromium
npm run test:ui
```

浏览器测试使用模拟的本地文件桥接，验证界面交互，不读取或删除真实照片。Windows 原生测试使用临时生成的图像，验证系统缩略图及回收站恢复；真实存储卡、RAW 相机样本、HEIC 扩展和安装器仍需在目标设备上验收。

## 数据与性能

Tauri 应用标识为 `com.yinxu.siftly.windows`；`library.json` 保存目录、设置、评分、标签与编辑参数，使用临时文件加原子替换。文件条目仅在内存中建立，原片无需复制进数据库。

扫描以 256 个文件为一批传输。缩略图、当前预览和预取有独立并发配额 4 / 2 / 1；离屏请求取消，重复请求合并。浏览器图像缓存限制为约 96 MiB，后端编码缓存限制为 64 MiB；磁盘缩略图最多 512 MiB / 8192 个文件。编辑预览最多 1800 像素，最终导出重新读取原图。

导入和导出先写同目录临时文件，再以禁止覆盖的方式提交。破坏性操作前复核文件大小、修改时间和操作系统文件身份，阻止扫描后被替换的文件遭到误删。原始文件修改时间和 Windows 卷/文件身份用于检测变化；不支持在其他程序同时改写照片时执行清理。

## 源码结构

- `src/`：三栏图库、预览、编辑器与确认对话框。
- `src-tauri/src/`：扫描、配对、校验复制、文件安全、RAW 解码、编辑、XMP 和 Windows Shell。
- `e2e/`：Playwright 界面回归测试。
- `scripts/`：Windows 开发和产物打包脚本。
- `../.github/workflows/build-windows.yml`：Windows 原生测试及 EXE / MSI 构建。

第三方组件与 RAW 解码库重建方式见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
