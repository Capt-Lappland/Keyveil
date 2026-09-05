const apps = {
  Safari: {
    icon: "◢",
    groups: [
      { title: "标签页", icon: "▱", accent: "#d9a2ff", items: [["新建标签页", "⌘ T"], ["关闭标签页", "⌘ W"], ["重新打开标签页", "⇧ ⌘ T"], ["下一个标签页", "⌃ ⇥"], ["上一个标签页", "⌃ ⇧ ⇥"]] },
      { title: "浏览", icon: "⌁", accent: "#93c8ff", items: [["聚焦地址栏", "⌘ L"], ["查找页面内容", "⌘ F"], ["重新载入页面", "⌘ R"], ["返回", "⌘ ["], ["显示下载项", "⌥ ⌘ L"]] },
      { title: "窗口", icon: "□", accent: "#86f0e2", items: [["新建窗口", "⌘ N"], ["关闭窗口", "⇧ ⌘ W"], ["最小化窗口", "⌘ M"], ["进入全屏", "⌃ ⌘ F"], ["显示阅读列表", "⌃ ⌘ 2"]] }
    ]
  },
  Figma: {
    icon: "F",
    groups: [
      { title: "工具", icon: "✦", accent: "#ff957c", items: [["移动工具", "V"], ["画框", "F"], ["钢笔工具", "P"], ["文本工具", "T"], ["评论", "C"]] },
      { title: "编辑", icon: "◇", accent: "#c49cff", items: [["复制", "⌘ C"], ["粘贴", "⌘ V"], ["编组", "⌘ G"], ["创建组件", "⌥ ⌘ K"], ["复制属性", "⌥ ⌘ C"]] },
      { title: "视图", icon: "◎", accent: "#75e4c4", items: [["缩放至适合", "⇧ 1"], ["缩放至选区", "⇧ 2"], ["显示网格", "⇧ G"], ["显示标尺", "⇧ R"], ["快速操作", "⌘ / "]] }
    ]
  },
  Xcode: {
    icon: "⌁",
    groups: [
      { title: "运行", icon: "▷", accent: "#72baff", items: [["构建", "⌘ B"], ["运行", "⌘ R"], ["测试", "⌘ U"], ["停止", "⌘ ."], ["清理构建", "⇧ ⌘ K"]] },
      { title: "编辑", icon: "⌘", accent: "#9ae5ff", items: [["快速打开", "⇧ ⌘ O"], ["格式化", "⌃ I"], ["移动行向上", "⌥ ⌘ ["], ["重命名", "⌃ ⌘ E"], ["添加文档", "⌥ ⌘ /"]] },
      { title: "导航", icon: "⌁", accent: "#bca7ff", items: [["显示导航器", "⌘ 0"], ["显示检查器", "⌥ ⌘ 0"], ["跳到定义", "⌃ ⌘ J"], ["后退", "⌃ ⌘ ←"], ["项目搜索", "⇧ ⌘ F"]] }
    ]
  }
};

const overlay = document.querySelector("#shortcutOverlay");
const grid = document.querySelector("#shortcutGrid");
const title = document.querySelector("#paletteTitle");
const menuAppName = document.querySelector("#menuAppName");
const appIcon = document.querySelector("#appIcon");
const search = document.querySelector("#shortcutSearch");
const count = document.querySelector("#shortcutCount");
const demoButton = document.querySelector("#demoButton");
let currentApp = "Safari";
let commandHeld = false;
let demoPinned = false;

function keycaps(value) {
  return value.split(" ").map((key) => `<kbd>${key}</kbd>`).join("");
}

function renderShortcuts(query = "") {
  const term = query.trim().toLocaleLowerCase();
  const groups = apps[currentApp].groups.map((group) => ({
    ...group,
    items: group.items.filter(([name, keys]) => `${name} ${keys}`.toLocaleLowerCase().includes(term))
  })).filter((group) => group.items.length);

  const total = groups.reduce((sum, group) => sum + group.items.length, 0);
  count.textContent = `${total} 个快捷键`;
  if (!groups.length) {
    grid.innerHTML = `<div class="no-results">没有找到匹配的快捷键</div>`;
    return;
  }
  grid.innerHTML = groups.map((group) => `
    <section class="shortcut-group" style="--accent:${group.accent}">
      <h3 class="group-title"><span>${group.icon}</span>${group.title}</h3>
      ${group.items.map(([name, keys]) => `<div class="shortcut-row"><span>${name}</span><span class="keys">${keycaps(keys)}</span></div>`).join("")}
    </section>
  `).join("");
}

function showOverlay({ pinned = false } = {}) {
  demoPinned = pinned;
  overlay.classList.add("is-visible");
  overlay.setAttribute("aria-hidden", "false");
  document.body.classList.add("overlay-open");
  renderShortcuts(search.value);
}

function hideOverlay() {
  demoPinned = false;
  overlay.classList.remove("is-visible");
  overlay.setAttribute("aria-hidden", "true");
  document.body.classList.remove("overlay-open");
  search.blur();
}

function setApp(name) {
  currentApp = name;
  title.textContent = name;
  menuAppName.textContent = name;
  appIcon.textContent = apps[name].icon;
  appIcon.className = `app-icon ${name.toLowerCase()}`;
  document.querySelectorAll(".app-choice").forEach((button) => button.classList.toggle("active", button.dataset.app === name));
  search.value = "";
  renderShortcuts();
}

document.addEventListener("keydown", (event) => {
  if (event.key === "Meta" && !commandHeld) {
    commandHeld = true;
    showOverlay();
  }
  if (event.metaKey && event.key.toLowerCase() === "k" && overlay.classList.contains("is-visible")) {
    event.preventDefault();
    search.focus();
  }
  if (event.key === "Escape") hideOverlay();
});

document.addEventListener("keyup", (event) => {
  if (event.key === "Meta") {
    commandHeld = false;
    if (!demoPinned && document.activeElement !== search) hideOverlay();
  }
});

window.addEventListener("blur", () => {
  commandHeld = false;
  if (!demoPinned) hideOverlay();
});

search.addEventListener("input", () => renderShortcuts(search.value));
demoButton.addEventListener("click", () => overlay.classList.contains("is-visible") ? hideOverlay() : showOverlay({ pinned: true }));
overlay.querySelector(".backdrop").addEventListener("click", hideOverlay);
document.querySelectorAll(".app-choice").forEach((button) => button.addEventListener("click", () => setApp(button.dataset.app)));

function updateClock() {
  const now = new Date();
  const weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];
  document.querySelector("#clock").textContent = `${now.getMonth() + 1}月${now.getDate()}日 ${weekdays[now.getDay()]} ${now.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit", hour12: false })}`;
}

renderShortcuts();
updateClock();
setInterval(updateClock, 30000);
