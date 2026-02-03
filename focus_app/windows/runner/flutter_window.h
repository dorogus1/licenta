#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "win32_window.h"
#include "process_monitor.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;
  
  void OnBlocked(const std::string& name, uint32_t pid, HWND hwnd); // Helper

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Process monitor for blocking apps on Windows.
  std::unique_ptr<ProcessMonitor> process_monitor_;
  std::unique_ptr<class OverlayWindow> overlay_window_;

  // MethodChannel to communicate with Dart code.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
