#pragma once

#include <windows.h>
#include <string>
#include <vector>
#include <thread>
#include <mutex>
#include <atomic>
#include <functional>

class ProcessMonitor {
 public:
  using BlockedCallback = std::function<void(const std::string& name, uint32_t pid, HWND hwnd)>;

  ProcessMonitor();
  ~ProcessMonitor();

  // Return list of running processes as pair(name, pid)
  std::vector<std::pair<std::string, uint32_t>> GetRunningProcesses();

  // Set list of blocked executables (exact match, case-insensitive)
  void SetBlockList(const std::vector<std::string>& list);

  // Start/stop the background monitor
  void Start();
  void Stop();
  bool IsRunning() const;

  // Optional callback when a process is terminated
  void SetBlockedCallback(BlockedCallback cb);

  // Called by WinEventProc when foreground changes
  void HandleForegroundChange(const std::string& procName, uint32_t pid, HWND hwnd);

 private:
  void MonitorLoop();
  void ScanAndBlock();

  std::thread thread_;
  std::mutex mutex_;
  std::atomic<bool> running_;
  std::vector<std::string> block_list_;
  BlockedCallback blocked_cb_;
  HWINEVENTHOOK event_hook_ = nullptr;
};
