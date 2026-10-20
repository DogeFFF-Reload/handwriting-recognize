// MyScript 的设备证书。
//
// 证书本身（MyScript 开发者后台发的 MyCertificate.c）不进仓库：在 Mac 上复制到
//   app/InkTutor/MyScriptCertificate/MyCertificate.c
// 那个目录在 .gitignore 里；Xcode 的文件夹同步会把它编进 App。
// 没放证书时，CertificateFallback.c 里的弱定义生效（长度 0），App 照常编译运行，函数识别退回其他引擎。

#ifndef INKTUTOR_MYCERTIFICATE_H
#define INKTUTOR_MYCERTIFICATE_H

#include <stddef.h>

// 和 MyCertificate.c 里的定义一致（同一个宏挡住重复定义）。
#ifndef VO_CERTIFICATE_TYPE
#define VO_CERTIFICATE_TYPE
typedef struct _voCertificate
{
  const char* bytes;
  size_t length;
}
voCertificate;
#endif

extern voCertificate const myCertificate;

#endif
