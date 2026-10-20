#include "MyCertificate.h"

// 弱定义：MyScriptCertificate/MyCertificate.c 在的时候，链接器用那里的强定义；不在的时候用这个空证书。
__attribute__((weak)) voCertificate const myCertificate = { NULL, 0 };
