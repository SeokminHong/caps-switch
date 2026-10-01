#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

CFArrayRef _Nullable CKCopyKeyboards(void) CF_RETURNS_RETAINED;
bool CKSetMapping(uint64_t registryId, CFArrayRef _Nonnull mapping);
int32_t CKSetCapsLock(bool enabled);
