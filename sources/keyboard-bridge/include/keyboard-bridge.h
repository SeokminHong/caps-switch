#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

CFArrayRef _Nullable CKCopyKeyboards(void) CF_RETURNS_RETAINED;
bool CKSetMapping(uint64_t registryId, CFArrayRef _Nonnull mapping);
CFTypeRef _Nullable CKCreateKeyboardClient(void) CF_RETURNS_RETAINED;
CFArrayRef _Nullable CKCopyKeyboardsWithClient(CFTypeRef _Nonnull client) CF_RETURNS_RETAINED;
bool CKSetMappingWithClient(CFTypeRef _Nonnull client, uint64_t registryId, CFArrayRef _Nonnull mapping);
int32_t CKSetCapsLock(bool enabled);
