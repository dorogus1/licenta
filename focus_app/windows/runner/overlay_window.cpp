#include "overlay_window.h"
#include <string>
#include <dwmapi.h>

#pragma comment(lib, "dwmapi.lib")

OverlayWindow::OverlayWindow() {}

OverlayWindow::~OverlayWindow() { Hide(); }

void OverlayWindow::ShowOver(HWND target, const std::string& appName) {
  if (!IsWindow(target)) return;
  appName_ = appName;
  target_ = target;
  if (!hwnd_) {
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = OverlayWindow::WndProc;
    wc.hInstance = GetModuleHandle(NULL);
    wc.lpszClassName = "FocusAppOverlay";
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    RegisterClassA(&wc);

    int screenWidth = GetSystemMetrics(SM_CXSCREEN);
    int screenHeight = GetSystemMetrics(SM_CYSCREEN);
    int w = 450;
    int h = 280;
    int x = (screenWidth - w) / 2;
    int y = (screenHeight - h) / 2;

    hwnd_ = CreateWindowExA(WS_EX_TOPMOST | WS_EX_LAYERED,
                             "FocusAppOverlay", "Focus Shield",
                             WS_POPUP,
                             x, y, w, h,
                             NULL, NULL, GetModuleHandle(NULL), this);

    DWM_WINDOW_CORNER_PREFERENCE cornerPreference = DWMWCP_ROUND;
    DwmSetWindowAttribute(hwnd_, DWMWA_WINDOW_CORNER_PREFERENCE, &cornerPreference, sizeof(cornerPreference));

    SetLayeredWindowAttributes(hwnd_, 0, 250, LWA_ALPHA);
  }

  ShowWindow(hwnd_, SW_SHOW);
  UpdateWindow(hwnd_);
  SetForegroundWindow(hwnd_);
}

void OverlayWindow::Hide() {
  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
    target_ = nullptr;
  }
}

bool OverlayWindow::IsVisible() const { return hwnd_ && IsWindow(hwnd_); }

LRESULT CALLBACK OverlayWindow::WndProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
  if (uMsg == WM_CREATE) {
    CREATESTRUCTA* cs = (CREATESTRUCTA*)lParam;
    SetWindowLongPtrA(hwnd, GWLP_USERDATA, (LONG_PTR)cs->lpCreateParams);
    return 0;
  }
  
  auto inst = (OverlayWindow*)GetWindowLongPtrA(hwnd, GWLP_USERDATA);

  if (uMsg == WM_LBUTTONDOWN) {
    int x = LOWORD(lParam);
    int y = HIWORD(lParam);
    RECT r;
    GetClientRect(hwnd, &r);
    // Custom Close Button Hit Test (Top Right)
    if (x > r.right - 45 && y < 45) {
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

  if (uMsg == WM_PAINT) {
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(hwnd, &ps);
    RECT r;
    GetClientRect(hwnd, &r);
    
    // 1. Modern Dark Background
    HBRUSH bgBrush = CreateSolidBrush(RGB(20, 20, 25));
    FillRect(dc, &r, bgBrush);
    DeleteObject(bgBrush);

    // 2. Accent Top Border
    RECT borderRect = {0, 0, r.right, 4};
    HBRUSH accentBrush = CreateSolidBrush(RGB(108, 99, 255)); // Indigo Accent
    FillRect(dc, &borderRect, accentBrush);
    DeleteObject(accentBrush);

    // 3. Custom Close Button (X)
    SetTextColor(dc, RGB(150, 150, 150));
    SetBkMode(dc, TRANSPARENT);
    HFONT hFontX = CreateFontA(20, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 0, 0, 0, 0, "Segoe MDL2 Assets");
    if (!hFontX) hFontX = CreateFontA(18, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 0, 0, 0, 0, "Arial");
    SelectObject(dc, hFontX);
    TextOutA(dc, r.right - 30, 15, "X", 1);
    DeleteObject(hFontX);

    // 4. Shield Icon (Simple GDI Drawing)
    HPEN hIconPen = CreatePen(PS_SOLID, 3, RGB(108, 99, 255));
    SelectObject(dc, hIconPen);
    MoveToEx(dc, r.right / 2 - 20, 40, NULL);
    LineTo(dc, r.right / 2 + 20, 40);
    LineTo(dc, r.right / 2 + 20, 60);
    LineTo(dc, r.right / 2, 80);
    LineTo(dc, r.right / 2 - 20, 60);
    LineTo(dc, r.right / 2 - 20, 40);
    DeleteObject(hIconPen);

    // 5. Main Title
    SetTextColor(dc, RGB(255, 255, 255));
    HFONT hFontTitle = CreateFontA(26, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 0, 0, PROOF_QUALITY, 0, "Segoe UI");
    SelectObject(dc, hFontTitle);
    RECT titleRect = {40, 100, r.right - 40, 140};
    DrawTextA(dc, "Timpul tău este prețios!", -1, &titleRect, DT_CENTER | DT_SINGLELINE);
    DeleteObject(hFontTitle);

    // 6. Description Text
    SetTextColor(dc, RGB(180, 180, 190));
    HFONT hFontSub = CreateFontA(18, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 0, 0, PROOF_QUALITY, 0, "Segoe UI");
    SelectObject(dc, hFontSub);
    RECT textRect = {50, 150, r.right - 50, 240};
    DrawTextA(dc, "Această aplicație a fost blocată pentru a te ajuta să rămâi productiv și concentrat pe ceea ce contează cu adevărat.", -1, &textRect, DT_CENTER | DT_WORDBREAK);
    DeleteObject(hFontSub);

    EndPaint(hwnd, &ps);
    return 0;
  }
  return DefWindowProcA(hwnd, uMsg, wParam, lParam);
}
