#pragma once
#include <cstdint>

namespace off {
// ---- module: UnityFramework (arm64/arm64e) — dump 2026-10-15 ----
// Fill kExpectedUUID before trusting anything below:
//   dwarfdump --uuid Payload/FreeFire.app/Frameworks/UnityFramework.framework/UnityFramework
constexpr const char* kModule       = "UnityFramework";
constexpr const char* kDumpDate     = "2026-10-15";
constexpr const char* kExpectedUUID = "";   // empty = UUID gate disabled

// Il2Cpp static chain: __DATA slot -> Il2CppClass -> static_fields -> field
constexpr uintptr_t InitBase     = 0xA342EFC;
constexpr uintptr_t StaticFields = 0x5C;
constexpr uintptr_t CurrentMatch = 0x50;

// Match / player
constexpr uintptr_t LocalPlayer  = 0x94;
constexpr uintptr_t DictEntities = 0x68;
constexpr uintptr_t Player_IsDead = 0x50;
constexpr uintptr_t AimRotation  = 0x440;
constexpr uintptr_t Weapon       = 0x434;
constexpr uintptr_t Bones_Head   = 0x49C;
constexpr uintptr_t CharController = 0x348;
constexpr uintptr_t LocalPlayerAttributes = 0x500;

// UnityEngine.Object base field — native object pointer
constexpr uintptr_t Obj_CachedPtr = 0x10;

// Transform (Unity 2021+ Il2Cpp layout — VERIFY against dump)
constexpr uintptr_t Tf_LocalRotation = 0x10;
constexpr uintptr_t Tf_LocalPosition = 0x20;
constexpr uintptr_t Tf_LocalScale    = 0x30;
constexpr uintptr_t Tf_Father        = 0x48;

// Camera
constexpr uintptr_t MainCameraTransform = 0x28C;  // Camera component (or Transform — probe both)
constexpr uintptr_t Cam_ViewMatrixField = 0xE8;   // may hold float* or inline matrix

// Dictionary<long, Player> internals
constexpr uintptr_t Dict_Entries = 0x18;
constexpr uintptr_t Dict_Count   = 0x20;
constexpr uintptr_t Entry_Stride = 0x18;
constexpr uintptr_t Entry_Hash   = 0x00;   // <0 == free slot
constexpr uintptr_t Entry_Value  = 0x10;

// Weapon
constexpr uintptr_t Weapon_GunFeelProfile = 0x3B0;
constexpr uintptr_t WeaponData            = 0x58;
constexpr uintptr_t ReloadSpeed           = 0x158;
constexpr uintptr_t WGP_EnableRecoil      = 0x1D0;
constexpr uintptr_t WGP_EnableGunFeel     = 0x1D4;
constexpr uintptr_t WGP_EnableSpread      = 0x1D6;
constexpr uintptr_t WGP_HipRecoilPitchScale = 0x1A4;
constexpr uintptr_t WGP_HipRecoilYawScale   = 0xA0;
constexpr uintptr_t WGP_HipSpreadLimit      = 0x128;
constexpr uintptr_t WGP_AdsSpreadLimit      = 0xFC;

// CharacterController
constexpr uintptr_t CCT_UseGravity   = 0x38;
constexpr uintptr_t CCT_SolveCollisions = 0x7D;

// Attributes
constexpr uintptr_t Attr_UnlimitedAmmo = 0x114;
}
