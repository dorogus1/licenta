#include "overlay_window.h"
#include "resource.h"
#include <string>
#include <dwmapi.h>

#pragma comment(lib, "dwmapi.lib")

OverlayWindow::OverlayWindow() {}

OverlayWindow::~OverlayWindow() { Hide(); }

void OverlayWindow::ShowOver(HWND target, const std::string& appName) {
  if (!IsWindow(target)) return;
  appName_ = appName;
  target_ = target;

  int w = 480;
  int h = 320;
  int x, y;

  RECT targetRect;
  if (GetWindowRect(target, &targetRect)) {
    x = targetRect.left + (targetRect.right - targetRect.left - w) / 2;
    y = targetRect.top + (targetRect.bottom - targetRect.top - h) / 2;
  } else {
    int screenWidth = GetSystemMetrics(SM_CXSCREEN);
    int screenHeight = GetSystemMetrics(SM_CYSCREEN);
    x = (screenWidth - w) / 2;
    y = (screenHeight - h) / 2;
  }

  // Ensure it's within screen bounds
  int screenWidth = GetSystemMetrics(SM_CXSCREEN);
  int screenHeight = GetSystemMetrics(SM_CYSCREEN);
  if (x < 0) x = 0;
  if (y < 0) y = 0;
  if (x + w > screenWidth) x = screenWidth - w;
  if (y + h > screenHeight) y = screenHeight - h;

  if (!hwnd_) {
    WNDCLASSEXW wc = {0};
    wc.cbSize = sizeof(WNDCLASSEXW);
    wc.lpfnWndProc = OverlayWindow::WndProc;
    wc.hInstance = GetModuleHandle(NULL);
    wc.lpszClassName = L"FocusAppOverlay";
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    RegisterClassExW(&wc);

    hwnd_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_LAYERED,
                             L"FocusAppOverlay", L"Focus Shield",
                             WS_POPUP,
                             x, y, w, h,
                             NULL, NULL, GetModuleHandle(NULL), this);

    DWM_WINDOW_CORNER_PREFERENCE cornerPreference = DWMWCP_ROUND;
    DwmSetWindowAttribute(hwnd_, DWMWA_WINDOW_CORNER_PREFERENCE, &cornerPreference, sizeof(cornerPreference));

    SetLayeredWindowAttributes(hwnd_, 0, 245, LWA_ALPHA);
  } else {
    SetWindowPos(hwnd_, HWND_TOPMOST, x, y, w, h, SWP_SHOWWINDOW);
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
    CREATESTRUCTW* cs = (CREATESTRUCTW*)lParam;
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)cs->lpCreateParams);
    return 0;
  }
  
  auto inst = (OverlayWindow*)GetWindowLongPtrW(hwnd, GWLP_USERDATA);

  if (uMsg == WM_LBUTTONDOWN) {
    int x = LOWORD(lParam);
    int y = HIWORD(lParam);
    RECT r;
    GetClientRect(hwnd, &r);
    // Custom Close Button Hit Test (Top Right)
    if (x > r.right - 50 && y < 50) {
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
    
    // Use double buffering to avoid flicker
    HDC memDC = CreateCompatibleDC(dc);
    HBITMAP memBM = CreateCompatibleBitmap(dc, r.right, r.bottom);
    SelectObject(memDC, memBM);

    // 1. Modern Dark Background
    HBRUSH bgBrush = CreateSolidBrush(RGB(18, 18, 23));
    FillRect(memDC, &r, bgBrush);
    DeleteObject(bgBrush);

    // 2. Accent Top Border (Gradient)
    for(int i=0; i<4; i++) {
        RECT borderRect = {0, i, r.right, i+1};
        HBRUSH accentBrush = CreateSolidBrush(RGB(100 + i*10, 90 + i*5, 240)); 
        FillRect(memDC, &borderRect, accentBrush);
        DeleteObject(accentBrush);
    }

    // 3. Custom Close Button (X)
    SetBkMode(memDC, TRANSPARENT);
    SetTextColor(memDC, RGB(180, 180, 180));
    HFONT hFontX = CreateFontW(22, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
    SelectObject(memDC, hFontX);
    RECT xRect = {r.right - 40, 10, r.right - 10, 40};
    DrawTextW(memDC, L"X", -1, &xRect, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    DeleteObject(hFontX);

    // 4. App Logo Icon (Replacing the shield)
    HICON hIcon = (HICON)LoadImageW(GetModuleHandle(NULL), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON, 64, 64, LR_DEFAULTCOLOR);
    if (hIcon) {
        DrawIconEx(memDC, (r.right - 64) / 2, 40, hIcon, 64, 64, 0, NULL, DI_NORMAL);
        DestroyIcon(hIcon);
    }

    // 5. Main Title
    SetTextColor(memDC, RGB(255, 255, 255));
    HFONT hFontTitle = CreateFontW(28, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
    SelectObject(memDC, hFontTitle);
    RECT titleRect = {40, 115, r.right - 40, 155};
    DrawTextW(memDC, L"Timpul tau este pretios!", -1, &titleRect, DT_CENTER | DT_SINGLELINE);
    DeleteObject(hFontTitle);

    // 6. Description Text
    SetTextColor(memDC, RGB(200, 200, 210));
    HFONT hFontSub = CreateFontW(19, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
    SelectObject(memDC, hFontSub);
    RECT textRect = {50, 170, r.right - 50, 280};
    
    std::wstring description = L"Aceasta aplicatie a fost blocata pentru a te ajuta sa ramai productiv si concentrat pe ceea ce conteaza cu adevarat.";
    DrawTextW(memDC, description.c_str(), -1, &textRect, DT_CENTER | DT_WORDBREAK);
    DeleteObject(hFontSub);

    // Copy to screen
    BitBlt(dc, 0, 0, r.right, r.bottom, memDC, 0, 0, SRCCOPY);

    DeleteObject(memBM);
    DeleteDC(memDC);
    EndPaint(hwnd, &ps);
    return 0;
  }
  return DefWindowProcW(hwnd, uMsg, wParam, lParam);
}
