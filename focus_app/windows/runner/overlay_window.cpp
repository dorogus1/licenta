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

    hwnd_ = CreateWindowExA(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED,
                             "FocusAppOverlay", "",
                             WS_POPUP,
                             CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT,
                             NULL, NULL, GetModuleHandle(NULL), this);

    CreateWindowA("STATIC", appName_.c_str(), WS_CHILD | WS_VISIBLE | SS_CENTER,
                  10, 10, 300, 24, hwnd_, NULL, GetModuleHandle(NULL), NULL);
    CreateWindowA("BUTTON", "Inchide aplicatia", WS_CHILD | WS_VISIBLE,
                  10, 44, 160, 32, hwnd_, (HMENU)1001, GetModuleHandle(NULL), NULL);

    SetLayeredWindowAttributes(hwnd_, 0, 255, LWA_ALPHA);
  } else {
    HWND staticText = FindWindowExA(hwnd_, NULL, "STATIC", NULL);
    if (staticText) SetWindowTextA(staticText, appName.c_str());
  }


  SetTimer(hwnd_, 1, 20, NULL);
  ShowWindow(hwnd_, SW_SHOWNA);
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

  if (uMsg == WM_TIMER && wParam == 1 && inst) {
    if (!IsWindow(inst->target_)) {
      inst->Hide();
      return 0;
    }
    // Hide if target is minimized (iconic)
    if (IsIconic(inst->target_)) {
      inst->Hide();
      return 0;
    }

    // Check if we should hide because user Alt-Tabbed away
    HWND fg = GetForegroundWindow();
    if (fg != inst->target_ && fg != hwnd) {
      inst->Hide();
      return 0;
    }

    // Follow the target window size and position
    RECT r;
    GetWindowRect(inst->target_, &r);
    SetWindowPos(hwnd, HWND_TOPMOST, r.left, r.top, r.right - r.left, r.bottom - r.top, SWP_NOACTIVATE);
    
    // Reposition child controls (Button) to be centered
    RECT client;
    GetClientRect(hwnd, &client);
    int width = client.right - client.left;
    int height = client.bottom - client.top;
    
    // Hide original static text in favor of custom paint, but keep button
    HWND btn = FindWindowExA(hwnd, NULL, "BUTTON", NULL);
    if (btn) {
       SetWindowPos(btn, NULL, (width - 160)/2, height/2 + 40, 0, 0, SWP_NOSIZE | SWP_NOZORDER);
    }
    
    return 0;
  }

  if (uMsg == WM_COMMAND) {
    if (LOWORD(wParam) == 1001) {
      // find parent class instance and attempt to close target
      if (inst && inst->target_) {
        // try WM_CLOSE
        PostMessage(inst->target_, WM_CLOSE, 0, 0);
        // if still visible after short delay, try terminate
        Sleep(200);
        if (IsWindow(inst->target_)) {
          DWORD pid = 0;
          GetWindowThreadProcessId(inst->target_, &pid);
          HANDLE h = OpenProcess(PROCESS_TERMINATE, FALSE, pid);
          if (h) {
            TerminateProcess(h, 1);
            CloseHandle(h);
          }
        }
      }
      return 0;
    }
  }
  if (uMsg == WM_PAINT) {
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(hwnd, &ps);
    RECT r;
    GetClientRect(hwnd, &r);
    
    // Solid Black Background
    HBRUSH brush = CreateSolidBrush(RGB(0, 0, 0));
    FillRect(dc, &r, brush);
    DeleteObject(brush);
    
    // White Text
    SetTextColor(dc, RGB(255, 255, 255));
    SetBkMode(dc, TRANSPARENT);
    
    // Create a larger font for impact
    HFONT hFont = CreateFontA(32, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 
                              OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY, 
                              DEFAULT_PITCH | FF_SWISS, "Segoe UI");
    HFONT hOldFont = (HFONT)SelectObject(dc, hFont);
    
    const char* msg = "Aplicatia este blocata!\nTreci inapoi la treaba.";
    RECT textRect = r;
    // Move text up a bit so it doesn't overlap button
    textRect.bottom -= 60; 
    DrawTextA(dc, msg, -1, &textRect, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOCLIP);
    
    SelectObject(dc, hOldFont);
    DeleteObject(hFont);
    
    EndPaint(hwnd, &ps);
    return 0;
  }
  return DefWindowProcA(hwnd, uMsg, wParam, lParam);
}
