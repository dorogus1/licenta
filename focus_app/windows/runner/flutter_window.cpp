#include "flutter_window.h"
#include "overlay_window.h"
#include "icon_utils.h"

#include <optional>
#include <flutter/encodable_value.h>

#include "flutter/generated_plugin_registrant.h"

struct BlockedEvent {
  std::string name;
  uint32_t pid;
  HWND hwnd;
};
const UINT WM_PROCESS_BLOCKED = WM_APP + 1;

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::OnBlocked(const std::string& name, uint32_t pid, HWND hwnd) {
  if (GetCurrentThreadId() != GetWindowThreadProcessId(GetHandle(), NULL)) {
    // We are on a background thread. Post message to main thread.
    BlockedEvent* evt = new BlockedEvent{name, pid, hwnd};
    PostMessage(GetHandle(), WM_PROCESS_BLOCKED, 0, (LPARAM)evt);
    return;
  }

  // Main thread logic
  if (overlay_window_) overlay_window_->ShowOver(hwnd, name);
  if (method_channel_) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("name")] = flutter::EncodableValue(name);
    m[flutter::EncodableValue("pid")] = flutter::EncodableValue(static_cast<int>(pid));
    method_channel_->InvokeMethod("onBlocked", std::make_unique<flutter::EncodableValue>(m));
  }
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  // Initialize process monitor and MethodChannel for communication with Dart.
  process_monitor_ = std::make_unique<ProcessMonitor>();
  overlay_window_ = std::make_unique<OverlayWindow>();
  process_monitor_->SetBlockedCallback([this](const std::string& name, uint32_t pid, HWND hwnd) {
    this->OnBlocked(name, pid, hwnd);
  });
  method_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "focus_app/process_monitor",
      &flutter::StandardMethodCodec::GetInstance());

  std::function<void(const flutter::MethodCall<flutter::EncodableValue>&, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>)> handler =
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const std::string& method = call.method_name();
        if (method == "getRunningProcesses") {
          auto procs = process_monitor_->GetRunningProcesses();
          flutter::EncodableList list;
          for (auto &p : procs) {
            flutter::EncodableMap m;
            m[flutter::EncodableValue("name")] = flutter::EncodableValue(p.first);
            m[flutter::EncodableValue("pid")] = flutter::EncodableValue(static_cast<int>(p.second));
            list.push_back(m);
          }
          result->Success(flutter::EncodableValue(list));
        } else if (method == "startMonitor") {
          process_monitor_->Start();
          result->Success();
        } else if (method == "stopMonitor") {
          process_monitor_->Stop();
          if (overlay_window_) overlay_window_->Hide();
          result->Success();
        } else if (method == "getInstalledApps") {
          // enumerate uninstall registry keys (Unicode API + UTF-8 conversion)
          auto WideToUtf8 = [](const std::wstring& w) -> std::string {
            if (w.empty()) return {};
            int size = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), NULL, 0, NULL, NULL);
            if (size <= 0) return {};
            std::string s(size, 0);
            WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), &s[0], size, NULL, NULL);
            return s;
          };

          flutter::EncodableList out;
          HKEY roots[2] = {HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER};
          const wchar_t* paths[] = {L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
                                    L"SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall"};
          for (auto rk : roots) {
            for (auto path : paths) {
              HKEY h;
              if (RegOpenKeyExW(rk, path, 0, KEY_READ, &h) == ERROR_SUCCESS) {
                wchar_t sub[256];
                DWORD idx = 0;
                DWORD subSize = (DWORD)(sizeof(sub)/sizeof(wchar_t));
                while (RegEnumKeyExW(h, idx++, sub, &subSize, NULL, NULL, NULL, NULL) == ERROR_SUCCESS) {
                  HKEY s;
                  if (RegOpenKeyExW(h, sub, 0, KEY_READ, &s) == ERROR_SUCCESS) {
                    wchar_t namew[512] = {0};
                    DWORD size = sizeof(namew);
                    if (RegQueryValueExW(s, L"DisplayName", NULL, NULL, (LPBYTE)namew, &size) == ERROR_SUCCESS && namew[0]) {
                      wchar_t iconw[512] = {0};
                      size = sizeof(iconw);
                      RegQueryValueExW(s, L"DisplayIcon", NULL, NULL, (LPBYTE)iconw, &size);
                      // try to extract executable name from DisplayIcon
                      std::string exeName;
                      std::string iconStrUtf;
                      if (iconw[0]) {
                        iconStrUtf = WideToUtf8(std::wstring(iconw));
                        auto comma = iconStrUtf.find(',');
                        if (comma != std::string::npos) iconStrUtf = iconStrUtf.substr(0, comma);
                        if (!iconStrUtf.empty() && (iconStrUtf.front() == '"' || iconStrUtf.front() == '\'')) iconStrUtf = iconStrUtf.substr(1);
                        if (!iconStrUtf.empty() && (iconStrUtf.back() == '"' || iconStrUtf.back() == '\'')) iconStrUtf.pop_back();
                        auto pos = iconStrUtf.find_last_of("\\/");
                        exeName = (pos == std::string::npos) ? iconStrUtf : iconStrUtf.substr(pos + 1);
                      }
                      
                      // Fix: If the extracted exeName is just an .ico file, it's not the process name.
                      if (exeName.size() >= 4 && exeName.substr(exeName.size() - 4) == ".ico") {
                        exeName = ""; 
                      }

                      flutter::EncodableMap m;
                      std::string nameUtf = WideToUtf8(std::wstring(namew));
                      m[flutter::EncodableValue("name")] = flutter::EncodableValue(nameUtf);
                      m[flutter::EncodableValue("id")] = flutter::EncodableValue(nameUtf);
                      m[flutter::EncodableValue("exe")] = flutter::EncodableValue(exeName);
                      m[flutter::EncodableValue("icon")] = flutter::EncodableValue(iconStrUtf);
                      
                      // Extract icon
                      std::string iconPath = exeName.empty() ? iconStrUtf : exeName;
                      // if exeName is just filename, prefer full path from iconStrUtf if valid
                      if (iconStrUtf.find(":\\") != std::string::npos) iconPath = iconStrUtf;
                      
                      std::string base64Icon = ExtractIconAsPngBase64(iconPath);
                      m[flutter::EncodableValue("iconData")] = flutter::EncodableValue(base64Icon);

                      out.push_back(m);
                    }
                    RegCloseKey(s);
                  }
                  // reset subSize for next iteration
                  subSize = (DWORD)(sizeof(sub)/sizeof(wchar_t));
                }
                RegCloseKey(h);
              }
            }
          }
          result->Success(flutter::EncodableValue(out));
        } else if (method == "setBlockList") {
          std::vector<std::string> list;
          const flutter::EncodableValue* args = call.arguments();
          if (args && std::holds_alternative<flutter::EncodableList>(*args)) {
            const auto& arr = std::get<flutter::EncodableList>(*args);
            for (const auto& v : arr) {
              if (std::holds_alternative<std::string>(v)) {
                list.push_back(std::get<std::string>(v));
              }
            }
          }
          process_monitor_->SetBlockList(list);
          result->Success();
        } else if (method == "isRunning") {
          result->Success(flutter::EncodableValue(process_monitor_->IsRunning()));
        } else if (method == "getForegroundApp") {
          HWND hwnd = GetForegroundWindow();
          DWORD pid = 0;
          GetWindowThreadProcessId(hwnd, &pid);
          std::string exeName;
          HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, FALSE, pid);
          if (h) {
            char buffer[MAX_PATH] = {0};
            DWORD size = MAX_PATH;
            if (QueryFullProcessImageNameA(h, 0, buffer, &size)) {
              std::string full(buffer);
              auto pos = full.find_last_of("\\/");
              exeName = (pos == std::string::npos) ? full : full.substr(pos + 1);
            }
            CloseHandle(h);
          }
          flutter::EncodableMap m;
          m[flutter::EncodableValue("exe")] = flutter::EncodableValue(exeName);
          m[flutter::EncodableValue("pid")] = flutter::EncodableValue(static_cast<int>(pid));
          result->Success(flutter::EncodableValue(m));
        } else {
          result->NotImplemented();
        }
      };

  method_channel_->SetMethodCallHandler(handler);

  return true;
}

void FlutterWindow::OnDestroy() {
  if (method_channel_) {
    method_channel_.reset();
  }
  if (process_monitor_) {
    process_monitor_->Stop();
    process_monitor_.reset();
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_PROCESS_BLOCKED: {
      BlockedEvent* evt = reinterpret_cast<BlockedEvent*>(lparam);
      if (evt) {
        OnBlocked(evt->name, evt->pid, evt->hwnd);
        delete evt;
      }
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
