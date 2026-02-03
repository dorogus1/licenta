#include "icon_utils.h"

#include <vector>
#include <string>
#include <sstream>
#include <algorithm>
#include <memory>
#include <Shlobj.h>
#include <gdiplus.h>
#pragma comment(lib, "gdiplus.lib")

using namespace Gdiplus;

static std::string Base64Encode(const std::vector<BYTE>& data) {
  static const char* table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string out;
  int val=0, valb=-6;
  for (BYTE c : data) {
    val = (val<<8) + c;
    valb += 8;
    while (valb >= 0) {
      out.push_back(table[(val>>valb)&0x3F]);
      valb -= 6;
    }
  }
  if (valb>-6) out.push_back(table[((val<<8)>>(valb+8))&0x3F]);
  while (out.size()%4) out.push_back('=');
  return out;
}

static bool GetPngBytesFromHICON(HICON hIcon, std::vector<BYTE>& out) {
  if (!hIcon) return false;
  // init GDI+
  static bool gdiInit = [](){
    GdiplusStartupInput input;
    ULONG_PTR token;
    GdiplusStartup(&token, &input, NULL);
    return true;
  }();

  ICONINFO info;
  if (!GetIconInfo(hIcon, &info)) return false;
  HBITMAP hbm = info.hbmColor;
  if (!hbm) {
    // cleanup
    if (info.hbmMask) DeleteObject(info.hbmMask);
    return false;
  }
  Bitmap bmp(hbm, NULL);
  IStream* istream = NULL;
  if (CreateStreamOnHGlobal(NULL, TRUE, &istream) != S_OK) {
    DeleteObject(info.hbmColor);
    if (info.hbmMask) DeleteObject(info.hbmMask);
    return false;
  }
  CLSID clsid;
  // get png encoder
  UINT numEnc, sizeEnc;
  GetImageEncodersSize(&numEnc, &sizeEnc);
  if (sizeEnc == 0) {
    istream->Release();
    DeleteObject(info.hbmColor);
    if (info.hbmMask) DeleteObject(info.hbmMask);
    return false;
  }
  std::unique_ptr<BYTE[]> pb(new BYTE[sizeEnc]);
  ImageCodecInfo* pImageCodecInfo = reinterpret_cast<ImageCodecInfo*>(pb.get());
  GetImageEncoders(numEnc, sizeEnc, pImageCodecInfo);
  for (UINT j = 0; j < numEnc; ++j) {
    if (wcscmp(pImageCodecInfo[j].MimeType, L"image/png") == 0) {
      clsid = pImageCodecInfo[j].Clsid;
      break;
    }
  }
  Status s = bmp.Save(istream, &clsid, NULL);
  if (s != Ok) {
    istream->Release();
    DeleteObject(info.hbmColor);
    if (info.hbmMask) DeleteObject(info.hbmMask);
    return false;
  }
  // get HGLOBAL and size
  HGLOBAL hg = NULL;
  if (GetHGlobalFromStream(istream, &hg) != S_OK) {
    istream->Release();
    DeleteObject(info.hbmColor);
    if (info.hbmMask) DeleteObject(info.hbmMask);
    return false;
  }
  SIZE_T size = GlobalSize(hg);
  void* data = GlobalLock(hg);
  if (!data) {
    GlobalUnlock(hg);
    istream->Release();
    DeleteObject(info.hbmColor);
    if (info.hbmMask) DeleteObject(info.hbmMask);
    return false;
  }
  out.resize(size);
  memcpy(out.data(), data, size);
  GlobalUnlock(hg);
  istream->Release();
  DeleteObject(info.hbmColor);
  if (info.hbmMask) DeleteObject(info.hbmMask);
  return true;
}

std::string ExtractIconAsPngBase64(const std::string& iconPath) {
  if (iconPath.empty()) return {};
  // Try to extract icon handle from the file
  HICON hIcon = NULL;
  std::string path = iconPath;
  // ensure path uses proper char encoding
  // Use ExtractIconEx to get large icon
  UINT count = ExtractIconExA(path.c_str(), 0, &hIcon, NULL, 1);
  if (count == 0 || !hIcon) {
    // fallback: try SHGetFileInfo to get icon
    SHFILEINFOA sfi = {0};
    if (SHGetFileInfoA(path.c_str(), 0, &sfi, sizeof(sfi), SHGFI_ICON | SHGFI_LARGEICON)) {
      hIcon = sfi.hIcon;
    }
  }
  if (!hIcon) return {};
  std::vector<BYTE> png;
  const bool ok = GetPngBytesFromHICON(hIcon, png);
  // destroy icon if ExtractIconEx created it (ExtractIconEx docs: must destroy if returned)
  DestroyIcon(hIcon);
  if (!ok) return {};
  return Base64Encode(png);
}
