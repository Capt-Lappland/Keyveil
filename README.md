<div align="center">

<img src="docs/screenshots/icon.png" width="120" alt="Keyveil app icon">

# Keyveil

**Hold ⌘. Reveal every shortcut.**
**按住 ⌘，看清每一个快捷键。**

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://github.com/Capt-Lappland/Keyveil)
[![License MIT](https://img.shields.io/badge/License-MIT-2ea44f)](LICENSE)
[![Languages](https://img.shields.io/badge/Languages-English%20%C2%B7%20%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-4c8bf5)](#简体中文)

[English](#english) · [简体中文](#简体中文)

<img src="docs/screenshots/panel-light.jpg" alt="Keyveil listing every shortcut of Safari in a panel over the desktop" width="100%">

</div>

---

## English

Keyveil is a macOS menu bar app. Hold **⌘** and it lists every keyboard shortcut of the app you are working in; release it and the panel disappears. Double-tap **⌘** to pin the panel, and type to search it.

| | |
| --- | --- |
| Hold / release `⌘` | Show / hide the panel |
| Double-tap `⌘` | Pin or unpin it |
| `Escape` | Close a pinned panel |
| Type | Filter by shortcut name or key |

| Dark mode | First launch |
| --- | --- |
| <img src="docs/screenshots/panel-dark.jpg" alt="The same panel in dark mode"> | <img src="docs/screenshots/onboarding.jpg" alt="The first-launch setup window" width="360"> |

**Build**

```bash
git clone https://github.com/Capt-Lappland/Keyveil.git
cd Keyveil
./scripts/package-app.sh release
```

Unzip `dist/Keyveil.zip`, move `Keyveil.app` to `/Applications`, and launch it from there. macOS 14 or later. The first launch asks for Accessibility and Input Monitoring access — that is what lets Keyveil read the active app's menus and watch the Command key.

MIT licensed — see [LICENSE](LICENSE).

---

## 简体中文

Keyveil 是一个 macOS 菜单栏应用。按住 **⌘**，它会把当前正在用的那个应用的**全部快捷键**列出来；松开就消失。双击 **⌘** 可以把面板钉住，直接打字就能筛选。

| | |
| --- | --- |
| 按住 / 松开 `⌘` | 显示 / 收起面板 |
| 双击 `⌘` | 钉住或取消钉住 |
| `Escape` | 关闭已钉住的面板 |
| 打字 | 按快捷键名称或按键筛选 |

| 深色模式 | 首次启动 |
| --- | --- |
| <img src="docs/screenshots/panel-dark.jpg" alt="深色模式下的同一个面板"> | <img src="docs/screenshots/onboarding.jpg" alt="首次启动的权限引导窗口" width="360"> |

**构建**

```bash
git clone https://github.com/Capt-Lappland/Keyveil.git
cd Keyveil
./scripts/package-app.sh release
```

解压 `dist/Keyveil.zip`，把 `Keyveil.app` 移到 `/Applications` 再启动。需要 macOS 14 或更高版本。首次启动会请求「辅助功能」和「输入监控」权限——前者用来读取当前应用的菜单，后者用来观察 Command 键。

MIT 许可，详见 [LICENSE](LICENSE)。
