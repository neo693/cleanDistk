# CleanDisk

**CleanDisk** 是一款专为 macOS 打造的高效磁盘清理与空间可视化工具。基于 **SwiftUI** 与 **AppKit** 原生开发，具备极佳的性能与优雅的交互体验。

---

## 🌟 核心功能

### 1. 📊 磁盘空间可视化 (Treemap & 目录树)
- **矩形树图 (Treemap View)**：直观展示磁盘文件与文件夹的空间占用比例，按文件大小以不同色彩区块呈现。
- **目录树视图 (Directory Tree View)**：支持按层级展开/收起目录，迅速锁定占用空间最大的“大文件”。
- **文件联动**：支持双击下钻文件夹、右键定位在 Finder 中查看或安全移至废纸篓。

### 2. 🛠️ 开发者专用清理 (Developer Cleaner)
针对开发者痛点，深度扫描并一键清理缓存与中间构建文件：
- **Xcode**：DerivedData、Archives、iOS/macOS Simulator 模拟器缓存及 DeviceSupport。
- **Node.js**：`node_modules` 依赖文件夹、npm / yarn / pnpm 全局缓存。
- **Python**：`pip` 缓存、虚拟环境 (`.venv` / `venv`)、`__pycache__` 字节码。
- **Rust & Go**：Cargo / Go build 及 module 编译缓存与 `target` 目录。
- **Package Managers**：CocoaPods, Carthage, Swift Package Manager (SPM) 缓存。

### 3. 🤖 AI 大模型缓存清理 (Large Model Cleaner)
随着本地 AI 工具普及，大模型权重与缓存迅速消耗磁盘空间。CleanDisk 专门优化了对本地 AI 工具链的扫描：
- **HuggingFace** (`~/.cache/huggingface`)
- **Ollama Models** (`~/.ollama/models`)
- **LM Studio** (`~/.cache/lm-studio`)
- **PyTorch / vLLM** (`~/.cache/torch`)

### 4. 🗑️ 卸载残留文件清理 (App Leftover Cleaner)
智能检测已被卸载软件残留在系统内的配置文件、日志和缓存：
- 扫描 `~/Library/Application Support`
- 扫描 `~/Library/Caches`
- 扫描 `~/Library/Preferences`
- 扫描 `~/Library/Logs` 及 `Saved Application State`

### 5. 🌐 浏览器缓存清理 (Browser Cleaner)
支持主流 Mac 浏览器的缓存文件一键清理：
- Safari, Google Chrome, Microsoft Edge, Mozilla Firefox, Brave, Arc

### 6. 🛡️ 安全防误删机制
- 所有清理操作默认**将文件移至 macOS 系统废纸篓 (Trash)**，避免硬删除导致的数据丢失。
- 关键系统目录防误删安全保护机制。

---

## 💻 系统要求

- **操作系统**：macOS 13.0 (Ventura) 或更高版本
- **架构**：Apple Silicon (M1/M2/M3/M4) 及 Intel 架构全支持
- **开发工具**：Swift 5.9+ / Xcode 15+

---

## 🚀 编译与运行

### 1. 本地直接运行
在项目根目录下，使用 Swift Package Manager 命令行直接构建并启动：

```bash
swift run
```

### 2. 一键打包 Release 应用与 DMG 镜像
项目提供了自动化构建打包脚本 `build.sh`，可完成 Release 编译、自动生成应用图标 `AppIcon.icns`、打包 `.app` 应用包以及生成可安装的 `.dmg` 文件：

```bash
# 赋予脚本执行权限（如需要）
chmod +x build.sh

# 运行构建打包脚本
./build.sh
```

构建完成后，根目录下会生成：
- `CleanDisk.app`：原生 macOS 应用包（可通过 `open CleanDisk.app` 运行）
- `CleanDisk.dmg`：标准的 macOS 安装镜像

---

## 🏗️ 项目架构

项目使用现代 **MVVM** 模式编写，源码位于 `Sources/` 目录下：

```text
Sources/
├── App/
│   └── MacDiskCleanerApp.swift       # 应用入口与生命周期管理
├── Models/
│   ├── DiskNode.swift                # 磁盘文件树与尺寸节点模型
│   ├── CleanerItem.swift             # 清理项目数据模型
│   └── ScanError.swift               # 扫描异常与错误枚举
├── Services/
│   ├── DiskScanner.swift             # 多线程并发磁盘扫描引擎
│   ├── DeveloperCleanerScanner.swift # 开发者缓存扫描器
│   ├── LargeModelCleanerScanner.swift# AI 模型缓存扫描器
│   ├── AppLeftoverScanner.swift      # 应用残留扫描器
│   ├── BrowserCleanerScanner.swift   # 浏览器缓存扫描器
│   ├── TrashManager.swift            # 废纸篓安全删除服务
│   └── FileSystemWatcher.swift       # 文件系统变更实时监听
├── ViewModels/
│   └── MainViewModel.swift           # 全局与各模块状态 ViewModel
└── Views/
    ├── MainView.swift                # 主界面框架与侧边栏响应
    ├── TreemapView.swift             # 矩形树图可视化渲染视图
    ├── DirectoryTreeView.swift       # 树状文件列表视图
    ├── DeveloperCleanerView.swift    # 开发者清理模块视图
    ├── AppLeftoverCleanerView.swift  # 应用残留清理模块视图
    ├── BrowserCleanerView.swift      # 浏览器清理模块视图
    └── LargeModelCleanerView.swift   # 大模型清理模块视图
```

---

## 📄 开源许可

本项目采用 MIT 许可证，详情参阅 LICENSE 文件。
