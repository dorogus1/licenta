#include "overlay_window.h"
#include "resource.h"
#include <string>
#include <dwmapi.h>

#pragma comment(lib, "dwmapi.lib")

#define TIMER_SYNC_ID 1

OverlayWindow::OverlayWindow() {}

OverlayWindow::~OverlayWindow() { Hide(); }

void OverlayWindow::ShowOver(HWND target, const std::string& appName) {
  if (!IsWindow(target)) return;
  appName_ = appName;
  target_ = target;

  RECT r;
  GetWindowRect(target, &r);
  int w = r.right - r.left;
  int h = r.bottom - r.top;

  if (!hwnd_) {
    WNDCLASSEXW wc = {0};
    wc.cbSize = sizeof(WNDCLASSEXW);
    wc.lpfnWndProc = OverlayWindow::WndProc;
    wc.hInstance = GetModuleHandle(NULL);
    wc.lpszClassName = L"FocusAppOverlay";
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    RegisterClassExW(&wc);

    // Removed WS_EX_TOPMOST to allow other apps to go over the overlay
    hwnd_ = CreateWindowExW(WS_EX_LAYERED,
                             L"FocusAppOverlay", L"Focus Shield",
                             WS_POPUP,
                             r.left, r.top, w, h,
                             NULL, NULL, GetModuleHandle(NULL), this);

    DWM_WINDOW_CORNER_PREFERENCE cornerPreference = DWMWCP_ROUND;
    DwmSetWindowAttribute(hwnd_, DWMWA_WINDOW_CORNER_PREFERENCE, &cornerPreference, sizeof(cornerPreference));

    SetLayeredWindowAttributes(hwnd_, 0, 245, LWA_ALPHA);
    
    // Set the target app window as the owner of our overlay.
    // This makes the overlay always stay on top of the target window in Z-order.
    SetWindowLongPtr(hwnd_, GWLP_HWNDPARENT, (LONG_PTR)target);

    SetTimer(hwnd_, TIMER_SYNC_ID, 50, NULL);
  } else {
    // Ensure the owner is updated if we reuse the window for a different target
    if ((HWND)GetWindowLongPtr(hwnd_, GWLP_HWNDPARENT) != target) {
        SetWindowLongPtr(hwnd_, GWLP_HWNDPARENT, (LONG_PTR)target);
    }
    SetWindowPos(hwnd_, NULL, r.left, r.top, w, h, SWP_NOZORDER | SWP_SHOWWINDOW | SWP_NOACTIVATE);
  }

  ShowWindow(hwnd_, SW_SHOW);
  UpdateWindow(hwnd_);
}

void OverlayWindow::Hide() {
  if (hwnd_) {
    KillTimer(hwnd_, TIMER_SYNC_ID);
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
    target_ = nullptr;
  }
}

bool OverlayWindow::IsVisible() const { return hwnd_ && IsWindow(hwnd_); }

LRESULT CALLBACK OverlayWindow::WndProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
  auto inst = (OverlayWindow*)GetWindowLongPtrW(hwnd, GWLP_USERDATA);

  switch (uMsg) {
    case WM_CREATE: {
      CREATESTRUCTW* cs = (CREATESTRUCTW*)lParam;
      SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)cs->lpCreateParams);
      return 0;
    }

    case WM_TIMER: {
      if (wParam == TIMER_SYNC_ID && inst && inst->target_) {
        if (!IsWindow(inst->target_)) {
            inst->Hide();
            return 0;
        }
        
        // If target is minimized, hide overlay, otherwise show it
        if (IsIconic(inst->target_)) {
            if (IsWindowVisible(hwnd)) ShowWindow(hwnd, SW_HIDE);
            return 0;
        } else {
            if (!IsWindowVisible(hwnd)) ShowWindow(hwnd, SW_SHOWNA);
        }

        RECT r;
        if (GetWindowRect(inst->target_, &r)) {
            int w = r.right - r.left;
            int h = r.bottom - r.top;
            
            RECT current;
            GetWindowRect(hwnd, &current);
            if (current.left != r.left || current.top != r.top || 
                (current.right - current.left) != w || (current.bottom - current.top) != h) {
              SetWindowPos(hwnd, NULL, r.left, r.top, w, h, SWP_NOZORDER | SWP_NOACTIVATE);
              InvalidateRect(hwnd, NULL, FALSE);
            }
        }
      }
      return 0;
    }

    case WM_LBUTTONDOWN: {
      int x = LOWORD(lParam);
      int y = HIWORD(lParam);
      RECT r;
      GetClientRect(hwnd, &r);
      
      // Close button (X) in top right
      if (x > r.right - 60 && y < 60) {
        if (inst && inst->target_) {
          DWORD pid = 0;
          GetWindowThreadProcessId(inst->target_, &pid);
          HANDLE h = OpenProcess(PROCESS_TERMINATE, FALSE, pid);
          if (h) {
            TerminateProcess(h, 1);
            CloseHandle(h);
          }
          inst->Hide();
        }
      }

      // "BACK TO FOCUS" button at the bottom
      int centerX = r.right / 2;
      RECT btnRect = {centerX - 120, r.bottom - 100, centerX + 120, r.bottom - 40};
      if (x >= btnRect.left && x <= btnRect.right && y >= btnRect.top && y <= btnRect.bottom) {
          if (inst && inst->target_) {
              DWORD pid = 0;
              GetWindowThreadProcessId(inst->target_, &pid);
              HANDLE h = OpenProcess(PROCESS_TERMINATE, FALSE, pid);
              if (h) {
                TerminateProcess(h, 1);
                CloseHandle(h);
              }
              inst->Hide();
          }
      }
      return 0;
    }

    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC dc = BeginPaint(hwnd, &ps);
      RECT r;
      GetClientRect(hwnd, &r);
      
      HDC memDC = CreateCompatibleDC(dc);
      HBITMAP memBM = CreateCompatibleBitmap(dc, r.right, r.bottom);
      SelectObject(memDC, memBM);

      // Background - elegant dark grey
      HBRUSH bgBrush = CreateSolidBrush(RGB(20, 20, 25));
      FillRect(memDC, &r, bgBrush);
      DeleteObject(bgBrush);

      // Accent top bar
      RECT borderRect = {0, 0, r.right, 6};
      HBRUSH accentBrush = CreateSolidBrush(RGB(108, 99, 255));
      FillRect(memDC, &borderRect, accentBrush);
      DeleteObject(accentBrush);

      SetBkMode(memDC, TRANSPARENT);
      
      // Draw "X" button
      SetTextColor(memDC, RGB(100, 100, 120));
      HFONT hFontX = CreateFontW(22, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
      SelectObject(memDC, hFontX);
      RECT xRect = {r.right - 50, 15, r.right - 15, 50};
      DrawTextW(memDC, L"\x2715", -1, &xRect, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
      DeleteObject(hFontX);

      int centerX = r.right / 2;
      int centerY = r.bottom / 2;

      // Draw Icon
      HICON hIcon = (HICON)LoadImageW(GetModuleHandle(NULL), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON, 96, 96, LR_DEFAULTCOLOR);
      if (hIcon) {
          DrawIconEx(memDC, centerX - 48, centerY - 160, hIcon, 96, 96, 0, NULL, DI_NORMAL);
          DestroyIcon(hIcon);
      }

      // Title
      SetTextColor(memDC, RGB(255, 255, 255));
      HFONT hFontTitle = CreateFontW(42, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
      SelectObject(memDC, hFontTitle);
      RECT titleRect = {40, centerY - 40, r.right - 40, centerY + 20};
      DrawTextW(memDC, L"Moment de concentrare", -1, &titleRect, DT_CENTER | DT_SINGLELINE);
      DeleteObject(hFontTitle);

      // Subtitle
      SetTextColor(memDC, RGB(180, 180, 190));
      HFONT hFontSub = CreateFontW(22, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
      SelectObject(memDC, hFontSub);
      RECT textRect = {centerX - 300, centerY + 30, centerX + 300, r.bottom - 120};
      DrawTextW(memDC, L"Ai ales s\x0103 blochezi aceast\x0103 aplica\x021Bie pentru a-\x021Bi atinge obiectivele \x0219i a r\x0103m\x00E2ne productiv.", -1, &textRect, DT_CENTER | DT_WORDBREAK);
      DeleteObject(hFontSub);

      // "BACK TO FOCUS" Button
      RECT btnRect = {centerX - 120, r.bottom - 100, centerX + 120, r.bottom - 40};
      
      // Button Background
      HBRUSH btnBrush = CreateSolidBrush(RGB(108, 99, 255));
      SelectObject(memDC, btnBrush);
      HPEN hPen = CreatePen(PS_SOLID, 1, RGB(108, 99, 255));
      SelectObject(memDC, hPen);
      RoundRect(memDC, btnRect.left, btnRect.top, btnRect.right, btnRect.bottom, 20, 20);
      DeleteObject(btnBrush);
      DeleteObject(hPen);

      // Button Text
      SetTextColor(memDC, RGB(255, 255, 255));
      HFONT hFontBtn = CreateFontW(20, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
      SelectObject(memDC, hFontBtn);
      DrawTextW(memDC, L"\x00CENAPOI LA LUCRU", -1, &btnRect, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
      DeleteObject(hFontBtn);

      BitBlt(dc, 0, 0, r.right, r.bottom, memDC, 0, 0, SRCCOPY);
      DeleteObject(memBM);
      DeleteDC(memDC);
      EndPaint(hwnd, &ps);
      return 0;
    }
  }
  return DefWindowProcW(hwnd, uMsg, wParam, lParam);
}
