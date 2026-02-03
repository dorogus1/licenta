#pragma once
#include <windows.h>
#include <string>

class OverlayWindow {
 public:
  OverlayWindow();
  ~OverlayWindow();

  // Show overlay over target window (topmost) and update with app name
  void ShowOver(HWND target, const std::string& appName);
  void Hide();
  bool IsVisible() const;

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam);
  HWND hwnd_ = nullptr;
  HWND target_ = nullptr;
  std::string appName_;
};
