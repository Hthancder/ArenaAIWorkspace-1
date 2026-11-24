function $(s) {
  return document.querySelector(s);
}
const IS_DEV = window.location.host === "127.0.0.1:8080";
const T = {
  master: $("#t"),
  fileRow: function () {
    const tmp = document.createElement("template");
    tmp.innerHTML = this.master.content.querySelector("table tr.file-row").outerHTML;
    return tmp.content;
  },
  pathRow: function () {
    const tmp = document.createElement("template");
    tmp.innerHTML = this.master.content.querySelector("table tr.path-row").outerHTML;
    return tmp.content;
  },
  uploadLoading: function () {
    const tmp = document.createElement("template");
    tmp.innerHTML = this.master.content.querySelector(".upload-loading").outerHTML;
    return tmp.content;
  },
};

const EXECUTABLE = {
  ir: "ir tx_from_file",
  sub: "subghz tx_from_file",
  js: "js run_from_file",
  bjs: "js run_from_file",
  txt: "badusb run_from_file",
  mp3: "play",
  wav: "play",
};

const Dialog = {
  _bg: function (show) {
    let bg = $(".dialog-background");
    document.querySelectorAll(".dialog").forEach((d) => d.classList.add("hidden"));
    bg.classList.toggle("hidden", !show);
  },
  show: function (dialogName) {
    this._bg(true);
    $(".dialog." + dialogName).classList.remove("hidden");
  },
  hide: function () {
    if (otaBusy || _runningUpload) return;
    const editor = $(".dialog.editor:not(.hidden) .file-content");
    if (editor && (editorSaving || (isModified(editor) && !confirm("Discard unsaved changes?")))) return;
    this._bg(false);
    this.loading.hide();
    if (currentDrive && currentPath) {
      updateURL(currentDrive, currentPath, null);
    }
  },
  loading: {
    show: function (message) {
      $(".loading-area").classList.remove("hidden");
      $(".loading-area .text").textContent = message || "Loading...";
    },
    hide: function () {
      $(".loading-area").classList.add("hidden");
    },
  },
  showOneInput: function (name, inputVal, data) {
    const dbForm = {
      renameFolder: { title: "Rename Folder: " + inputVal, label: "New Folder Name:", action: "Rename" },
      renameFile: { title: "Rename File: " + inputVal, label: "New File Name:", action: "Rename" },
      createFolder: { title: "Create Folder", label: "Folder Name:", action: "Create Folder" },
      createFile: { title: "Create File", label: "File Name:", action: "Create File" },
      serial: { title: "Serial Command", label: "Command:", action: "Run" },
    };
    let config = dbForm[name];
    if (!config) return alert("Invalid dialog: " + name);
    let dialog = $(".dialog.oinput");
    dialog.setAttribute("data-cache", data);
    dialog.querySelector(".oinput-title").textContent = config.title;
    dialog.querySelector(".oinput-label").textContent = config.label;
    dialog.querySelector("#oinput-input").value = inputVal;
    dialog.querySelector(".act-save-oinput-file").textContent = config.action;
    this.show("oinput");
    dialog.querySelector("#oinput-input").select();
    return dialog;
  },
};

function handleAuthError() {
  if (confirm("Session expired or unauthorized. Go to the login page?")) {
    window.location.href = "/";
  } else {
    Dialog.loading.hide();
  }
}

async function requestGet(url, data) {
  return new Promise((resolve, reject) => {
    let req = new XMLHttpRequest();
    let realUrl = IS_DEV ? "/bruce" + url : url;
    if (data) realUrl += "?" + new URLSearchParams(data).toString();
    req.open("GET", realUrl, true);
    req.onload = () => {
      if (req.status >= 200 && req.status < 300) resolve(req.responseText);
      else if (req.status === 401) {
        handleAuthError();
        reject(new Error("Unauthorized (401)"));
      } else reject(new Error(`Request failed (${req.status})`));
    };
    req.onerror = () => reject(new Error("Network error"));
    req.send();
  });
}

function httpRequestError(message, req) {
  const err = new Error(message);
  err.status = req ? req.status : 0;
  err.body = req ? req.responseText : "";
  return err;
}

async function requestPost(url, data) {
  return new Promise((resolve, reject) => {
    let fd = new FormData();
    for (let key in data) {
      if (Object.prototype.hasOwnProperty.call(data, key)) fd.append(key, data[key]);
    }
    let req = new XMLHttpRequest();
    req.open("POST", IS_DEV ? "/bruce" + url : url, true);
    req.onload = () => {
      if (req.status >= 200 && req.status < 300) resolve(req.responseText);
      else if (req.status === 401) {
        handleAuthError();
        reject(httpRequestError("Unauthorized (401)", req));
      } else reject(httpRequestError(`Request failed (${req.status})`, req));
    };
    req.onerror = () => reject(httpRequestError("Network error", req));
    req.send(fd);
  });
}

function stringToId(str) {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = (hash << 5) - hash + str.charCodeAt(i);
    hash |= 0;
  }
  return "id_" + Math.abs(hash);
}

function parseHumanBytes(str) {
  if (!str) return 0;
  const m = String(str).match(/([\d.]+)\s*(B|kB|MB|GB)/i);
  if (!m) return 0;
  const val = parseFloat(m[1]);
  const unit = m[2].toLowerCase();
  if (unit === "gb") return val * 1024 * 1024 * 1024;
  if (unit === "mb") return val * 1024 * 1024;
  if (unit === "kb") return val * 1024;
  return val;
}

function formatUptime(sec) {
  sec = parseInt(sec || 0, 10);
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  if (h > 0) return `${h}h ${m}m ${s}s`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

let activeTab = "dashboard";
function switchTab(tabName) {
  if (tabName !== "files" && typeof payloadPickerActive !== "undefined" && payloadPickerActive) {
    payloadPickerActive = false;
    document.getElementById("payload-picker-banner")?.classList.add("hidden");
    document.querySelectorAll(".act-pick-payload").forEach(button => button.remove());
  }
  activeTab = tabName;
  document.querySelectorAll(".tab-btn").forEach((btn) => {
    btn.classList.toggle("active", btn.getAttribute("data-tab") === tabName);
  });
  document.querySelectorAll(".tab-pane").forEach((pane) => {
    pane.classList.toggle("hidden", pane.id !== "tab-" + tabName);
  });
  if (tabName === "screen") {
    reloadScreen();
    autoReloadScreen();
    loadScreenSettings();
  } else {
    autoReloadScreen();
  }
  if (tabName === "personalize") {
    loadPersonalizeForm();
  } else if (tabName === "dashboard") {
    uxLoad(true);
  }
  if (tabName === "console" && $("#console-in")) {
    $("#console-in").focus();
  }
  if (tabName === "seclab") {
    refreshSecLab();
    startSecLabPoll();
  } else {
    stopSecLabPoll();
  }
  if (tabName === "monitor") {
    refreshMonitor();
    startMonitorPoll();
  } else {
    stopMonitorPoll();
  }
  if (tabName === "studio") {
    refreshStudio();
    startStudioPoll();
  } else {
    stopStudioPoll();
  }
}

document.querySelectorAll(".tab-btn").forEach((btn) => {
  btn.addEventListener("click", () => switchTab(btn.getAttribute("data-tab")));
});

const _queueUpload = [];
let _runningUpload = false;
let _uploadFailures = 0;
function appendFileToQueue(files, drive = currentDrive, path = currentPath) {
  Dialog.show("upload");
  const body = $(".dialog.upload .dialog-body");
  for (const file of files) {
    const filename = file.webkitRelativePath || file.name;
    const row = T.uploadLoading();
    row.querySelector(".upload-name").textContent = filename + " — waiting";
    const bar = row.querySelector(".upload-loading .bar");
    const label = row.querySelector(".upload-name");
    body.appendChild(row);
    _queueUpload.push({file, filename, drive, path, bar, label});
  }
}

async function appendDroppedFiles(entry, drive, path) {
  if (entry.isFile) {
    const file = await new Promise((resolve, reject) => entry.file(resolve, reject));
    appendFileToQueue([new File([file], entry.fullPath.substring(1), { type: file.type })], drive, path);
  } else if (entry.isDirectory) {
    const reader = entry.createReader();
    while (true) {
      const entries = await new Promise((resolve, reject) => reader.readEntries(resolve, reject));
      if (!entries.length) break;
      for (const child of entries) await appendDroppedFiles(child, drive, path);
    }
  }
}

async function uploadFile() {
  if (_runningUpload) return;
  _runningUpload = true;
  $(".upload-close").disabled = true;
  $(".upload-summary").textContent = "Uploading… Do not close this page.";
  try {
    while (_queueUpload.length) {
      const item = _queueUpload.shift();
      item.label.textContent = item.filename + " — uploading";
      try {
        await new Promise((resolve, reject) => {
          const fd = new FormData();
          fd.append("file", item.file, item.filename);
          const req = new XMLHttpRequest();
          req.upload.onprogress = (e) => {
            if (e.lengthComputable) item.bar.style.width = Math.round(e.loaded / e.total * 100) + "%";
          };
          req.onload = () => req.status >= 200 && req.status < 300 ? resolve() : reject(new Error(`HTTP ${req.status}: ${req.responseText || "Upload failed"}`));
          req.onerror = () => reject(new Error("Connection lost; the file may be incomplete"));
          req.onabort = () => reject(new Error("Upload interrupted; the file may be incomplete"));
          req.ontimeout = () => reject(new Error("Upload timed out; the file may be incomplete"));
          req.open("POST", (IS_DEV ? "/bruce" : "") + "/upload?" + new URLSearchParams({fs:item.drive, folder:item.path}), true);
          req.timeout = 600000;
          req.send(fd);
        });
        item.label.textContent = item.filename + " — complete";
      } catch (error) {
        _uploadFailures++;
        item.label.textContent = item.filename + " — failed: " + error.message;
      }
    }
  } finally {
    _runningUpload = false;
    $(".upload-close").disabled = false;
    $(".upload-summary").textContent = _uploadFailures ? `${_uploadFailures} file(s) failed. Check storage/connection and retry them.` : "All files uploaded.";
    fetchSystemInfo(true).catch(() => {});
    fetchFiles(currentDrive, currentPath);
  }
}

async function runCommand(cmd) {
  Dialog.loading.show("Running command...");
  try {
    await requestPost("/cm", { cmnd: cmd });
  } catch (error) {
    alert("Failed to run command: " + error.message);
  } finally {
    Dialog.loading.hide();
  }
}

async function quickCli(cmd) {
  const box = activeTab === "studio" ? $("#st-msg") : activeTab === "monitor" ? $("#mon-msg") : $("#dash-action-status");
  try {
    const res = await requestPost("/cm", { cmnd: cmd, capture: "1" });
    box.className = "ota-status ok";
    box.textContent = `${cmd}: ${res.trim() || "done"}`;
  } catch (err) {
    box.className = "ota-status err";
    box.textContent = err.message || "Command failed";
  }
}

function getSerialCommand(fileName) {
  let parts = fileName.split(".");
  if (parts.length > 1) return EXECUTABLE[parts[parts.length - 1].toLowerCase()];
  return undefined;
}

function calcHash(str) {
  let hash = 5381;
  str = str.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
  for (let i = 0; i < str.length; i++) {
    hash = (((hash << 5) + hash) ^ str.charCodeAt(i)) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}

function updateLineNumbers() {
  const textarea = $(".dialog.editor .file-content");
  const lineNumbers = $(".dialog.editor .line-numbers");
  if (!textarea || !lineNumbers) return;
  const lineCount = textarea.value.split("\n").length;
  let out = "";
  for (let i = 1; i <= lineCount; i++) out += i + "\n";
  lineNumbers.textContent = out;
}

function syncScrolling() {
  const textarea = $(".dialog.editor .file-content");
  const lineNumbers = $(".dialog.editor .line-numbers");
  if (textarea && lineNumbers) lineNumbers.scrollTop = textarea.scrollTop;
}

function renderFileRow(fileList) {
  $("table.explorer tbody").innerHTML = "";
  fileList
    .split("\n")
    .sort((a, b) => {
      let [aFirst, ...aRest] = a.split(":");
      let [bFirst, ...bRest] = b.split(":");
      if (aFirst !== bFirst) return bFirst.localeCompare(aFirst);
      return aRest.join(":").toLowerCase().localeCompare(bRest.join(":").toLowerCase());
    })
    .forEach((line) => {
      let e;
      let [type, name, size] = line.split(":");
      if (size === undefined) return;
      let dPath = ((currentPath.endsWith("/") ? currentPath : currentPath + "/") + name).replace(/\/\//g, "/");
      if (type === "pa") {
        if (dPath === "/") return;
        e = T.pathRow();
        let preFolder = currentPath.substring(0, currentPath.lastIndexOf("/")) || "/";
        e.querySelector(".path-row").setAttribute("data-path", preFolder);
        e.querySelector(".path-row td").classList.add("act-browse");
      } else if (type === "Fi") {
        e = T.fileRow();
        e.querySelector(".file-row").setAttribute("data-file", dPath);
        e.querySelector(".act-rename").setAttribute("data-action", "renameFile");
        e.querySelector(".col-name").classList.add("act-edit-file");
        e.querySelector(".col-name").textContent = name;
        e.querySelector(".col-name").setAttribute("title", name);
        e.querySelector(".col-size").textContent = size;
        if (payloadPickerActive) {
          const pick = document.createElement("button");
          pick.type = "button"; pick.className = "btn-action act-pick-payload";
          pick.textContent = "Dùng làm payload";
          e.querySelector(".col-action").appendChild(pick);
        }
        e.querySelector(".col-action").classList.add("type-file");
        let downloadUrl = (IS_DEV ? "/bruce" : "") + `/file?fs=${currentDrive}&name=${encodeURIComponent(dPath)}&action=download`;
        e.querySelector(".act-download").setAttribute("download", name);
        e.querySelector(".act-download").setAttribute("href", downloadUrl);
        let serialCmd = getSerialCommand(name);
        if (serialCmd) {
          e.querySelector(".act-play").setAttribute("data-cmd", serialCmd + ' "' + dPath + '"');
          e.querySelector(".col-action").classList.add("executable");
        }
      } else if (type === "Fo") {
        e = T.fileRow();
        e.querySelector(".col-name").classList.add("act-browse");
        e.querySelector(".file-row").setAttribute("data-path", dPath);
        e.querySelector(".act-rename").setAttribute("data-action", "renameFolder");
        e.querySelector(".col-name").textContent = name;
        e.querySelector(".col-name").setAttribute("title", name);
        e.querySelector(".col-action").classList.add("type-folder");
      }
      if (e) $("table.explorer tbody").appendChild(e);
    });
}

let sdCardAvailable = false;
let currentDrive;
let currentPath;
let lastSysInfo = {};
let filesRequestGeneration = 0;
let payloadPickerActive = false;
function startPayloadPicker() {
  payloadPickerActive = true;
  document.getElementById("payload-picker-banner").classList.remove("hidden");
  switchTab("files");
  fetchFiles(currentDrive || "LittleFS", currentPath || "/");
}
function cancelPayloadPicker() {
  payloadPickerActive = false;
  document.getElementById("payload-picker-banner").classList.add("hidden");
  document.querySelectorAll(".act-pick-payload").forEach(button => button.remove());
  switchTab("studio"); switchStSlab("badusb");
}
function openRecordings(drive) {
  payloadPickerActive = false;
  document.getElementById("payload-picker-banner").classList.add("hidden");
  switchTab("files"); fetchFiles(drive, "/BruceMIC");
}
const btnRefreshFolder = $("#refresh-folder");

function updateURL(drive, path, editFile = null) {
  const params = new URLSearchParams();
  if (drive) params.set("drive", drive);
  if (path && path !== "/") params.set("path", path);
  if (editFile) params.set("edit", editFile);
  const newURL = window.location.pathname + (params.toString() ? "?" + params.toString() : "");
  window.history.replaceState({ drive, path, editFile }, "", newURL);
}

function getURLParams() {
  const params = new URLSearchParams(window.location.search);
  return { drive: params.get("drive"), path: params.get("path") || "/", editFile: params.get("edit") };
}

async function fetchFiles(drive, path) {
  const generation = ++filesRequestGeneration;
  btnRefreshFolder.classList.add("reloading");
  $("table.explorer tbody").innerHTML = '<tr><td colspan="3" style="text-align:center;color:var(--muted)">Loading...</td></tr>';
  currentDrive = drive;
  currentPath = path;
  updateURL(drive, path, getURLParams().editFile);
  $(`.act-browse.active`)?.classList.remove("active");
  $(`.act-browse[data-drive='${drive}']`)?.classList.add("active");
  $(".current-path").textContent = drive + ":/" + (path === "/" ? "" : path.replace(/^\/+/, ""));
  try {
    const req = await requestGet("/listfiles", { fs: drive, folder: path });
    if (generation !== filesRequestGeneration) return;
    renderFileRow(req);
    if (!$("table.explorer tbody").children.length) $("table.explorer tbody").innerHTML = '<tr><td colspan="3">This folder is empty.</td></tr>';
  } catch (error) {
    if (generation !== filesRequestGeneration) return;
    const tbody = $("table.explorer tbody");
    tbody.innerHTML = '<tr><td colspan="3"></td></tr>';
    tbody.querySelector("td").textContent = `Could not load folder: ${error.message}. Use refresh to retry.`;
  } finally {
    if (generation === filesRequestGeneration) btnRefreshFolder.classList.remove("reloading");
  }
}

function applyThemeCss(pri, sec, bg, style) {
  const root = document.documentElement.style;
  if (style !== undefined) document.documentElement.dataset.menuStyle = String(style);
  if (pri) root.setProperty("--color", pri);
  if (sec) root.setProperty("--sec-color", sec);
  if (bg) root.setProperty("--background", bg);
}

async function fetchSystemInfo(silent = false) {
  if (!silent) Dialog.loading.show("Fetching system info...");
  try {
    let info = JSON.parse(await requestGet("/systeminfo"));
    lastSysInfo = info;
    applyThemeCss(info.PRI_COLOR, info.SEC_COLOR, info.BG_COLOR, info.MENU_STYLE);
    $(".bruce-version").textContent = info.BRUCE_VERSION || "dev";
    if ($("#owner-badge")) $("#owner-badge").textContent = info.OWNER || "DSolution";
    if ($("#tele-board")) $("#tele-board").textContent = `${info.BOARD || "Bruce"} • ${info.MDNS || "bruce"}.local`;
    if ($("#tele-bat")) {
      const bat = info.BAT !== undefined ? `${info.BAT}%${info.CHG ? " CHG" : ""}` : "--";
      $("#tele-bat").textContent = info.BAT_MV ? `${bat} (${(info.BAT_MV / 1000).toFixed(2)}V)` : bat;
    }
    if ($("#tele-dma")) $("#tele-dma").textContent = `${info.DMA_FREE || "--"} / ${info.DMA_BLOCK || "--"}`;
    if ($("#tele-cpu") && info.CPU_MHZ) $("#tele-cpu").textContent = `${info.CPU_MHZ} MHz`;
    if ($("#tele-ram")) $("#tele-ram").textContent = `${info.HEAP_FREE || "--"} / ${info.PSRAM_FREE || "--"}`;
    if ($("#tele-ota")) $("#tele-ota").textContent = info.OTA_SLOT ? `${info.OTA_SLOT} → ${info.OTA_NEXT || "-"}` : "--";
    if ($("#tele-net")) {
      if (info.WIFI_MODE === "STA") {
        const rssiTxt = info.WIFI_RSSI ? ` ${info.WIFI_RSSI}dBm` : "";
        $("#tele-net").textContent = `LAN ${info.WIFI_SSID || ""} (${info.WIFI_IP || "-"}${rssiTxt})`;
      } else if (info.WIFI_MODE === "AP") {
        $("#tele-net").textContent = `AP ${info.AP_SSID || "BruceNet"} (${info.WIFI_IP || "192.168.4.1"})`;
      } else {
        $("#tele-net").textContent = "--";
      }
    }

    if ($("#dash-mdns")) $("#dash-mdns").textContent = `http://${info.MDNS || "bruce"}.local (${info.WIFI_IP || "-"})`;
    if ($("#dash-uptime")) $("#dash-uptime").textContent = `Up ${formatUptime(info.UPTIME_SEC)}`;
    if ($("#kv-board")) $("#kv-board").textContent = info.BOARD || "--";
    if ($("#kv-owner")) $("#kv-owner").textContent = `${info.OWNER || "--"} / ${info.BOOT_TAG || "--"}`;
    if ($("#kv-mac")) $("#kv-mac").textContent = info.MAC || "--";
    if ($("#kv-dma")) $("#kv-dma").textContent = `${info.DMA_FREE || "--"} (max ${info.DMA_BLOCK || "--"})`;
    if ($("#kv-heap")) $("#kv-heap").textContent = info.HEAP_FREE || "--";
    if ($("#kv-psram")) $("#kv-psram").textContent = info.PSRAM_FREE || "--";
    if ($("#wids-log-st")) $("#wids-log-st").textContent = info.WIDS_LOG ? "/wids_alerts.txt present" : "No alerts logged yet";
    if ($("#ble-log-st")) $("#ble-log-st").textContent = info.BLE_LOG ? "/ble_guard.log present" : "No events logged yet";
    if ($("#btn-open-wids")) $("#btn-open-wids").disabled = !info.WIDS_LOG;
    if ($("#btn-open-ble")) $("#btn-open-ble").disabled = !info.BLE_LOG;
    if ($("#dash-dualboot-card")) $("#dash-dualboot-card").classList.toggle("hidden", !info.DUALBOOT);

    const sdTotalBytes = parseHumanBytes(info.SD?.total);
    const sdUsedBytes = parseHumanBytes(info.SD?.used);
    sdCardAvailable = info.HAS_SD !== false && info.SD && info.SD.total !== "0 B";
    const sdBox = $(".free-space .free-sd");
    if (sdBox) {
      sdBox.classList.toggle("disabled-drive", info.HAS_SD === false);
      sdBox.querySelector("span").textContent = info.HAS_SD === false
        ? "No SD Slot (LittleFS Only)"
        : (sdCardAvailable ? `${info.SD.used} / ${info.SD.total}` : "Not Detected");
    }
    if ($("#meter-sd")) $("#meter-sd").style.width = sdTotalBytes > 0 ? Math.min(100, (sdUsedBytes * 100) / sdTotalBytes).toFixed(1) + "%" : "0%";

    const fsTotalBytes = parseHumanBytes(info.LittleFS?.total);
    const fsUsedBytes = parseHumanBytes(info.LittleFS?.used);
    $(".free-space .free-fs span").textContent = `${info.LittleFS.used} / ${info.LittleFS.total}`;
    if ($("#meter-fs")) $("#meter-fs").style.width = fsTotalBytes > 0 ? Math.min(100, (fsUsedBytes * 100) / fsTotalBytes).toFixed(1) + "%" : "0%";
  } finally {
    if (!silent) Dialog.loading.hide();
  }
}

async function openFileInEditor(drive, filePath) {
  let editor = $(".dialog.editor .file-content");
  $(".dialog.editor .editor-file-name").textContent = filePath;
  editor.value = "";
  Dialog.loading.show("Fetching content...");
  try {
    let r = await requestGet(`/file?fs=${drive}&name=${encodeURIComponent(filePath)}&action=edit`);
    currentDrive = drive;
    editor.value = r;
    editor.setAttribute("data-hash", calcHash(r));
    updateLineNumbers();
    $(".act-save-edit-file").disabled = true;
    $(".act-run-edit-file").classList.toggle("hidden", getSerialCommand(filePath) === undefined);
    Dialog.show("editor");
    updateURL(currentDrive, currentPath, filePath);
  } catch (err) {
    alert("Cannot open file: " + err.message);
  } finally {
    Dialog.loading.hide();
  }
}

let editorSaving = false;
async function saveEditorFile(runFile = false) {
  if (editorSaving) return;
  editorSaving = true;
  const editor = $(".dialog.editor .file-content");
  const filename = $(".dialog.editor .editor-file-name").textContent.trim();
  const content = editor.value;
  const drive = currentDrive;
  $(".act-save-edit-file").disabled = true;
  $(".act-run-edit-file").disabled = true;
  Dialog.loading.show("Saving...");
  try {
    if (isModified(editor)) {
      await requestPost("/edit", { fs: drive, name: filename, content });
      editor.setAttribute("data-hash", calcHash(content));
    }
    if (runFile) {
      if (isModified(editor)) throw new Error("File changed during save. Save again before running.");
      const serial = getSerialCommand(filename);
      if (serial !== undefined) await runCommand(serial + ' "' + filename + '"');
    }
  } catch (error) {
    alert("Save or run failed: " + error.message + ". Check the file before retrying.");
  } finally {
    editorSaving = false;
    $(".act-save-edit-file").disabled = !isModified(editor);
    $(".act-run-edit-file").disabled = false;
    Dialog.loading.hide();
  }
}

function isModified(target) {
  return target.getAttribute("data-hash") !== calcHash(target.value);
}

function openNavigator() {
  switchTab("screen");
}

let selectedOtaFile = null;
let otaBusy = false;
let otaCommitting = false;
let otaAbortCtrl = null;
let otaCancelled = false;

window.addEventListener("beforeunload", (e) => {
  if (otaBusy) {
    e.preventDefault();
    e.returnValue = "";
  }
});

function openOtaModal() {
  if (otaBusy) {
    Dialog.show("ota");
    return;
  }
  selectedOtaFile = null;
  $("#ota-start-btn").disabled = true;
  $("#ota-cancel-btn").classList.add("hidden");
  $("#ota-status").className = "ota-status hidden";
  $("#ota-prog").classList.add("hidden");
  $("#ota-file-input").value = "";
  $("#ota-cur-slot").textContent = lastSysInfo.OTA_SLOT || "--";
  $("#ota-nxt-slot").textContent = lastSysInfo.OTA_NEXT || "--";
  $("#ota-max-sz").textContent = lastSysInfo.OTA_MAX || "4.0 MB";
  const netMode = lastSysInfo.WIFI_MODE === "STA"
    ? `LAN WiFi (${lastSysInfo.WIFI_SSID || ""}) • http://${lastSysInfo.WIFI_IP || "-"}/ota`
    : `AP Hotspot (${lastSysInfo.AP_SSID || "BruceNet"}) • Switch to LAN WiFi for faster router OTA`;
  $("#ota-net-line").textContent = netMode;
  Dialog.show("ota");
}

async function scanWifiNets() {
  const list = $("#wifi-scan-list");
  list.innerHTML = '<div style="color:var(--muted);font-size:12px;padding:6px">Scanning 2.4 GHz networks...</div>';
  try {
    const res = JSON.parse(await requestGet("/wifiscan"));
    if (!res.nets || res.nets.length === 0) {
      list.innerHTML = '<div style="color:var(--muted);font-size:12px;padding:6px">No networks found.</div>';
      return;
    }
    list.innerHTML = "";
    res.nets.forEach((n) => {
      const item = document.createElement("button");
      item.type = "button";
      item.className = "wifi-net-item";
      const badge = n.saved ? "Saved" : (n.enc ? "Locked" : "Open");
      const nameSpan = document.createElement("span");
      nameSpan.textContent = n.ssid;
      const metaSpan = document.createElement("span");
      metaSpan.className = "wifi-net-meta";
      metaSpan.textContent = `${badge} • ${n.rssi} dBm`;
      item.appendChild(nameSpan);
      item.appendChild(metaSpan);
      item.onclick = () => {
        document.querySelectorAll(".wifi-net-item").forEach((x) => x.classList.remove("sel"));
        item.classList.add("sel");
        $("#wifi-ssid-input").value = n.ssid;
        $("#wifi-pwd-input").placeholder = n.saved ? "Saved credential (leave blank or enter new)" : "Enter Wi-Fi password";
      };
      list.appendChild(item);
    });
  } catch (err) {
    list.innerHTML = "";
    const msgEl = document.createElement("div");
    msgEl.style.cssText = "color:#ffb3ba;font-size:12px;padding:6px";
    msgEl.textContent = err.message || "Scan failed";
    list.appendChild(msgEl);
  }
}

async function openWifiModal(selectedNetwork = null) {
  if (otaBusy) return;
  $("#wifi-conn-msg").className = "ota-status hidden";
  try {
    const st = JSON.parse(await requestGet("/wifistatus"));
    $("#wifi-cur-status").textContent = st.mode === "STA"
      ? `Connected to LAN: ${st.ssid} (${st.ip} • ${st.rssi} dBm)`
      : `Currently in AP Mode (${st.ssid} at ${st.ip}). Connect below to expose WebUI & OTA on 192.168.x.x.`;
  } catch (_) {
    $("#wifi-cur-status").textContent = "Select your router below to switch device to LAN Wi-Fi.";
  }
  if (selectedNetwork) {
    $("#wifi-ssid-input").value = selectedNetwork.ssid || "";
    $("#wifi-pwd-input").value = "";
    $("#wifi-pwd-input").placeholder = selectedNetwork.saved ? "Saved credential (leave blank or enter new)" : "Enter Wi-Fi password";
  }
  Dialog.show("wifi");
  scanWifiNets();
}

async function validateOtaFile(file) {
  selectedOtaFile = null;
  $("#ota-start-btn").disabled = true;
  const st = $("#ota-status");
  if (!file) return;
  if (!file.name.toLowerCase().endsWith(".bin")) {
    st.className = "ota-status err";
    st.textContent = "Invalid extension. Select a .bin firmware file.";
    return;
  }
  const hdr = new Uint8Array(await file.slice(0, 36).arrayBuffer());
  if (hdr.length < 36 || hdr[0] !== 0xe9) {
    st.className = "ota-status err";
    st.textContent = "Invalid ESP32 binary (missing 0xE9 magic).";
    return;
  }
  if (!(hdr[32] === 0x32 && hdr[33] === 0x54 && hdr[34] === 0xcd && hdr[35] === 0xab)) {
    st.className = "ota-status err";
    st.textContent = "Blocked: looks like factory.bin / bootloader! Use DSolution-183-2mic-ota.bin.";
    return;
  }
  selectedOtaFile = file;
  st.className = "ota-status ok";
  st.textContent = `Ready: ${file.name} (${(file.size / 1048576).toFixed(2)} MB) — Valid App Image`;
  $("#ota-start-btn").disabled = false;
}

let SCREEN_NAVIGATING = false;
async function runNavigation(direction) {
  if (SCREEN_NAVIGATING) return;
  SCREEN_NAVIGATING = true;
  $(".navigator-canvas").setAttribute("aria-busy", "true");
  document.querySelectorAll(".navigator-canvas .nav").forEach((b) => { b.disabled = true; });
  try {
    drawCanvasLoading();
    await requestPost("/cm", { cmnd: `nav ${direction.toLowerCase()}` });
    // The device consumes the event asynchronously after responding.
    await new Promise((resolve) => setTimeout(resolve, 120));
    await reloadScreen(true);
  } catch (error) {
    $("#screen-status").textContent = `Navigation failed: ${error.message}`;
  } finally {
    SCREEN_NAVIGATING = false;
    $(".navigator-canvas").setAttribute("aria-busy", "false");
    document.querySelectorAll(".navigator-canvas .nav").forEach((b) => { b.disabled = false; });
  }
}

const btnForceReload = $("#force-reload");
let SCREEN_RELOAD = null;
let SCREEN_RERUN = false;
function reloadScreen(force = false) {
  if (SCREEN_RELOAD) {
    if (force === true) SCREEN_RERUN = true;
    return SCREEN_RELOAD;
  }
  btnForceReload.classList.add("reloading");
  SCREEN_RELOAD = (async () => {
    do {
      SCREEN_RERUN = false;
      try {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 8000);
        let response;
        let data;
        try {
          response = await fetch((IS_DEV ? "/bruce" : "") + "/getscreen", { cache: "no-store", signal: controller.signal });
          if (!response.ok) throw new Error(`Screen request failed (${response.status})`);
          if (response.headers.get("X-Screen-Logging") === "inactive") throw new Error("Screen logging is inactive");
          data = new Uint8Array(await response.arrayBuffer());
        } finally { clearTimeout(timeout); }
        const result = await renderTFT(data);
        const warnings = [];
        if (response.headers.get("X-Screen-Truncated") === "1" || response.headers.get("X-Screen-Base") === "0") warnings.push("History is incomplete; navigate to redraw the screen");
        if (result.missing) warnings.push(`${result.missing} image(s) could not be loaded`);
        if (result.unknown) warnings.push(`${result.unknown} unsupported drawing command(s)`);
        if (response.headers.get("X-Screen-Unmapped") === "1") warnings.push("Bitmap or sprite drawing may be missing from the mirror");
        if (response.headers.get("X-Screen-Off") === "1") warnings.push("Backlight off; mirror remains active");
        $("#screen-status").textContent = warnings.length ? warnings.join(" · ") : "Screen connected";
      } catch (error) {
        $("#screen-status").textContent = `Screen unavailable: ${error.name === "AbortError" ? "request timed out" : error.message}`;
        console.error("Failed to reload screen:", error);
      }
    } while (SCREEN_RERUN);
  })().finally(() => {
    btnForceReload.classList.remove("reloading");
    SCREEN_RELOAD = null;
  });
  return SCREEN_RELOAD;
}

const eConfigAutoReload = $("#navigator-auto-reload");
let AUTO_RELOAD_SCREEN = null;
let AUTO_RELOAD_GENERATION = 0;
async function taskReloader(generation) {
  const timer = parseInt(eConfigAutoReload.value, 10);
  if (generation !== AUTO_RELOAD_GENERATION || timer <= 0 || activeTab !== "screen") return;
  await reloadScreen();
  if (generation === AUTO_RELOAD_GENERATION && activeTab === "screen" && parseInt(eConfigAutoReload.value, 10) > 0)
    AUTO_RELOAD_SCREEN = setTimeout(() => taskReloader(generation), parseInt(eConfigAutoReload.value, 10));
}
function autoReloadScreen() {
  const generation = ++AUTO_RELOAD_GENERATION;
  if (AUTO_RELOAD_SCREEN) clearTimeout(AUTO_RELOAD_SCREEN);
  AUTO_RELOAD_SCREEN = null;
  if (parseInt(eConfigAutoReload.value, 10) > 0 && activeTab === "screen") taskReloader(generation);
}

async function loadScreenSettings() {
  const status = $("#screen-settings-status");
  try {
    const settings = JSON.parse(await requestGet("/screen/settings"));
    for (const [id, value] of [["#screen-dimmer", settings.dimmer], ["#screen-off", settings.off], ["#screen-power", settings.power]]) {
      if (document.activeElement !== $(id)) $(id).value = String(value);
    }
    status.className = "ota-status hidden";
  } catch (err) {
    status.className = "ota-status err";
    status.textContent = `Could not load display settings: ${err.message}`;
  }
}
$("#screen-settings-save")?.addEventListener("click", async () => {
  const status = $("#screen-settings-status");
  const dimmer = $("#screen-dimmer").value;
  const off = $("#screen-off").value;
  const power = $("#screen-power").value;
  if (!/^(?:0|[1-9]\d*)$/.test(dimmer) || +dimmer > 600 ||
      !/^(?:-1|0|[1-9]\d*)$/.test(off) || +off > 600 || !["0", "1", "2"].includes(power)) {
    status.className = "ota-status err";
    status.textContent = "Use integer timeouts in the displayed ranges.";
    return;
  }
  try {
    const data = JSON.parse(await requestPost("/screen/settings", {dimmer, off, power}));
    status.className = "ota-status ok";
    status.textContent = data.msg || "Saved";
  } catch (err) {
    status.className = "ota-status err";
    status.textContent = err.message || "Could not save display settings";
  }
});

let loadingDrawn = false;
// Bound memory use and refresh replaced files instead of caching images forever.
const imageCache = new Map();
let imageCacheGeneration = 0;
async function renderTFT(data) {
  loadingDrawn = false;
  const visibleCanvas = $("#navigator-screen");
  // Validate framing before touching the previous frame, including the screen info.
  if (data.length < 8 || data[0] !== 0xaa || data[1] !== 8 || data[2] !== 99) throw new Error("Invalid screen frame");
  const minimumPacket = {0:5, 1:13, 2:13, 3:15, 4:15, 5:11, 6:11, 7:17, 8:17, 9:13, 10:13,
    11:13, 12:19, 13:17, 14:13, 15:13, 16:13, 17:13, 18:12, 19:9, 20:11, 21:11, 22:14, 99:8};
  let unknown = 0;
  for (let p = 0; p < data.length;) {
    if (data[p] !== 0xaa || p + 3 > data.length || data[p + 1] < 3 || p + data[p + 1] > data.length ||
        (minimumPacket[data[p + 2]] && data[p + 1] < minimumPacket[data[p + 2]]))
      throw new Error("Incomplete screen frame");
    if (!minimumPacket[data[p + 2]]) unknown++;
    p += data[p + 1];
  }
  const width = (data[3] << 8) | data[4], height = (data[5] << 8) | data[6];
  if (!width || !height || width > 1024 || height > 1024) throw new Error("Invalid screen dimensions");
  // Draw offscreen: slow or failed image loads cannot blank a good visible frame.
  const canvas = document.createElement("canvas");
  canvas.width = width; canvas.height = height;
  const ctx = canvas.getContext("2d");
  let missingImages = 0;

  const loadImage = async (url) => {
    const entry = imageCache.get(url);
    if (entry && Date.now() - entry.time < 30000) return entry.image;
    imageCache.delete(url);
    return new Promise((resolve, reject) => {
      const img = new Image();
      const timer = setTimeout(() => { img.onload = img.onerror = null; reject(new Error("Image timed out")); }, 4000);
      img.onload = () => {
        clearTimeout(timer);
        if (imageCache.size >= 32) imageCache.delete(imageCache.keys().next().value);
        imageCache.set(url, { image: img, time: Date.now() }); resolve(img);
      };
      img.onerror = () => { clearTimeout(timer); reject(new Error("Image unavailable")); };
      img.src = `${url}&mirrorVersion=${Math.floor(Date.now() / 30000)}-${imageCacheGeneration}`;
    });
  };

  const drawImageCached = async (img_url, input) => {
    if (IS_DEV) img_url = "/bruce" + img_url;
    let img = await loadImage(img_url);
    let drawX = input.x;
    let drawY = input.y;
    if (input.center === 1) {
      drawX += (canvas.width - img.width) / 2;
      drawY += (canvas.height - img.height) / 2;
    }
    ctx.drawImage(img, drawX, drawY);
  };

  const color565toCSS = (c) => `rgb(${(((c >> 11) & 0x1f) * 255) / 31},${(((c >> 5) & 0x3f) * 255) / 63},${((c & 0x1f) * 255) / 31})`;

  const drawRoundRect = (ctx, input, fill) => {
    const { x, y, w, h, r } = input;
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
    if (fill) ctx.fill();
    else ctx.stroke();
  };

  let startData = 0;
  const getByteValue = (dataType) => {
    if (dataType === "int8") return data[startData++];
    if (dataType === "int16") {
      let value = (data[startData] << 8) | data[startData + 1];
      startData += 2;
      return value;
    }
    let strLength = parseInt(dataType.substring(1), 10);
    let strBytes = data.slice(startData, startData + strLength);
    startData += strLength;
    return new TextDecoder().decode(strBytes);
  };

  const byteToObject = (fn, size) => {
    let keysMap = {
      0: ["fg"], 1: ["x", "y", "w", "h", "fg"], 2: ["x", "y", "w", "h", "fg"],
      3: ["x", "y", "w", "h", "r", "fg"], 4: ["x", "y", "w", "h", "r", "fg"],
      5: ["x", "y", "r", "fg"], 6: ["x", "y", "r", "fg"],
      7: ["x", "y", "x2", "y2", "x3", "y3", "fg"], 8: ["x", "y", "x2", "y2", "x3", "y3", "fg"],
      9: ["x", "y", "rx", "ry", "fg"], 10: ["x", "y", "rx", "ry", "fg"],
      11: ["x", "y", "x1", "y1", "fg"], 12: ["x", "y", "r", "ir", "startAngle", "endAngle", "fg", "bg"],
      13: ["x", "y", "bx", "by", "wd", "fg", "bg"],
      14: ["x", "y", "size", "fg", "bg", "txt"], 15: ["x", "y", "size", "fg", "bg", "txt"],
      16: ["x", "y", "size", "fg", "bg", "txt"], 17: ["x", "y", "size", "fg", "bg", "txt"],
      18: ["x", "y", "center", "ms", "fs", "file"], 19: ["x", "y", "fg"],
      20: ["x", "y", "h", "fg"], 21: ["x", "y", "w", "fg"],
      22: ["x", "y", "size", "fg", "bg", "datum", "txt"], 99: ["w", "h", "rotation"],
    };
    let r = {};
    let lengthLeft = size - 3;
    for (let key of keysMap[fn] || []) {
      if (["txt", "file"].includes(key)) r[key] = getByteValue(`s${lengthLeft}`);
      else if (["rotation", "fs", "datum"].includes(key)) {
        lengthLeft -= 1;
        r[key] = getByteValue("int8");
        if (key === "fs") r[key] = r[key] === 0 ? "SD" : "FS";
      } else {
        lengthLeft -= 2;
        r[key] = getByteValue("int16");
        if (["x", "y", "x1", "y1", "x2", "y2", "x3", "y3", "bx", "by"].includes(key) && r[key] >= 0x8000) r[key] -= 0x10000;
      }
    }
    return r;
  };

  let offset = 0;
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  let screenText = [];

  while (offset < data.length) {
    ctx.beginPath();
    if (data[offset] !== 0xaa) break;
    startData = offset + 1;
    let size = getByteValue("int8");
    let fn = getByteValue("int8");
    offset += size;
    let input = byteToObject(fn, size);
    ctx.lineWidth = 1;
    ctx.fillStyle = "black";
    ctx.strokeStyle = "black";
    switch (fn) {
      case 99:
        if (canvas.width !== input.w || canvas.height !== input.h) {
          if (!input.w || !input.h || input.w > 1024 || input.h > 1024) throw new Error("Invalid screen dimensions");
          canvas.width = input.w; canvas.height = input.h;
        }
        break;
      case 0:
        ctx.fillStyle = color565toCSS(input.fg);
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        break;
      case 1:
        ctx.strokeStyle = color565toCSS(input.fg);
        ctx.strokeRect(input.x, input.y, input.w, input.h);
        break;
      case 2:
        ctx.fillStyle = color565toCSS(input.fg);
        ctx.fillRect(input.x, input.y, input.w, input.h);
        break;
      case 3:
        ctx.strokeStyle = color565toCSS(input.fg);
        drawRoundRect(ctx, input, false);
        break;
      case 4:
        ctx.fillStyle = color565toCSS(input.fg);
        drawRoundRect(ctx, input, true);
        break;
      case 5:
        ctx.strokeStyle = color565toCSS(input.fg);
        ctx.arc(input.x, input.y, input.r, 0, Math.PI * 2);
        ctx.stroke();
        break;
      case 6:
        ctx.fillStyle = color565toCSS(input.fg);
        ctx.arc(input.x, input.y, input.r, 0, Math.PI * 2);
        ctx.fill();
        break;
      case 7:
      case 8:
        ctx.beginPath();
        ctx.moveTo(input.x, input.y);
        ctx.lineTo(input.x2, input.y2);
        ctx.lineTo(input.x3, input.y3);
        ctx.closePath();
        if (fn === 8) { ctx.fillStyle = color565toCSS(input.fg); ctx.fill(); }
        else { ctx.strokeStyle = color565toCSS(input.fg); ctx.stroke(); }
        break;
      case 9:
      case 10:
        ctx.beginPath();
        ctx.ellipse(input.x, input.y, input.rx, input.ry, 0, 0, Math.PI * 2);
        if (fn === 10) { ctx.fillStyle = color565toCSS(input.fg); ctx.fill(); }
        else { ctx.strokeStyle = color565toCSS(input.fg); ctx.stroke(); }
        break;
      case 11:
        ctx.strokeStyle = color565toCSS(input.fg);
        ctx.moveTo(input.x, input.y);
        ctx.lineTo(input.x1, input.y1);
        ctx.stroke();
        break;
      case 12:
        ctx.strokeStyle = color565toCSS(input.fg);
        ctx.lineWidth = input.r - input.ir || 1;
        ctx.beginPath();
        ctx.arc(input.x, input.y, (input.r + input.ir) / 2, ((input.startAngle + 90 || 0) * Math.PI) / 180, ((input.endAngle + 90 || 0) * Math.PI) / 180);
        ctx.stroke();
        break;
      case 13:
        ctx.strokeStyle = color565toCSS(input.fg);
        ctx.lineWidth = input.wd || 1;
        ctx.moveTo(input.x, input.y);
        ctx.lineTo(input.bx, input.by);
        ctx.stroke();
        break;
      case 14:
      case 15:
      case 16:
      case 17:
      case 22: {
        const opaqueText = input.bg !== input.fg;
        ctx.fillStyle = color565toCSS(input.bg);
        input.txt = input.txt.replaceAll("\\n", "\n");
        screenText.push(input.txt);
        // Built-in font cells are approximately 6 x 8 pixels per scale unit.
        const fw = input.size * 6;
        const datum = fn === 22 && input.datum <= 8 ? input.datum : fn === 14 ? 1 : fn === 15 ? 2 : 0;
        const align = datum % 3;
        const yOffset = datum >= 6 ? input.size * 8 : datum >= 3 ? input.size * 4 : 0;
        ctx.font = `${input.size * 8}px monospace`;
        ctx.textBaseline = "top";
        ctx.textAlign = align === 1 ? "center" : align === 2 ? "right" : "left";
        input.txt.split(/\r?\n/).forEach((line, i) => {
          const o = align === 2 ? line.length * fw : align === 1 ? line.length * fw / 2 : 0;
          const y = input.y - yOffset + i * input.size * 8;
          if (opaqueText) { ctx.fillStyle = color565toCSS(input.bg); ctx.fillRect(input.x - o, y, line.length * fw, input.size * 8); }
          ctx.fillStyle = color565toCSS(input.fg);
          ctx.fillText(line, input.x, y);
        });
        break;
      }
      case 18:
        try { await drawImageCached(`/file?fs=${input.fs}&name=${encodeURIComponent(input.file)}&action=image`, input); }
        catch (error) { missingImages++; console.warn("Mirror image unavailable", input.file, error); }
        break;
      case 19:
        ctx.fillStyle = color565toCSS(input.fg);
        ctx.fillRect(input.x, input.y, 1, 1);
        break;
      case 20:
        ctx.fillStyle = color565toCSS(input.fg);
        ctx.fillRect(input.x, input.y, 1, input.h);
        break;
      case 21:
        ctx.fillStyle = color565toCSS(input.fg);
        ctx.fillRect(input.x, input.y, input.w, 1);
        break;
    }
  }

  if (visibleCanvas.width !== canvas.width || visibleCanvas.height !== canvas.height) {
    visibleCanvas.width = canvas.width; visibleCanvas.height = canvas.height;
  }
  visibleCanvas.getContext("2d").drawImage(canvas, 0, 0);
  const allText = screenText.join(" ").toLowerCase();
  const isWiFiMenu = ["wifi", "evil portal", "deauth", "handshake"].some((k) => allText.includes(k));
  $("#wifi-warning").classList.toggle("hidden", !isWiFiMenu);
  return { missing: missingImages, unknown };
}

function drawCanvasLoading() {
  if (loadingDrawn || !showNavigating) return;
  loadingDrawn = true;
  $("#screen-status").textContent = "Navigating…";
}

function updateBootPreview() {
  const owner = ($("#pers-owner").value || "DSolution").trim();
  const tag = ($("#pers-tag").value || "ESP32-S3 SEC LAB").trim();
  const mdns = ($("#pers-mdns").value || "bruce").trim().replace(/\.local$/i, "");
  const pri = $("#pers-pri").value;
  const sec = $("#pers-sec").value;
  const bg = $("#pers-bg").value;
  $("#bm-owner-pill").textContent = owner.slice(0, 12);
  $("#bm-title").textContent = owner;
  $("#bm-sub").textContent = tag;
  $("#bm-mdns").textContent = `http://${mdns || "bruce"}.local`;
  const box = $("#boot-preview");
  box.style.setProperty("--bm-pri", pri);
  box.style.setProperty("--bm-sec", sec);
  box.style.setProperty("--bm-bg", bg);
}

async function loadPersonalizeForm() {
  try {
    const p = JSON.parse(await requestGet("/personalize"));
    $("#pers-owner").value = p.ownerName || "DSolution";
    $("#pers-tag").value = p.bootBannerTag || "ESP32-S3 SEC LAB";
    $("#pers-mdns").value = p.mdnsHost || "bruce";
    $("#pers-apssid").value = p.apSsid || "BruceNet";
    $("#pers-appwd").value = p.apPwd || "";
    $("#pers-pri").value = p.priColor || "#00f0ff";
    $("#pers-sec").value = p.secColor || "#50aebd";
    $("#pers-bg").value = p.bgColor || "#070d12";
    $("#pers-style").value = String(p.menuStyle ?? 0);
    applyThemeCss(p.priColor, p.secColor, p.bgColor, p.menuStyle);
    updateBootPreview();
  } catch (err) {
    console.error("Personalize load failed:", err);
  }
}

["#pers-owner", "#pers-tag", "#pers-mdns", "#pers-pri", "#pers-sec", "#pers-bg"].forEach((sel) => {
  $(sel)?.addEventListener("input", updateBootPreview);
});

document.querySelectorAll(".preset-chip").forEach((chip) => {
  chip.addEventListener("click", () => {
    $("#pers-pri").value = chip.getAttribute("data-pri").toLowerCase();
    $("#pers-sec").value = chip.getAttribute("data-sec").toLowerCase();
    $("#pers-bg").value = chip.getAttribute("data-bg").toLowerCase();
    updateBootPreview();
  });
});

$("#btn-reload-pers")?.addEventListener("click", loadPersonalizeForm);
$("#btn-save-pers")?.addEventListener("click", async () => {
  const pwd = $("#pers-appwd").value;
  if (pwd.length > 0 && pwd.length < 8) {
    alert("AP password must be blank (open) or at least 8 characters.");
    return;
  }
  const st = $("#pers-status");
  try {
    const res = JSON.parse(await requestPost("/personalize", {
      ownerName: $("#pers-owner").value.trim(),
      bootBannerTag: $("#pers-tag").value.trim(),
      mdnsHost: $("#pers-mdns").value.trim(),
      apSsid: $("#pers-apssid").value.trim(),
      apPwd: pwd,
      priColor: $("#pers-pri").value,
      secColor: $("#pers-sec").value,
      bgColor: $("#pers-bg").value,
      menuStyle: $("#pers-style").value,
    }));
    applyThemeCss(res.priColor, res.secColor, res.bgColor, res.menuStyle);
    $("#pers-pri").value = res.priColor;
    $("#pers-sec").value = res.secColor;
    $("#pers-bg").value = res.bgColor;
    updateBootPreview();
    st.className = "ota-status ok";
    st.textContent = res.msg || "Saved!";
    fetchSystemInfo(true);
  } catch (err) {
    st.className = "ota-status err";
    st.textContent = err.message || "Failed to save";
  }
});

const cmdHistory = [];
let cmdHistIdx = -1;
async function execConsoleCmd(cmdText) {
  const cmd = cmdText.trim();
  if (!cmd) return;
  cmdHistory.unshift(cmd);
  if (cmdHistory.length > 30) cmdHistory.pop();
  cmdHistIdx = -1;
  const out = $("#console-out");
  out.textContent += `# ${cmd}\n`;
  out.scrollTop = out.scrollHeight;
  try {
    const res = await requestPost("/cm", { cmnd: cmd, capture: "1" });
    out.textContent += res.endsWith("\n") ? res : res + "\n";
  } catch (err) {
    out.textContent += `[error] ${err.message}\n`;
  }
  out.scrollTop = out.scrollHeight;
}

$("#console-run")?.addEventListener("click", () => {
  const inp = $("#console-in");
  const val = inp.value;
  inp.value = "";
  execConsoleCmd(val);
});

$("#console-clear")?.addEventListener("click", () => {
  $("#console-out").textContent = "";
});

$("#console-in")?.addEventListener("keydown", (e) => {
  if (e.key === "Enter") {
    e.preventDefault();
    $("#console-run").click();
  } else if (e.key === "ArrowUp" && cmdHistory.length > 0) {
    e.preventDefault();
    cmdHistIdx = Math.min(cmdHistory.length - 1, cmdHistIdx + 1);
    $("#console-in").value = cmdHistory[cmdHistIdx];
  } else if (e.key === "ArrowDown") {
    e.preventDefault();
    if (cmdHistIdx > 0) {
      cmdHistIdx--;
      $("#console-in").value = cmdHistory[cmdHistIdx];
    } else {
      cmdHistIdx = -1;
      $("#console-in").value = "";
    }
  }
});

document.querySelectorAll(".chip-cmd").forEach((ch) => {
  ch.addEventListener("click", () => execConsoleCmd(ch.getAttribute("data-cmd")));
});

// All clock controls use the same device endpoint and local-time convention.
async function syncBrowserTime() {
  const localEpoch = Math.floor(Date.now() / 1000) - new Date().getTimezoneOffset() * 60;
  await requestPost("/personalize", { epoch: String(localEpoch) });
}
$("#act-sync-time")?.addEventListener("click", async () => {
  const box = $("#dash-action-status");
  try {
    await syncBrowserTime();
    box.className = "ota-status ok";
    box.textContent = "Device clock synced to browser local time!";
  } catch (err) {
    box.className = "ota-status err";
    box.textContent = err.message || "Time sync failed";
  }
});

$("#act-led-theme")?.addEventListener("click", () => {
  const hex = (lastSysInfo.PRI_COLOR || "#00F0FF").replace("#", "");
  quickCli("led hex " + hex);
});

$("#btn-open-wids")?.addEventListener("click", () => openFileInEditor("LittleFS", "/wids_alerts.txt"));
$("#btn-open-ble")?.addEventListener("click", () => openFileInEditor("LittleFS", "/ble_guard.log"));

$("#btn-switch-xiaozhi")?.addEventListener("click", async () => {
  if (!confirm("Switch device to XiaoZhi HeyLily?")) return;
  try { await requestGet("/reboot", { target: "xiaozhi" }); }
  catch (_) { alert("Could not switch OS. If OTA is running, wait or cancel it first."); }
});
$("#btn-switch-bootmenu")?.addEventListener("click", async () => {
  if (!confirm("Reboot into Dual-Boot Launcher Menu?")) return;
  try { await requestGet("/reboot", { target: "menu" }); }
  catch (_) { alert("Could not open boot menu. If OTA is running, wait or cancel it first."); }
});

$("#btn-save-png")?.addEventListener("click", () => {
  const canvas = $("#navigator-screen");
  const a = document.createElement("a");
  a.download = `bruce-screen-${Date.now()}.png`;
  a.href = canvas.toDataURL("image/png");
  a.click();
});

let oldTimerSession = sessionStorage.getItem("autoReload") || "1000";
if (eConfigAutoReload.querySelector(`option[value="${oldTimerSession}"]`)) {
  eConfigAutoReload.querySelector(`option[value="${oldTimerSession}"]`).selected = true;
}
eConfigAutoReload.addEventListener("change", (e) => {
  e.preventDefault();
  autoReloadScreen();
  sessionStorage.setItem("autoReload", eConfigAutoReload.value);
});

btnForceReload.addEventListener("click", async (e) => {
  e.preventDefault();
  imageCache.clear();
  imageCacheGeneration++;
  drawCanvasLoading();
  await reloadScreen(true);
});

$("#ota-file-input").addEventListener("change", (e) => validateOtaFile(e.target.files[0]));
const otaDrop = $("#ota-drop-zone");
otaDrop.addEventListener("dragover", (e) => { e.preventDefault(); otaDrop.classList.add("drag"); });
otaDrop.addEventListener("dragleave", () => otaDrop.classList.remove("drag"));
otaDrop.addEventListener("drop", (e) => {
  e.preventDefault();
  otaDrop.classList.remove("drag");
  if (e.dataTransfer.files[0]) validateOtaFile(e.dataTransfer.files[0]);
});
$("#ota-cancel-btn").addEventListener("click", async () => {
  if (!otaBusy || otaCommitting) return;
  otaCancelled = true;
  $("#ota-prog-msg").textContent = "Cancelling...";
  if (otaAbortCtrl) otaAbortCtrl.abort();
});

$("#ota-start-btn").addEventListener("click", async () => {
  if (!selectedOtaFile || otaBusy) return;
  otaBusy = true;
  otaCancelled = false;
  otaCommitting = false;
  let session = "";
  $("#ota-start-btn").disabled = true;
  $("#ota-cancel-btn").classList.remove("hidden");
  $("#ota-prog").classList.remove("hidden");
  $("#ota-bar-fill").style.width = "0%";
  $("#ota-prog-pct").textContent = "0%";
  $("#ota-prog-msg").textContent = "Initializing OTA slot...";
  $("#ota-status").className = "ota-status ok";
  const base = IS_DEV ? "/bruce" : "";
  const t0 = Date.now();
  try {
    const beginFd = new FormData();
    beginFd.append("size", String(selectedOtaFile.size));
    const br = await fetch(base + "/ota/begin", { method: "POST", body: beginFd });
    const bd = await br.json().catch(() => ({}));
    if (!br.ok || !bd.ok) throw new Error(bd.msg || "Failed to initialize OTA");
    if (typeof bd.session !== "string" || !bd.session) throw new Error("OTA session missing. Refresh the page and try again.");
    session = bd.session;
    if (otaCancelled) throw new Error("OTA cancelled by user.");

    const chunkSize = bd.chunkSize || 32768;
    let offset = 0;
    let retries = 0;
    while (offset < selectedOtaFile.size) {
      if (otaCancelled) throw new Error("OTA cancelled by user.");
      const end = Math.min(offset + chunkSize, selectedOtaFile.size);
      const slice = selectedOtaFile.slice(offset, end);
      let ok = false;
      let lastErr = "Network error";
      for (let attempt = 0; attempt < 5 && !otaCancelled; attempt++) {
        otaAbortCtrl = new AbortController();
        const timer = setTimeout(() => otaAbortCtrl.abort(), 12000);
        try {
          const cr = await fetch(`${base}/ota/chunk?offset=${offset}`, {
            method: "POST",
            headers: { "Content-Type": "application/octet-stream", "X-OTA-Session": session },
            body: slice,
            signal: otaAbortCtrl.signal,
          });
          clearTimeout(timer);
          const cd = await cr.json().catch(() => ({}));
          if ((cr.ok && cd.ok) || (cr.status === 409 && typeof cd.written === "number")) {
            const next = cd.written;
            if (!Number.isSafeInteger(next) || next <= offset || next > selectedOtaFile.size)
              throw new Error("Invalid OTA offset from device");
            offset = next;
            ok = true;
            break;
          }
          lastErr = cd.msg || `HTTP ${cr.status}`;
          if (cr.status >= 400 && cr.status < 500 && cr.status !== 408) break;
        } catch (err) {
          clearTimeout(timer);
          lastErr = otaCancelled ? "OTA cancelled by user." : (err.message || "Connection reset");
        }
        retries++;
        $("#ota-prog-msg").textContent = `Retrying chunk (${retries})...`;
        await new Promise((r) => setTimeout(r, 350 * (attempt + 1)));
      }
      if (!ok) throw new Error(lastErr);
      const pct = Math.min(100, Math.round((offset * 100) / selectedOtaFile.size));
      const sec = Math.max(0.2, (Date.now() - t0) / 1000);
      const kbps = (offset / 1024 / sec).toFixed(0);
      const eta = offset > 0 ? Math.max(0, Math.round((selectedOtaFile.size - offset) / (offset / sec))) : 0;
      $("#ota-bar-fill").style.width = pct + "%";
      $("#ota-prog-pct").textContent = pct + "%";
      $("#ota-prog-msg").textContent = `${(offset / 1048576).toFixed(2)}/${(selectedOtaFile.size / 1048576).toFixed(2)} MB • ${kbps} KB/s • ETA ${eta}s${retries ? ` • ${retries} retries` : ""}`;
    }

    if (otaCancelled) throw new Error("OTA cancelled by user.");
    otaCommitting = true;
    $("#ota-cancel-btn").classList.add("hidden");
    $("#ota-prog-msg").textContent = "Verifying & committing OTA slot...";
    const fr = await fetch(base + "/ota/commit", { method: "POST", headers: { "X-OTA-Session": session } });
    const fd = await fr.json().catch(() => ({}));
    if (!fr.ok || !fd.ok) throw new Error(fd.msg || "OTA commit failed");
    if (fd.restartScheduled === false) {
      otaBusy = false;
      $("#ota-status").className = "ota-status err";
      $("#ota-status").textContent = "Firmware verified, but automatic restart failed. Restart the device manually.";
      $("#ota-prog-msg").textContent = "Restart manually to use the update.";
      return;
    }

    $("#ota-bar-fill").style.width = "100%";
    $("#ota-prog-pct").textContent = "100%";
    $("#ota-status").className = "ota-status ok";
    $("#ota-status").textContent = "OTA Flash Complete! Rebooting device...";
    otaBusy = false;
    $("#ota-cancel-btn").classList.add("hidden");
    for (let s = 1; s <= 20; s++) {
      $("#ota-prog-msg").textContent = `Waiting for reboot (${Math.floor(s * 1.5)}s)...`;
      await new Promise((r) => setTimeout(r, 1500));
      try {
        const ping = await fetch(base + "/systeminfo", { cache: "no-store" });
        if (ping.ok) {
          $("#ota-prog-msg").textContent = "Device back online! Reloading...";
          setTimeout(() => location.reload(), 600);
          return;
        }
      } catch (_) {}
    }
    location.reload();
  } catch (err) {
    otaBusy = false;
    $("#ota-cancel-btn").classList.add("hidden");
    if (session && !otaCommitting) await fetch(base + "/ota/abort", { method: "POST", headers: { "X-OTA-Session": session } }).catch(() => {});
    $("#ota-status").className = "ota-status err";
    $("#ota-status").textContent = otaCommitting
      ? "Commit reply lost or failed. Check the device and do not power it off; the update may have completed."
      : (err.message || "OTA upload failed.");
    $("#ota-start-btn").disabled = false;
  }
});

$("#wifi-pwd-input").addEventListener("keyup", (e) => {
  if (e.key === "Enter" || e.keyCode === 13) {
    e.preventDefault();
    $("#wifi-connect-btn").click();
  }
});
$("#wifi-rescan-btn").addEventListener("click", () => scanWifiNets());
$("#wifi-connect-btn").addEventListener("click", async () => {
  const ssid = $("#wifi-ssid-input").value.trim();
  const pwd = $("#wifi-pwd-input").value;
  const msg = $("#wifi-conn-msg");
  if (!ssid) return alert("Please select or enter a Wi-Fi SSID.");
  $("#wifi-connect-btn").disabled = true;
  try {
    const res = JSON.parse(await requestPost("/wificonnect", { ssid, pwd }));
    if (!res.ok) throw new Error(res.msg || "Connection failed");
    msg.className = "ota-status ok";
    const mdns = lastSysInfo.MDNS || "bruce";
    msg.textContent = `Switching to "${ssid}"... Connect your computer to "${ssid}" and visit http://${mdns}.local/ota (or check the 192.168.x.x IP on the Bruce display).`;
  } catch (err) {
    msg.className = "ota-status err";
    msg.textContent = err.message || "Failed to switch Wi-Fi";
  } finally {
    $("#wifi-connect-btn").disabled = false;
  }
});

window.ondragenter = (e) => {
  if ($(".dialog.ota:not(.hidden)") || activeTab !== "files") return;
  if (e.dataTransfer && Array.from(e.dataTransfer.types || []).includes("Files")) {
    $(".upload-area").classList.remove("hidden");
  }
};
$(".upload-area").ondragleave = () => $(".upload-area").classList.add("hidden");
$(".upload-area").ondragover = (e) => e.preventDefault();
$(".upload-area").ondrop = async (e) => {
  e.preventDefault();
  $(".upload-area").classList.add("hidden");
  const drive = currentDrive, path = currentPath;
  if (!drive || !path || _runningUpload) return;
  _uploadFailures = 0;
  $(".dialog.upload .dialog-body").innerHTML = "";
  try {
    const items = Array.from(e.dataTransfer.items || []);
    if (items.length && items.some(i => typeof i.webkitGetAsEntry === "function")) {
      for (const item of items) {
        const entry = item.webkitGetAsEntry && item.webkitGetAsEntry();
        if (entry) await appendDroppedFiles(entry, drive, path);
        else if (item.getAsFile && item.getAsFile()) appendFileToQueue([item.getAsFile()], drive, path);
      }
    } else appendFileToQueue(e.dataTransfer.files || [], drive, path);
  } catch (error) {
    _uploadFailures++;
    Dialog.show("upload");
    $(".upload-summary").textContent = "Could not read all dropped files: " + error.message;
  }
  if (_queueUpload.length) uploadFile();
  else if (_uploadFailures) $(".upload-close").disabled = false;
};

document.querySelectorAll(".inp-uploader").forEach((el) => {
  el.addEventListener("change", (e) => {
    let files = e.target.files;
    if (!files || files.length === 0) return;
    if (!currentDrive || !currentPath) { alert("Choose a folder before uploading."); return; }
    if (!_runningUpload) { _uploadFailures = 0; $(".dialog.upload .dialog-body").innerHTML = ""; }
    appendFileToQueue(files);
    if (!_runningUpload) uploadFile();
    e.target.value = "";
  });
});

$("#tab-files").addEventListener("click", async (e) => {
  const pick = e.target.closest(".act-pick-payload");
  if (pick && payloadPickerActive) {
    e.preventDefault();
    const path = pick.closest(".file-row")?.getAttribute("data-file");
    if (!path) return;
    const fs = document.getElementById("st-badusb-fs"), field = document.getElementById("st-badusb-path");
    fs.value = currentDrive; field.value = path;
    fs.dataset.touched = "1"; field.dataset.touched = "1";
    cancelPayloadPicker();
    const msg = document.getElementById("st-badusb-msg");
    msg.className = "ota-status"; msg.textContent = "Đã chọn file. Nhấn Set Payload để lưu; chưa chạy payload.";
    msg.classList.remove("hidden");
    return;
  }
  let browseAction = e.target.closest(".act-browse");
  if (browseAction) {
    e.preventDefault();
    let drive = browseAction.getAttribute("data-drive") || currentDrive || "LittleFS";
    if (drive === "SD" && lastSysInfo.HAS_SD === false) return;
    let path = browseAction.getAttribute("data-path") || browseAction.closest("tr")?.getAttribute("data-path") || "/";
    if (drive === currentDrive && path === currentPath) return;
    fetchFiles(drive, path);
    return;
  }

  let editFileAction = e.target.closest(".act-edit-file");
  if (editFileAction) {
    e.preventDefault();
    let file = editFileAction.closest("tr").getAttribute("data-file");
    if (file) openFileInEditor(currentDrive, file);
    return;
  }

  let oActionOInput = e.target.closest(".act-oinput");
  if (oActionOInput) {
    e.preventDefault();
    let action = oActionOInput.getAttribute("data-action");
    if (!action) return;
    let value = "", data = "";
    if (action.startsWith("rename")) {
      let row = oActionOInput.closest("tr");
      let filePath = row.getAttribute("data-file") || row.getAttribute("data-path");
      if (filePath) {
        value = filePath.substring(filePath.lastIndexOf("/") + 1);
        data = `${action}|${filePath}`;
      }
    } else if (action.startsWith("create")) {
      data = `${action}|${currentPath}`;
    } else data = action;
    Dialog.showOneInput(action, value, data);
    return;
  }

  let actDeleteFile = e.target.closest(".act-delete");
  if (actDeleteFile) {
    e.preventDefault();
    let row = actDeleteFile.closest(".file-row");
    let file = row.getAttribute("data-file") || row.getAttribute("data-path");
    if (!file || !confirm(`Delete ${file}?\nThis action cannot be undone.`)) return;
    Dialog.loading.show("Deleting...");
    try {
      await requestGet("/file", { fs: currentDrive, action: "delete", name: file });
      fetchSystemInfo(true).catch(() => {});
      fetchFiles(currentDrive, currentPath);
    } catch (error) { alert("Delete failed: " + error.message); }
    finally { Dialog.loading.hide(); }
    return;
  }

  let actPlay = e.target.closest(".act-play");
  if (actPlay) {
    e.preventDefault();
    let cmd = actPlay.getAttribute("data-cmd");
    if (cmd) { actPlay.blur(); await runCommand(cmd); }
  }
});

$(".dialog-background").addEventListener("click", (e) => {
  if (e.target.matches(".act-dialog-close")) {
    e.preventDefault();
    Dialog.hide();
  }
});

$(".act-save-oinput-file").addEventListener("click", async () => {
  let dialog = $(".dialog.oinput");
  let fileName = $("#oinput-input").value.trim();
  if (!fileName) return alert("Input cannot be empty.");
  let action = dialog.getAttribute("data-cache");
  if (!action) return;
  let refreshList = true;
  let [actionType, path] = action.split("|");
  try {
  if (actionType.startsWith("rename")) {
    Dialog.loading.show("Renaming...");
    await requestPost("/rename", { fs: currentDrive, filePath: path, fileName });
  } else if (actionType === "createFolder") {
    Dialog.loading.show("Creating Folder...");
    await requestGet("/file", { fs: currentDrive, action: "create", name: path.replace(/\/+$/, "") + "/" + fileName });
  } else if (actionType === "createFile") {
    Dialog.loading.show("Creating File...");
    await requestGet("/file", { fs: currentDrive, action: "createfile", name: path.replace(/\/+$/, "") + "/" + fileName });
  } else if (actionType === "serial") {
    await runCommand(fileName);
    refreshList = false;
  }
  if (refreshList) fetchFiles(currentDrive, currentPath);
  Dialog.hide();
  } catch (error) { alert("Action failed: " + error.message); }
  finally { Dialog.loading.hide(); }
});

$(".act-save-credential").addEventListener("click", async () => {
  let username = $("#cred-username").value.trim();
  let password = $("#cred-password").value.trim();
  if (!username || !password) return alert("Username and password cannot be empty.");
  Dialog.loading.show("Saving Credentials...");
  await requestGet("/wifi", { usr: username, pwd: password });
  Dialog.loading.hide();
  alert("Credentials saved successfully!");
});

$(".act-save-edit-file").addEventListener("click", () => saveEditorFile());
$(".act-run-edit-file").addEventListener("click", async function () {
  await saveEditorFile(true);
  this.blur();
});

let showNavigating = localStorage.getItem("showNavigating") === "true";
function updateShowHideNavigatingButton() {
  $(".act-hide-show-navigating").textContent = `'Navigating...' status: ${showNavigating ? "Shown" : "Hidden"}`;
}
updateShowHideNavigatingButton();
$(".act-hide-show-navigating").addEventListener("click", (e) => {
  e.preventDefault();
  showNavigating = !showNavigating;
  localStorage.setItem("showNavigating", showNavigating ? "true" : "false");
  updateShowHideNavigatingButton();
});

document.querySelectorAll(".act-reboot").forEach((btn) => {
  btn.addEventListener("click", async (e) => {
    e.preventDefault();
    if (!confirm("Reboot the device now?")) return;
    Dialog.loading.show("Rebooting...");
    try {
      await requestGet("/reboot");
      setTimeout(() => location.reload(), 2500);
    } catch (_) {
      Dialog.loading.hide();
      alert("Could not reboot. If OTA is running, wait or cancel it first.");
    }
  });
});

document.querySelectorAll(".act-bootloader").forEach((btn) => {
  btn.addEventListener("click", async (e) => {
    e.preventDefault();
    if (!confirm("Reboot into USB ROM Download Bootloader?\n(Device Wi-Fi/WebUI will stop until reflashed or reset)")) return;
    Dialog.loading.show("Entering USB ROM Bootloader...");
    try { await requestPost("/bootloader", {}); }
    catch (_) { Dialog.loading.hide(); alert("Could not enter bootloader. If OTA is running, wait or cancel it first."); }
  });
});

$(".navigator-canvas").addEventListener("click", async (e) => {
  let nav = e.target.closest(".nav");
  if (!nav) return;
  let direction = nav.getAttribute("data-direction");
  if (direction === "Menu") direction = "Esc"; // DSolution Select hold is Back
  await runNavigation(direction.toLowerCase());
});

window.addEventListener("keydown", async (e) => {
  let key = e.key.toLowerCase();
  if ($(".dialog.editor:not(.hidden)")) {
    if ((e.ctrlKey || e.metaKey) && key === "s") {
      e.preventDefault(); e.stopImmediatePropagation();
      await saveEditorFile();
      return;
    } else if (e.altKey && key === "enter") {
      e.preventDefault(); e.stopImmediatePropagation();
      await saveEditorFile(true);
      return;
    }
  }
  if (activeTab === "screen" && $(".dialog-background.hidden")) {
    const tag = (e.target && e.target.tagName) ? e.target.tagName.toLowerCase() : "";
    if (!["input", "textarea", "select", "button", "a"].includes(tag) && !e.target?.isContentEditable) {
      const map_navigator = {
        arrowup: "Up", arrowdown: "Down", arrowleft: "Prev", arrowright: "Next",
        enter: "Sel", backspace: "Esc", m: "Menu", pageup: "NextPage", pagedown: "PrevPage",
      };
      if (key === "r") { e.preventDefault(); e.stopImmediatePropagation(); reloadScreen(); return; }
      if (key in map_navigator) {
        e.preventDefault(); e.stopImmediatePropagation();
        $(`.navigator-canvas .nav[data-direction="${map_navigator[key]}"]`)?.click();
        return;
      }
    }
  }
  if (key === "escape" && $(".dialog-background:not(.hidden)")) {
    if (otaBusy) return;
    $(".dialog:not(.hidden) .act-escape")?.click();
  }
});

$(".file-content").addEventListener("keydown", function (e) {
  if (!$(".dialog.editor:not(.hidden)")) return;
  const textarea = this;
  const start = textarea.selectionStart;
  const end = textarea.selectionEnd;
  const tabSpaces = "  ";
  const insertText = (text, newStart, newEnd) => {
    textarea.setSelectionRange(start, end);
    document.execCommand("insertText", false, text);
    textarea.setSelectionRange(newStart, newEnd);
  };
  if (e.key === "Tab") {
    e.preventDefault();
    if (start === end && !e.shiftKey) insertText(tabSpaces, start + 2, start + 2);
    return;
  }
  if (e.key === "Enter") {
    e.preventDefault();
    const lineStart = textarea.value.lastIndexOf("\n", start - 1) + 1;
    const indent = (textarea.value.slice(lineStart, start).match(/^ */) || [""])[0];
    insertText("\n" + indent, start + 1 + indent.length, start + 1 + indent.length);
    return;
  }
  const pairs = { "(": ")", "{": "}", "[": "]", '"': '"', "'": "'" };
  if (e.key in pairs) {
    e.preventDefault();
    const sel = textarea.value.slice(start, end);
    insertText(e.key + sel + pairs[e.key], start + 1, start + 1 + sel.length);
  }
});

$(".file-content").addEventListener("keyup", (e) => {
  if ($(".dialog.editor:not(.hidden)")) {
    $(".act-save-edit-file").disabled = !isModified(e.target);
    updateLineNumbers();
  }
});
$(".file-content").addEventListener("scroll", () => { if ($(".dialog.editor:not(.hidden)")) syncScrolling(); });
$(".file-content").addEventListener("input", (e) => { if ($(".dialog.editor:not(.hidden)")) { updateLineNumbers(); $(".act-save-edit-file").disabled = editorSaving || !isModified(e.target); } });

$(".oinput-text-submit").addEventListener("keyup", function (e) {
  if (e.key === "Enter" || e.keyCode === 13) {
    e.preventDefault();
    this.closest(".dialog").querySelector(".btn-default")?.click();
  }
});

(async function () {
  try { await fetchSystemInfo(); } catch (_) { /* Folder view remains available for retry. */ }
  const urlParams = getURLParams();
  let initialDrive = urlParams.drive || (sdCardAvailable ? "SD" : "LittleFS");
  let initialPath = urlParams.path || "/";
  await fetchFiles(initialDrive, initialPath);

  if (urlParams.editFile) {
    switchTab("files");
    setTimeout(() => openFileInEditor(currentDrive, urlParams.editFile), 100);
  }

  setInterval(() => {
    if ($(".dialog-background.hidden") && !_runningUpload && !otaBusy) {
      fetchSystemInfo(true).catch(() => {});
    }
  }, 15000);
})();

// ============ SECLAB DASHBOARD ============
let secLabTimer = null;
let secLabBusy = false;
let secLabStatusOk = true;
let secLabPlusState = {};
let secLabNaptState = {};
let secLabNaptBusy = false;
let secLabLastNaptActionAt = 0;
let secLabStatusErrShown = false;
let secLabLastActionAt = 0;
const secLabMsgTimers = new WeakMap();

function startSecLabPoll() {
  stopSecLabPoll();
  secLabTimer = setInterval(() => {
    if (activeTab === "seclab" && $(".dialog-background.hidden") && !otaBusy) {
      refreshSecLab().catch(() => {});
    }
  }, 2600);
}
function stopSecLabPoll() {
  if (secLabTimer) { clearInterval(secLabTimer); secLabTimer = null; }
}
let monTimer = null;
let monLastSys = null;
let monLastSecLab = null;
let monFilter = "all";
function startMonitorPoll(){
  stopMonitorPoll();
  monTimer = setInterval(()=>{
    const auto = document.getElementById("mon-auto");
    if(activeTab==="monitor" && (!auto || auto.checked) && !document.hidden && !otaBusy){
      refreshMonitor().catch(()=>{});
    }
  }, 3000);
}
function stopMonitorPoll(){ if(monTimer){ clearInterval(monTimer); monTimer=null; } }

let studioTimer = null;
let studioLastSys = null;
let studioLastSecLab = null;
let studioLastQr = null;
let studioLastBadusb = null;
let studioRefreshGeneration = 0;

// BadUSB Auto-Run — WebUI controls
const badUsbEditableFields = ["st-badusb-fs", "st-badusb-path", "st-badusb-delayMs", "st-badusb-trigger-sel", "st-badusb-confirm-toggle", "st-badusb-confirmMs", "st-badusb-once-toggle", "st-badusb-enabled-toggle"];
badUsbEditableFields.forEach(id => {
  const field = document.getElementById(id);
  ["input", "change"].forEach(event => field?.addEventListener(event, () => { field.dataset.touched = "1"; }));
});
function badUsbFieldsSaved(...ids) {
  ids.forEach(id => { const field = document.getElementById(id); if (field) delete field.dataset.touched; });
}
document.getElementById("st-badusb-set-payload")?.addEventListener("click", async ()=>{
  const fs=document.getElementById("st-badusb-fs")?.value.trim()||"LittleFS";
  const path=document.getElementById("st-badusb-path")?.value.trim();
  const msgBox=document.getElementById("st-badusb-msg");
  if(!path){ if(msgBox){ msgBox.className="ota-status err"; msgBox.textContent="Enter payload path"; msgBox.classList.remove("hidden"); } return; }
  try{ const raw=await requestPost("/badusb/autorun",{action:"setpayload", payloadFs:fs, payloadPath:path}); const d=JSON.parse(raw); if(msgBox){ msgBox.className="ota-status "+(d.ok?"ok":"err"); msgBox.textContent=d.msg||""; msgBox.classList.remove("hidden"); } if (d.ok) badUsbFieldsSaved("st-badusb-fs", "st-badusb-path"); refreshStudio(); } catch(e){ if(msgBox){ msgBox.className="ota-status err"; msgBox.textContent=e.message; msgBox.classList.remove("hidden"); } }
});
document.getElementById("st-badusb-enabled-toggle")?.addEventListener("change", async (e)=>{
  const field=e.target, msg=document.getElementById("st-badusb-msg");
  field.disabled=true;
  try {
    const d=JSON.parse(await requestPost("/badusb/autorun",{action:"enable",enabled:field.checked?"1":"0"}));
    if (!d.ok) throw new Error(d.msg || "Không thể đổi trạng thái");
    msg.className="ota-status ok"; msg.textContent=d.msg || "Đã lưu trạng thái.";
  } catch(err) {
    msg.className="ota-status err"; msg.textContent=(err.message || "Không thể đổi trạng thái") + ". Kiểm tra trạng thái thiết bị sau khi kết nối lại.";
  } finally {
    msg.classList.remove("hidden");
    badUsbFieldsSaved("st-badusb-enabled-toggle");
    field.disabled=false;
    await refreshStudio();
  }
});
document.getElementById("st-badusb-test")?.addEventListener("click", async ()=>{
  const msgBox=document.getElementById("st-badusb-msg");
  try{ const raw=await requestPost("/badusb/autorun",{action:"testrun"}); const d=JSON.parse(raw); if(msgBox){ msgBox.className="ota-status "+(d.ok?"ok":"err"); msgBox.textContent=d.msg||""; msgBox.classList.remove("hidden"); } } catch(e){ if(msgBox){ msgBox.className="ota-status err"; msgBox.textContent=e.message; msgBox.classList.remove("hidden"); } }
});
document.getElementById("st-badusb-clear")?.addEventListener("click", async ()=>{
  const msgBox=document.getElementById("st-badusb-msg");
  try{ const raw=await requestPost("/badusb/autorun",{action:"clearpayload"}); const d=JSON.parse(raw); if(msgBox){ msgBox.className="ota-status "+(d.ok?"ok":"err"); msgBox.textContent=d.msg||""; msgBox.classList.remove("hidden"); } const pathEl=document.getElementById("st-badusb-path"); if(pathEl && d.ok) pathEl.value=""; if (d.ok) badUsbFieldsSaved("st-badusb-path", "st-badusb-fs"); refreshStudio(); } catch(e){ if(msgBox){ msgBox.className="ota-status err"; msgBox.textContent=e.message; msgBox.classList.remove("hidden"); } }
});
document.getElementById("st-badusb-save-settings")?.addEventListener("click", async (event) => {
  const button = event.currentTarget, msg = document.getElementById("st-badusb-msg");
  const el = id => document.getElementById("st-badusb-" + id);
  const value = id => el(id).value.trim();
  const groups = [
    {name:"Delay", ids:["delayMs"], data:{action:"setdelay", delayMs:value("delayMs")}},
    {name:"Trigger", ids:["trigger-sel"], data:{action:"settrigger", trigger:value("trigger-sel")}},
    {name:"Confirm", ids:["confirm-toggle","confirmMs"], data:{action:"setconfirm", confirmWindow:el("confirm-toggle").checked?"1":"0", confirmMs:value("confirmMs")}},
    {name:"Run once", ids:["once-toggle"], data:{action:"setrunonce", runOncePerPlug:el("once-toggle").checked?"1":"0"}}
  ].filter(g => g.ids.some(id => el(id).dataset.touched));
  const fail = text => { msg.className="ota-status err"; msg.textContent=text; msg.classList.remove("hidden"); };
  if (!groups.length) { fail("Không có thay đổi cần lưu."); return; }
  for (const g of groups) {
    const d=g.data;
    if ((d.action==="setdelay" && (!/^\d+$/.test(d.delayMs) || +d.delayMs>10000)) ||
        (d.action==="setconfirm" && (!/^\d+$/.test(d.confirmMs) || +d.confirmMs<1000 || +d.confirmMs>10000)) ||
        (d.action==="settrigger" && !["0","2"].includes(d.trigger))) {
      fail("Giá trị không hợp lệ: " + g.name + ". Chưa lưu mục nào."); return;
    }
  }
  groups.forEach(g => { g.snapshot=g.ids.map(id => el(id).type === "checkbox" ? el(id).checked : el(id).value); });
  button.disabled=true;
  const saved=[], failed=[];
  for (const g of groups) {
    try {
      const d=JSON.parse(await requestPost("/badusb/autorun",g.data));
      if (!d.ok) throw new Error(d.msg || "rejected");
      saved.push(g.name);
      g.ids.forEach((id,i) => { const f=el(id); if ((f.type === "checkbox" ? f.checked : f.value) === g.snapshot[i]) delete f.dataset.touched; });
    } catch(e) { failed.push(g.name + ": " + (e.message || "lỗi")); }
  }
  button.disabled=false;
  msg.className="ota-status " + (failed.length ? "err" : "ok");
  msg.textContent=(saved.length ? "Đã lưu: " + saved.join(", ") + ". " : "") + (failed.length ? "Chưa xác nhận: " + failed.join("; ") + ". Kiểm tra trạng thái trước khi thử lại." : "");
  msg.classList.remove("hidden");
  refreshStudio();
});


document.getElementById("pt-refresh")?.addEventListener("click", portalRefresh);
document.getElementById("pt-save")?.addEventListener("click", portalSave);
document.getElementById("pt-cancel")?.addEventListener("click", ()=> portalSetForm("", "", ""));
document.getElementById("pt-preset")?.addEventListener("change", (e)=>{ const v=e.target.value; const nameEl=document.getElementById("pt-name"), apEl=document.getElementById("pt-ap"), cEl=document.getElementById("pt-content"), cust=document.getElementById("pt-rickroll-custom"); if(cust) cust.classList.toggle("hidden", v!=="rickroll-custom"); if(v==="google"){ if(nameEl) nameEl.value="google.html"; if(apEl) apEl.value="Free Wifi"; if(cEl) cEl.value=`<!-- AP="Free Wifi" -->\n<!DOCTYPE html><html><head><title>Sign in: Google Accounts</title><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{font-family:Arial,sans-serif;background:#fff;margin:0;padding:20px}.container{max-width:420px;margin:40px auto;border:1px solid #CEC0DE;border-radius:8px;padding:20px;box-shadow:0 2px 10px rgba(0,0,0,.1)}h2{text-align:center;color:#202124}input{width:100%;padding:12px;margin:8px 0;border:1px solid #ccc;border-radius:6px}button{width:100%;padding:12px;background:#0b57d0;color:#fff;border:none;border-radius:6px}</style></head><body><div class="container"><h2>Sign in</h2><p>Use your Google Account</p><form action="/post"><input name="email" placeholder="Email or phone" required><input name="password" type="password" placeholder="Password" required><button type="submit">Next</button></form></div></body></html>`; } else if(v==="rickroll"){ if(nameEl) nameEl.value="rickroll.html"; if(apEl) apEl.value="Free Wifi"; if(cEl) cEl.value=`<!-- AP="Free Wifi" -->\n<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Free Wifi</title><style>body{margin:0;background:#000;color:#fff;text-align:center;font-family:sans-serif}video{width:100%;max-height:60vh} .card{max-width:560px;margin:20px auto;background:#111;padding:16px;border-radius:12px}input{width:100%;padding:12px;margin:8px 0;border-radius:8px;border:none}button{width:100%;padding:12px;background:#ff0000;color:#fff;border:none;border-radius:8px}</style></head><body><video autoplay muted loop playsinline controls src="https://www.w3schools.com/html/mov_bbb.mp4"></video><div class="card"><h2>🎵 Never Gonna Give You Up!</h2><p>Free Wifi Connected! Enter password to continue</p><form action="/post"><input name="password" type="password" placeholder="WiFi password" required><button type="submit">Connect</button></form></div></body></html>`; } else if(v==="rickroll-custom"){ if(nameEl) nameEl.value="rickroll-custom.html"; if(apEl) apEl.value="Free Wifi"; if(document.getElementById("pt-rr-title")) document.getElementById("pt-rr-title").value="Free Wifi Connected! 🎉"; if(document.getElementById("pt-rr-msg")) document.getElementById("pt-rr-msg").value="Enter WiFi password to stay connected"; if(document.getElementById("pt-rr-video")) document.getElementById("pt-rr-video").value="https://www.w3schools.com/html/mov_bbb.mp4"; if(document.getElementById("pt-rr-btn")) document.getElementById("pt-rr-btn").value="Connect"; } else if(v==="fake-update"){ if(nameEl) nameEl.value="fake-update.html"; if(apEl) apEl.value="Router Update"; if(cEl) cEl.value=`<!-- AP="Router Update" -->\n<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Router Update</title><style>body{font-family:sans-serif;background:#d3d3d3;display:flex;justify-content:center;align-items:center;height:100vh;margin:0}.box{background:#fff;padding:24px;border-radius:12px;max-width:360px;width:90%;text-align:center}input{width:100%;padding:12px;margin:8px 0;border:1px solid #ccc;border-radius:6px}button{width:100%;padding:12px;background:#007bff;color:#fff;border:none;border-radius:6px}</style></head><body><div class="box"><h2>Router Update Required</h2><p>Enter WiFi password to update</p><form action="/post"><input name="password" type="password" placeholder="Password" required><button type="submit">Update</button></form></div></body></html>`; } else if(v==="wifi-login"){ if(nameEl) nameEl.value="wifi-login.html"; if(apEl) apEl.value="Free Wifi"; if(cEl) cEl.value=`<!-- AP="Free Wifi" -->\n<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{font-family:sans-serif;max-width:420px;margin:40px auto;padding:20px}h2{text-align:center}input{width:100%;padding:10px;margin:8px 0;border:1px solid #ccc;border-radius:6px}button{width:100%;padding:12px;background:#0b57d0;color:#fff;border:none;border-radius:6px}</style></head><body><h2>Free Wifi — Login</h2><p>Enter password to continue</p><form action="/post"><input name="email" placeholder="Email"><input name="password" type="password" placeholder="Password" required><button type="submit">Connect</button></form></body></html>`; } else if(v==="custom"){ if(nameEl) nameEl.value=""; if(cEl) cEl.value=""; } });
document.getElementById("pt-rr-generate")?.addEventListener("click", ()=>{ const title=document.getElementById("pt-rr-title")?.value||"Free Wifi Connected!"; const msg=document.getElementById("pt-rr-msg")?.value||"Enter WiFi password"; const video=document.getElementById("pt-rr-video")?.value||"https://www.w3schools.com/html/mov_bbb.mp4"; const btn=document.getElementById("pt-rr-btn")?.value||"Connect"; const ap=document.getElementById("pt-ap")?.value||"Free Wifi"; const isYouTube=video.includes("youtube.com")||video.includes("youtu.be"); let media=isYouTube?`<iframe width="100%" height="315" src="${video.replace("watch?v=","embed/")}" frameborder="0" allow="autoplay; encrypted-media" allowfullscreen></iframe>`:`<video autoplay muted loop playsinline controls src="${video}" style="width:100%;max-height:60vh;background:#000"></video>`; const html=`<!-- AP="${ap}" -->\n<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><style>body{margin:0;background:#000;color:#fff;text-align:center;font-family:sans-serif} .card{max-width:560px;margin:20px auto;background:#111;padding:16px;border-radius:12px}input{width:100%;padding:12px;margin:8px 0;border-radius:8px;border:none}button{width:100%;padding:12px;background:#ff0000;color:#fff;border:none;border-radius:8px}</style></head><body>${media}<div class="card"><h2>${title}</h2><p>${msg}</p><form action="/post"><input name="password" type="password" placeholder="WiFi password" required><button type="submit">${btn}</button></form></div></body></html>`; const cEl=document.getElementById("pt-content"); if(cEl) cEl.value=html; });
document.getElementById("pt-new")?.addEventListener("click", ()=>{
  const base=`<html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{font-family:sans-serif;max-width:420px;margin:40px auto;padding:20px}input{width:100%;padding:10px;margin:8px 0;border:1px solid #ccc;border-radius:6px}button{width:100%;padding:12px;background:#0b57d0;color:#fff;border:none;border-radius:6px}h2{text-align:center}</style></head><body><h2>Free Wifi — Đăng nhập</h2><p>Vui lòng nhập mật khẩu WiFi để tiếp tục</p><form action="/post"><input name="email" placeholder="Email" required><input name="password" type="password" placeholder="Mật khẩu" required><button type="submit">Kết nối</button></form></body></html>`;
  portalSetForm("my-portal.html","<!-- AP=\"Free Wifi\" -->\n"+base,"Free Wifi");
});
document.getElementById("pt-clearactive")?.addEventListener("click", async ()=>{
  const msg=document.getElementById("pt-msg");
  try{ const raw=await requestPost("/portal/templates",{action:"clearactive"}); const j=JSON.parse(raw); if(msg){ msg.className="ota-status "+(j.ok?"ok":"err"); msg.textContent=j.msg; msg.classList.remove("hidden"); } portalRefresh(); }catch(e){ if(msg){ msg.className="ota-status err"; msg.textContent=e.message; msg.classList.remove("hidden"); } }
});
document.getElementById("pt-preview")?.addEventListener("click", ()=>{
  const c=document.getElementById("pt-content")?.value||"";
  if(!c.trim()) return;
  const w=window.open(); w.document.write(c); w.document.close();
});
document.getElementById("pt-import")?.addEventListener("click", async ()=>{
  const txt=prompt("Dán toàn bộ HTML mẫu vào đây (Ctrl+V), sẽ tạo file mới:");
  if(!txt) return;
  const name=prompt("Đặt tên file (vd facebook.html):","imported.html");
  if(!name) return;
  const msg=document.getElementById("pt-msg");
  try{ const raw=await requestPost("/portal/templates",{action:"save", name, content:txt}); const j=JSON.parse(raw); if(msg){ msg.className="ota-status "+(j.ok?"ok":"err"); msg.textContent=j.msg; msg.classList.remove("hidden"); } portalRefresh(); }catch(e){ if(msg){ msg.className="ota-status err"; msg.textContent=e.message; msg.classList.remove("hidden"); } }
});
document.getElementById("pt-file")?.addEventListener("change", async (e)=>{
  const f=e.target.files[0]; if(!f) return;
  const txt=await f.text();
  portalSetForm(f.name, txt, "");
  const msg=document.getElementById("pt-msg");
  if(msg){ msg.className="ota-status ok"; msg.textContent="Đã nạp file "+f.name+" vào ô soạn — bấm Lưu mẫu để lưu lên thiết bị"; msg.classList.remove("hidden"); }
});
document.getElementById("pt-list")?.addEventListener("click", async (e)=>{
  const t=e.target;
  const use=t.closest("[data-pt-use]")?.getAttribute("data-pt-use");
  const edit=t.closest("[data-pt-edit]")?.getAttribute("data-pt-edit");
  const dup=t.closest("[data-pt-dup]")?.getAttribute("data-pt-dup");
  const del=t.closest("[data-pt-del]")?.getAttribute("data-pt-del");
  const msg=document.getElementById("pt-msg");
  if(use){
    try{ const raw=await requestPost("/portal/templates",{action:"active", path:use}); const j=JSON.parse(raw); if(msg){ msg.className="ota-status "+(j.ok?"ok":"err"); msg.textContent=j.msg; msg.classList.remove("hidden"); } portalRefresh(); }catch(err){ if(msg){ msg.className="ota-status err"; msg.textContent=err.message; msg.classList.remove("hidden"); } }
  } else if(edit){
    try{ const raw=await requestPost("/portal/templates",{action:"get", path:edit}); const j=JSON.parse(raw); if(j.ok){ let ap=j.content.match(/<!-- AP="([^"]+)" -->/); portalSetForm(edit.split("/").pop(), j.content.replace(/<!-- AP="[^"]+" -->\n?/,""), ap?ap[1]:""); if(msg){ msg.className="ota-status ok"; msg.textContent="Đã nạp để sửa: "+edit; msg.classList.remove("hidden"); } document.getElementById("pt-content")?.scrollIntoView({behavior:"smooth"}); } }catch(err){ if(msg){ msg.className="ota-status err"; msg.textContent=err.message; msg.classList.remove("hidden"); } }
  } else if(dup){
    const newName=prompt("Tên file nhân bản:", dup.split("/").pop().replace(".html","-copy.html"));
    if(!newName) return;
    try{ const raw=await requestPost("/portal/templates",{action:"get", path:dup}); const j=JSON.parse(raw); if(j.ok){ const raw2=await requestPost("/portal/templates",{action:"save", name:newName, content:j.content}); const k=JSON.parse(raw2); if(msg){ msg.className="ota-status "+(k.ok?"ok":"err"); msg.textContent=k.msg; msg.classList.remove("hidden"); } portalRefresh(); } }catch(err){ if(msg){ msg.className="ota-status err"; msg.textContent=err.message; msg.classList.remove("hidden"); } }
  } else if(del){
    if(!confirm("Xoá mẫu "+del+" ?")) return;
    try{ const raw=await requestPost("/portal/templates",{action:"delete", path:del}); const j=JSON.parse(raw); if(msg){ msg.className="ota-status "+(j.ok?"ok":"err"); msg.textContent=j.msg; msg.classList.remove("hidden"); } portalRefresh(); }catch(err){ if(msg){ msg.className="ota-status err"; msg.textContent=err.message; msg.classList.remove("hidden"); } }
  }
});
// auto refresh when opening WiFi slab
document.querySelectorAll('[data-slab="wifi"]').forEach(b=> b.addEventListener("click", ()=> setTimeout(portalRefresh, 300)));
if(document.getElementById("pt-list")) setTimeout(portalRefresh, 800);

function startStudioPoll(){
  stopStudioPoll();
  studioTimer = setInterval(()=>{
    const auto = document.getElementById("st-auto");
    if(activeTab==="studio" && (!auto || auto.checked) && !document.hidden && !otaBusy){
      refreshStudio().catch(()=>{});
    }
  }, 3000);
}
function stopStudioPoll(){ if(studioTimer){ clearInterval(studioTimer); studioTimer=null; } }
function switchStSlab(name){
  if (!document.getElementById("stslab-" + name)) name = "overview";
  document.querySelectorAll('[id^="stslab-"]').forEach(v=>v.classList.toggle("hidden", v.id!=="stslab-"+name));
  document.querySelectorAll("[data-stslab]").forEach(b=>{ const on=b.dataset.stslab===name; b.classList.toggle("active", on); b.setAttribute("aria-selected", on?"true":"false"); });
  try{ localStorage.setItem("studioSlab", name);}catch(e){}
}
document.querySelectorAll("[data-stslab]").forEach(b=> b.addEventListener("click", ()=> switchStSlab(b.dataset.stslab)));
document.querySelectorAll("[data-stslab-jump]").forEach(b=> b.addEventListener("click", ()=> switchStSlab(b.dataset.stslabJump)));
try{ const savedSt=localStorage.getItem("studioSlab"); if(savedSt) switchStSlab(savedSt); }catch(e){}
document.getElementById("st-refresh")?.addEventListener("click", ()=> refreshStudio());
document.getElementById("st-auto")?.addEventListener("change", (e)=>{ if(e.target.checked) refreshStudio(); });
["st-sync-time", "st-clock-sync"].forEach(id => {
  document.getElementById(id)?.addEventListener("click", async () => {
    const button = document.getElementById(id);
    const label = button.textContent;
    button.disabled = true;
    button.textContent = "Syncing...";
    try {
      await syncBrowserTime();
      button.textContent = "Synced ✔";
      refreshStudio();
    } catch (err) {
      button.textContent = "Sync failed";
    } finally {
      button.disabled = false;
      setTimeout(() => { button.textContent = label; }, 2000);
    }
  });
});
document.getElementById("st-qr-add")?.addEventListener("click", async ()=>{
  const nameEl=document.getElementById("st-qr-name"), contEl=document.getElementById("st-qr-content"), msg=document.getElementById("st-qr-msg");
  const name=(nameEl?.value||"").trim(), content=(contEl?.value||"").trim();
  if(!name || !content){ if(msg){ msg.className="ota-status err"; msg.textContent="Enter both name and content"; msg.classList.remove("hidden"); } return; }
  try{
    const raw=await requestPost("/studio/qrcodes", {action:"add", name, content});
    const d=JSON.parse(raw); if(d.ok){ if(msg){ msg.className="ota-status ok"; msg.textContent=d.msg||"Added"; msg.classList.remove("hidden"); } if(nameEl) nameEl.value=""; if(contEl) contEl.value=""; refreshStudio(); } else { if(msg){ msg.className="ota-status err"; msg.textContent=d.msg||"Add failed"; msg.classList.remove("hidden"); } }
  } catch(e){ if(msg){ msg.className="ota-status err"; msg.textContent=(e.message||"Add failed"); msg.classList.remove("hidden"); } }
});
document.getElementById("st-dual-xiaozhi")?.addEventListener("click", ()=> requestGet("/reboot?target=xiaozhi").then(()=>{}).catch(()=>{}));
document.getElementById("st-dual-menu")?.addEventListener("click", ()=> requestGet("/reboot?target=menu").then(()=>{}).catch(()=>{}));

// delegated actions for QR preview/delete
document.addEventListener("click", (e)=>{
  const t=e.target.closest("[data-st-qr-show]");
  if (!t) return;
  e.preventDefault();
  const name=t.dataset.stQrShow, content=t.dataset.stQrContent || "";
  const box=document.getElementById("st-qr-preview"), title=document.getElementById("st-qr-preview-title");
  const cont=document.getElementById("st-qr-preview-content"), qb=document.getElementById("st-qr-preview-box");
  if (title) title.textContent=name;
  if (cont) cont.textContent=content;
  if (qb) {
    qb.replaceChildren();
    try {
      qrcode.stringToBytes = qrcode.stringToBytesFuncs["UTF-8"];
      const qr=qrcode(0, "M"); qr.addData(content); qr.make();
      qb.innerHTML=qr.createImgTag(4, 16);
    } catch (_) { qb.textContent="QR preview unavailable: content is too long or invalid."; }
  }
  if (box) box.classList.remove("hidden");
});
document.addEventListener("click", (e)=>{
  const t=e.target.closest("[data-st-qr-del]");
  if(t){ e.preventDefault(); const name=t.dataset.stQrDel; if(!confirm("Delete QR '"+name+"'?")) return; requestPost("/studio/qrcodes", {action:"delete", name}).then(raw=>{ const d=JSON.parse(raw); const msg=document.getElementById("st-qr-msg"); if(msg){ msg.className="ota-status "+(d.ok?"ok":"err"); msg.textContent=d.msg||""; msg.classList.remove("hidden"); } refreshStudio(); }).catch(e=>{ const msg=document.getElementById("st-qr-msg"); if(msg){ msg.className="ota-status err"; msg.textContent=e.message||"Delete failed"; msg.classList.remove("hidden"); } }); }
});
document.addEventListener("click", (e)=>{
  const t=e.target.closest("[data-st-play-wav]");
  if(t){ e.preventDefault(); const path=t.dataset.stPlayWav; const pl=document.getElementById("st-sonar-player"); if(pl && path){ pl.src=(IS_DEV?"/bruce":"")+"/file?fs=LittleFS&action=download&name="+encodeURIComponent(path); pl.classList.remove("hidden"); pl.play().catch(()=>{}); } }
});


function switchMonSlab(name){
  if (!document.getElementById("monslab-" + name)) name = "overview";
  document.querySelectorAll('[id^="monslab-"]').forEach(v=>v.classList.toggle("hidden", v.id!=="monslab-"+name));
  document.querySelectorAll("[data-monslab]").forEach(b=>{ const on=b.dataset.monslab===name; b.classList.toggle("active", on); b.setAttribute("aria-selected", on?"true":"false"); });
  try{ localStorage.setItem("monitorSlab", name);}catch(e){}
}

async function refreshMonitor(){
  const msgBox=document.getElementById("mon-msg");
  const lastEl=document.getElementById("mon-last");
  const isPreview = window.location.hostname==="127.0.0.1" || window.location.hostname==="localhost" || window.location.port==="8002" || window.location.port==="8001";
  try{
    const sysP = requestGet("/systeminfo").then(j=>JSON.parse(j));
    const secP = requestGet("/seclab/status").then(j=>JSON.parse(j));
    const [sys, sec] = await Promise.all([sysP.catch(()=>null), secP.catch(()=>null)]);
    if(sys) monLastSys = sys;
    if(sec) monLastSecLab = sec;
    // Preview fallback: if no device backend, use mock data so tab is not empty
    if(!monLastSys && isPreview){
      monLastSys = {BRUCE_VERSION:"1.17-preview", BOARD:"DSolution 1.83 2-Mic", OWNER:"DSolution", MAC:"AA:BB:CC:DD:EE:FF", UPTIME_SEC: 3421, BAT: 76, BAT_MV: 3980, CHG:true, CPU_MHZ:240, HEAP_FREE:"68 KB", PSRAM_FREE:"2.1 MB", DMA_FREE:"41 KB", DMA_BLOCK:"32 KB", DUALBOOT:true, OTA_SLOT:"ota_1", OTA_NEXT:"ota_0", OTA_MAX:"4.0 MB", WIFI_MODE:"AP", WIFI_IP:"192.168.4.1", WIFI_SSID:"", WIFI_RSSI:0, AP_SSID:"BruceNet", MDNS:"bruce", SD:{free:"1.2 GB", used:"800 MB", total:"2.0 GB"}, LittleFS:{free:"1.4 MB", used:"600 KB", total:"2.0 MB"}, HAS_SD:true, WIDS_LOG:true, BLE_LOG:true, PRI_COLOR:"#00f0ff", SEC_COLOR:"#50aebd", BG_COLOR:"#070d12", MENU_STYLE:0, BRIGHT:80};
    }
    if(!monLastSecLab && isPreview){
      monLastSecLab = {napt:{running:true, starting:false, uptimeSec:128, staConnected:true, staSsid:"MyHomeWiFi", staIp:"192.168.1.23", apSsid:"BruceNet", apIp:"192.168.4.1", clients:[{ip:"192.168.4.2", mac:"11:22:33:44:55:66"}], total:24, blocked:3, trackers:5, autoBlock:true, blockList:["ads.example.com"], feed:[{dom:"ads.example.com", ip:"0.0.0.0", blk:true},{dom:"api.example.com", ip:"1.2.3.4", trk:true}]}, probe:{devices:[{id:1, os:"iPhone", rot:2, pnls:["MyHomeWiFi"], rssi:-52, watched:false}], totalMacs:3}, bleGatt:{mode:"SCAN", txPhy:"1M", connected:false, profiles:[{name:"HeartRate", addr:"AA:BB:CC:DD:EE:01", path:"/ble_gatt/hr.json", services:2, chars:5}]}, airtime:{bestCh:6, bestScore:78, channels:[{ch:1, load:22, retry:5, rssi:-45, sampled:true},{ch:6, load:12, retry:2, rssi:-52, sampled:true},{ch:11, load:65, retry:12, rssi:-60, sampled:true}], hidden:[{ssid:"HiddenNet", bssid:"AA:BB:CC:DD:EE:FF", ch:6, rssi:-58, decloaked:true}]}, sonar:{armed:true, alarm:false, carrierHz:18000, sens:"mid", peak:12, signal:"OK", events:[{dir:"left", pct:34, ts:12}]}, usb:{psramFree:2100000, flashImgBytes:65536, vaultFiles:[{name:"payload.txt", size:124}]}, plus:{available:true, osProfile:"windows", portalHandoff:true, httpAuto:true, httpRedact:true, bleSafeFuzzer:false, lanGuardAuto:true, permissionCheck:true, pairJustWorks:true, hidAutoArm:false, hidTimeoutSec:25, httpPort:3128, osWarn:true, pmkidAutoExport:false, csaChannel:1, csaBursts:3}, pmkid:{running:false, hashes:2}, csa:{running:false}, portal:{running:false, armed:true, napt:false, handoffDone:false}, lanAudit:{running:false, devices:3, findings:1, findingList:[{ip:"192.168.4.1", port:80, proto:"http", verdict:"open", risk:"HIGH"}]}, responderPlus:{running:false}, lanGuard:{running:true, alerts:[{kind:"ARP", ip:"192.168.4.5", detail:"new MAC"}], arpChanges:1, dhcpMismatch:0, arpWatch:true, dhcpSniff:true, dhcpComparison:"ok"}, httpInspector:{running:false, port:3128, findings:[{host:"example.com", kind:"GET", detail:"cleartext"}]}, ledLink:{running:false, bytes:0}, bleAudit:{findings:2, findingList:[{verdict:"WEAK", uuid:"0x1800", detail:"no auth"}]}, pairAudit:{verdict:"NOT_RUN"}, tagBeacon:{running:false}, chain:{running:[{id:"evil-twin-route", step:"Verify", status:"RUN"}]}};
    }
    if(!monLastSys && !monLastSecLab) throw new Error("no data");
    lastSysInfo = monLastSys || lastSysInfo;
    if(lastEl) lastEl.textContent = new Date().toLocaleTimeString() + (isPreview && !sys ? " · preview mock" : "");
    renderMonitorOverview(monLastSys, monLastSecLab);
    renderMonitorNetwork(monLastSys, monLastSecLab);
    renderMonitorSystem(monLastSys);
    renderMonitorAlerts(monLastSecLab);
    if(msgBox){
      if(isPreview && !sys){ msgBox.className="ota-status ok"; msgBox.textContent="Preview mode — no device backend, showing mock data. Connect device for live data."; msgBox.classList.remove("hidden"); }
      else msgBox.classList.add("hidden");
    }
  }catch(e){
    if(msgBox){ msgBox.className="ota-status err"; msgBox.textContent=e.message||"Monitor refresh failed"; msgBox.classList.remove("hidden"); }
    console.warn("refreshMonitor",e);
  }
}
function renderMonitorOverview(sys, sec){
  if(!sys && !sec) return;
  sys = sys||monLastSys||{}; sec = sec||monLastSecLab||{};
  const set=(id,txt)=>{ const el=document.getElementById(id); if(el) el.textContent=txt; };
  const badge=(id,txt,cls)=>{ const el=document.getElementById(id); if(!el) return; el.textContent=txt; el.className="sl-badge "+(cls||""); };
  // device
  set("mon-ov-device", `${sys.BOARD||"Bruce"} • ${sys.BRUCE_VERSION||"dev"}`);
  set("mon-ov-device-sub", `${sys.MAC||"--"} · Up ${formatUptime(sys.UPTIME_SEC)} · ${sys.MDNS||"bruce"}.local`);
  badge("mon-ov-device-badge", sys.WIFI_MODE==="STA" ? `LAN ${sys.WIFI_RSSI||0}dBm` : sys.WIFI_MODE||"--", sys.WIFI_MODE==="STA"?"on":"");
  // power
  const batTxt = sys.BAT!==undefined ? `${sys.BAT}%${sys.CHG?" CHG":""}` : "--";
  const mv = sys.BAT_MV? ` ${(sys.BAT_MV/1000).toFixed(2)}V`:"";
  set("mon-ov-power", batTxt+mv);
  set("mon-ov-power-sub", `CPU ${sys.CPU_MHZ||"--"} MHz · Heap ${sys.HEAP_FREE||"--"} · DMA ${sys.DMA_FREE||"--"}`);
  badge("mon-ov-power-badge", (sys.BAT!==undefined && sys.BAT<20)?"LOW":"OK", (sys.BAT!==undefined && sys.BAT<20)?"alert":"on");
  // mem
  set("mon-ov-mem", `${sys.HEAP_FREE||"--"} / ${sys.PSRAM_FREE||"--"}`);
  set("mon-ov-mem-sub", `Heap free / PSRAM free · DMA ${sys.DMA_FREE||"--"} (max ${sys.DMA_BLOCK||"--"})`);
  // network
  const n = sec?.napt||{};
  const netTxt = sys.WIFI_MODE==="STA" ? `LAN ${sys.WIFI_SSID||""} (${sys.WIFI_IP||"-"})` : sys.WIFI_MODE==="AP" ? `AP ${sys.AP_SSID||"BruceNet"} (${sys.WIFI_IP||"192.168.4.1"})` : "--";
  set("mon-ov-net", netTxt);
  set("mon-ov-net-sub", n.running ? `NAPT ON · ${ (n.clients||[]).length } clients · ${n.total||0} queries` : n.starting? "NAPT STARTING...":"NAPT OFF • STA "+(sys.WIFI_SSID||"--"));
  badge("mon-ov-net-badge", sys.WIFI_MODE||"--", sys.WIFI_MODE==="STA"?"on":"");
  // napt
  set("mon-ov-napt", n.running ? `ON (${ (n.clients||[]).length }c/${n.total||0}q)` : n.starting?"STARTING":"OFF");
  set("mon-ov-napt-sub", `Clients ${(n.clients||[]).length} · Queries ${n.total||0} · Blocked ${n.blocked||0} · Trackers ${n.trackers||0}`);
  const monNaptBtn = document.getElementById("mon-napt-toggle");
  if (monNaptBtn) {
    const active = !!(n.running || n.starting);
    monNaptBtn.textContent = active ? "Stop NAPT" : "Start NAPT";
    monNaptBtn.classList.toggle("btn-danger", active);
    monNaptBtn.classList.toggle("btn-default", !active);
  }
  // alerts
  const lg = sec?.lanGuard||{}, rp=sec?.responderPlus||{}, hi=sec?.httpInspector||{}, sn=sec?.sonar||{};
  const alertCount = (lg.alerts? lg.alerts.length:0) + (hi.findings? hi.findings.length:0) + (sn.events? sn.events.length:0) + (rp.running?1:0);
  set("mon-ov-alerts", `${alertCount} alerts`);
  set("mon-ov-alerts-sub", `WIDS:${sys.WIDS_LOG?1:0} LAN-Guard:${lg.alerts?lg.alerts.length:0} HTTP:${hi.findings?hi.findings.length:0} Sonar:${sn.events?sn.events.length:0}`);
  badge("mon-ov-alerts-badge", alertCount? `${alertCount} NEW`:"IDLE", alertCount?"alert":"");
  // chains
  const chain = sec?.chain||{};
  const chainBox=document.getElementById("mon-ov-chains");
  if(chainBox){
    const running = chain.running||[];
    const list = (Array.isArray(running)? running:[]).map(c=>`<div class="sl-item"><span>${slEsc(c.id||c.chain||"chain")} <small class="muted-sm">${slEsc(c.step||c.phase||"")}</small></span><span class="sl-tag ok">${slEsc(c.status||"RUN")}</span></div>`).join("");
    chainBox.innerHTML = list || `<div class="sl-item muted-sm">No chain running — launch from SecLab or device WiFi→Chains</div>`;
    const badgeC=document.getElementById("mon-ov-chain-badge");
    if(badgeC){ const cnt=running.length; badgeC.textContent=cnt? `${cnt} RUN`:"IDLE"; badgeC.className="sl-badge "+(cnt?"on":""); }
  }
  // quick wifi list teaser (reuse network scan cache)
  // keep wifi badge
}
function renderMonitorNetwork(sys, sec){
  if(!sys && !sec) return;
  sys = sys||monLastSys||{}; sec = sec||monLastSecLab||{};
  const set=(id,txt)=>{ const el=document.getElementById(id); if(el) el.textContent=txt; };
  const badge=(id,txt,cls)=>{ const el=document.getElementById(id); if(!el) return; el.textContent=txt; el.className="sl-badge "+(cls||""); };
  set("mon-net-mode", `${sys.WIFI_MODE||"--"} / ${sys.WIFI_IP||"--"}`);
  set("mon-net-ssid", `${sys.WIFI_SSID||"--"} ${sys.WIFI_RSSI? `(${sys.WIFI_RSSI}dBm)`:""}`);
  set("mon-net-ap", `${sys.AP_SSID||"BruceNet"} (${sys.WIFI_IP||"--"})`);
  set("mon-net-mdns", `${sys.MDNS||"bruce"}.local`);
  badge("mon-wifi-mode", sys.WIFI_MODE||"--", sys.WIFI_MODE==="STA"?"on":"");
  const n=sec?.napt||{};
  badge("mon-napt-badge", n.running? `ON (${n.uptimeSec||0}s)` : n.starting? "STARTING":"OFF", n.running?"on": (n.starting?"alert":""));
  set("mon-napt-up", n.staConnected? `${n.staSsid} (${n.staIp})` : "Not connected");
  set("mon-napt-ap", `${n.apSsid||"BruceNet"} (${n.apIp||"192.168.4.1"})`);
  set("mon-napt-stat", `${(n.clients||[]).length} / ${n.total||0}`);
  set("mon-napt-blk", `${n.blocked||0} / ${n.trackers||0}`);
  const dnsBox=document.getElementById("mon-napt-dns");
  if(dnsBox){ const feed=n.feed||[]; dnsBox.innerHTML = feed.slice(-12).reverse().map(f=>{ const cls=f.blk?"blk":(f.trk?"alert":"ok"); return `<div class="sl-item"><span>${slEsc(f.dom)} <small class="muted-sm">${slEsc(f.ip||"")}</small></span><span class="sl-tag ${cls}">${f.blk?"BLK":(f.trk?"TRK":"OK")}</span></div>`; }).join("") || `<div class="sl-item muted-sm">No DNS yet</div>`; }
  const cliBox=document.getElementById("mon-napt-clients");
  if(cliBox){ cliBox.innerHTML = (n.clients||[]).map(c=>`<div class="sl-item"><span>${slEsc(c.ip)}</span><small class="muted-sm">${slEsc(c.mac||"")}</small></div>`).join("")||`<div class="sl-item muted-sm">No clients</div>`; }
  // air + probe
  const air=sec?.airtime||{};
  const probe=sec?.probe||{};
  const airBadge=document.getElementById("mon-air-badge");
  if(airBadge){ const ch=air.bestCh; airBadge.textContent = ch? `EST. BEST CH ${ch}` : "NO SCAN YET"; }
  const bars=document.getElementById("mon-air-bars");
  if(bars && typeof renderAirChannelBars==="function"){ bars.innerHTML = renderAirChannelBars(air); }
  const hid=document.getElementById("mon-air-hidden");
  if(hid){ hid.innerHTML=(air.hidden||[]).map(h=>`<div class="sl-item"><span>${slEsc(h.decloaked?h.ssid:"<Hidden>")} <small class="muted-sm">${slEsc(h.bssid)}</small></span><span class="sl-tag ${h.decloaked?"ok":""}">C${h.ch} ${h.rssi}dB</span></div>`).join("")||`<div class="sl-item muted-sm">No hidden SSIDs</div>`; }
  const prb=document.getElementById("mon-probe-list");
  if(prb){ prb.innerHTML=(probe.devices||[]).slice(0,10).map(p=>`<div class="sl-item"><span>#${p.id} ${slEsc(p.os)} (${p.rot} MACs) <small class="muted-sm">${slEsc((p.pnls||[]).join(", "))}</small></span><span class="sl-tag ${p.watched?"blk":""}">${p.rssi}dB</span></div>`).join("")||`<div class="sl-item muted-sm">No probe data</div>`; }
}
function renderMonitorSystem(sys){
  if(!sys) sys=monLastSys||{}; if(!sys || !Object.keys(sys).length) return;
  const set=(id,txt)=>{ const el=document.getElementById(id); if(el) el.textContent=txt; };
  set("mon-sys-uptime", `Up ${formatUptime(sys.UPTIME_SEC)}`);
  set("mon-sys-bat", `${sys.BAT!==undefined? sys.BAT+"%":"--"} ${sys.BAT_MV? `(${(sys.BAT_MV/1000).toFixed(2)}V)`:""} ${sys.CHG?"CHG":""}`);
  set("mon-sys-cpu", `${sys.CPU_MHZ||"--"} MHz · ${sys.BOARD||"--"}`);
  set("mon-sys-ota", `${sys.OTA_SLOT||"--"} → ${sys.OTA_NEXT||"--"} (max ${sys.OTA_MAX||"--"})`);
  set("mon-sys-heap", sys.HEAP_FREE||"--");
  set("mon-sys-psram", sys.PSRAM_FREE||"--");
  set("mon-sys-dma", `${sys.DMA_FREE||"--"} / ${sys.DMA_BLOCK||"--"}`);
  set("mon-sys-build", `${sys.BRUCE_VERSION||"dev"} / style ${sys.MENU_STYLE||0}`);
  // storage meters
  const fsTotal=parseHumanBytes(sys.LittleFS?.total), fsUsed=parseHumanBytes(sys.LittleFS?.used);
  const sdTotal=parseHumanBytes(sys.SD?.total), sdUsed=parseHumanBytes(sys.SD?.used);
  set("mon-fs-used", `${sys.LittleFS?.used||"--"} / ${sys.LittleFS?.total||"--"}`);
  set("mon-fs-free", sys.LittleFS?.free||"--");
  set("mon-fs-free2", sys.LittleFS?.free||"--");
  const mfs=document.getElementById("mon-meter-fs"); if(mfs) mfs.style.width = fsTotal? Math.min(100,(fsUsed*100)/fsTotal).toFixed(1)+"%":"0%";
  set("mon-sd-used", `${sys.SD?.used||"--"} / ${sys.SD?.total||"--"}`);
  set("mon-sd-free", sys.SD?.free||"--");
  set("mon-sd-free2", sys.SD?.free||"--");
  const msd=document.getElementById("mon-meter-sd"); if(msd) msd.style.width = sdTotal? Math.min(100,(sdUsed*100)/sdTotal).toFixed(1)+"%":"0%";
}
function renderMonitorAlerts(sec){
  if(!sec) sec=monLastSecLab||{}; if(!sec || !Object.keys(sec).length) return;
  const feed=document.getElementById("mon-alerts-feed");
  const plusFeed=document.getElementById("mon-plus-feed");
  const plus = sec.plus||{}, pm=sec.pmkid||{}, cs=sec.csa||{}, pt=sec.portal||{}, la=sec.lanAudit||{}, rp=sec.responderPlus||{}, lg=sec.lanGuard||{}, hi=sec.httpInspector||{}, ll=sec.ledLink||{}, ba=sec.bleAudit||{}, pa=sec.pairAudit||{}, tb=sec.tagBeacon||{}, sn=sec.sonar||{};
  const items=[];
  // Build unified list with type tag
  (lg.alerts||[]).slice(-8).forEach(a=> items.push({type:"guard", html:`<div class="sl-item" data-type="guard"><span>2B ${slEsc(a.kind)} <small class="muted-sm">${slEsc(a.ip||"")} ${slEsc(a.detail||"")}</small></span><span class="sl-tag blk">${slEsc(a.kind||"GUARD")}</span></div>`, ts:a.ts||a.time||0}));
  (hi.findings||[]).slice(-10).forEach(f=> items.push({type:"http", html:`<div class="sl-item" data-type="http"><span>2C ${slEsc(f.host||"")} ${slEsc(f.kind||"")} <small class="muted-sm">${slEsc(f.detail||"")}</small></span><span class="sl-tag alert">${slEsc(f.kind||"HTTP")}</span></div>`, ts:f.ts||0}));
  (sn.events||[]).slice(-6).forEach(ev=> items.push({type:"sonar", html:`<div class="sl-item" data-type="sonar"><span>Sonar ${slEsc(ev.dir||"")} ${ev.pct||ev.score||0}% <small class="muted-sm">${ev.ts||0}s</small></span><span class="sl-tag ${ev.alarm?"blk":""}">${ev.alarm?"ALERT":"EVT"}</span></div>`, ts:ev.ts||0}));
  (ba.findingList||[]).slice(-6).forEach(f=> items.push({type:"ble", html:`<div class="sl-item" data-type="ble"><span>4A ${slEsc(f.verdict||"")} <small class="muted-sm">${slEsc(f.uuid||f.handle||"")}</small></span><span class="sl-tag ${f.risk==="HIGH"?"blk":""}">BLE</span></div>`, ts:0}));
  if(pm.running) items.push({type:"wids", html:`<div class="sl-item" data-type="wids"><span>1A PMKID RUN <small class="muted-sm">${pm.hashes||0} hashes</small></span><span class="sl-tag on">RUN</span></div>`});
  if(cs.running) items.push({type:"wids", html:`<div class="sl-item" data-type="wids"><span>1B CSA RUN <small class="muted-sm">CH${plus.csaChannel||1} x${plus.csaBursts||3}</small></span><span class="sl-tag on">CSA</span></div>`});
  if(pt.running) items.push({type:"wids", html:`<div class="sl-item" data-type="wids"><span>1B Portal-NAPT <small class="muted-sm">${pt.napt?"HANDOFF ON":"PORTAL"}</small></span><span class="sl-tag ok">PORTAL</span></div>`});
  (la.findingList||[]).slice(-6).forEach(f=> items.push({type:"guard", html:`<div class="sl-item" data-type="guard"><span>2A ${slEsc(f.ip)}:${f.port} ${slEsc(f.proto)} <small class="muted-sm">${slEsc(f.verdict||"")}</small></span><span class="sl-tag ${f.risk==="HIGH"?"blk":""}">${f.risk||""}</span></div>`}));
  if(pa.verdict) items.push({type:"ble", html:`<div class="sl-item" data-type="ble"><span>4B Pairing ${slEsc(pa.verdict)} <small class="muted-sm">${slEsc(pa.addr||"")}</small></span><span class="sl-tag ${pa.verdict.indexOf("JUST_WORKS")>=0?"alert":""}">${slEsc(pa.verdict)}</span></div>`});
  if(tb.running) items.push({type:"ble", html:`<div class="sl-item" data-type="ble"><span>Tag Beacon ${slEsc(tb.current||"")} <small class="muted-sm">${tb.rotations||0} rotations</small></span><span class="sl-tag on">BEACON</span></div>`});
  // chain
  const chain=sec.chain||{};
  (chain.running||[]).forEach(c=> items.push({type:"chain", html:`<div class="sl-item" data-type="chain"><span>Chain ${slEsc(c.id||c.chain)} <small class="muted-sm">${slEsc(c.step||c.phase||"")}</small></span><span class="sl-tag on">CHAIN</span></div>`}));

  // sort? keep insertion order
  if(feed){
    const filtered = monFilter==="all" ? items : items.filter(it=>it.type===monFilter);
    feed.innerHTML = filtered.map(it=>it.html).join("") || `<div class="sl-item muted-sm">No ${monFilter==="all"?"":monFilter} alerts — all quiet. Filters: All/WIDS/Guard/HTTP/Sonar/BLE/Chains</div>`;
  }
  // mirror SecLab+ feed for reference
  if(plusFeed){
    const srcFeed=document.getElementById("sl-plus-feed");
    if(srcFeed && srcFeed.innerHTML) plusFeed.innerHTML = srcFeed.innerHTML;
  }
}


async function refreshStudio(){
  const generation = ++studioRefreshGeneration;
  const msgBox=document.getElementById("st-msg");
  const lastEl=document.getElementById("st-last");
  const isPreview = window.location.hostname==="127.0.0.1" || window.location.hostname==="localhost" || window.location.port==="8002" || window.location.port==="8001";
  try{
    const sysP = requestGet("/systeminfo").then(j=>JSON.parse(j)).catch(()=>null);
    const secP = requestGet("/seclab/status").then(j=>JSON.parse(j)).catch(()=>null);
    const qrP = requestGet("/studio/qrcodes").then(j=>JSON.parse(j)).catch(()=>null);
    const badusbP = requestGet("/badusb/autorun").then(j=>JSON.parse(j)).catch(()=>null);
    const [sys, sec, qr, badusb] = await Promise.all([sysP, secP, qrP, badusbP]);
    if (generation !== studioRefreshGeneration) return;
    if(sys) studioLastSys = sys;
    if(sec) studioLastSecLab = sec;
    if(qr && qr.qrcodes) studioLastQr = qr.qrcodes;
    if(badusb) studioLastBadusb = badusb;
    if(!studioLastBadusb && isPreview){
      studioLastBadusb = {enabled:false, armed:false, running:false, payloadFs:"LittleFS", payloadPath:"/payload.txt", payloadLabel:"LittleFS:/payload.txt", delayMs:1500, confirmWindow:true, confirmMs:3000, trigger:0, runOncePerPlug:true, lastMounted:false};
    }
    if(!studioLastSys && isPreview){
      studioLastSys = {BRUCE_VERSION:"1.17-preview", BOARD:"DSolution 1.83 2-Mic", OWNER:"DSolution", MAC:"AA:BB:CC:DD:EE:FF", UPTIME_SEC: 3421, BAT:76, BAT_MV:3980, CHG:true, CPU_MHZ:240, DUALBOOT:true, OTA_SLOT:"ota_1", OTA_NEXT:"ota_0", OTA_MAX:"4.0 MB"};
    }
    if(!studioLastSecLab && isPreview){
      studioLastSecLab = {sonar:{armed:true, alarm:false, carrierHz:18000, sens:"mid", peak:12, signal:"OK", events:[{dir:"left", pct:34, ts:12},{dir:"right", pct:22, ts:45}], action:"Arm"}, usb:{psramFree:2100000, flashImgBytes:65536, vaultFiles:[{name:"payload.txt", size:124}]}, plus:{available:true}};
    }
    if(!studioLastQr && isPreview){
      studioLastQr = [{name:"Bruce AP", content:"WIFI:T:WPA;S:BruceNet;P:brucenet;;"}, {name:"Bruce Wiki", content:"https://github.com/pr3y/Bruce/wiki"}, {name:"Bruce Site", content:"https://bruce.computer"}];
    }
    if(!studioLastSys && !studioLastSecLab) throw new Error("no studio data");
    lastSysInfo = studioLastSys || lastSysInfo;
    const missing = [["System",sys],["SecLab",sec],["QR",qr],["Auto-Run",badusb]].filter(x=>!x[1]).map(x=>x[0]);
    if(lastEl) lastEl.textContent = missing.length ? "Dữ liệu có thể cũ" : "Cập nhật " + new Date().toLocaleTimeString();
    renderStudioOverview(studioLastSys, studioLastSecLab, studioLastQr);
    renderStudioMic(studioLastSys, studioLastSecLab);
    renderStudioQr(studioLastQr);
    renderStudioClock(studioLastSys);
    renderStudioBadusb(studioLastBadusb);
    if(msgBox){
      if(isPreview && !sys){ msgBox.className="ota-status ok"; msgBox.textContent="Preview mode \u2014 showing mock Studio data. Connect device for live."; msgBox.classList.remove("hidden"); }
      else if (missing.length) { msgBox.className="ota-status err"; msgBox.textContent="Không cập nhật được: " + missing.join(", ") + ". Dữ liệu hiển thị có thể cũ; kiểm tra kết nối và thử Refresh."; msgBox.classList.remove("hidden"); }
      else msgBox.classList.add("hidden");
    }
  }catch(e){
    if (generation !== studioRefreshGeneration) return;
    if (lastEl) lastEl.textContent = "Không cập nhật được — dữ liệu có thể cũ";
    if(msgBox){ msgBox.className="ota-status err"; msgBox.textContent=e.message||"Studio refresh failed"; msgBox.classList.remove("hidden"); }
    console.warn("refreshStudio",e);
  }
}
function renderStudioOverview(sys, sec, qr){
  if(!sys && !sec) { sys=studioLastSys||{}; sec=studioLastSecLab||{}; } else { sys=sys||studioLastSys||{}; sec=sec||studioLastSecLab||{}; }
  const set=(id,txt)=>{ const el=document.getElementById(id); if(el) el.textContent=txt; };
  const badge=(id,txt,cls)=>{ const el=document.getElementById(id); if(!el) return; el.textContent=txt; el.className="sl-badge "+(cls||""); };
  const now=new Date();
  const timeStr=now.toLocaleTimeString();
  set("st-ov-clock", timeStr);
  set("st-ov-clock-sub", `${sys.BOARD||"Bruce"} \u00b7 Up ${formatUptime(sys.UPTIME_SEC)}`);
  badge("st-ov-clock-badge", sys.DUALBOOT? "DUAL":"TIME", sys.DUALBOOT?"on":"");
  // mic
  set("st-ov-mic", "ES7210 48kHz");
  set("st-ov-mic-sub", `Gain 24 dB \u00b7 DMA ${sys.DMA_FREE||"--"}`);
  // sonar
  const sn=sec?.sonar||{};
  set("st-ov-sonar", sn.armed ? (sn.alarm?"ALERT!":"ARMED") : "IDLE");
  set("st-ov-sonar-sub", `${sn.carrierHz||"--"} Hz \u00b7 ${sn.sens||"--"} \u00b7 ${sn.peak||0}%`);
  badge("st-ov-sonar-badge", sn.armed? (sn.alarm?"ALERT":"ARMED"):"IDLE", sn.alarm?"alert":(sn.armed?"on":""));
  // qr
  const qrCount = Array.isArray(qr)? qr.length : (Array.isArray(studioLastQr)? studioLastQr.length:0);
  set("st-ov-qr", `${qrCount} codes`);
  set("st-ov-qr-sub", qrCount? `${qrCount} saved \u00b7 tap QR tab to view` : "No QR yet");
  // dual
  set("st-ov-dual", sys.OTA_SLOT||"--");
  set("st-ov-dual-sub", `${sys.OTA_SLOT||"--"} \u2192 ${sys.OTA_NEXT||"--"}`);
  badge("st-ov-dual-badge", sys.DUALBOOT?"DUAL":"single", sys.DUALBOOT?"on":"");
  // mic files overview
  const micBox=document.getElementById("st-ov-mic-files");
  if(micBox){
    // try to list mic files via existing file API cache if any, else mock
    micBox.innerHTML = `<div class="sl-item"><span>Record via device: <b>Studio</b> \u2192 <b>Microphone</b> \u2192 <b>Record</b></span><span class="sl-tag ok">ES7210</span></div><div class="sl-item"><span>/BruceMIC \u00b7 SD or LittleFS</span><button type="button" class="btn-action" onclick="switchStSlab('mic')">Chọn ổ</button></div>`;
  }
  const sonarBox=document.getElementById("st-ov-sonar-events");
  if(sonarBox){
    const evs=(sn.events||[]).slice(-4).reverse();
    sonarBox.innerHTML = evs.map(ev=> `<div class="sl-item"><span>${slEsc(ev.dir||"")} ${ev.pct||0}% <small class="muted-sm">${ev.ts||0}s</small></span><span class="sl-tag ${ev.alarm?"alert":""}">${ev.alarm?"ALERT":"EVT"}</span></div>`).join("") || `<div class="sl-item muted-sm">No sonar events \u2014 arm on device</div>`;
  }
}
function renderStudioMic(sys, sec){
  if(!sys) sys=studioLastSys||{}; if(!sec) sec=studioLastSecLab||{};
  const set=(id,txt)=>{ const el=document.getElementById(id); if(el) el.textContent=txt; };
  const sn=sec?.sonar||{};
  set("st-sonar-cfg", sn.carrierHz? `${sn.carrierHz} Hz / ${sn.sens||"-"}` : "Not run yet");
  set("st-sonar-act", sn.action||sn.signal||"--");
  set("st-sonar-pk", `${sn.peak||0}%`);
  set("st-sonar-dir", sn.signal||"--");
  const badge=document.getElementById("st-sonar-badge");
  if(badge){ badge.textContent=sn.armed? (sn.alarm?"ALERT!":"ARMED"):"IDLE"; badge.className="sl-badge "+(sn.alarm?"alert":(sn.armed?"on":"")); }
  const evBox=document.getElementById("st-sonar-events");
  if(evBox){
    evBox.innerHTML=(sn.events||[]).slice().reverse().map(ev=>{
      const wav = ev.wav? `<button type="button" class="sl-tag ok" data-st-play-wav="${slEsc(ev.wav)}">Play</button>` : "";
      return `<div class="sl-item"><span>${slEsc(ev.dir||ev.type||"evt")} ${ev.pct||ev.score||0}% <small class="muted-sm">${ev.ts||0}s ${slEsc(ev.detail||"")}</small></span><span>${wav}</span></div>`;
    }).join("") || `<div class="sl-item muted-sm">Launch Studio \u2192 Microphone \u2192 Sonar Guard on device</div>`;
  }
  // mic files list
  const micList=document.getElementById("st-mic-files");
  if(micList){
    // attempt to fetch file list if we have file browser cache, else show hint
    micList.innerHTML = `<div class="sl-item muted-sm">Recordings use <code>/BruceMIC</code> on SD when mounted, otherwise LittleFS. Use <b>Files</b> or device <b>Record</b>.</div><div class="sl-item"><span>Quick open</span><span><button type="button" class="btn-action" onclick="openRecordings('LittleFS')">LittleFS</button> <button type="button" class="btn-action" onclick="openRecordings('SD')">SD</button></span></div>`;
  }
}
function renderStudioQr(qr){
  const list=Array.isArray(qr)? qr : (studioLastQr||[]);
  const badge=document.getElementById("st-qr-count");
  if(badge) badge.textContent = `${list.length} codes`;
  const box=document.getElementById("st-qr-list");
  if(!box) return;
  if(!list.length){
    box.innerHTML=`<div class="sl-item muted-sm">No QRCodes yet \u2014 add one above or via device <b>Studio \u2192 QRCodes \u2192 Save&amp;Display</b></div>`;
    return;
  }
  box.innerHTML = list.map(q=> `<div class="sl-item"><span><strong>${slEsc(q.name||q.menuName)}</strong><br><small class="mono muted-sm">${slEsc((q.content||"").slice(0,64))}${(q.content||"").length>64?"\u2026":""}</small></span><span style="display:flex;gap:6px"><button type="button" class="sl-tag ok" data-st-qr-show="${slEsc(q.name||q.menuName)}" data-st-qr-content="${slEsc(q.content||"")}">View</button><button type="button" class="sl-tag blk" data-st-qr-del="${slEsc(q.name||q.menuName)}">Del</button></span></div>`).join("");
}
function renderStudioClock(sys){
  if(!sys) sys=studioLastSys||{};
  const set=(id,txt)=>{ const el=document.getElementById(id); if(el) el.textContent=txt; };
  const now=new Date();
  set("st-clock-time", now.toLocaleTimeString());
  set("st-clock-tz", Intl.DateTimeFormat().resolvedOptions().timeZone || "Browser local");
  set("st-clock-uptime", formatUptime(sys.UPTIME_SEC));
  set("st-clock-ntp", "Sync manually or check on device");
  set("st-dual-slot", sys.OTA_SLOT||"--");
  set("st-dual-next", sys.OTA_NEXT||"--");
  set("st-dual-active", sys.DUALBOOT? "active":"--");
  set("st-dual-max", sys.OTA_MAX||"--");
  const b=document.getElementById("st-dual-badge");
  if(b){ b.textContent=sys.DUALBOOT?"DUAL":"single"; b.className="sl-badge "+(sys.DUALBOOT?"on":""); }
}

function renderStudioBadusb(b){
  const d=b||studioLastBadusb||{};
  const set=(id,txt)=>{ const el=document.getElementById(id); if(el) el.textContent=txt; };
  const badge=(id,txt,cls)=>{ const el=document.getElementById(id); if(!el) return; el.textContent=txt; el.className="sl-badge "+(cls||""); };
  const enabled = !!d.enabled; const armed=!!d.armed; const running=!!d.running;
  set("st-badusb-enabled", enabled?"ON":"OFF");
  set("st-badusb-armed", armed?"YES":"NO");
  set("st-badusb-payload", d.payloadLabel|| (d.payloadPath? d.payloadFs+":"+d.payloadPath : "—"));
  set("st-badusb-trigger", (d.trigger==1?"VBUS unavailable": d.trigger==2?"Delayed":"Enumeration")+" · " + (d.runOncePerPlug?"Once":"Loop"));
  set("st-badusb-delay", (d.delayMs||0)+"ms");
  set("st-badusb-confirm", d.confirmWindow? "ON "+(d.confirmMs||3000)+"ms":"OFF");
  badge("st-badusb-badge", running?"RUNNING": enabled? (armed?"ARMED":"IDLE"):"OFF", running?"alert": enabled?"on":"");
  const setField=(id, value, checkbox=false) => {
    const field=document.getElementById(id);
    if (!field || field.dataset.touched || document.activeElement === field) return;
    if (checkbox) field.checked=!!value; else field.value=String(value ?? "");
  };
  setField("st-badusb-enabled-toggle", enabled, true);
  setField("st-badusb-confirm-toggle", d.confirmWindow, true);
  setField("st-badusb-once-toggle", d.runOncePerPlug, true);
  setField("st-badusb-fs", d.payloadFs || "LittleFS");
  setField("st-badusb-path", d.payloadPath || "");
  setField("st-badusb-delayMs", d.delayMs ?? 1500);
  setField("st-badusb-trigger-sel", d.trigger ?? 0);
  setField("st-badusb-confirmMs", d.confirmMs ?? 3000);
}

let portalTemplates=[], portalActive="";
async function portalRefresh(){
  const msg=document.getElementById("pt-msg");
  const badge=document.getElementById("sl-portal-badge");
  const activeEl=document.getElementById("pt-active");
  const countEl=document.getElementById("pt-count");
  const listEl=document.getElementById("pt-list");
  try{
    const raw=await requestGet("/portal/templates");
    const j=JSON.parse(raw);
    portalTemplates=j.templates||[];
    portalActive=j.active||"";
    if(activeEl) activeEl.textContent=portalActive||"(mặc định Google/Router)";
    if(countEl) countEl.textContent=String(portalTemplates.length);
    if(badge) { badge.textContent=portalActive?portalActive.split("/").pop():"mặc định"; badge.className="sl-badge "+(portalActive?"on":""); }
    if(listEl){
      if(!portalTemplates.length) listEl.innerHTML=`<div class="sl-item muted-sm">Chưa có mẫu nào — bấm <b>+ Mẫu mới</b> hoặc <b>Tải file .html</b> để thêm. Mẫu sẽ lưu ở <code>/portal_templates/</code></div>`;
      else listEl.innerHTML=portalTemplates.map(x=>`<div class="sl-item"><span><strong>${slEsc(x.name)}</strong><br><small class="mono muted-sm">${slEsc(x.path)} · ${x.size}B ${x.ap?`· AP: ${slEsc(x.ap)}`:""} ${portalActive===x.path?`· <b>Active</b>`:""}</small></span><span style="display:flex;gap:6px"><button type="button" class="sl-tag ok" data-pt-use="${slEsc(x.path)}">Dùng</button><button type="button" class="sl-tag" data-pt-edit="${slEsc(x.path)}">Sửa</button><button type="button" class="sl-tag" data-pt-dup="${slEsc(x.path)}">Nhân bản</button><button type="button" class="sl-tag blk" data-pt-del="${slEsc(x.path)}">Xoá</button></span></div>`).join("");
    }
    if(msg){ msg.classList.add("hidden"); }
  }catch(e){
    if(msg){ msg.className="ota-status err"; msg.textContent=e.message||"Không tải được danh sách"; msg.classList.remove("hidden"); }
  }
}
function portalSetForm(name, content, ap){
  const n=document.getElementById("pt-name"), c=document.getElementById("pt-content"), a=document.getElementById("pt-ap");
  if(n) n.value=name||"";
  if(c) c.value=content||"";
  if(a) a.value=ap||"";
}
async function portalSave(){
  const n=document.getElementById("pt-name")?.value.trim();
  const c=document.getElementById("pt-content")?.value||"";
  const ap=document.getElementById("pt-ap")?.value.trim()||"";
  const msg=document.getElementById("pt-msg");
  if(!n){ if(msg){ msg.className="ota-status err"; msg.textContent="Thiếu tên file (vd google.html)"; msg.classList.remove("hidden"); } return; }
  if(!c.trim()){ if(msg){ msg.className="ota-status err"; msg.textContent="Thiếu nội dung HTML"; msg.classList.remove("hidden"); } return; }
  try{ const raw=await requestPost("/portal/templates",{action:"save", name:n, content:c, apName:ap}); const j=JSON.parse(raw); if(msg){ msg.className="ota-status "+(j.ok?"ok":"err"); msg.textContent=j.msg||""; msg.classList.remove("hidden"); } if(j.ok) { portalRefresh(); } }catch(e){ if(msg){ msg.className="ota-status err"; msg.textContent=e.message; msg.classList.remove("hidden"); } }
}

function slEsc(s) {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}
function slShowMsg(box, text, ok, autoHideMs) {
  if (!box) return;
  const oldTimer = secLabMsgTimers.get(box);
  if (oldTimer) clearTimeout(oldTimer);
  box.className = "ota-status " + (ok ? "ok" : "err");
  box.textContent = text;
  box.classList.remove("hidden");
  if (autoHideMs) {
    secLabMsgTimers.set(box, setTimeout(() => {
      box.classList.add("hidden");
      secLabMsgTimers.delete(box);
    }, autoHideMs));
  }
}
function slErrorText(e, fallback) {
  let msg = e?.message || fallback;
  try {
    const d = JSON.parse(e?.body || "");
    if (d && d.msg) msg = d.msg;
  } catch (_) {}
  return msg || fallback;
}
function slBusyButtons(busy) {
  document.querySelectorAll("[data-sl-action], #sl-plus-pair-mode").forEach((b) => { b.disabled = busy; });
  const box = $("#sl-plus-msg");
  if (box) box.setAttribute("aria-busy", busy ? "true" : "false");
}
function slBusyNaptButtons(busy) {
  document.querySelectorAll("#sl-napt-start, #sl-napt-stop, #sl-napt-auto, #sl-napt-export, #sl-napt-clear, #mon-napt-toggle, #mon-napt-export").forEach((b) => {
    b.disabled = busy;
  });
  const box = $("#sl-napt-msg");
  if (box) box.setAttribute("aria-busy", busy ? "true" : "false");
}

async function naptPost(params, messageBox = $("#sl-napt-msg")) {
  if (params.action === "block" || params.action === "unblock") {
    const domain = String(params.domain || "").trim();
    if (!domain) {
      slShowMsg($("#sl-napt-msg"), "Enter a domain to block or unblock", false, 0);
      return false;
    }
    params.domain = domain;
  }
  if (secLabNaptBusy) return false;
  secLabNaptBusy = true;
  secLabLastNaptActionAt = Date.now();
  slBusyNaptButtons(true);
  const box = messageBox;
  let ok = false;
  try {
    const raw = await requestPost("/seclab/napt", params);
    const d = JSON.parse(raw);
    ok = !!d.ok;
    slShowMsg(box, d.msg || (ok ? "NAPT action OK" : "NAPT action failed"), ok, ok ? 4500 : 0);
    await refreshSecLab();
  } catch (e) {
    slShowMsg(box, slErrorText(e, "NAPT action failed"), false, 0);
  } finally {
    secLabNaptBusy = false;
    slBusyNaptButtons(false);
  }
  return ok;
}

async function seclabPlusPost(params) {
  if (secLabBusy) return;
  secLabBusy = true;
  secLabLastActionAt = Date.now();
  slBusyButtons(true);
  const box = $("#sl-plus-msg");
  try {
    const raw = await requestPost("/seclab/action", params);
    const d = JSON.parse(raw);
    if (d.ok === false) {
      slShowMsg(box, d.msg || "SecLab+ action failed", false, 0);
    } else {
      slShowMsg(box, d.msg || "SecLab+ action OK", true, 4500);
    }
    await refreshSecLab();
  } catch (e) {
    slShowMsg(box, slErrorText(e, "SecLab+ action failed"), false, 0);
  } finally {
    secLabBusy = false;
    slBusyButtons(false);
  }
}

function slNumber(id, min, max, label) {
  const el = $(id);
  const raw = el ? String(el.value || "").trim() : "";
  const n = Number(raw);
  if (!Number.isFinite(n) || n < min || n > max) {
    slShowMsg($("#sl-plus-msg"), `${label} must be ${min}-${max}`, false, 0);
    if (el) el.focus();
    return null;
  }
  return Math.round(n);
}
function slMacOk(v) {
  return /^(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}$|^[0-9a-fA-F]{12}$/.test(String(v || "").trim());
}
function slBuildParams(btn, action) {
  const p = { action };
  const key = btn.dataset.slToggle;
  if (key && Object.prototype.hasOwnProperty.call(secLabPlusState, key)) {
    p.enable = secLabPlusState[key] ? "0" : "1";
  }
  if (action === "os_profile") {
    p.profile = $("#sl-plus-os")?.value || "windows";
  } else if (action === "lan_start") {
    p.deep = $("#sl-plus-lan-mode")?.value || "1";
  } else if (action === "csa_config") {
    const ch = slNumber("#sl-plus-csa-channel", 1, 14, "CSA channel");
    if (ch === null) return null;
    const bursts = slNumber("#sl-plus-csa-bursts", 1, 20, "CSA bursts");
    if (bursts === null) return null;
    p.channel = String(ch);
    p.bursts = String(bursts);
  } else if (action === "http_port") {
    const port = slNumber("#sl-plus-http-port", 1024, 65535, "Proxy port");
    if (port === null) return null;
    p.port = String(port);
  } else if (action === "hid_timeout") {
    const sec = slNumber("#sl-plus-hid-timeout", 3, 300, "LED timeout");
    if (sec === null) return null;
    p.duration = String(sec);
  } else if (action === "tag_start") {
    const sec = slNumber("#sl-plus-tag-duration", 5, 300, "Beacon duration");
    if (sec === null) return null;
    p.duration = String(sec);
  } else if (action === "pair_audit") {
    const addrEl = $("#sl-plus-addr");
    const addr = addrEl?.value.trim() || "";
    if (!slMacOk(addr)) {
      slShowMsg($("#sl-plus-msg"), "Enter BLE MAC as AA:BB:CC:DD:EE:FF", false, 0);
      addrEl?.focus();
      return null;
    }
    p.addr = addr;
    p.type = $("#sl-plus-pair-type")?.value || "0";
    p.justworks = ($("#sl-plus-pair-mode")?.value || "justworks") === "justworks" ? "1" : "0";
  }
  return p;
}

document.querySelectorAll("[data-sl-action]").forEach((btn) => {
  btn.addEventListener("click", () => {
    if (secLabBusy) return;
    const confirmText = btn.dataset.slConfirm;
    if (confirmText && !window.confirm(confirmText)) return;
    const p = slBuildParams(btn, btn.dataset.slAction);
    if (!p) return;
    if (p.action === "ble_fuzzer" && p.enable === "1" &&
        !window.confirm("Boundary writes may modify or disrupt the target. Enable only for authorized devices?")) return;
    seclabPlusPost(p);
  });
});

$("#sl-plus-pair-mode")?.addEventListener("change", (ev) => {
  const jw = ev.target.value === "justworks";
  secLabPlusState.pairJustWorks = jw;
  slSyncSecLabToggles(secLabPlusState);
  seclabPlusPost({ action: "pair_mode", enable: jw ? "1" : "0" });
});

function slSetInput(id, value) {
  const el = $(id);
  if (el && document.activeElement !== el) el.value = String(value);
}

function slSyncSecLabToggles(plus) {
  document.querySelectorAll("[data-sl-toggle]").forEach((btn) => {
    const key = btn.dataset.slToggle;
    if (!Object.prototype.hasOwnProperty.call(plus, key)) return;
    const on = !!plus[key];
    btn.textContent = on ? btn.dataset.slLabelOn : btn.dataset.slLabelOff;
    btn.classList.toggle("btn-default", on);
    btn.classList.toggle("btn-warn", key === "pairJustWorks" && !on);
    btn.setAttribute("aria-pressed", on ? "true" : "false");
  });
}

// Treat absent/invalid measurements as unknown, not as a quiet channel.
function renderAirChannelBars(air) {
  const channels = Array.isArray(air.channels) ? air.channels : [];
  const bars = channels.map((c) => {
    const ch = Number(c?.ch);
    if (!Number.isInteger(ch) || ch < 1 || ch > 13) return "";
    const loadRaw = Number(c.load), retryRaw = Number(c.retry), rssiRaw = Number(c.rssi);
    const sampled = c.sampled !== false && c.load != null && c.retry != null && c.rssi != null &&
      Number.isFinite(loadRaw) && Number.isFinite(retryRaw) && Number.isFinite(rssiRaw);
    const load = sampled ? Math.max(0, Math.min(100, loadRaw)) : 0;
    const retry = Math.max(0, Math.min(100, retryRaw || 0));
    const rssi = Math.max(-128, Math.min(0, rssiRaw || 0));
    const color = !sampled ? "#667080" : load < 30 ? "#2ce59b" : load < 65 ? "#ffb020" : "#ff5d6c";
    const bestCls = sampled && Number(air.bestCh) === ch ? " best" : "";
    const title = sampled ? `CH${ch}: estimated ${load}% load, ${retry}% retry, ${rssi}dBm` : `CH${ch}: not sampled`;
    return `<div class="sl-bar-col${bestCls}" title="${title}"><div class="sl-bar-fill" style="height:${sampled ? Math.max(4, load) : 0}%;background:${color}"></div><span>${ch}</span></div>`;
  }).join("");
  return bars || `<div class="muted-sm" style="grid-column:span 13;text-align:center;margin:auto">Run WiFi -> Channel Analyzer to populate</div>`;
}

async function refreshSecLab() {
  try {
    const raw = await requestGet("/seclab/status");
    const d = JSON.parse(raw);

    // #1 NAPT
    const n = d.napt || {};
    secLabNaptState = n;
    const nb = $("#sl-napt-badge");
    if (nb) {
      nb.textContent = n.running ? `ON (${n.uptimeSec || 0}s)` : (n.starting ? "STARTING..." : "OFF");
      nb.className = "sl-badge " + (n.running ? "on" : (n.starting ? "alert" : ""));
    }
    const naptActive = !!(n.running || n.starting);
    $("#sl-napt-start")?.classList.toggle("hidden", naptActive);
    $("#sl-napt-stop")?.classList.toggle("hidden", !naptActive);
    if (!n.running && !n.starting && n.lastErr && $("#sl-napt-msg")) {
      const box = $("#sl-napt-msg");
      if (Date.now() - secLabLastNaptActionAt > 8000 &&
          (box.classList.contains("hidden") || box.className.indexOf(" ok") >= 0)) {
        slShowMsg(box, n.lastErr, false, 0);
      }
    }
    if ($("#sl-napt-up")) $("#sl-napt-up").textContent = n.staConnected ? `${n.staSsid} (${n.staIp})` : "Not connected";
    if ($("#sl-napt-ap")) $("#sl-napt-ap").textContent = `${n.apSsid || "BruceNet"} (${n.apIp || "192.168.4.1"})`;
    if ($("#sl-napt-stat")) $("#sl-napt-stat").textContent = `${(n.clients || []).length} / ${n.total || 0}`;
    if ($("#sl-napt-blk")) $("#sl-napt-blk").textContent = `${n.blocked || 0} / ${n.trackers || 0}`;
    const naptAuto = $("#sl-napt-auto");
    if (naptAuto) {
      naptAuto.textContent = `Auto-Block Trackers: ${n.autoBlock ? "ON" : "OFF"}`;
      naptAuto.classList.toggle("btn-default", !!n.autoBlock);
      naptAuto.setAttribute("aria-pressed", n.autoBlock ? "true" : "false");
    }

    if ($("#sl-blk-chips")) {
      $("#sl-blk-chips").innerHTML = (n.blockList || []).map((dom) =>
        `<span class="sl-chip">${slEsc(dom)}<button type="button" data-napt-action="unblock" data-napt-domain="${slEsc(dom)}" aria-label="Unblock ${slEsc(dom)}">&times;</button></span>`
      ).join("") || `<span class="muted-sm">No custom domains in /napt_block.txt</span>`;
    }
    if ($("#sl-dns-feed")) {
      $("#sl-dns-feed").innerHTML = (n.feed || []).map((f) => {
        const cls = f.blk ? "blk" : (f.trk ? "alert" : "ok");
        const act = f.blk ? `unblock` : `block`;
        return `<div class="sl-item"><span>${slEsc(f.dom)} <small class="muted-sm">${slEsc(f.ip)}</small></span><button type="button" class="sl-tag ${cls}" data-napt-action="${act}" data-napt-domain="${slEsc(f.dom)}" aria-label="${act} ${slEsc(f.dom)}">${f.blk ? "BLK" : (f.trk ? "TRK" : "OK")}</button></div>`;
      }).join("") || `<div class="sl-item muted-sm">No DNS queries captured yet</div>`;
    }
    if ($("#sl-napt-clients")) {
      $("#sl-napt-clients").innerHTML = (n.clients || []).map((c) =>
        `<div class="sl-item"><span>${slEsc(c.ip)}</span><small class="muted-sm">${slEsc(c.mac)}</small></div>`
      ).join("") || `<div class="sl-item muted-sm">No clients connected to AP</div>`;
    }

    // #6 Sonar
    const sn = d.sonar || {};
    if ($("#sl-sonar-badge")) {
      $("#sl-sonar-badge").textContent = sn.armed ? (sn.alarm ? "ALERT!" : "ARMED") : "IDLE";
      $("#sl-sonar-badge").className = "sl-badge " + (sn.alarm ? "alert" : (sn.armed ? "on" : ""));
    }
    if ($("#sl-sonar-cfg")) $("#sl-sonar-cfg").textContent = sn.carrierHz ? `${sn.carrierHz} Hz / ${sn.sens || "-"}` : "Not run yet";
    if ($("#sl-sonar-act")) $("#sl-sonar-act").textContent = sn.action || "--";
    if ($("#sl-sonar-pk")) $("#sl-sonar-pk").textContent = `${sn.peak || 0}%`;
    if ($("#sl-sonar-dir")) $("#sl-sonar-dir").textContent = sn.signal || "--";
    if ($("#sl-sonar-events")) {
      $("#sl-sonar-events").innerHTML = (sn.events || []).slice().reverse().map((ev) => {
        const right = ev.wav
          ? `<span><button type="button" class="sl-tag ok" data-sl-play-wav="${slEsc(ev.wav)}">Play</button> <a class="sl-tag" href="${IS_DEV ? "/bruce" : ""}/file?fs=LittleFS&amp;action=download&amp;name=${encodeURIComponent(ev.wav)}">WAV</a></span>`
          : `<small class="muted-sm">${ev.ts || 0}s</small>`;
        return `<div class="sl-item"><span>${slEsc(ev.dir)} (${ev.pct ?? ev.score ?? 0}%)</span>${right}</div>`;
      }).join("") || `<div class="sl-item muted-sm">Launch Others -> Sonar Guard on device</div>`;
    }

    // #8 Virtual USB Vault
    const u = d.usb || {};
    const vaultFiles = u.vaultFiles || [];
    const vaultTotalBytes = vaultFiles.reduce((acc, f) => acc + (Number(f.size) || 0), 0);
    const vaultSzStr = vaultTotalBytes >= 1024 ? (vaultTotalBytes / 1024).toFixed(1) + " KB" : vaultTotalBytes + " B";
    if ($("#sl-usb-psram")) {
      const psStr = u.psramFree ? (u.psramFree / 1048576).toFixed(2) + " MB" : "--";
      $("#sl-usb-psram").textContent = `${psStr} / ${vaultFiles.length}f (${vaultSzStr})`;
    }
    if ($("#sl-usb-img")) $("#sl-usb-img").textContent = u.flashImgBytes ? Math.round(u.flashImgBytes / 1024) + " KB saved" : "None";
    if ($("#sl-vault-list")) {
      $("#sl-vault-list").innerHTML = vaultFiles.map((vf) => {
        const fp = "/usb_vault/" + vf.name;
        return `<div class="sl-item"><span>${slEsc(vf.name)} <small class="muted-sm">${vf.size}B</small></span><span><a class="sl-tag" href="${IS_DEV ? "/bruce" : ""}/file?fs=LittleFS&amp;action=download&amp;name=${encodeURIComponent(fp)}">Get</a> <button type="button" class="sl-tag blk" data-sl-delete-vault="${slEsc(fp)}">Del</button></span></div>`;
      }).join("") || `<div class="sl-item muted-sm">/usb_vault is empty. Upload files or Ducky .txt!</div>`;
    }

    // #4 Air-Time & Hidden SSID
    const air = d.airtime || {};
    if ($("#sl-air-best")) {
      const ch = Number(air.bestCh);
      const score = Number(air.bestScore);
      const partial = air.neighborsComplete === false ? " · PARTIAL" : "";
      $("#sl-air-best").textContent = Number.isInteger(ch) && ch >= 1 && ch <= 13 && Number.isFinite(score) && score >= 0
        ? `EST. BEST CH ${ch} (${score}%)${partial}` : Array.isArray(air.channels) && air.channels.length ? "SCAN INCOMPLETE" : "NO SCAN YET";
    }
    if ($("#sl-air-bars")) $("#sl-air-bars").innerHTML = renderAirChannelBars(air);
    if ($("#sl-air-hidden")) {
      $("#sl-air-hidden").innerHTML = (air.hidden || []).map((h) =>
        `<div class="sl-item"><span>${slEsc(h.decloaked ? h.ssid : "<Hidden>")} <small class="muted-sm">${slEsc(h.bssid)}</small></span><span class="sl-tag ${h.decloaked ? "ok" : ""}">C${h.ch} ${h.rssi}dB</span></div>`
      ).join("") || `<div class="sl-item muted-sm">No hidden SSIDs cached</div>`;
    }

    // #2 Probe Radar & #12 BLE GATT
    const prb = d.probe || {};
    if ($("#sl-prb-stat")) $("#sl-prb-stat").textContent = `${(prb.devices || []).length} / ${prb.totalMacs || 0}`;
    if ($("#sl-prb-list")) {
      $("#sl-prb-list").innerHTML = (prb.devices || []).slice(0, 15).map((p) =>
        `<div class="sl-item"><span>#${p.id} ${slEsc(p.os)} (${p.rot} MACs) <small class="muted-sm">${slEsc((p.pnls || []).join(", "))}</small></span><span class="sl-tag ${p.watched ? "blk" : ""}">${p.rssi}dB</span></div>`
      ).join("") || `<div class="sl-item muted-sm">Run WiFi -> Probe Radar to cluster devices</div>`;
    }

    const bg = d.bleGatt || {};
    if ($("#sl-ble-phy")) {
      $("#sl-ble-phy").textContent = `PHY ${bg.txPhy || "1M"}`;
      $("#sl-ble-phy").className = "sl-badge " + (bg.connected ? "on" : "");
    }
    if ($("#sl-ble-mode")) $("#sl-ble-mode").textContent = `${bg.mode || "IDLE"}${bg.target ? " (" + bg.target + ")" : ""}`;
    if ($("#sl-ble-profs")) {
      $("#sl-ble-profs").innerHTML = (bg.profiles || []).map((gp) =>
        `<div class="sl-item"><span>${slEsc(gp.name)} <small class="muted-sm">${slEsc(gp.addr)}</small></span><button type="button" class="sl-tag" data-sl-open-file="${slEsc(gp.path)}">${gp.services}S/${gp.chars}C</button></div>`
      ).join("") || `<div class="sl-item muted-sm">No saved GATT profiles in /ble_gatt</div>`;
    }

    // SecLab+ 1A-4B control center
    const plus = d.plus || {};
    secLabPlusState = plus;
    if (!secLabStatusOk && Date.now() - secLabLastActionAt > 8000) {
      slShowMsg($("#sl-plus-msg"), "SecLab+ status restored", true, 3000);
    }
    secLabStatusOk = true;
    secLabStatusErrShown = false;
    const pm = d.pmkid || {}, cs = d.csa || {}, pt = d.portal || {};
    const la = d.lanAudit || {}, rp = d.responderPlus || {}, lg = d.lanGuard || {}, hi = d.httpInspector || {};
    const ll = d.ledLink || {}, ba = d.bleAudit || {}, pa = d.pairAudit || {}, tb = d.tagBeacon || {};
    const setTxt = (id, txt) => { const el = $(id); if (el) el.textContent = txt; };
    const pmkHashes = Number(pm.hashes ?? (Array.isArray(pm.captures) ? pm.captures.length : 0)) || 0;
    setTxt("#sl-plus-pmkid", `${pm.running ? "RUN" : "IDLE"} / ${pmkHashes} hash${pmkHashes === 1 ? "" : "es"}`);
    setTxt("#sl-plus-csa", `${cs.running ? "CSA RUN" : "CSA IDLE"} / ${pt.napt ? "NAPT ON" : (pt.armed ? "HANDOFF ARMED" : "PORTAL IDLE")}`);
    setTxt("#sl-plus-lan", `${la.devices ?? 0} / ${la.findings ?? 0}`);
    const guardObservations = (Number(lg.arpChanges) || 0) + (Number(lg.dhcpMismatch ?? lg.rogueDhcp) || 0);
    const guardStatus = !lg.running ? "GUARD OFF" : guardObservations ? `${guardObservations} OBSERVATIONS` :
      (!lg.arpWatch || !lg.dhcpSniff || lg.dhcpComparison === "unavailable") ? "GUARD PARTIAL" : "GUARD LIMITED";
    setTxt("#sl-plus-guard", `${rp.running ? "RESP ON" : "RESP OFF"} / ${guardStatus}`);
    setTxt("#sl-plus-http", hi.running ? `PROXY :${hi.port || plus.httpPort || 3128} / ${hi.findings?.length ?? 0}` : "OFF");
    setTxt("#sl-plus-led", `${ll.running ? "ARMED" : "IDLE"} / ${ll.bytes ?? 0}B`);
    setTxt("#sl-plus-perm", `${plus.permissionCheck ? "CHECK ON" : "CHECK OFF"} / ${plus.hidAutoArm ? "AUTO ON" : "AUTO OFF"}`);
    setTxt("#sl-plus-ble", `${ba.findings ?? 0} findings / Writes ${plus.bleSafeFuzzer ? "ON" : "OFF"}`);
    setTxt("#sl-plus-pair", `${pa.verdict || "NOT_RUN"} / ${tb.running ? tb.current || "BEACON" : "BEACON OFF"}`);
    setTxt("#sl-plus-network", `Proxy :${plus.httpPort || 3128} / ${plus.httpRedact ? "Redact ON" : "Redact OFF"}`);
    setTxt("#sl-plus-settings", `Pair ${plus.pairJustWorks ? "Just Works" : "MITM"} / CSA CH${plus.csaChannel || 1}x${plus.csaBursts || 3}`);
    setTxt("#sl-plus-active", `${plus.available === false ? "LITE BUILD" : "READY"} / ${plus.osProfile || "Windows"} / LED ${plus.hidTimeoutSec || 25}s`);
    const active = [pm.running, cs.running, pt.running, pt.napt, la.running, rp.running, lg.running, hi.running, ll.running, tb.running, pa.verdict === "RUNNING"].filter(Boolean).length;
    const badge = $("#sl-plus-badge");
    if (badge) { badge.textContent = plus.available === false ? "LITE" : `${active} ACTIVE`; badge.className = "sl-badge " + (active ? "on" : ""); }
    const osSel = $("#sl-plus-os");
    if (osSel && plus.osProfile && document.activeElement !== osSel) {
      const name = String(plus.osProfile).toLowerCase();
      osSel.value = name.startsWith("mac") ? "macos" : (name.startsWith("lin") ? "linux" : "windows");
    }
    slSyncSecLabToggles(plus);
    const slPair = (startAct, stopAct, active) => {
      document.querySelector(`[data-sl-action="${startAct}"]`)?.classList.toggle("hidden", !!active);
      document.querySelector(`[data-sl-action="${stopAct}"]`)?.classList.toggle("hidden", !active);
    };
    slPair("pmkid_start", "pmkid_stop", pm.running);
    slPair("csa_start", "csa_stop", cs.running);
    slPair("portal_start", "portal_stop", pt.running || pt.napt);
    slPair("lan_start", "lan_stop", la.running);
    slPair("responder_start", "responder_stop", rp.running);
    slPair("guard_start", "guard_stop", lg.running);
    slPair("http_start", "http_stop", hi.running);
    slPair("led_start", "led_stop", ll.running);
    slPair("tag_start", "tag_stop", tb.running);
    slSetInput("#sl-plus-csa-channel", plus.csaChannel || 1);
    slSetInput("#sl-plus-csa-bursts", plus.csaBursts || 3);
    slSetInput("#sl-plus-http-port", plus.httpPort || 3128);
    slSetInput("#sl-plus-hid-timeout", plus.hidTimeoutSec || 25);
    const pairMode = $("#sl-plus-pair-mode");
    if (pairMode && document.activeElement !== pairMode) {
      pairMode.value = plus.pairJustWorks ? "justworks" : "mitm";
    }

    const feed = [];
    const push = (label, value, cls) => feed.push(`<div class="sl-item"><span>${slEsc(label)}</span><span class="sl-tag ${cls || ""}">${slEsc(value)}</span></div>`);
    if (pm.lastErr) push("1A PMKID", pm.lastErr, "blk");
    if (pmkHashes) push("1A PMKID", `${pmkHashes} hashcat line(s) ready`, "ok");
    if (cs.verdict) push("1B CSA/PMF", cs.verdict, cs.verdict.indexOf("WEAK") >= 0 ? "alert" : "ok");
    if (pt.handoffDone) push("1B Portal -> NAPT", pt.napt ? "Internet handoff ONLINE" : "Handoff recorded", pt.napt ? "ok" : "");
    (la.findingList || []).slice(-6).forEach((f) => push(`2A ${f.ip}:${f.port} ${f.proto}`, f.verdict + (f.risk === "HIGH" ? " HIGH" : ""), f.risk === "HIGH" ? "blk" : ""));
    (lg.alerts || []).slice(-4).forEach((a) => push(`2B ${a.kind}`, `${a.ip} ${a.detail}`, "alert"));
    (hi.findings || []).slice(-6).forEach((f) => push(`2C ${f.host} ${f.kind}`, f.detail || "cleartext", "alert"));
    if (ll.decoded) push("3A LED Exfil", ll.decoded, "ok");
    (ba.findingList || []).slice(-5).forEach((f) => push(`4A ${f.verdict}`, `${f.uuid || f.handle} ${f.detail || ""}`, f.risk === "HIGH" ? "blk" : ""));
    if (pa.verdict) push("4B Pairing", pa.verdict, pa.verdict.indexOf("JUST_WORKS") >= 0 ? "alert" : "");
    if (tb.current) push("4B Tag Verify", `${tb.current} (${tb.rotations || 0})`, tb.running ? "ok" : "");
    const feedEl = $("#sl-plus-feed");
    if (feedEl) feedEl.innerHTML = feed.join("") || `<div class="sl-item muted-sm">Launch a SecLab+ tool from the buttons above or from the device menu.</div>`;
    syncOverviewTiles(n, air, prb, bg, sn, u, plus, la, hi, ll, ba, pa, tb);
  } catch (e) {
    secLabStatusOk = false;
    console.warn("SecLab+ status refresh failed", e);
    const badge = $("#sl-plus-badge");
    if (badge) { badge.textContent = "STATUS ERR"; badge.className = "sl-badge alert"; }
    if (!secLabStatusErrShown && Date.now() - secLabLastActionAt > 8000) {
      slShowMsg($("#sl-plus-msg"), slErrorText(e, "SecLab+ status unavailable; retrying..."), false, 0);
      secLabStatusErrShown = true;
    }
  }
}

function playSonarWav(path) {
  const pl = $("#sl-sonar-player");
  if (!pl) return;
  pl.classList.remove("hidden");
  pl.src = (IS_DEV ? "/bruce" : "") + "/file?fs=LittleFS&action=audio&name=" + encodeURIComponent(path);
  pl.play().catch(() => {});
}

async function deleteVaultFile(path) {
  if (!confirm("Delete " + path + "?")) return;
  await requestGet("/file", { fs: "LittleFS", action: "delete", name: path });
  refreshSecLab();
}

function slDelegatedAction(containerId, selector, handler) {
  const root = $(containerId);
  if (!root) return;
  root.addEventListener("click", (ev) => {
    const target = ev.target instanceof Element ? ev.target.closest(selector) : null;
    if (target && root.contains(target)) handler(target);
  });
}
slDelegatedAction("#sl-blk-chips", "[data-napt-domain]", (el) => {
  naptPost({ action: el.dataset.naptAction || "unblock", domain: el.dataset.naptDomain || "" });
});
slDelegatedAction("#sl-dns-feed", "[data-napt-domain]", (el) => {
  naptPost({ action: el.dataset.naptAction || "block", domain: el.dataset.naptDomain || "" });
});
slDelegatedAction("#sl-sonar-events", "[data-sl-play-wav]", (el) => {
  if (el.dataset.slPlayWav) playSonarWav(el.dataset.slPlayWav);
});
slDelegatedAction("#sl-vault-list", "[data-sl-delete-vault]", (el) => {
  if (el.dataset.slDeleteVault) deleteVaultFile(el.dataset.slDeleteVault);
});
slDelegatedAction("#sl-ble-profs", "[data-sl-open-file]", (el) => {
  if (el.dataset.slOpenFile) openFileInEditor("LittleFS", el.dataset.slOpenFile);
});

$("#sl-refresh")?.addEventListener("click", () => refreshSecLab());
$("#sl-napt-start")?.addEventListener("click", () => {
  const ssid = $("#sl-napt-ssid")?.value.trim() || "";
  const pwd = $("#sl-napt-pwd")?.value || "";
  const p = { action: "start" };
  if (ssid) {
    p.ssid = ssid;
    p.pwd = pwd;
  }
  naptPost(p);
});
$("#sl-napt-stop")?.addEventListener("click", () => naptPost({ action: "stop" }));
$("#sl-napt-auto")?.addEventListener("click", () => {
  const enable = secLabNaptState.autoBlock ? "0" : "1";
  naptPost({ action: "autoblock", enable });
});
$("#sl-napt-export")?.addEventListener("click", async () => {
  if (await naptPost({ action: "export" })) openFileInEditor("LittleFS", "/napt_dns.log");
});
$("#sl-napt-clear")?.addEventListener("click", () => {
  if (!window.confirm("Clear the NAPT DNS feed log?")) return;
  naptPost({ action: "clear" });
});
$("#sl-blk-add")?.addEventListener("click", () => {
  const inp = $("#sl-blk-input");
  const dom = inp?.value.trim();
  if (!dom) return;
  inp.value = "";
  naptPost({ action: "block", domain: dom });
});

$("#sl-vault-up")?.addEventListener("change", async function () {
  if (!this.files.length) return;
  const msg = $("#sl-vault-msg");
  try {
    await requestGet("/listfiles", { fs: "LittleFS", folder: "/usb_vault" }).catch(() => {});
    const total = this.files.length;
    let i = 0;
    for (const file of this.files) {
      i++;
      if (msg) {
        msg.className = "ota-status ok";
        msg.textContent = `Uploading ${i}/${total}: ${file.name}...`;
      }
      const fd = new FormData();
      fd.append("folder", "/usb_vault");
      fd.append("fs", "LittleFS");
      fd.append("file", file, file.name);
      const res = await fetch(IS_DEV ? "/bruce/upload" : "/upload", { method: "POST", body: fd });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
    }
    if (msg) {
      msg.className = "ota-status ok";
      msg.textContent = `Uploaded ${total} file(s) to /usb_vault`;
    }
  } catch (e) {
    if (msg) {
      msg.className = "ota-status err";
      msg.textContent = `Upload failed: ${e?.message || e}`;
    }
  } finally {
    this.value = "";
    refreshSecLab();
  }
});

$("#sl-vault-newtxt")?.addEventListener("click", async () => {
  let nm = prompt("Payload filename in /usb_vault (e.g. demo.txt):", "payload.txt");
  if (!nm) return;
  nm = nm.trim().replace(/^\/+/, "");
  if (!nm) return;
  const full = "/usb_vault/" + nm;
  await requestGet("/file", { fs: "LittleFS", action: "createfile", name: full });
  await openFileInEditor("LittleFS", full);
  refreshSecLab();
});

// Canonicalise 16-bit PCM WAV files for the board without decoding or inventing audio.
// Metadata chunks are safely skipped; long clips are trimmed only after confirmation.
function prepareUiSound(input, event) {
  const limits = {select:250, back:250, success:1000, warning:1000, find:1000};
  if (!Object.prototype.hasOwnProperty.call(limits, event)) throw new Error("Unknown sound event.");
  const bytes = new Uint8Array(input);
  if (bytes.length < 12 || bytes.length > 2 * 1024 * 1024) throw new Error("WAV must be between 12 bytes and 2 MB.");
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const tag = (p, t) => p + 4 <= bytes.length && [...t].every((c, i) => bytes[p + i] === c.charCodeAt(0));
  if (!tag(0, "RIFF") || !tag(8, "WAVE")) throw new Error("Select a RIFF WAV file.");
  const end = v.getUint32(4, true) + 8;
  if (end > bytes.length || end < 12) throw new Error("WAV is incomplete.");
  let fmt = null, data = null;
  for (let p = 12; p + 8 <= end;) {
    const len = v.getUint32(p + 4, true), start = p + 8;
    if (len > end - start) throw new Error("WAV chunk is incomplete.");
    if (tag(p, "fmt ") && !fmt) {
      if (len < 16) throw new Error("Invalid WAV format.");
      fmt = {type:v.getUint16(start,true), channels:v.getUint16(start+2,true), rate:v.getUint32(start+4,true),
        byteRate:v.getUint32(start+8,true), align:v.getUint16(start+12,true), bits:v.getUint16(start+14,true)};
    } else if (tag(p, "data") && !data) data = {start, len};
    p = start + len + (len & 1);
  }
  if (!fmt || !data || fmt.type !== 1 || ![1,2].includes(fmt.channels) || fmt.rate !== 48000 ||
      fmt.bits !== 16 || fmt.align !== fmt.channels * 2 || fmt.byteRate !== 48000 * fmt.align ||
      !data.len || data.len % fmt.align) throw new Error("Use uncompressed PCM, 16-bit, 48 kHz, mono or stereo.");
  const max = 48000 * fmt.align * limits[event] / 1000;
  const count = Math.min(data.len, max);
  const result = new Uint8Array(44 + count), out = new DataView(result.buffer);
  const put = (p, t) => [...t].forEach((c, i) => { result[p + i] = c.charCodeAt(0); });
  put(0,"RIFF"); out.setUint32(4, count + 36, true); put(8,"WAVE"); put(12,"fmt ");
  out.setUint32(16,16,true); out.setUint16(20,1,true); out.setUint16(22,fmt.channels,true);
  out.setUint32(24,48000,true); out.setUint32(28,fmt.byteRate,true); out.setUint16(32,fmt.align,true);
  out.setUint16(34,16,true); put(36,"data"); out.setUint32(40,count,true);
  result.set(bytes.subarray(data.start,data.start+count),44);
  return {bytes:result, trimmed:data.len > count, maxMs:limits[event]};
}

$("#ux-wav-upload")?.addEventListener("click", async () => {
  const status = $("#ux-wav-status"), button = $("#ux-wav-upload");
  const file = $("#ux-wav-file").files[0], event = $("#ux-wav-event").value;
  if (!file) { status.textContent = "Choose a WAV file first."; return; }
  if (file.size > 2 * 1024 * 1024) { status.textContent = "File exceeds the 2 MB preparation limit."; return; }
  if (_runningUpload || otaBusy) { status.textContent = "Wait for the current upload or OTA to finish."; return; }
  button.disabled = true;
  try {
    const prepared = prepareUiSound(await file.arrayBuffer(), event);
    const note = prepared.trimmed ? ` It will be trimmed to ${prepared.maxMs} ms.` : "";
    if (!confirm(`Upload ${event}.wav to LittleFS? Any existing ${event}.wav will be overwritten.${note}`)) return;
    if (_runningUpload || otaBusy) throw new Error("Another upload has started. Try again.");
    _uploadFailures = 0;
    $(".dialog.upload .dialog-body").innerHTML = "";
    const normalized = new File([prepared.bytes], `${event}.wav`, {type:"audio/wav"});
    appendFileToQueue([normalized], "LittleFS", "/ui-sounds");
    status.textContent = "See upload status. Then enable WAV for this event on the device.";
    uploadFile();
  } catch (error) { status.textContent = `Cannot prepare sound: ${error.message}`; }
  finally { button.disabled = false; }
});

// Board controls: all mutations use a custom same-origin header; the endpoint
// still checks the authenticated WebUI session. Saving is explicit, not on drag.
async function uxPost(action, value) {
  const body = new FormData();
  body.append("action", action);
  if (value !== undefined) body.append("value", String(value));
  const response = await fetch((IS_DEV ? "/bruce" : "") + "/ux", {
    method: "POST", headers: {"X-Bruce-UI": "1"}, body, credentials: "same-origin"
  });
  let data = {};
  try { data = await response.json(); } catch (_) {}
  if (!response.ok) throw new Error(data.msg || `Request failed (${response.status})`);
  return data;
}
let uxGeneration = 0;
let uxFindStartRequest = null;
async function uxLoad(showSettings = false, generation = uxGeneration) {
  const status = $("#ux-status");
  if (!status) return;
  try {
    const data = JSON.parse(await requestGet("/ux"));
    if (generation !== uxGeneration) return;
    if (showSettings) {
      $("#ux-sound").checked = !!data.sound;
      $("#ux-menu-tones").checked = !!data.menuTones;
      $("#ux-volume").value = data.volume;
      $("#ux-brightness").value = Math.max(5, data.brightness);
      uxRangeLabels();
    }
    const states = {
      idle: "Ready.", queued: "Waiting for the WebUI screen or a device menu...", playing: "Playing find signal...",
      playing_silent: "Speaker muted or busy; LED may blink if enabled...",
      finished: "Signal sent. Check the device speaker.", cancelled: "Find cancelled.",
      expired: "Find expired. Return to the WebUI screen or a menu and try again.",
      silent_or_busy: "Speaker muted, busy, or unavailable. Check Sound settings and try again."
    };
    status.textContent = states[data.find] || "Status unavailable.";
    const finding = data.find === "queued" || data.find === "playing" || data.find === "playing_silent";
    $("#ux-find")?.classList.toggle("hidden", finding);
    $("#ux-stop")?.classList.toggle("hidden", !finding);
  } catch (err) { if (generation === uxGeneration) status.textContent = "Controls unavailable. Check your connection or sign in again."; }
}
function uxRangeLabels() {
  const vol = $("#ux-volume"), bright = $("#ux-brightness");
  if (vol && $("#ux-volume-label")) $("#ux-volume-label").textContent = vol.value;
  if (bright && $("#ux-brightness-label")) $("#ux-brightness-label").textContent = bright.value;
}
$("#ux-volume")?.addEventListener("input", uxRangeLabels);
$("#ux-brightness")?.addEventListener("input", uxRangeLabels);
$("#ux-save")?.addEventListener("click", async () => {
  const status = $("#ux-status"), button = $("#ux-save");
  button.disabled = true;
  try {
    await uxPost("sound", $("#ux-sound").checked ? 1 : 0);
    await uxPost("menuTones", $("#ux-menu-tones").checked ? 1 : 0);
    await uxPost("volume", $("#ux-volume").value);
    await uxPost("brightness", $("#ux-brightness").value);
    status.textContent = "Saved. Volume applies to the next sound.";
  } catch (err) { status.textContent = `Could not save all settings: ${err.message}. Reload to check current values.`; }
  finally { button.disabled = false; }
});
$("#ux-find")?.addEventListener("click", async () => {
  const status = $("#ux-status"), button = $("#ux-find");
  const generation = ++uxGeneration;
  button.disabled = true;
  status.textContent = "Sending find request…";
  try {
    uxFindStartRequest = uxPost("find");
    let data;
    try { data = await uxFindStartRequest; }
    finally { uxFindStartRequest = null; }
    if (generation !== uxGeneration) return;
    status.textContent = data.msg;
    while (generation === uxGeneration) {
      await new Promise(resolve => setTimeout(resolve, 2000));
      if (generation === uxGeneration) await uxLoad(false, generation);
    }
  } catch (err) { if (generation === uxGeneration) status.textContent = err.message; }
  finally { if (generation === uxGeneration) button.disabled = false; }
});
$("#ux-stop")?.addEventListener("click", async () => {
  const generation = ++uxGeneration;
  const findButton = $("#ux-find"), stopButton = $("#ux-stop");
  findButton.disabled = true;
  stopButton.disabled = true;
  $("#ux-status").textContent = "Stopping…";
  try {
    // Stop must reach the device after a pending Find request, not race it.
    if (uxFindStartRequest) await uxFindStartRequest.catch(() => {});
    const data = await uxPost("stop");
    if (generation === uxGeneration) $("#ux-status").textContent = data.msg;
  } catch (err) { if (generation === uxGeneration) $("#ux-status").textContent = err.message; }
  finally { stopButton.disabled = false; if (generation === uxGeneration) findButton.disabled = false; }
});
if ($("#ux-status")) uxLoad(true);

// Keep the browser's applied palette/layout in sync with device-side changes.
// Do not overwrite a potentially unsaved Personalize form.
if (typeof setInterval === "function") setInterval(() => { if (!document.hidden && !otaBusy) fetchSystemInfo(true).catch(() => {}); }, 15000);

 // ==== SecLab compact subtabs + overview mirror (2026-11) ====
 function switchSlab(name){
   if (!document.getElementById("slab-" + name)) name = "overview";
   const views=document.querySelectorAll('[id^="slab-"]');
   const btns=document.querySelectorAll("[data-slab]");
   views.forEach(v=>v.classList.toggle("hidden", v.id!=="slab-"+name));
   btns.forEach(b=>{ const on=b.dataset.slab===name; b.classList.toggle("active", on); b.setAttribute("aria-selected", on?"true":"false"); });
   try{ localStorage.setItem("seclabSlab", name);}catch(e){}
   // re-trigger lazy resize for bars if switching to wifi
   if(name==="wifi"){ const el=document.getElementById("sl-air-bars"); if(el && el.innerHTML.trim()==="") refreshSecLab(); }
 }
 function syncOverviewTiles(n, air, prb, bg, sn, u, plus, la, hi, ll, ba, pa, tb){
   try{
     const ovNapt=document.getElementById("ov-napt");
     if(ovNapt) ovNapt.textContent = n.running ? (n.apSsid||"BruceNet")+" ON" : (n.starting ? "STARTING":"OFF");
     const ovNaptBadge=document.getElementById("ov-napt-badge");
     if(ovNaptBadge){ const nb=document.getElementById("sl-napt-badge"); if(nb){ ovNaptBadge.textContent=nb.textContent; ovNaptBadge.className=nb.className; } }
     const ovNaptDetail=document.getElementById("ov-napt-detail");
     if(ovNaptDetail) ovNaptDetail.textContent = `Clients ${(n.clients||[]).length} · Queries ${n.total||0} · Blk ${n.blocked||0}`;
     const ovAir=document.getElementById("ov-air");
     if(ovAir){ const ab=document.getElementById("sl-air-best"); if(ab) ovAir.textContent=ab.textContent; }
     const ovAirDetail=document.getElementById("ov-air-detail");
     if(ovAirDetail){ const chs=(air.channels||[]).length; ovAirDetail.textContent = chs? `${chs} ch scanned · best CH ${air.bestCh||"--"}` : "No scan yet"; }
     const ovProbe=document.getElementById("ov-probe");
     if(ovProbe){ const s=document.getElementById("sl-prb-stat"); const phy=document.getElementById("sl-ble-phy"); ovProbe.textContent=(s? s.textContent:"0 / 0")+" · "+(phy? phy.textContent:"PHY 1M"); }
     const ovProbeDetail=document.getElementById("ov-probe-detail");
     if(ovProbeDetail){ const devs=(prb.devices||[]).length; ovProbeDetail.textContent = `${devs} clusters · BLE ${(bg.mode||"IDLE")}`; }
     const ovLan=document.getElementById("ov-lan");
     if(ovLan){ const el=document.getElementById("sl-plus-lan"); if(el) ovLan.textContent=el.textContent; }
     const ovBle=document.getElementById("ov-ble");
     if(ovBle){ const el=document.getElementById("sl-plus-ble"); let txt=el? el.textContent:"IDLE"; ovBle.textContent=txt; }
     const ovBleDetail=document.getElementById("ov-ble-detail");
     if(ovBleDetail){ ovBleDetail.textContent = `${ba.findings||0} findings · ${(ll.running?"LED ARMED":"LED idle")} · ${pa.verdict||"no pairing"}`; }
     const ovStudio=document.getElementById("ov-studio");
     if(ovStudio){ const idle = (sn.alarm? "ALERT": (sn.armed? "ARMED":"IDLE")); const files=(u.vaultFiles||[]).length; ovStudio.textContent = `${idle} · ${files} files`; }
     const ovStudioDetail=document.getElementById("ov-studio-detail");
     if(ovStudioDetail){ const sig=sn.signal||"--"; ovStudioDetail.textContent=`Signal ${sig} · /usb_vault ${u.flashImgBytes? Math.round(u.flashImgBytes/1024)+"KB img":"no img"}`; }
   }catch(e){ console.warn("syncOverviewTiles",e); }
 }
 document.querySelectorAll("[data-slab]").forEach(btn=>{
   btn.addEventListener("click", ()=> switchSlab(btn.dataset.slab));
 });
 document.querySelectorAll("[data-monslab]").forEach(btn=>{
   btn.addEventListener("click", ()=> switchMonSlab(btn.dataset.monslab));
 });
 document.querySelectorAll("[data-monslab-jump]").forEach(b=>{
   b.addEventListener("click", ()=>{ switchMonSlab(b.dataset.monslabJump); });
 });
 document.querySelectorAll("[data-jump-tab]").forEach(b=>{
   b.addEventListener("click", ()=>{
     const tab=b.dataset.jumpTab, slab=b.dataset.jumpSlab;
     switchTab(tab);
     setTimeout(()=>{ if(slab && tab==="seclab") switchSlab(slab); }, 120);
   });
 });
 document.querySelectorAll(".mon-filter").forEach(btn=>{
   btn.addEventListener("click", ()=>{
     document.querySelectorAll(".mon-filter").forEach(x=>x.classList.remove("active","btn-default"));
     btn.classList.add("active","btn-default");
     monFilter=btn.dataset.filter||"all";
     renderMonitorAlerts(monLastSecLab);
   });
 });
 document.getElementById("mon-alerts-clear")?.addEventListener("click", () => {
   const all = document.querySelector('.mon-filter[data-filter="all"]');
   if (all) all.click();
 });
 document.getElementById("mon-refresh")?.addEventListener("click", ()=> refreshMonitor());
 document.getElementById("mon-auto")?.addEventListener("change", (e)=>{ if(e.target.checked) refreshMonitor(); });
 document.getElementById("mon-net-scan")?.addEventListener("click", async ()=>{
   const box=document.getElementById("mon-net-scanlist");
   if(!box) return;
   box.textContent="Scanning 2.4 GHz...";
   try {
     const data=JSON.parse(await requestGet("/wifiscan"));
     box.replaceChildren();
     const nets=data.nets || [];
     for (const n of nets) {
       const row=document.createElement("div"); row.className="sl-item";
       const info=document.createElement("span");
       info.textContent=`${n.ssid || ""} · CH${n.channel || "?"} ${n.enc ? "🔒" : "🔓"} ${n.rssi}dBm ${n.bssid || ""}`;
       const button=document.createElement("button"); button.type="button"; button.className="sl-tag"; button.textContent="Use";
       button.addEventListener("click", () => openWifiModal(n));
       row.append(info, button); box.appendChild(row);
     }
     if (!nets.length) box.textContent="No APs";
   } catch(e) { box.textContent=`Scan failed: ${e.message}`; }
 });
 document.getElementById("mon-napt-toggle")?.addEventListener("click", async ()=>{
   const state = monLastSecLab?.napt;
   const box = document.getElementById("mon-msg");
   if (!state) { slShowMsg(box, "NAPT status unavailable; refresh first.", false, 0); return; }
   const action = state.running || state.starting ? "stop" : "start";
   await naptPost({action}, box);
   // Refresh without erasing the action result shown in Monitor.
   const cls=box?.className, message=box?.textContent;
   await refreshMonitor();
   if (box && message) { box.className=cls; box.textContent=message; }
 });
 document.getElementById("mon-napt-export")?.addEventListener("click", async ()=>{
   if (await naptPost({action:"export"}, document.getElementById("mon-msg"))) {
     openFileInEditor("LittleFS", "/napt_dns.log");
   }
 });
 (function(){
   let last="overview";
   try{ const v=localStorage.getItem("monitorSlab"); if(v) last=v; }catch(e){}
   const tryApply=()=>{ if(document.getElementById("monslab-overview")){ switchMonSlab(last); } else setTimeout(tryApply, 150); };
   if(document.readyState==="complete") tryApply(); else window.addEventListener("load", tryApply);
   // persist on switch
   const orig=switchMonSlab;
   window.switchMonSlab = function(name){ orig(name); try{ localStorage.setItem("monitorSlab", name);}catch(e){} };
 })();

 document.querySelectorAll("[data-slab-jump]").forEach(b=>{
   b.addEventListener("click", ()=>{ switchSlab(b.dataset.slabJump); document.getElementById("tab-seclab")?.scrollIntoView({behavior:"smooth", block:"start"}); });
 });
 // restore last slab or default overview
 (function(){
   let last="overview";
   try{ const v=localStorage.getItem("seclabSlab"); if(v) last=v; }catch(e){}
   // ensure correct view active after DOM ready
   const check=()=>{ if(document.getElementById("slab-overview")) switchSlab(last); else setTimeout(check, 120); };
   if(document.readyState==="complete") check(); else window.addEventListener("load", check);
 })();
 // when switching main tab to seclab, ensure slab bar visible
 (function(){
   const origSwitchTab = window.switchTab;
   if(typeof origSwitchTab==="function"){
     window.switchTab = function(name){
       origSwitchTab(name);
       if(name==="seclab"){
         // re-apply stored slab
         try{ const s=localStorage.getItem("seclabSlab")||"overview"; switchSlab(s);}catch(e){}
       }
     };
   }
 })();

