# DualGuard

**简体中文** · [English](README.en.md)

**让 WorkBuddy 国内版与国际版在同一台 Windows 上和平共处。**

一套纯脚本的进程级隔离方案：不修改任何程序文件、不写入 `HKLM`、不需要管理员权限。删除两个目录即可完全回滚。

`Windows 10 / 11` · `PowerShell 5.1` · `无需管理员` · `MIT`

---

## 它解决什么问题

同时安装 WorkBuddy 国内版（`www.workbuddy.cn`）与国际版（`www.workbuddy.ai`）时，会出现**双向干扰**：

- 更新任意一版，另一版会被强制关闭
- 更严重的情况：更新后另一个版本的主程序被覆盖、快捷方式指向同一个应用
- 担心更新过程顺带清掉另一版的会话记录与登录态

这不是玄学，有两个具体成因：

**成因一：共用的更新缓存。** 两个客户端都会往 `%TEMP%` 下写 `workbuddy-update-x64*` 目录。一方下载的安装包躺在那里，另一方启动时可能把它"恢复"成自己的更新并执行——而那个安装包属于谁，它自己并不知道。

**成因二：整包重装的更新方式。** 更新不是打补丁，而是「下载完整安装包 → 静默卸载 → 重装」。所以任何对程序文件的修改都会在下一次更新时被整目录替换冲掉。

> 结论：**改程序文件没有意义，能改的只有运行环境。**

---

## 原理：一次进程级的环境变量改写

`TEMP` 是逐进程的环境变量，子进程继承父进程的环境块。因此在拉起 `exe` **之前**把它改掉，该进程及其派生的更新器、下载器就再也看不到共用缓存目录。

```mermaid
flowchart LR
    A["双击 WorkBuddy AI.cmd"] --> B["dg-launch.ps1 -Product ai"]
    B --> C["解析 WorkBuddyAI.exe"]
    C --> D["TMP/TEMP =<br/>%LOCALAPPDATA%\WB-Isolated\ai\temp"]
    D --> E["Start-Process"]
    E --> F["WorkBuddyAI.exe<br/>及其全部子进程"]
    F --> G["更新器落在<br/>...\ai\temp\workbuddy-update-x64"]
    G --> H(["国内版永远读不到"])
```

改动只发生在**当前进程的环境块**：系统环境变量不动、注册表不动、安装目录不动。进程退出即消失。

---

## 文件清单

| 文件 | 作用 |
|---|---|
| `DualGuard.cmd` | **主入口**，打开维护菜单 |
| `WorkBuddy CN.cmd` | 以隔离 TEMP 启动国内版 |
| `WorkBuddy AI.cmd` | 以隔离 TEMP 启动国际版（**开机自启项指向此文件**） |
| `dg-launch.ps1` | 启动器：解析 exe 路径 → 建隔离 TEMP → 注入 `TMP`/`TEMP` → 拉起进程 |
| `dg-menu.ps1` | 维护菜单：状态诊断、快照、清缓存、冻结/解冻 |
| `README.md` | 本文件（中文） |
| `README.en.md` | 英文版（内容与本文等价） |

**本目录只放静态文件，不产生任何运行产物，也不放任何历史记录。** 日志与快照统一写到 `%LOCALAPPDATA%\DualGuard\`，所以整个目录可以整体拷贝、打包、甚至设为只读。

> `dg-launch.ps1` 不能删：两个启动 `.cmd` 与开机自启都依赖它。

---

## 快速开始

**顺序：先配置，后启动。**

原因只有一条：冻结和清缓存都要求「客户端未运行」。首次配置时两个客户端还没启动，天然满足这个条件；一旦先启动再去配置，就得先把两版全部退出才能继续，白绕一圈。

### 首次配置（3 步）

1. 把整个目录放到任意位置——路径可含空格与中文，脚本用 `%~dp0` / `$PSScriptRoot` 自动定位
2. **双击 `DualGuard.cmd`**，按顺序做三件事：
   - 选 `5` 冻结自动更新
   - 选 `3` 生成首份快照并清理共用缓存（结尾要输入 `yes` 确认；若这台机器还从没用过客户端、数据目录为空，快照为空属正常）
   - 选 `0` 退出
3. **再用 `WorkBuddy CN.cmd` 和 `WorkBuddy AI.cmd` 启动两个版本**（首次运行会自动创建隔离目录）

至此隔离生效，且已有一份干净备份。

### 之后日常

| 场景 | 操作 |
|---|---|
| 启动 | 双击 `WorkBuddy CN.cmd` / `WorkBuddy AI.cmd` |
| 更新 | `DualGuard.cmd` → 选 `4` 解冻 → 退出另一版 → 点应用内更新 → 选 `5` 重新冻结 |
| 开机自启（可选） | 把 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 下对应项指向 `WorkBuddy AI.cmd` 的**完整路径**（务必带引号） |

> 桌面 / 开始菜单里旧的 `WorkBuddy.lnk` 仍直达 `exe`，双击会绕过隔离。建议删除，改为右键启动 `.cmd` → 发送到 → 桌面快捷方式。

---

## 维护菜单

双击 `DualGuard.cmd`：

```
========================================================
  DualGuard   WorkBuddy 双版本隔离与维护
========================================================

== 状态 ==
  国内版  D:\workbuddy\WorkBuddy.exe
          版本 5.9.2   端点 https://www.workbuddy.cn
  国际版  F:\软件\WorkBuddyAI\WorkBuddyAI.exe
          版本 5.8.4   端点 https://www.workbuddy.ai
  进程: 两版均未运行  [OK]
  自动更新: 已冻结（两侧）
  自启项  WorkBuddy.WorkBuddyAI = "C:\Tools\DualGuard\WorkBuddy AI.cmd"
  共用缓存: 无遗留安装包  [OK]
========================================================
  1  生成快照                  需两个客户端退出
  2  清理共用更新缓存          需两个客户端退出
  3  依次执行 1 + 2           需两个客户端退出，推荐
  4  解冻自动更新              允许应用内更新
  5  冻结自动更新              阻断自动更新
  6  刷新状态
  0  退出
========================================================
```

| 选项 | 行为 | 安全设计 |
|---|---|---|
| `1` 快照 | 复制 `~\.workbuddy`、`~\.workbuddy-ai`、`%LOCALAPPDATA%\CodeBuddyExtension` 并打包，保留最近 5 份 | 先做进程检查，未全部退出则循环等待；排除日志/缓存等大目录 |
| `2` 清缓存 | 删除系统 `%TEMP%` 下的 `workbuddy-update-x64*` | 需输入完整 `yes`；**任何位于 `WB-Isolated` 下的路径强制跳过** |
| `3` 快照 + 清缓存 | 按「先备份、后删除」顺序执行 | 同上 |
| `4` 解冻 | 删除 6 个占位文件，恢复应用内更新 | — |
| `5` 冻结 | 在两侧隔离 TEMP 各建 3 个同名空文件 | — |
| `6` 刷新 | 重读状态 | — |

---

## 冻结与更新

**冻结不是禁用更新，而是让"无人看管时的自动更新"失败。**

做法：在各自的隔离 TEMP 里，用**同名零字节文件**占住缓存目录名

```
%LOCALAPPDATA%\WB-Isolated\cn\temp\workbuddy-update-x64
%LOCALAPPDATA%\WB-Isolated\cn\temp\workbuddy-update-x64-workbuddy
%LOCALAPPDATA%\WB-Isolated\cn\temp\workbuddy-update-x64-workbuddy-ai
%LOCALAPPDATA%\WB-Isolated\ai\temp\   （同上三个）
```

目录名被文件占据 → 更新器无法创建缓存目录 → 下载环节失败。这个"锁"在安装目录之外，重装不会被冲掉。

> 生效时机：占位文件是文件系统状态，**对之后启动的进程立即生效**。已经在运行的实例看不到它——它们用的是启动时拿到的旧 `TEMP`。所以「先冻结、后启动」是唯一不需要反复退出客户端的顺序。

更新时按下面的顺序操作，应用内更新照常可用。

### 方式 A：应用内更新（推荐）

前提：要更新的那一版**是通过 `.cmd` 启动的**。否则它的 `TEMP` 是系统目录，解冻没有意义。

1. 双击 `DualGuard.cmd` → 选 `4` 解冻（删除 6 个占位文件，可随时做，不影响运行中的实例）
2. 完全退出**另一个**版本（托盘图标右键退出，点窗口 × 不算）
3. 在要更新的那一版里点更新提示 → 等下载完成 → 提示重启时让它重启
4. 双击 `DualGuard.cmd` → 选 `6`，确认版本号已变、端点没串
5. 选 `5` 重新冻结

> 如果第 3 步点击后没反应，先完全退出该客户端、再用 `.cmd` 重新启动然后重试——更新器可能还停在上一次"下载失败"的状态里。

### 方式 B：官网安装包覆盖

1. 从官网下载最新安装包
2. 完全退出**两个**版本
3. 双击安装包，装到**原来那个安装目录**（不要让安装器换路径）
4. 启动前双击 `DualGuard.cmd` → 选 `5` 重新冻结（覆盖安装可能不受冻结影响，装完确认一下状态）

**不需要先卸载任何东西。** 安装器内部本来就会先做一次静默卸载再装回去——这正是"整包重装"的由来。

**想更稳一点**：更新前先做一次快照（`DualGuard.cmd` → 选 `1`，需两版退出），万一更新出问题，数据还在。

---

## 数据与日志位置

| 内容 | 路径 |
|---|---|
| 隔离 TEMP（含占位文件） | `%LOCALAPPDATA%\WB-Isolated\{cn,ai}\temp` |
| 启动日志 | `%LOCALAPPDATA%\DualGuard\logs\dg-launch.log` |
| 维护日志 | `%LOCALAPPDATA%\DualGuard\logs\dg-maintain.log` |
| 快照 | `%LOCALAPPDATA%\DualGuard\snapshots\dg-yyyyMMdd-HHmmss.zip` |
| 程序本体 | 工具所在目录（静态，无产物） |

所有写入都在用户目录下，因此**不需要管理员权限**。

---

## 验证隔离是否生效

**一、干跑（不启动应用）**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\dg-launch.ps1 -Product ai -DryRun
```

预期输出中 `iso : isolated=True`，且 `temp` 指向 `WB-Isolated\ai\temp`。

**二、看隔离目录里有没有实际活动**

通过 `.cmd` 启动国际版，正常使用几分钟，然后检查：

```powershell
Get-ChildItem "$env:LOCALAPPDATA\WB-Isolated\ai\temp" | Select-Object Name, LastWriteTime
```

目录里出现客户端运行期写入的临时文件，说明该进程的 `TEMP` 确实指向这里。

**三、最强的证据**

触发一次更新检查（或等它自己检查），再回来看同一位置有没有出现 `workbuddy-update-x64` 子目录。出现了，说明更新器确实在用隔离目录，闭环成立——这正是共用缓存冲突被切断的那一刻。

---

## 适用范围与已知限制

**做到的事**

- 切断"一方读取另一方更新缓存中的安装包"这条路径
- 让自动更新在文件系统层面可控，而不是仅依赖 UI 开关
- 覆盖开机自启入口
- 在安装器行为不可控的前提下，提供可恢复的备份

**做不到的事（重要）**

- **不提供"绝对互不干扰"的保证。** 安装器是二进制程序，它在静默重装时是否按进程名结束另一实例、是否记忆上次的安装目录，脚本层面无法干预。本工具降低概率，不消除风险。
- **冻结依赖经验假设。** 它假设更新器必须先创建 `workbuddy-update-x64` 目录才能下载。若存在未知的第四种命名或备用下载路径，占位文件就挡不住——此时唯一损失是几个空文件。
- **路径探测是启发式的。** 脚本按候选清单 + 注册表 + 目录扫描定位 `exe`。安装到非常规位置时，需修改 `dg-launch.ps1` 里的 `Find-CnExe` / `Find-AiExe` 或 `dg-menu.ps1` 里的 `Get-CnExe` / `Get-AiExe`。
- **`@genieworkbuddy-desktop-updater` 不受 TEMP 影响。** 两版更新器版本一致时基本无害，未做处理。
- 依赖 PowerShell 5.1（Windows 内置），不保证在 PowerShell 7 下的行为。

**必须遵守的操作纪律**

1. 两个版本不要同时执行更新
2. 更新任一版之前，先完全退出另一版
3. 启动一律走 `.cmd`，不要用直达 `exe` 的旧快捷方式

---

## 回滚

| 对象 | 操作 |
|---|---|
| 自启项 | 把 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 下的 `WorkBuddy.WorkBuddyAI` 改回原来的值，即国际版安装目录下的 `WorkBuddyAI.exe` 完整路径（带引号） |
| 隔离目录 | 删除 `%LOCALAPPDATA%\WB-Isolated` |
| 日志 / 快照 | 删除 `%LOCALAPPDATA%\DualGuard` |
| 程序 | 删除本目录 |

本工具不修改任何程序文件、不修改 `HKLM`、不修改两个客户端的数据根（`~\.workbuddy` / `~\.workbuddy-ai`），回滚无残留。

---

## 常见问题

**Q：会不会因为改 TEMP 让客户端出错？**

不会。TEMP 只影响临时文件落点，客户端本来就允许它可变（企业环境下 TEMP 常被重定向）。

**Q：冻结之后还能更新吗？**

能。菜单选 `4` 解冻即可，或用官网安装包覆盖安装，后者任何时候都不受阻挡。

**Q：我只有一个版本，还需要它吗？**

不需要。共用缓存冲突只在两版并存时才有意义。

**Q：为什么启动器叫 `WorkBuddy CN.cmd` 而不是 `DualGuard CN.cmd`？**

启动器按"它启动什么"命名，用户一眼能选对；工具入口 `DualGuard.cmd` 按"工具"命名。两套命名各司其职。

**Q：为什么 `dg-menu.ps1` 开头有 BOM？**

PowerShell 5.1 在读取无 BOM 的 `.ps1` 时会按系统 ANSI 代码页解析，中文会变乱码。`.cmd` 则只用 ASCII，避免代码页问题。

**Q：会不会把我的数据搞丢？**

工具本身只读数据、只写自己的日志与快照。真正的风险来自客户端更新器，所以提供了快照功能：选 `1` 生成的 zip 包含两个数据根与登录态，可直接解压回原位。

---

## 声明

本项目为第三方工具，与 WorkBuddy 官方无关，不包含任何客户端二进制文件，也未修改其程序文件。

以 [MIT License](LICENSE) 授权。脚本按现状提供，使用前请自行评估风险。
