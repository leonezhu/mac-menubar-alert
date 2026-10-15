# MenuBarAlert · macOS 菜单栏警示语

在 macOS 菜单栏（屏幕右上角状态栏）常驻显示你自己配置的警示语。纯系统自带 Swift 编译，**不依赖任何第三方工具**（不需要 Homebrew、不需要完整 Xcode、不需要开发者账号）。

源码目录：`/Users/xiong/Documents/GitHub/menubar-alert`（本目录）

运行后各文件位置：

| 项目 | 位置 |
| --- | --- |
| 应用 | `~/Applications/MenuBarAlert.app` |
| 配置文件 | `~/.menubar-alert.json`（改完 2 秒内自动生效，无需重启） |
| 日志 | `~/Library/Logs/MenuBarAlert.log` |
| 开机自启（可选） | `~/Library/LaunchAgents/local.menubar-alert.plist` |

## 环境要求

- macOS 11 或更高（本机实测 macOS 13.7.8）
- Swift 编译器：终端执行 `swiftc --version` 能输出版本号即可

如果没有 `swiftc`，安装 Xcode Command Line Tools（会弹窗确认）：

```bash
xcode-select --install
```

## 安装与启动

### 一条命令（推荐）

```bash
cd /Users/xiong/Documents/GitHub/menubar-alert
./run
```

`./run` 依次做三件事：

1. 用 `swiftc -O` 编译 `src/main.swift`
2. 组装成 `MenuBarAlert.app`（写入 `resources/Info.plist` + 本机自签名），安装到 `~/Applications`
3. 启动它（如果已经在运行，先杀掉再拉起，保证跑的是新编译的版本）

看到 `==> 已启动` 后，菜单栏右上角就会出现警示语（默认 `⚠️ 今天最重要的一件事是什么？`）。

首次运行如果报 `Permission denied`，说明脚本执行位丢了（从压缩包解压会发生，`git clone` 不会）：

```bash
chmod +x run build.sh install.sh
```

这个程序是 `LSUIElement` 类型：**没有 Dock 图标，也没有窗口**。所有操作都点菜单栏上的那段文字进行，退出也从那个菜单里点「退出」。

### 分步执行（想看清楚每一步时）

```bash
./install.sh                            # 只编译 + 安装，不启动
open ~/Applications/MenuBarAlert.app    # 启动
```

### 只编译、不安装

```bash
./build.sh
open build/MenuBarAlert.app
```

产物在 `build/MenuBarAlert.app`，适合先看效果；`build/` 是编译产物，已在 `.gitignore` 中忽略。

### 开机自动启动

启动程序后，点菜单栏上的文字 → 勾选 **开机自动启动**。它会在 `~/Library/LaunchAgents/local.menubar-alert.plist` 写一个 LaunchAgent，下次登录自动拉起。取消勾选即删除该文件。

## macOS 上"安装应用"是怎么一回事

macOS **没有**一个叫 `run` 的系统命令可以装应用。对普通 `.app` 来说，"安装"本质上就是把 app 包复制到 `/Applications` 或 `~/Applications`——本项目的 `install.sh` 做的就是这件事（外加写 `Info.plist`、做一次本机自签名）。

其他真正常见的"安装"方式，供对照：

| 命令 | 适用场景 | 本机情况 |
| --- | --- | --- |
| `cp -R Xxx.app ~/Applications/` | 普通 .app（本项目走的路子） | 可用 |
| `sudo installer -pkg Xxx.pkg -target /` | 分发的是 `.pkg` 安装包 | 本项目不需要 |
| `brew install --cask xxx` | 用 Homebrew 装现成软件 | 未安装 Homebrew |
| `open Xxx.app` | 这是**启动**，不是安装 | — |

所以"一条命令装好并跑起来"这种体验，得由项目自己提供入口脚本——本项目的 `./run` 就是这个入口。

## 换成你自己的警示语

两种方式，效果一样：

1. **点菜单栏那段文字 → 选「编辑警示语…」**，用「文本编辑」改完保存；
2. 直接编辑 `~/.menubar-alert.json`（主目录下的隐藏文件）。

保存后 **2 秒内菜单栏自动更新**，不需要重启程序。

```json
{
  "prefix" : "🚨",
  "phrases" : ["先确认，再动手", "别在周五下午发版"],
  "intervalSeconds" : 30,
  "rotate" : true
}
```

| 字段 | 含义 | 默认值 |
| --- | --- | --- |
| `prefix` | 显示在警示语前面的符号/emoji；填 `""` 表示不加 | `"⚠️"` |
| `phrases` | 警示语列表；多条时可轮播 | 两条示例 |
| `intervalSeconds` | 轮播间隔（秒），最小 2 | `20` |
| `rotate` | 是否让多条警示语自动轮播（也可在菜单里勾选） | `false` |

写坏了也不会失联：

- 某个字段缺失或类型不对（例如 `phrases` 写成了字符串）→ 该字段退回默认值，其余照常生效；
- 整个 JSON 语法错误 → **继续显示上一次生效的内容**，只在日志里记一条错误。

## 菜单项

点菜单栏上那段文字会弹出菜单：

- **当前：…** —— 只读，显示完整文字（菜单栏上过长会被系统截断）
- **下一条警示语** —— 有多条时手动切换
- **编辑警示语…** / **显示配置文件位置** / **重新加载配置**
- **多条自动轮播** —— 开关，勾选状态会写回配置文件
- **开机自动启动** —— 开关，见上文
- **退出** —— 没有 Dock 图标，只能从这里退出

## 更新 / 重新编译

改完 `src/main.swift` 后，还是同一条命令（它会把正在运行的旧版本换掉）：

```bash
./run
```

## 卸载

1. 点菜单栏文字 → 取消「开机自动启动」→ 点「退出」
2. 删除文件：

```bash
rm -rf ~/Applications/MenuBarAlert.app
rm -f ~/.menubar-alert.json ~/Library/LaunchAgents/local.menubar-alert.plist
```

## 故障排查

| 现象 | 处理 |
| --- | --- |
| 菜单栏没出现文字 | 看日志 `tail -n 20 ~/Library/Logs/MenuBarAlert.log`，正常应有 `自检：状态栏项目可见=true`；若是 `false` 或宽度为 0，通常是菜单栏图标太多被系统挤出去了，删掉几个其他图标即可 |
| 想知道"现在应该显示什么" | `~/Applications/MenuBarAlert.app/Contents/MacOS/MenuBarAlert --print`（打印后立即退出，不开界面） |
| 改了配置没反应 | 确认改的是 `~/.menubar-alert.json`；保存后等 2 秒；还不行点菜单「重新加载配置」并看日志 |
| 换台机器打开被拦 | 右键点 app → 打开；或 `xattr -dr com.apple.quarantine ~/Applications/MenuBarAlert.app` |
| 想确认程序在跑 | `pgrep -lx MenuBarAlert` |
| `./run` 报 Permission denied | `chmod +x run build.sh install.sh` |

## 文件结构

```
menubar-alert/
├── run                  一条命令：编译 + 安装 + 启动（入口）
├── src/main.swift       程序源码（单文件）
├── resources/Info.plist app 元信息（LSUIElement = 无 Dock 图标）
├── build.sh             只编译到 build/MenuBarAlert.app
├── install.sh           编译 + 安装到 ~/Applications（不启动）
├── .gitignore           忽略 build/
└── README.md
```

## 已验证的事实（macOS 13.7.8 / Swift 5.8.1）

- `swiftc -O` 编译通过，无错误无警告
- `./run` 一条命令完成编译 → 安装到 `~/Applications` → 启动，运行中的旧实例被自动替换
- 启动自检日志：`状态栏项目可见=true，宽度=212.0pt`（系统确实为这段文字分配了菜单栏位置）
- 热更新实测：改配置文件后约 4 秒，日志出现「配置变更：… 当前显示「…」」
- 容错实测：把 `phrases` 故意写成字符串，程序仍正常显示并退回默认列表

## 注意事项

- 菜单栏空间有限，警示语建议 10～20 字以内，过长会把其他图标挤掉。
- 只想要一个图标不要文字：`prefix` 留空，`phrases` 里放一个 emoji。
- 本机为 Intel（x86_64），编译出的是 x86_64 版本；换 Apple Silicon 机器后重新跑一次 `./run` 即为原生版本。
- 只做了本机自签名，适合自己这台机器使用；拷给别人会被 Gatekeeper 拦。
