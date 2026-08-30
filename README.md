# AI 学习工作流 · Linux 版

一套把「厚教材 → 能真正学会」的固定流程，封装成可一键复现的 Obsidian 库：
拆书（MinerU）→ 五级水平拆解 → 二八定律学习计划 → 十问测试 → 一页速查表。

本仓库是 **Linux 版**（主目标发行版：CachyOS / Arch Linux），对应 Windows 版仓库
[xiaomaogou66/HelpToStudy_Windows_Only](https://github.com/xiaomaogou66/HelpToStudy_Windows_Only)。
库内容（模板 / 提示词 / 斜杠命令 / Obsidian 配置）两边保持一致；`_工具` 为平台差异区。

> Linux 版只保留 **MinerU 拆书**：教材请提供 **PDF**（扫描版 / 数学书均可，
> 云端 OCR + 公式转 LaTeX）；EPUB / Word 不在支持范围。

## 运行前提：两个 API

| 需要 | 用途 | 怎么获得 |
| --- | --- | --- |
| AI 供应商的 API | 拆书、五级拆解、出学案、十问测试、生成速查表等全部 AI 功能 | 任选一种：① 本机安装并登录 Codex CLI 或 Claude Code；② 在 AI 供应商后台申请 API Key，安装后粘贴到 cc-switch / Claudian 设置中 |
| MinerU 的 API Token | 扫描版、数学公式类教材的云端 OCR 解析（公式转 LaTeX） | 到 [MinerU 官网](https://mineru.net) 注册账号，免费领取 Token；安装后运行 `_工具/设置MinerU令牌.sh` 粘贴即可 |

## 一键安装（CachyOS / Arch 优先）

### 推荐方式：Release 单文件引导器

到本仓库的 Releases 页面下载最新的 `HelpToStudy-QuickInstall.sh`，在终端运行：

```bash
chmod +x HelpToStudy-QuickInstall.sh
./HelpToStudy-QuickInstall.sh
```

它会自动完成：

- 从 Release 下载库压缩包并解压到临时目录
- 检测/安装环境：Obsidian、Python、Node.js、Git、Claude Code、cc-switch
  （CachyOS 上 Obsidian 走官方仓库 `pacman -S obsidian`，cc-switch 走 AUR
  `cc-switch-bin`，自动探测 paru → yay；已装的最新版直接跳过，缺失的自动安装）
- 安装「AI 学习工作流」Obsidian 库（默认 `~/ObsidianVaults/AI学习工作流`；
  niri / GNOME 等环境用 zenity 选目录（环境配置会自动安装），KDE 用 kdialog，
  也可直接命令行输入）
- 装完自动用 Obsidian 打开库

> **niri 用户**：安装库时会自动把「拆书（MinerU）」「设置MinerU令牌」
> 「打开库」注册为应用启动器条目（`~/.local/share/applications`），
> 可从 fuzzel / rofi 等启动器直接启动，也可以全程在终端运行。

#### 常用参数

```bash
./HelpToStudy-QuickInstall.sh --vault-path "/home/me/我的资料/AI学习工作流"
./HelpToStudy-QuickInstall.sh --skip-env
./HelpToStudy-QuickInstall.sh --skip-mineru --no-open-obsidian
```

| 参数 | 作用 |
| --- | --- |
| `--skip-env` | 跳过环境检测/安装，只装库 |
| `--skip-claude` | 跳过 Claude Code 安装 |
| `--update` | 检测到旧版本时直接升级，不再询问 |
| `--vault-path "路径"` | 指定库安装位置 |
| `--no-dialog` | 不弹目录选择框，用默认位置 |
| `--skip-python` | 跳过 Python 虚拟环境与拆书依赖 |
| `--skip-mineru` | 不装 MinerU 云端 OCR 工具 |
| `--no-open-obsidian` | 装完不自动打开 Obsidian |
| `--force` | 目标目录已存在时不询问，直接继续 |
| `--no-desktop` | 不注册应用启动器条目（默认会注册到 `~/.local/share/applications`） |

### 备用方式：手动 ZIP 或克隆

到 Releases 下载 `HelpToStudy-Vault-<版本>.zip`（或克隆本仓库），解压后：

1. 运行 `./环境配置.sh`：检测/安装环境
   （`./环境配置.sh --check-only` 只查不装；`--skip-claude` 跳过 Claude Code；
   装完会自动打开 cc-switch 供粘贴 API Key）
2. 运行 `./安装.sh`：安装库（或双击 `环境配置.desktop` / `安装.desktop`）

> 若文件管理器提示脚本不可执行，先 `chmod +x *.sh _工具/*.sh`；
> 双击 `.desktop` 时如提示不受信任，在属性中允许执行 / 设为信任；
> niri 等平铺环境下建议从终端或应用启动器（fuzzel / rofi）启动。

### 装完之后的设置

- 首次打开若提示「信任社区插件」，选信任（插件文件已随库装好，
  包含 Copilot、Dataview、QuickAdd、Templater、Claudian、Excalidraw CN）。
- 打开右侧边栏的 Claudian，在设置中选择后端（本机 Codex 或 Claude Code）。
- 扫描版/数学书才需要：运行 `_工具/设置MinerU令牌.sh`，粘贴 MinerU 免费 Token。
- 打开 `00-使用指南/📖 使用说明.md`，开始你的第一个学习主题。

## 这个库能做什么

| 命令 / 工具 | 用途 |
| --- | --- |
| `_工具/拆书.sh` | PDF → MinerU 云端解析（公式转 LaTeX）+ 按章拆分 |
| `_工具/设置MinerU令牌.sh` | 保存 MinerU Token |
| `/拆书` | 导入教材 PDF 并按章节拆分（Claudian 中触发） |
| `/新主题-拆解与计划` | 五级水平拆解 + 二八定律 10 次学习计划，一键写入笔记 |
| `/学案` | 每章生成学案 + Session 记录 |
| `/测试我` | 十问考官测试，记录分数和薄弱点 |
| `/速查表` | 生成一页速查表（开课前 5 分钟复习） |
| `/更新进度` | 自动更新主题主页的进度/级别/薄弱点 |

核心原则：笔记就是记忆。进度永远写在笔记里（frontmatter + 固定标记区），
AI 只负责读写，不把整个库塞进对话，因此省钱、可长期使用。

### 拆书引擎能力（MinerU 单流程）

- 仅支持 PDF：MinerU 云端 OCR（扫描版）+ 公式转 LaTeX，自动按章拆分；
  英文书默认 `--mineru-language en`，中文书加 `--mineru-language ch`
- **大扫描件也传得上去**：上传按「≤200 页 且 ≤25 MB」分块（`mineru-open-api` 的
  上传超时窗口在 1–2 MB/s 的上行下只吃得下几十 MB）；每页平均体积一超上限就先用
  Ghostscript 降到 200 DPI（实测 191 MB → 63 MB，识别精度不受影响，结果缓存在
  `_工具/.mineru_cache/`，同一本书重跑不压第二次），单份上传超时还会自动对半切小重传。
  可调：`--mineru-chunk-mb 8`、`--mineru-dpi 150`、`--mineru-dpi 0`（不压缩直传）
- **章节识别**支持中/英/意/西/法常见标题（含意大利语序数词课名、目录页码格式）；
  章标题被 OCR 整批打掉时（如《现代西班牙语》每课用了装饰字体的 UNIDAD 标题，
  16 课只认出 7 个），默认自动改走「每章固定收尾小节」定位：从正文里挖出
  每章都出现、只出现一次且间隔均匀的小节（如「作业 (Trabajos de casa)」）当章界锚点，
  实测 16 课一次切准；只有比通用识别切出更多章时才采用，正常书不受影响。
  可自己指定：`--chapter-end-pattern '习题\s*\(Ejercicios'`；关掉：`--chapter-end-pattern off`
- 识别不到章节时全书保存为一个文件并提示校准，绝不乱切；重切不耗额度（把
  `00-MinerU解析全文.md` 交给 `_工具/拆书.sh` 即可），还可用 `--opener-pattern`
  补充定位：
  `python _工具/split_textbook.py "<书>/00-MinerU解析全文.md" --out "04-教材分块" --split-mode chapter --opener-pattern "Impariamo a parlare"`
- 生成的章节笔记里图片统一使用 Obsidian 原生嵌入 `![[图片名]]`；
  前言/目录、书后总词汇表各自单独成块，分块字数合计 = 全文字数，不漏不重
- 想先看分块计划不耗额度：`--mineru-dry-run`

## 目录结构

```
AI学习工作流/
├── 00-使用指南/        首页、使用说明
├── 01-提示词库/        Step1-5 提示词原文（含合并版）
├── 02-模板/            新主题、Session 记录、速查表模板
├── 03-学习主题/        每个主题一个文件夹（主页/计划/测试/速查表）
├── 04-教材分块/        拆书结果（00-教材信息、00-目录、01-全书大纲、章节分块）
├── _工具/              拆书脚本 + 启动器 + requirements.txt + .venv（可选）
├── copilot/            Copilot 插件自定义提示词
├── .claude/commands/   Claudian 斜杠命令（输入 / 触发）
└── .obsidian/          插件与配置（随库装好）
```

## 隐私说明（重要）

- `.gitignore` 已排除：个人学习主题、拆书内容、备份、插件 data.json
  （可能含 API 密钥）、会话记录、Token 文件。
- 安装时不会复制原电脑上的任何个人笔记与密钥，只复制工作流本身。
- 如果希望把个人笔记也同步到 GitHub，请自行调整 `.gitignore`，并确保
  data.json 和 Token 文件仍被排除。

## 常见问题

**Q：引导器下载失败 / 离线环境怎么装？**
A：直接到 Releases 下载 `HelpToStudy-Vault-<版本>.zip`，解压后手动运行
「环境配置.sh」→「安装.sh」，效果与一键安装相同。

**Q：装过旧版本，怎么升级？**
A：再次运行一键引导器（或解压新版 ZIP 后运行「安装.sh」）。目标目录已存在时
会询问是否继续，个人笔记保留，只覆盖/补充工作流文件。

**Q：装完打开 Obsidian 没有 Claudian 图标？**
A：确认 `.obsidian/community-plugins.json` 已复制且首次打开时选择了「信任」。
如果插件未加载，可在设置 → 第三方插件中手动启用。

**Q：Claudian 提示找不到 Codex / Claude？**
A：先运行「环境配置.sh」安装 Claude Code（或自行安装 Codex CLI），
并在 Claudian 设置里选择后端。

**Q：拆书报「找不到 MinerU 命令行工具」？**
A：安装时已自动执行 `pip install mineru-open-api`（可用 `--skip-mineru` 跳过）。
手动补救：`_工具/.venv/bin/pip install mineru-open-api`。

**Q：拆书卡在「上传解析中」反复重试，报 `context deadline exceeded`？**
A：扫描版单份体积太大（200 页能到 127 MB），上行没传完就被工具的超时掐断。
现在默认会自动降到 200 DPI 并按 ≤25 MB/份分块（需要 ghostscript，「环境配置.sh」
已一并安装），单份仍超时会自动切小重传。网络还是慢就：
`_工具/拆书.sh 某本书.pdf --mineru-chunk-mb 8`；先看计划不耗额度：`--mineru-dry-run`。

**Q：整本书只切出两三个大文件（章节没识别到）？**
A：章标题用了装饰字体时会被 OCR 整批打掉，工具已默认自动改按「每章固定收尾小节」
定位章界。拿已生成的全文重切不耗额度：
`_工具/拆书.sh "04-教材分块/<书名>/00-MinerU解析全文.md"`；
需要时再给收尾小节正则：`--chapter-end-pattern '作业\s*\(Trabajos de casa'`。

**Q：AUR 助手（paru/yay）都没有，cc-switch 装不上？**
A：手动执行：
`git clone https://aur.archlinux.org/cc-switch-bin.git && cd cc-switch-bin && makepkg -si`

**Q：Ubuntu / Fedora 能用吗？**
A：环境配置脚本保留了 apt / dnf 分支，但完整测试以 CachyOS / Arch 为准；
其他发行版建议用官方安装包或容器方式运行。

**Q：我用的 niri（无桌面环境），怎么启动拆书？**
A：终端运行 `_工具/拆书.sh` 即可；安装库时已注册应用启动器，
也可从 fuzzel / rofi 等启动器搜索「拆书（MinerU）」。
目录/文件选择由 zenity 提供（环境配置.sh 会自动安装 zenity、xdg-utils）。

## 从零开始维护

改了什么想同步回仓库？直接在仓库里改，然后：

```bash
git add -A
git commit -m "更新说明"
git push
```

内容目录（`00-使用指南`、`01-提示词库`、`02-模板`、`.claude`、`.obsidian`、
`copilot`、`AGENTS.md`、`CLAUDE.md`）与 Windows 仓库保持一致；`_工具` 为平台差异区，
不参与同步。

想一键推到 GitHub：`./push-to-github.sh [仓库名] [public|private]`
（默认 `HelpToStudy_Linux`、private；需要已安装并登录 `gh`）。

### 发布新版本

打 tag 并推送，GitHub Actions 会自动构建发布包并生成 Release：

```bash
git tag v1.0.0
git push origin v1.0.0
```

也可以在本地生成资产后手动发布（Actions 不可用时的兜底）：

```bash
./scripts/build-release.sh -t v1.0.0 -r xiaomaogou66/HelpToStudy_Linux -o ./dist
```

会生成 `HelpToStudy-Vault-<版本>.zip`、`HelpToStudy-QuickInstall.sh` 和
`release-notes.md`；手动发布时把前两个文件作为 Release 资产上传即可。

### 库可以随便拷贝、移动

`_工具` 里的拆书启动器全部使用相对路径（自动定位库目录、虚拟环境和
Token 文件），不依赖任何本机绝对路径。整个库文件夹可以拷贝到 U 盘、
换电脑、移动位置，运行 `_工具/拆书.sh` 依然能用；缺 Python 或依赖时
启动器会给出明确提示。
