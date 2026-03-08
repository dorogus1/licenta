#include "flutter_window.h"
#include "overlay_window.h"
#include "icon_utils.h"

#include <optional>
#include <algorithm>
#include <cctype>
#include <set>
#include <shlobj.h>
#include <shlguid.h>
#include <objbase.h>
#include <filesystem>
#include <flutter/encodable_value.h>

namespace fs = std::filesystem;

// Helper to resolve .lnk files
std::string ResolveShortcut(const std::wstring& shortcutPath) {
    IShellLinkW* psl;
    std::string result = "";
    
    // Initialize COM if not already
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);

    HRESULT hres = CoCreateInstance(CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER, IID_IShellLinkW, (LPVOID*)&psl);
    if (SUCCEEDED(hres)) {
        IPersistFile* ppf;
        hres = psl->QueryInterface(IID_IPersistFile, (LPVOID*)&ppf);
        if (SUCCEEDED(hres)) {
            hres = ppf->Load(shortcutPath.c_str(), STGM_READ);
            if (SUCCEEDED(hres)) {
                wchar_t target[MAX_PATH];
                hres = psl->GetPath(target, MAX_PATH, NULL, SLGP_RAWPATH);
                if (SUCCEEDED(hres)) {
                    // Convert wstring to utf8
                    int size = WideCharToMultiByte(CP_UTF8, 0, target, -1, NULL, 0, NULL, NULL);
                    if (size > 0) {
                        std::string s(size - 1, 0);
                        WideCharToMultiByte(CP_UTF8, 0, target, -1, &s[0], size, NULL, NULL);
                        result = s;
                    }
                }
            }
            ppf->Release();
        }
        psl->Release();
    }
    return result;
}

#include "flutter/generated_plugin_registrant.h"

struct BlockedEvent {
  std::string name;
  uint32_t pid;
  HWND hwnd;
};
const UINT WM_PROCESS_BLOCKED = WM_APP + 1;

static std::string ToLowerCopy(const std::string& s) {
  std::string r = s;
  std::transform(r.begin(), r.end(), r.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return r;
}

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
          flutter::EncodableList out;
          std::vector<std::wstring> startMenuPaths;
          
          // 1. System-wide Start Menu
          wchar_t commonPath[MAX_PATH];
          if (SHGetSpecialFolderPathW(NULL, commonPath, CSIDL_COMMON_PROGRAMS, FALSE)) {
            startMenuPaths.push_back(commonPath);
          }
          // 2. User-specific Start Menu
          wchar_t userPath[MAX_PATH];
          if (SHGetSpecialFolderPathW(NULL, userPath, CSIDL_PROGRAMS, FALSE)) {
            startMenuPaths.push_back(userPath);
          }

          std::set<std::string> seenExes;

          for (const auto& basePath : startMenuPaths) {
            try {
              for (const auto& entry : fs::recursive_directory_iterator(basePath)) {
                if (entry.is_regular_file() && entry.path().extension() == ".lnk") {
                  std::string targetExe = ResolveShortcut(entry.path().wstring());
                  if (targetExe.empty() || targetExe.find(".exe") == std::string::npos) continue;

                  std::string exeName = fs::path(targetExe).filename().string();
                  std::string displayName = entry.path().stem().string();

                  // Avoid duplicates
                  if (seenExes.count(ToLowerCopy(exeName))) continue;
                  seenExes.insert(ToLowerCopy(exeName));

                  flutter::EncodableMap m;
                  m[flutter::EncodableValue("name")] = flutter::EncodableValue(displayName);
                  m[flutter::EncodableValue("id")] = flutter::EncodableValue(displayName);
                  m[flutter::EncodableValue("exe")] = flutter::EncodableValue(exeName);
                  
                  // Extract icon from the target exe
                  std::string base64Icon = ExtractIconAsPngBase64(targetExe);
                  m[flutter::EncodableValue("iconData")] = flutter::EncodableValue(base64Icon);

                  out.push_back(m);
                }
              }
            } catch (...) {}
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
        } else if (method == "forceToForeground") {
          HWND hwnd = GetHandle();
          if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
          SetForegroundWindow(hwnd);
          SetFocus(hwnd);
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
