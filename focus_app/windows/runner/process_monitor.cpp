#include "process_monitor.h"
#include <windows.h>
#include <tlhelp32.h>
#include <psapi.h>
#include <algorithm>
#include <locale>
#include <vector>
#include <sstream>
#include <map>

static ProcessMonitor* g_instance = nullptr; // single-instance helper for WinEvent hook

static void CALLBACK WinEventProc(HWINEVENTHOOK hWinEventHook, DWORD event, HWND hwnd,
                                  LONG idObject, LONG idChild, DWORD dwEventThread, DWORD dwmsEventTime) {
  if (!g_instance) return;
  if (event == EVENT_SYSTEM_FOREGROUND && hwnd != NULL) {
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    char exeName[MAX_PATH] = {0};
    HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (h) {
      DWORD size = MAX_PATH;
      if (QueryFullProcessImageNameA(h, 0, exeName, &size)) {
        // extract filename
        std::string full(exeName);
        auto pos = full.find_last_of("\\/");
        std::string name = pos == std::string::npos ? full : full.substr(pos + 1);
        g_instance->HandleForegroundChange(name, pid, hwnd);
      }
      CloseHandle(h);
    }
  }
}

static std::string ToLowerCopy(const std::string& s) {
  std::string r = s;
  std::transform(r.begin(), r.end(), r.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return r;
}

static std::string WstringToUtf8(const std::wstring& w) {
  if (w.empty()) return {};
  int size_needed = ::WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), NULL, 0, NULL, NULL);
  std::string strTo(size_needed, 0);
  ::WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), &strTo[0], size_needed, NULL, NULL);
  return strTo;
}

ProcessMonitor::ProcessMonitor() : running_(false) {
  // Set global pointer for hook usage
  g_instance = this;
}

ProcessMonitor::~ProcessMonitor() {
  Stop();
  if (g_instance == this) g_instance = nullptr;
}

std::vector<std::pair<std::string, uint32_t>> ProcessMonitor::GetRunningProcesses() {
  std::vector<std::pair<std::string, uint32_t>> result;
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return result;

  PROCESSENTRY32W entry;
  entry.dwSize = sizeof(entry);
  if (Process32FirstW(snapshot, &entry)) {
    do {
      std::string name = WstringToUtf8(entry.szExeFile);
      result.emplace_back(name, entry.th32ProcessID);
    } while (Process32NextW(snapshot, &entry));
  }
  CloseHandle(snapshot);
  return result;
}

void ProcessMonitor::SetBlockList(const std::vector<std::string>& list) {
  std::lock_guard<std::mutex> lock(mutex_);
  block_list_.clear();
  std::ostringstream oss;
  oss << "SetBlockList: " << list.size() << " entries: ";
  for (const auto& v : list) {
    std::string l = ToLowerCopy(v);
    block_list_.push_back(l);
    // also add with/without .exe variations for robustness
    if (l.size() > 4 && l.substr(l.size()-4) == ".exe") {
      block_list_.push_back(l.substr(0, l.size()-4));
    } else {
      block_list_.push_back(l + ".exe");
    }
    oss << "[" << l << "] ";
  }
  OutputDebugStringA(oss.str().c_str());
}

void ProcessMonitor::Start() {
  bool expected = false;
  if (!running_.compare_exchange_strong(expected, true)) return; // already running
  OutputDebugStringA("ProcessMonitor: Start()");
  // Install WinEvent hook to monitor foreground window changes
  event_hook_ = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
                                NULL, WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
  // Start a light-weight thread to keep the running flag alive and optionally poll
  thread_ = std::thread([this]() { MonitorLoop(); });
}

void ProcessMonitor::Stop() {
  bool expected = true;
  if (!running_.compare_exchange_strong(expected, false)) return; // not running
  OutputDebugStringA("ProcessMonitor: Stop()");
  if (event_hook_) {
    UnhookWinEvent(event_hook_);
    event_hook_ = nullptr;
  }
  if (thread_.joinable()) thread_.join();
}

bool ProcessMonitor::IsRunning() const { return running_.load(); }

void ProcessMonitor::SetBlockedCallback(BlockedCallback cb) { blocked_cb_ = cb; }

void ProcessMonitor::ScanAndBlock() {
  // 1. Snapshot all processes
  HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (hSnapshot == INVALID_HANDLE_VALUE) return;

  struct PInfo {
    std::string name;
    DWORD ppid;
  };
  std::map<DWORD, PInfo> processes;

  PROCESSENTRY32W pe;
  pe.dwSize = sizeof(pe);
  if (Process32FirstW(hSnapshot, &pe)) {
    do {
      processes[pe.th32ProcessID] = {WstringToUtf8(pe.szExeFile), pe.th32ParentProcessID};
    } while (Process32NextW(hSnapshot, &pe));
  }
  CloseHandle(hSnapshot);

  // 2. Map PIDs to Visible Windows (optimization: enumerate once)
  std::map<DWORD, HWND> pidToWindow;
  EnumWindows([](HWND hwnd, LPARAM lParam) -> BOOL {
    auto* map = (std::map<DWORD, HWND>*)lParam;
    DWORD wpid;
    GetWindowThreadProcessId(hwnd, &wpid);
    if (IsWindowVisible(hwnd) && map->find(wpid) == map->end()) {
      (*map)[wpid] = hwnd;
    }
    return TRUE;
  }, (LPARAM)&pidToWindow);

  // 3. Check blocks with ancestry
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (block_list_.empty()) return;

    for (const auto& kv : processes) {
      DWORD pid = kv.first;
      const auto& info = kv.second;
      
      // If we don't have a visible window for this process, skip blocking it via overlay?
      // Or should we block it anyway? The overlay needs a window. 
      // If it's a background process, we can't show overlay over it.
      // But maybe we want to close it? For now, we only support overlay.
      auto wit = pidToWindow.find(pid);
      if (wit == pidToWindow.end()) continue;
      HWND hwnd = wit->second;

      bool blocked = false;

      // Check self
      std::string n = ToLowerCopy(info.name);
      for (const auto& b : block_list_) {
        if (n == b || n.find(b) != std::string::npos) {
          blocked = true;
          break;
        }
      }

      // Check ancestry
      if (!blocked) {
        DWORD currentPid = info.ppid;
        int depth = 0;
        while (currentPid != 0 && depth < 5) {
          auto it = processes.find(currentPid);
          if (it == processes.end()) break;
          
          std::string pName = ToLowerCopy(it->second.name);
          for (const auto& b : block_list_) {
            if (pName == b || pName.find(b) != std::string::npos) {
              blocked = true;
              break;
            }
          }
          if (blocked) break;
          currentPid = it->second.ppid;
          depth++;
        }
      }

      if (blocked) {
        ShowWindow(hwnd, SW_HIDE);
        // OutputDebugStringA(("ProcessMonitor: Polling Block -> " + info.name).c_str());
        if (blocked_cb_) blocked_cb_(info.name, pid, hwnd);
      }
    }
  }
}

void ProcessMonitor::MonitorLoop() {
  while (running_) {
    ScanAndBlock();
    ::Sleep(1000);
  }
}

// Helper to get Parent PID
static DWORD GetParentPid(DWORD pid) {
  HANDLE h = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (h == INVALID_HANDLE_VALUE) return 0;

  PROCESSENTRY32W pe = {0};
  pe.dwSize = sizeof(pe);
  DWORD ppid = 0;

  if (Process32FirstW(h, &pe)) {
    do {
      if (pe.th32ProcessID == pid) {
        ppid = pe.th32ParentProcessID;
        break;
      }
    } while (Process32NextW(h, &pe));
  }
  CloseHandle(h);
  return ppid;
}

// Helper to get Process Name by PID
static std::string GetProcessNameByPid(DWORD pid) {
  if (pid == 0) return "";
  char exeName[MAX_PATH] = {0};
  HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, FALSE, pid);
  if (h) {
    DWORD size = MAX_PATH;
    if (QueryFullProcessImageNameA(h, 0, exeName, &size)) {
      std::string full(exeName);
      auto pos = full.find_last_of("\\/");
      std::string name = pos == std::string::npos ? full : full.substr(pos + 1);
      CloseHandle(h);
      return name;
    }
    CloseHandle(h);
  }
  return "";
}

void ProcessMonitor::HandleForegroundChange(const std::string& procName, uint32_t pid, HWND hwnd) {
  std::lock_guard<std::mutex> lock(mutex_);
  
  // Lambda to check if a single name is blocked
  auto isBlocked = [&](const std::string& name) -> bool {
    std::string n = ToLowerCopy(name);
    for (const auto& blocked : block_list_) {
      if (n == blocked || n.find(blocked) != std::string::npos) {
        return true;
      }
    }
    return false;
  };

  // 1. Check current process
  if (isBlocked(procName)) {
    OutputDebugStringA(("ProcessMonitor: Direct Block -> " + procName).c_str());
    ShowWindow(hwnd, SW_HIDE);
    if (blocked_cb_) blocked_cb_(procName, pid, hwnd);
    return;
  }

  // 2. Check Ancestry (Parent -> Grandparent -> ...)
  // Deep check (up to 5 levels) to catch children of launchers (Steam, Riot, etc.)
  DWORD currentPid = pid;
  for (int i = 0; i < 5; i++) { 
    DWORD ppid = GetParentPid(currentPid);
    if (ppid == 0 || ppid == 4) break; // 4 is System process
    
    std::string pName = GetProcessNameByPid(ppid);
    if (pName.empty()) break;

    if (isBlocked(pName)) {
      OutputDebugStringA(("ProcessMonitor: Ancestry Block (Ancestor: " + pName + ") -> " + procName).c_str());
      ShowWindow(hwnd, SW_HIDE);
      if (blocked_cb_) blocked_cb_(procName, pid, hwnd);
      return;
    }
    currentPid = ppid;
  }
}