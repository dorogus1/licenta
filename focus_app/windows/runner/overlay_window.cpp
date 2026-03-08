#include "overlay_window.h"
#include <string>

OverlayWindow::OverlayWindow() {}

OverlayWindow::~OverlayWindow() { Hide(); }

void OverlayWindow::ShowOver(HWND target, const std::string& appName) {
  if (!IsWindow(target)) return;
  appName_ = appName;
  target_ = target;
  if (!hwnd_) {
    // register class
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = OverlayWindow::WndProc;
    wc.hInstance = GetModuleHandle(NULL);
    wc.lpszClassName = "FocusAppOverlay";
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    RegisterClassA(&wc);

    // Create a centered window
    int screenWidth = GetSystemMetrics(SM_CXSCREEN);
    int screenHeight = GetSystemMetrics(SM_CYSCREEN);
    int w = 500;
    int h = 300;
    int x = (screenWidth - w) / 2;
    int y = (screenHeight - h) / 2;

    hwnd_ = CreateWindowExA(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED,
                             "FocusAppOverlay", "",
                             WS_POPUP,
                             x, y, w, h,
                             NULL, NULL, GetModuleHandle(NULL), this);

    // Subtle X button in top-left
    CreateWindowA("BUTTON", "X", WS_CHILD | WS_VISIBLE | BS_FLAT,
                  10, 10, 30, 30, hwnd_, (HMENU)1001, GetModuleHandle(NULL), NULL);

    SetLayeredWindowAttributes(hwnd_, 0, 240, LWA_ALPHA);
  }

  ShowWindow(hwnd_, SW_SHOW);
  UpdateWindow(hwnd_);
}

void OverlayWindow::Hide() {
  if (hwnd_) {
    KillTimer(hwnd_, 1);
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
    target_ = nullptr;
  }
}

bool OverlayWindow::IsVisible() const { return hwnd_ && IsWindow(hwnd_); }

LRESULT CALLBACK OverlayWindow::WndProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
  if (uMsg == WM_CREATE) {
    // store pointer to instance
    CREATESTRUCTA* cs = (CREATESTRUCTA*)lParam;
    SetWindowLongPtrA(hwnd, GWLP_USERDATA, (LONG_PTR)cs->lpCreateParams);
    return 0;
  }
  
  auto inst = (OverlayWindow*)GetWindowLongPtrA(hwnd, GWLP_USERDATA);

  if (uMsg == WM_COMMAND) {
    if (LOWORD(wParam) == 1001) {
      // subtle X button clicked
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
      return 0;
    }
  }

  if (uMsg == WM_PAINT) {
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(hwnd, &ps);
    RECT r;
    GetClientRect(hwnd, &r);
    
    // Smooth Dark Background
    HBRUSH brush = CreateSolidBrush(RGB(30, 30, 30));
    FillRect(dc, &r, brush);
    DeleteObject(brush);
    
    // White Text
    SetTextColor(dc, RGB(240, 240, 240));
    SetBkMode(dc, TRANSPARENT);
    
    // Title Font
    HFONT hFontTitle = CreateFontA(28, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 
                                  OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY, 
                                  DEFAULT_PITCH | FF_SWISS, "Segoe UI");
    HFONT hOldFont = (HFONT)SelectObject(dc, hFontTitle);
    
    RECT titleRect = r;
    titleRect.top += 60;
    DrawTextA(dc, "Timpul tau este pretios!", -1, &titleRect, DT_CENTER | DT_TOP | DT_SINGLELINE | DT_NOCLIP);
    
    // Subtitle Font
    HFONT hFontSub = CreateFontA(20, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 
                                 OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY, 
                                 DEFAULT_PITCH | FF_SWISS, "Segoe UI");
    SelectObject(dc, hFontSub);
    
    RECT textRect = r;
    textRect.top += 120;
    textRect.left += 40;
    textRect.right -= 40;
    DrawTextA(dc, "Aceasta aplicatie a fost blocata pentru a te ajuta sa ramai productiv si concentrat pe ceea ce conteaza cu adevarat.", -1, &textRect, DT_CENTER | DT_TOP | DT_WORDBREAK | DT_NOCLIP);
    
    SelectObject(dc, hOldFont);
    DeleteObject(hFontTitle);
    DeleteObject(hFontSub);
    
    EndPaint(hwnd, &ps);
    return 0;
  }
  return DefWindowProcA(hwnd, uMsg, wParam, lParam);
}
