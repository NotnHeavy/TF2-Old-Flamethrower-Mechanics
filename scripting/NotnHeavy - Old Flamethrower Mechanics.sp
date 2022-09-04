//////////////////////////////////////////////////////////////////////////////
// MADE BY NOTNHEAVY. USES GPL-3, AS PER REQUEST OF SOURCEMOD               //
//////////////////////////////////////////////////////////////////////////////

// For dynamic memory allocation, this uses Scags' SM-Memory extension.
// https://forums.alliedmods.net/showthread.php?t=327729#

// For TF2 attributes, this uses nosoop's tf2attributes plugin, which is a fork of FlaminSarge's.

// For stdlib functions, this uses Scags' SM-Memory.

#pragma semicolon true 
#pragma newdecls required

#include <sourcemod>
#include <smmem>
#include <tf2attributes>
#include <dhooks>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>

#include "SMTC/SMTC"
#include "SMTC/Pointer"
#include "SMTC/Vector"
#include "SMTC/QAngle"
#include "SMTC/CUtlVector"
#include "SMTC/tf_shareddefs"

#define PLUGIN_NAME "NotnHeavy - Old Flamethrower Mechanics"

#define TF_FLAMETHROWER_MUZZLEPOS_FORWARD		70.00
#define TF_FLAMETHROWER_MUZZLEPOS_RIGHT			12.00
#define TF_FLAMETHROWER_MUZZLEPOS_UP			-12.00

#define OFM_CUTLVECTOR_SIZE 20 // in case cutlvector.inc isn't included from SMTC.

// i'm not including the entire enum for this LOL
// ai_activity.h
#define ACT_VM_PRIMARYATTACK 180

#define WL_None 0
#define WL_Feet 1
#define WL_Waist 2
#define WL_Eyes 3

#define DMGTYPE DMG_IGNITE | DMG_PREVENT_PHYSICS_FORCE | DMG_PREVENT_PHYSICS_FORCE

#define TF_FLAMETHROWER_AMMO_PER_SECOND_PRIMARY_ATTACK		14.00

// settings for m_takedamage
#define	DAMAGE_NO				0
#define DAMAGE_EVENTS_ONLY		1		// Call damage functions, but don't modify health
#define	DAMAGE_YES				2
#define	DAMAGE_AIM				3

#define TF_BURNING_DMG 3.00
#define TF_BURNING_FLAME_LIFE_PYRO	0.25		// pyro only displays burning effect momentarily
#define TF_BURNING_FLAME_LIFE		10.0
#define TF_BURNING_FLAME_LIFE_PLASMA 6.0

//////////////////////////////////////////////////////////////////////////////
// GLOBALS                                                                  //
//////////////////////////////////////////////////////////////////////////////

// entity flags, CBaseEntity::m_iEFlags
enum
{
	EFL_KILLME	=				(1<<0),	// This entity is marked for death -- This allows the game to actually delete ents at a safe time
	EFL_DORMANT	=				(1<<1),	// Entity is dormant, no updates to client
	EFL_NOCLIP_ACTIVE =			(1<<2),	// Lets us know when the noclip command is active.
	EFL_SETTING_UP_BONES =		(1<<3),	// Set while a model is setting up its bones.
	EFL_KEEP_ON_RECREATE_ENTITIES = (1<<4), // This is a special entity that should not be deleted when we restart entities only

	EFL_HAS_PLAYER_CHILD=		(1<<4),	// One of the child entities is a player.

	EFL_DIRTY_SHADOWUPDATE =	(1<<5),	// Client only- need shadow manager to update the shadow...
	EFL_NOTIFY =				(1<<6),	// Another entity is watching events on this entity (used by teleport)

	// The default behavior in ShouldTransmit is to not send an entity if it doesn't
	// have a model. Certain entities want to be sent anyway because all the drawing logic
	// is in the client DLL. They can set this flag and the engine will transmit them even
	// if they don't have a model.
	EFL_FORCE_CHECK_TRANSMIT =	(1<<7),

	EFL_BOT_FROZEN =			(1<<8),	// This is set on bots that are frozen.
	EFL_SERVER_ONLY =			(1<<9),	// Non-networked entity.
	EFL_NO_AUTO_EDICT_ATTACH =	(1<<10), // Don't attach the edict; we're doing it explicitly
	
	// Some dirty bits with respect to abs computations
	EFL_DIRTY_ABSTRANSFORM =	(1<<11),
	EFL_DIRTY_ABSVELOCITY =		(1<<12),
	EFL_DIRTY_ABSANGVELOCITY =	(1<<13),
	EFL_DIRTY_SURROUNDING_COLLISION_BOUNDS	= (1<<14),
	EFL_DIRTY_SPATIAL_PARTITION = (1<<15),
//	UNUSED						= (1<<16),

	EFL_IN_SKYBOX =				(1<<17),	// This is set if the entity detects that it's in the skybox.
											// This forces it to pass the "in PVS" for transmission.
	EFL_USE_PARTITION_WHEN_NOT_SOLID = (1<<18),	// Entities with this flag set show up in the partition even when not solid
	EFL_TOUCHING_FLUID =		(1<<19),	// Used to determine if an entity is floating

	// FIXME: Not really sure where I should add this...
	EFL_IS_BEING_LIFTED_BY_BARNACLE = (1<<20),
	EFL_NO_ROTORWASH_PUSH =		(1<<21),		// I shouldn't be pushed by the rotorwash
	EFL_NO_THINK_FUNCTION =		(1<<22),
	EFL_NO_GAME_PHYSICS_SIMULATION = (1<<23),

	EFL_CHECK_UNTOUCH =			(1<<24),
	EFL_DONTBLOCKLOS =			(1<<25),		// I shouldn't block NPC line-of-sight
	EFL_DONTWALKON =			(1<<26),		// NPC;s should not walk on this entity
	EFL_NO_DISSOLVE =			(1<<27),		// These guys shouldn't dissolve
	EFL_NO_MEGAPHYSCANNON_RAGDOLL = (1<<28),	// Mega physcannon can't ragdoll these guys.
	EFL_NO_WATER_VELOCITY_CHANGE  =	(1<<29),	// Don't adjust this entity's velocity when transitioning into water
	EFL_NO_PHYSCANNON_INTERACTION =	(1<<30),	// Physcannon can't pick these up or punt them
	EFL_NO_DAMAGE_FORCES =		(1<<31),	// Doesn't accept forces from physics damage
};

// CTFFlameEntity offsets. Should be used with CTFFlameEntity_Base.
enum
{
    CTFFLAMEENTITY_OFFSET_M_VECINITIALPOS = 0,                                                           // Vector m_vecInitialPos;
    CTFFLAMEENTITY_OFFSET_M_VECPREVPOS = CTFFLAMEENTITY_OFFSET_M_VECINITIALPOS + VECTOR_SIZE,            // Vector m_vecPrevPos;
    CTFFLAMEENTITY_OFFSET_M_VECBASEVELOCITY = CTFFLAMEENTITY_OFFSET_M_VECPREVPOS + VECTOR_SIZE,          // Vector m_vecBaseVelocity;
    CTFFLAMEENTITY_OFFSET_M_VECATTACKERVELOCITY = CTFFLAMEENTITY_OFFSET_M_VECBASEVELOCITY + VECTOR_SIZE, // Vector m_vecAttackerVelocity;
    CTFFLAMEENTITY_OFFSET_M_FLTIMEREMOVE = CTFFLAMEENTITY_OFFSET_M_VECATTACKERVELOCITY + VECTOR_SIZE,    // float m_flTimeRemove;
    CTFFLAMEENTITY_OFFSET_M_IDMGTYPE = CTFFLAMEENTITY_OFFSET_M_FLTIMEREMOVE + 4,                         // int m_iDmgType;
    CTFFLAMEENTITY_OFFSET_M_FLDMGAMOUNT = CTFFLAMEENTITY_OFFSET_M_IDMGTYPE + 4,                          // float m_flDmgAmount;
    CTFFLAMEENTITY_OFFSET_M_HENTITIESBURNT = CTFFLAMEENTITY_OFFSET_M_FLDMGAMOUNT + 4,                    // CUtlVector<EHANDLE> m_hEntitiesBurnt;
    CTFFLAMEENTITY_OFFSET_M_HATTACKER = CTFFLAMEENTITY_OFFSET_M_HENTITIESBURNT + OFM_CUTLVECTOR_SIZE,    // EHANDLE m_hAttacker;
    //CTFFLAMEENTITY_OFFSET_M_IATTACKERTEAM = CTFFLAMEENTITY_OFFSET_M_HATTACKER + 4,                       // int m_iAttackerTeam;
    CTFFLAMEENTITY_OFFSET_M_BCRITFROMBEHIND = CTFFLAMEENTITY_OFFSET_M_HATTACKER/*CTFFLAMEENTITY_OFFSET_M_IATTACKERTEAM*/ + 4,                 // bool m_bCritFromBehind;
    CTFFLAMEENTITY_OFFSET_M_BBURNEDENEMY = CTFFLAMEENTITY_OFFSET_M_BCRITFROMBEHIND + 1,                  // bool m_bBurnedEnemy;
    CTFFLAMEENTITY_OFFSET_M_HFLAMETHROWER = CTFFLAMEENTITY_OFFSET_M_BBURNEDENEMY + 2,                    // CHandle<CTFFlameThrower> m_hFlameThrower;

    CTFFLAMEENTITY_SIZE = CTFFLAMEENTITY_OFFSET_M_HFLAMETHROWER + 4
};

enum FlameThrowerState_t
{
	// Firing states.
	FT_STATE_IDLE = 0,
	FT_STATE_STARTFIRING,
	FT_STATE_FIRING,
	FT_STATE_SECONDARY,
};

enum PlayerAnimEvent_t
{
	PLAYERANIMEVENT_ATTACK_PRIMARY,
	PLAYERANIMEVENT_ATTACK_SECONDARY,
	PLAYERANIMEVENT_ATTACK_GRENADE,
	PLAYERANIMEVENT_RELOAD,
	PLAYERANIMEVENT_RELOAD_LOOP,
	PLAYERANIMEVENT_RELOAD_END,
	PLAYERANIMEVENT_JUMP,
	PLAYERANIMEVENT_SWIM,
	PLAYERANIMEVENT_DIE,
	PLAYERANIMEVENT_FLINCH_CHEST,
	PLAYERANIMEVENT_FLINCH_HEAD,
	PLAYERANIMEVENT_FLINCH_LEFTARM,
	PLAYERANIMEVENT_FLINCH_RIGHTARM,
	PLAYERANIMEVENT_FLINCH_LEFTLEG,
	PLAYERANIMEVENT_FLINCH_RIGHTLEG,
	PLAYERANIMEVENT_DOUBLEJUMP,

	// Cancel.
	PLAYERANIMEVENT_CANCEL,
	PLAYERANIMEVENT_SPAWN,

	// Snap to current yaw exactly
	PLAYERANIMEVENT_SNAP_YAW,

	PLAYERANIMEVENT_CUSTOM,				// Used to play specific activities
	PLAYERANIMEVENT_CUSTOM_GESTURE,
	PLAYERANIMEVENT_CUSTOM_SEQUENCE,	// Used to play specific sequences
	PLAYERANIMEVENT_CUSTOM_GESTURE_SEQUENCE,

	// TF Specific. Here until there's a derived game solution to this.
	PLAYERANIMEVENT_ATTACK_PRE,
	PLAYERANIMEVENT_ATTACK_POST,
	PLAYERANIMEVENT_GRENADE1_DRAW,
	PLAYERANIMEVENT_GRENADE2_DRAW,
	PLAYERANIMEVENT_GRENADE1_THROW,
	PLAYERANIMEVENT_GRENADE2_THROW,
	PLAYERANIMEVENT_VOICE_COMMAND_GESTURE,
	PLAYERANIMEVENT_DOUBLEJUMP_CROUCH,
	PLAYERANIMEVENT_STUN_BEGIN,
	PLAYERANIMEVENT_STUN_MIDDLE,
	PLAYERANIMEVENT_STUN_END,
	PLAYERANIMEVENT_PASSTIME_THROW_BEGIN,
	PLAYERANIMEVENT_PASSTIME_THROW_MIDDLE,
	PLAYERANIMEVENT_PASSTIME_THROW_END,
	PLAYERANIMEVENT_PASSTIME_THROW_CANCEL,

	PLAYERANIMEVENT_ATTACK_PRIMARY_SUPER,

	PLAYERANIMEVENT_COUNT
};

enum struct player_t
{
    int index;

    float m_flNextPrimaryAttack;
    float m_flStartFiringTime;
    float m_flNextPrimaryAttackAnim;
    float m_flAmmoUseRemainder;
    float m_flRemoveBurn;
    int m_iFlamethrowerAmmo;
    Pointer m_Shared;

    int GetAmmoCount(int iAmmoIndex)
    {
        return GetEntProp(this.index, Prop_Send, "m_iAmmo", .element = iAmmoIndex);
    }
    void SetAmmoCount(int iCount, int iAmmoIndex)
    {
        SetEntProp(this.index, Prop_Send, "m_iAmmo", iCount, .element = iAmmoIndex);
    }
}
static player_t PlayerData[MAXPLAYERS + 1];

static DHookSetup DHooks_CTFFlameThrower_PrimaryAttack;
static DHookSetup DHooks_CTFFlameThrower_FireAirBlast;
static DHookSetup DHooks_CTFFlameManager_OnCollide;
static DHookSetup DHooks_CTFPlayerShared_Burn;

static Handle SDKCall_CBaseEntity_Create;
static Handle SDKCall_CBaseEntity_CalcAbsoluteVelocity;
static Handle SDKCall_CBaseEntity_SetAbsVelocity;
static Handle SDKCall_CBaseEntity_SetAbsAngles;
static Handle SDKCall_CBaseEntity_CalcAbsolutePosition;
static Handle SDKCall_CBaseEntity_EyePosition;
static Handle SDKCall_CBaseEntity_EyeAngles;
static Handle SDKCall_CBaseCombatCharacter_Weapon_ShootPosition;
static Handle SDKCall_CTFWeaponBase_CanAttack;
static Handle SDKCall_CTFWeaponBase_CalcIsAttackCritical;
static Handle SDKCall_CTFWeaponBase_SendWeaponAnim;
static Handle SDKCall_CTFPlayer_DoAnimationEvent;

static int CTFFlameEntity_Base;

static Address CTFWeaponBase_m_iWeaponMode;
static Address CTFPlayerShared_m_pOuter;
static Address CTFPlayerShared_m_flBurnDuration;

static ConVar tf_flamethrower_velocity;
static ConVar tf_flamethrower_vecrand;

static ConVar notnheavy_flamethrower_enable;
static ConVar notnheavy_flamethrower_damage;
static ConVar notnheavy_flamethrower_oldafterburn_damage;
static ConVar notnheavy_flamethrower_oldafterburn_duration;
static ConVar notnheavy_flamethrower_falloff;

static Pointer MemoryPatch_CTFFlameEntity_OnCollide_Falloff;
static Pointer MemoryPatch_CTFFlameEntity_OnCollide_Falloff_Old;
static float MemoryPatch_CTFFlameEntity_OnCollide_Falloff_New;

//////////////////////////////////////////////////////////////////////////////
// PLUGIN INFO                                                              //
//////////////////////////////////////////////////////////////////////////////

public Plugin myinfo =
{
    name = PLUGIN_NAME,
    author = "NotnHeavy",
    description = "An attempt to revert flamethrower mechanics to how they were, pre-Jungle Inferno.",
    version = "1.0",
    url = "none"
};

//////////////////////////////////////////////////////////////////////////////
// INITIALISATION                                                           //
//////////////////////////////////////////////////////////////////////////////

public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    SMTC_Initialize();

    HookEvent("post_inventory_application", PostInventoryApplication);

    // Load config data!
    GameData config = LoadGameConfigFile(PLUGIN_NAME);

    DHooks_CTFFlameThrower_PrimaryAttack = DHookCreateFromConf(config, "CTFFlameThrower::PrimaryAttack()");
    DHookEnableDetour(DHooks_CTFFlameThrower_PrimaryAttack, false, Pre_PrimaryAttack); // just because i don't want to re-write ammo management entirely.
    DHookEnableDetour(DHooks_CTFFlameThrower_PrimaryAttack, true, Post_PrimaryAttack);

    DHooks_CTFFlameThrower_FireAirBlast = DHookCreateFromConf(config, "CTFFlameThrower::FireAirBlast()");
    DHookEnableDetour(DHooks_CTFFlameThrower_FireAirBlast, true, FireAirBlast);

    DHooks_CTFFlameManager_OnCollide = DHookCreateFromConf(config, "CTFFlameManager::OnCollide()");
    DHookEnableDetour(DHooks_CTFFlameManager_OnCollide, false, OnCollide);

    DHooks_CTFPlayerShared_Burn = DHookCreateFromConf(config, "CTFPlayerShared::Burn()");
    DHookEnableDetour(DHooks_CTFPlayerShared_Burn, true, Burn);

    StartPrepSDKCall(SDKCall_Static);
    PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CBaseEntity::Create()");
    PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);       // const char* szName; 
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);   // Vector& vecOrigin; 
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);   // QAngle& vecAngles; 
    PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);  // CBaseEntity* pOwner;
    PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer); // CBaseEntity*
    SDKCall_CBaseEntity_Create = EndPrepSDKCall();

    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CBaseEntity::CalcAbsoluteVelocity()");
    SDKCall_CBaseEntity_CalcAbsoluteVelocity = EndPrepSDKCall();

    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CBaseEntity::SetAbsVelocity()");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // const Vector& vecAbsVelocity;
    SDKCall_CBaseEntity_SetAbsVelocity = EndPrepSDKCall();

    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CBaseEntity::SetAbsAngles()");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // const QAngle& absAngles;
    SDKCall_CBaseEntity_SetAbsAngles = EndPrepSDKCall();

    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CBaseEntity::CalcAbsolutePosition()");
    SDKCall_CBaseEntity_CalcAbsolutePosition = EndPrepSDKCall();

    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "CBaseEntity::EyePosition()");
    PrepSDKCall_SetReturnInfo(SDKType_Vector, SDKPass_ByValue); // Vector
    SDKCall_CBaseEntity_EyePosition = EndPrepSDKCall();

    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "CBaseEntity::EyeAngles()");
    PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain); // QAngle&
    SDKCall_CBaseEntity_EyeAngles = EndPrepSDKCall();

    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "CBaseCombatCharacter::Weapon_ShootPosition()");
    PrepSDKCall_SetReturnInfo(SDKType_Vector, SDKPass_ByValue); // Vector
    SDKCall_CBaseCombatCharacter_Weapon_ShootPosition = EndPrepSDKCall();

    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "CTFWeaponBase::CanAttack()");
    PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain); // bool
    SDKCall_CTFWeaponBase_CanAttack = EndPrepSDKCall();

    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CTFWeaponBase::CalcIsAttackCritical()");
    SDKCall_CTFWeaponBase_CalcIsAttackCritical = EndPrepSDKCall();

    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "CTFWeaponBase::SendWeaponAnim()");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // int iActivity;
    PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);        // bool
    SDKCall_CTFWeaponBase_SendWeaponAnim = EndPrepSDKCall();

    StartPrepSDKCall(SDKCall_Player);
    PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CTFPlayer::DoAnimationEvent()");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // PlayerAnimEvent_t event;
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // int mData = 0;
    SDKCall_CTFPlayer_DoAnimationEvent = EndPrepSDKCall();

    CTFFlameEntity_Base = config.GetOffset("CTFFlameEntity::m_vecInitialPos");
    CTFWeaponBase_m_iWeaponMode = view_as<Address>(config.GetOffset("CTFWeaponBase::m_iWeaponMode"));
    CTFPlayerShared_m_pOuter = view_as<Address>(config.GetOffset("CTFPlayerShared::m_pOuter"));
    CTFPlayerShared_m_flBurnDuration = view_as<Address>(config.GetOffset("CTFPlayerShared::m_flBurnDuration"));

    MemoryPatch_CTFFlameEntity_OnCollide_Falloff = view_as<Pointer>(config.GetMemSig("CTFFlameEntity::OnCollide()") + config.GetOffset("MemoryPatch_CTFFlameEntity_OnCollide_Falloff"));
    MemoryPatch_CTFFlameEntity_OnCollide_Falloff_Old = MemoryPatch_CTFFlameEntity_OnCollide_Falloff.Dereference();

    delete config;

    // Load ConVars.
    tf_flamethrower_velocity = FindConVar("tf_flamethrower_velocity");
    tf_flamethrower_vecrand = FindConVar("tf_flamethrower_vecrand");

    // Setup convars. (These values are adjusted for before Jungle Inferno flame mechanics dropped.)
    notnheavy_flamethrower_enable = CreateConVar("notnheavy_flamethrower_enable", "1", "use old flamethrower mechanics?", FCVAR_CHEAT);
    notnheavy_flamethrower_damage = CreateConVar("notnheavy_flamethrower_damage", "6.80", "tf_flame danage number", FCVAR_CHEAT);
    notnheavy_flamethrower_oldafterburn_damage = CreateConVar("notnheavy_flamethrower_oldafterburn_damage", "0", "use old afterburn damage (3 per tick)", FCVAR_CHEAT);
    notnheavy_flamethrower_oldafterburn_duration = CreateConVar("notnheavy_flamethrower_oldafterburn_duration", "0", "use old afterburn duration (constant 10s, 6s with cow mangler)", FCVAR_CHEAT);
    notnheavy_flamethrower_falloff = CreateConVar("notnheavy_flamethrower_falloff", "0.70", "tf_flame falloff percentage when dealing damage", FCVAR_CHEAT);
    notnheavy_flamethrower_falloff.AddChangeHook(AdjustFalloff);
    MemoryPatch_CTFFlameEntity_OnCollide_Falloff_Patch();

    // Setup hooks for each client.
    for (int i = 1; i <= MaxClients; ++i)
    {
        if (IsClientInGame(i))
            SetupPlayerHooks(i);
    }

    PrintToServer("----------------------------------------------------------\n\"%s\" has loaded.\n----------------------------------------------------------", PLUGIN_NAME);
}

//////////////////////////////////////////////////////////////////////////////
// MEMORY PATCHES                                                           //
//////////////////////////////////////////////////////////////////////////////

public void OnPluginEnd()
{
    MemoryPatch_CTFFlameEntity_OnCollide_Falloff.Write(MemoryPatch_CTFFlameEntity_OnCollide_Falloff_Old);
}

static void MemoryPatch_CTFFlameEntity_OnCollide_Falloff_Patch()
{
    MemoryPatch_CTFFlameEntity_OnCollide_Falloff_New = notnheavy_flamethrower_falloff.FloatValue;
    MemoryPatch_CTFFlameEntity_OnCollide_Falloff.Write(AddressOf(MemoryPatch_CTFFlameEntity_OnCollide_Falloff_New));
}

//////////////////////////////////////////////////////////////////////////////
// UTIL                                                                     //
//////////////////////////////////////////////////////////////////////////////

// Uses a global trace result.
static void UTIL_TraceLine(const Vector& vecAbsStart, const Vector& vecAbsEnd, int mask, TraceEntityFilter pFilter, any data = 0)
{
    float startBuffer[3];
    float endBuffer[3];
    vecAbsStart.GetBuffer(startBuffer);
    vecAbsEnd.GetBuffer(endBuffer);
    TR_TraceRayFilter(startBuffer, endBuffer, mask, RayType_EndPoint, pFilter, data);
}

static bool CTraceFilterIgnoreObjects(int pServerEntity, int contentsMask, int pOwner)
{
    char class[MAX_NAME_LENGTH];
    GetEntityClassname(pServerEntity, class, sizeof(class));
    if (StrContains(class, "obj_") != -1 || pServerEntity == pOwner)
        return false;
    return true;
}

//////////////////////////////////////////////////////////////////////////////
// CTFPLAYERSHARED                                                          //
//////////////////////////////////////////////////////////////////////////////

static RuneTypes_t GetCarryingRuneType(int pThis)
{
    RuneTypes_t retVal = RUNE_NONE;
    for (RuneTypes_t i = view_as<RuneTypes_t>(0); i < RUNE_TYPES_MAX; ++i)
    {
        if (TF2_IsPlayerInCondition(pThis, view_as<TFCond>(GetConditionFromRuneType(i))))
        {
            retVal = i;
            break;
        }
    }
    return retVal;
}

//////////////////////////////////////////////////////////////////////////////
// CBASEENTITY                                                              //
//////////////////////////////////////////////////////////////////////////////

// Not gonna use my own methodmaps here, I don't think it matters so much with this project.
static bool IsEFlagSet(int pThis, int nEFlagMask)
{
    return (GetEntProp(pThis, Prop_Data, "m_iEFlags") & nEFlagMask) != 0;
}

static Vector GetAbsVelocity(int pThis)
{
    if (IsEFlagSet(pThis, EFL_DIRTY_ABSVELOCITY))
        SDKCall(SDKCall_CBaseEntity_CalcAbsoluteVelocity, pThis);
    return view_as<Vector>(GetEntityAddress(pThis) + FindDataMapInfo(pThis, "m_vecAbsVelocity")); // this returns Vector& internally, so here we'll also get the reference.
}

static QAngle GetAbsAngles(int pThis)
{
    if (IsEFlagSet(pThis, EFL_DIRTY_ABSTRANSFORM))
        SDKCall(SDKCall_CBaseEntity_CalcAbsolutePosition, pThis);
    return view_as<QAngle>(GetEntityAddress(pThis) + FindDataMapInfo(pThis, "m_angAbsRotation"));
}

// This vector is stored onto the accumulator and must be assigned immediately.
static Vector EyePosition(int pThis)
{
    Vector vecResult = Vector.Accumulator();
    float buffer[3];
    SDKCall(SDKCall_CBaseEntity_EyePosition, pThis, buffer);
    vecResult.SetFromBuffer(buffer);
    return vecResult;
}

static QAngle EyeAngles(int pThis)
{
    return SDKCall(SDKCall_CBaseEntity_EyeAngles, pThis);
}

//////////////////////////////////////////////////////////////////////////////
// CBASECOMBATCHARACTER                                                     //
//////////////////////////////////////////////////////////////////////////////

// This vector is stored onto the accumulator and must be assigned immediately.
static Vector Weapon_ShootPosition(int pThis)
{
    Vector vecResult = Vector.Accumulator();
    float buffer[3];
    SDKCall(SDKCall_CBaseCombatCharacter_Weapon_ShootPosition, pThis, buffer);
    vecResult.SetFromBuffer(buffer);
    return vecResult;
}

//////////////////////////////////////////////////////////////////////////////
// CTFPLAYER                                                                //
//////////////////////////////////////////////////////////////////////////////

static void DoAnimationEvent(int pThis, PlayerAnimEvent_t event, int mData = 0)
{
    SDKCall(SDKCall_CTFPlayer_DoAnimationEvent, pThis, event, mData);
}

static int GetEquippedDemoShield(int pThis)
{
    CUtlVector m_hMyWearables = view_as<CUtlVector>(GetEntityAddress(pThis) + FindSendPropInfo("CTFPlayer", "m_hMyWearables"));
    for (int i = 0; i < m_hMyWearables.Count(); ++i)
    {
        int wearable = m_hMyWearables.Get(i).DereferenceEHandle();
        char class[MAX_NAME_LENGTH];
        GetEntityClassname(wearable, class, sizeof(class));
        if (StrEqual(class, "tf_wearable_demoshield"))
            return wearable;
    }
    return -1;
}

//////////////////////////////////////////////////////////////////////////////
// CTFWEAPONBASE                                                            //
//////////////////////////////////////////////////////////////////////////////

static bool SendWeaponAnim(int pThis, int iActivity)
{
    return SDKCall(SDKCall_CTFWeaponBase_SendWeaponAnim, pThis, iActivity);
}

//////////////////////////////////////////////////////////////////////////////
// CTFFLAMETHROWER                                                          //
//////////////////////////////////////////////////////////////////////////////

// If allocated is set to false, this vector will be put onto the accumulator and must be assigned immediately. Otherwise, remember to free() when done.
static Vector GetMuzzlePosHelper(int pThis, bool bVisualPos, bool allocate = false)
{
    Vector vecMuzzlePos = Vector.Malloc();
    int pOwner = GetEntPropEnt(pThis, Prop_Send, "m_hOwnerEntity");
    if (pOwner != -1)
    {
        STACK_ALLOC(vecForward, Vector, VECTOR_SIZE);
        STACK_ALLOC(vecRight, Vector, VECTOR_SIZE);
        STACK_ALLOC(vecUp, Vector, VECTOR_SIZE);
        AngleVectors(GetAbsAngles(pOwner), vecForward, vecRight, vecUp);
        vecMuzzlePos.Assign(Weapon_ShootPosition(pOwner));
        vecMuzzlePos.Assign(vecMuzzlePos + vecRight * TF_FLAMETHROWER_MUZZLEPOS_RIGHT);

        // if asking for visual position of muzzle, include the forward component
        if (bVisualPos)
            vecMuzzlePos.Assign(vecMuzzlePos + vecForward * TF_FLAMETHROWER_MUZZLEPOS_FORWARD);
    }
    if (allocate)
        return vecMuzzlePos;
    else
    {
        Vector vecReturn = Vector.Accumulator();
        memcpy(vecReturn, vecMuzzlePos, VECTOR_SIZE);
        return vecReturn;
    }
}

// If allocated is set to false, this vector will be put onto the accumulator and must be assigned immediately. Otherwise, remember to free() when done.
static Vector GetVisualMuzzlePos(int pThis, bool allocate = false)
{
    return GetMuzzlePosHelper(pThis, true, allocate);
}

// If allocated is set to false, this vector will be put onto the accumulator and must be assigned immediately. Otherwise, remember to free() when done.
static Vector GetFlameOriginPos(int pThis, bool allocate = false)
{
    return GetMuzzlePosHelper(pThis, false, allocate);
}

static void SetWeaponState(int pThis, FlameThrowerState_t nWeaponState)
{
    if (GetEntProp(pThis, Prop_Send, "m_iWeaponState") == view_as<int>(nWeaponState))
        return;
    int pOwner = GetEntPropEnt(pThis, Prop_Data, "m_hOwner");

    switch (nWeaponState)
    {
        case FT_STATE_IDLE:
        {
            float flFiringForwardPull = 0.00;
            flFiringForwardPull = TF2Attrib_HookValueFloat(flFiringForwardPull, "firing_forward_pull", pThis);
            if (flFiringForwardPull)
                TF2_RemoveCondition(pOwner, view_as<TFCond>(TF_COND_SPEED_BOOST));
        }
        case FT_STATE_STARTFIRING:
        {
            float flFiringForwardPull = 0.00;
            flFiringForwardPull = TF2Attrib_HookValueFloat(flFiringForwardPull, "firing_forward_pull", pThis);
            if (flFiringForwardPull)
                TF2_AddCondition(pOwner, view_as<TFCond>(TF_COND_SPEED_BOOST));
        }
    }

    SetEntProp(pThis, Prop_Send, "m_iWeaponState", nWeaponState);
}

//////////////////////////////////////////////////////////////////////////////
// CTFFLAMEENTITY                                                           //
//////////////////////////////////////////////////////////////////////////////

static void SetCritFromBehind(Pointer pThis, bool bState)
{
    pThis.Write(bState, CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_BCRITFROMBEHIND, NumberType_Int8);
}

static int CreateFlameEntity(Vector vecOrigin, QAngle vecAngles, int pOwner, float flSpeed, int iDmgType, float m_flDmgAmount, bool bAlwaysCritFromBehind, bool bRandomize = true)
{
    int pFlame = SDKCall(SDKCall_CBaseEntity_Create, "tf_flame", vecOrigin, vecAngles, pOwner);
    if (pFlame == -1)
        return -1;

    Pointer flamePointer = Pointer(GetEntityAddress(pFlame));
    Vector m_vecBaseVelocity = view_as<Vector>(flamePointer + CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_VECBASEVELOCITY);
    if (HasEntProp(pOwner, Prop_Send, "m_hOwnerEntity") && GetEntPropEnt(pOwner, Prop_Send, "m_hOwnerEntity") != -1)
        flamePointer.WriteEHandle(GetEntPropEnt(pOwner, Prop_Send, "m_hOwnerEntity"), CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_HATTACKER); // pFlame->m_hAttacker = pOwner->GetOwnerEntity();
    else
        flamePointer.WriteEHandle(pOwner, CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_HATTACKER); // pFlame->m_hAttacker = pOwner;
    
    // this is not apparent anymore?
    // pFlame->m_iAttackerTeam = pAttacker->GetTeamNumber();
    //if (flamePointer.DereferenceEHandle(CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_HATTACKER) != -1)
    //    flamePointer.Write(GetEntProp(flamePointer.DereferenceEHandle(CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_HATTACKER), Prop_Send, "m_iTeamNum"), CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_IATTACKERTEAM);

    // Set team.
    SetEntProp(pFlame, Prop_Send, "m_iTeamNum", GetEntProp(pOwner, Prop_Send, "m_iTeamNum")); // pFlame->ChangeTeam( pOwner->GetTeamNumber() );
    flamePointer.Write(iDmgType, CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_IDMGTYPE); // pFlame->m_iDmgType = iDmgType;
    flamePointer.Write(m_flDmgAmount, CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_FLDMGAMOUNT); // pFlame->m_flDmgAmount = flDmgAmount;

    // Setup the initial velocity.
    STACK_ALLOC(vecForward, Vector, VECTOR_SIZE);
    STACK_ALLOC(vecRight, Vector, VECTOR_SIZE);
    STACK_ALLOC(vecUp, Vector, VECTOR_SIZE);
    AngleVectors(vecAngles, vecForward, vecRight, vecUp);

    float flFlameLifeMult = 1.00;
    flFlameLifeMult = TF2Attrib_HookValueFloat(flFlameLifeMult, "mult_flame_life", flamePointer.DereferenceEHandle(CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_HATTACKER)); // CALL_ATTRIB_HOOK_FLOAT_ON_OTHER( pFlame->m_hAttacker, flFlameLifeMult, mult_flame_life );
    float velocity = flFlameLifeMult * flSpeed;
    memcpy(m_vecBaseVelocity, vecForward * velocity, VECTOR_SIZE); // pFlame->m_vecBaseVelocity = vecForward * velocity;
    float iFlameSizeMult = 1.00;
    iFlameSizeMult = TF2Attrib_HookValueFloat(iFlameSizeMult, "mult_flame_size", flamePointer.DereferenceEHandle(CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_HATTACKER)); // CALL_ATTRIB_HOOK_FLOAT_ON_OTHER( pFlame->m_hAttacker, iFlameSizeMult, mult_flame_size );

    // pFlame->m_vecBaseVelocity += RandomVector( -velocity * iFlameSizeMult * tf_flamethrower_vecrand.GetFloat(), velocity * iFlameSizeMult * tf_flamethrower_vecrand.GetFloat() );
    if (bRandomize)
        m_vecBaseVelocity.Assign(m_vecBaseVelocity + RandomVector(-velocity * iFlameSizeMult * tf_flamethrower_vecrand.FloatValue, velocity * iFlameSizeMult * tf_flamethrower_vecrand.FloatValue));

    if (HasEntProp(pOwner, Prop_Send, "m_hOwnerEntity") && GetEntPropEnt(pOwner, Prop_Send, "m_hOwnerEntity") != -1)
        memcpy(flamePointer + CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_VECATTACKERVELOCITY, GetAbsVelocity(GetEntPropEnt(pOwner, Prop_Send, "m_hOwnerEntity")), VECTOR_SIZE); // pFlame->m_vecAttackerVelocity = pOwner->GetOwnerEntity()->GetAbsVelocity();
    SDKCall(SDKCall_CBaseEntity_SetAbsVelocity, pFlame, m_vecBaseVelocity); // pFlame->SetAbsVelocity( pFlame->m_vecBaseVelocity );	

    // Setup the initial angles.
    SDKCall(SDKCall_CBaseEntity_SetAbsAngles, pFlame, vecAngles); // pFlame->SetAbsAngles( vecAngles );
    SetCritFromBehind(flamePointer, bAlwaysCritFromBehind); // pFlame->SetCritFromBehind( bAlwaysCritFromBehind );
    
    return pFlame;
}

//////////////////////////////////////////////////////////////////////////////
// FORWARDS                                                                 //
//////////////////////////////////////////////////////////////////////////////

public void OnEntityCreated(int entity, const char[] classname)
{
    if (1 <= entity <= MaxClients)
        SetupPlayerHooks(entity);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (notnheavy_flamethrower_enable.BoolValue)
    {
        int flamethrower = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
        if (flamethrower == GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") && IsValidEntity(flamethrower))
        {
            char class[MAX_NAME_LENGTH];
            GetEntityClassname(flamethrower, class, sizeof(class));
            if (StrEqual(class, "tf_weapon_flamethrower"))
            {
                STACK_ALLOC(vecEye, Vector, VECTOR_SIZE);
                STACK_ALLOC(vecMuzzlePos, Vector, VECTOR_SIZE);
                vecEye.Assign(EyePosition(client));
                vecMuzzlePos.Assign(GetVisualMuzzlePos(flamethrower));
                UTIL_TraceLine(vecEye, vecMuzzlePos, MASK_SOLID, CTraceFilterIgnoreObjects, client);

                if (TR_GetFraction() < 1.00 && (TR_GetEntityIndex() == -1 || GetEntProp(TR_GetEntityIndex(), Prop_Data, "m_takedamage") == DAMAGE_NO))
                {
                    if (GetEntProp(flamethrower, Prop_Send, "m_iWeaponState") > view_as<int>(FT_STATE_IDLE))
                        SetWeaponState(flamethrower, FT_STATE_IDLE);
                    buttons &= ~IN_ATTACK;
                    return Plugin_Changed;
                }
            }
        }
    }

    return Plugin_Continue;
}

public void OnGameFrame()
{
    for (int client = 1; client <= MaxClients; ++client)
    {
        if (IsClientInGame(client) && PlayerData[client].m_flRemoveBurn < GetGameTime() && PlayerData[client].m_flRemoveBurn != 0.00 && notnheavy_flamethrower_enable.BoolValue && notnheavy_flamethrower_oldafterburn_duration.BoolValue)
        {
            PlayerData[client].m_flRemoveBurn = 0.00;
            TF2_RemoveCondition(client, TFCond_OnFire);
        }
    }
    OnGameFrame_2();
}

//////////////////////////////////////////////////////////////////////////////
// HOOKS                                                                    //
//////////////////////////////////////////////////////////////////////////////

public void AdjustFalloff(ConVar convar, const char[] oldValue, const char[] newValue)
{
    MemoryPatch_CTFFlameEntity_OnCollide_Falloff_Patch();
    PrintToServer("Flamethrower falloff with tf_flame has been changed to %f.", view_as<Pointer>(MemoryPatch_CTFFlameEntity_OnCollide_Falloff.Dereference()).Dereference());
}

static void SetupPlayerHooks(int entity)
{
    PlayerData[entity].index = entity; // dumb shortcut but whatever
    PlayerData[entity].m_flNextPrimaryAttack = 0.00;
    PlayerData[entity].m_Shared = view_as<Pointer>(GetEntityAddress(entity) + FindSendPropInfo("CTFPlayer", "m_Shared"));
    SDKHook(entity, SDKHook_OnTakeDamage, Pre_OnTakeDamage);
}

// pre-call CTFPlayer::OnTakeDamage(), using SDKHooks.
// Re-write afterburn damage, if the convar notnheavy_flamethrower_oldafterburn_damage is true.
Action Pre_OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    if (notnheavy_flamethrower_enable.BoolValue && notnheavy_flamethrower_oldafterburn_damage.BoolValue && damagetype == (DMG_BURN | DMG_PREVENT_PHYSICS_FORCE))
    {
        damage = TF_BURNING_DMG;
        if (IsValidEntity(weapon))
            damage = TF2Attrib_HookValueFloat(damage, "mult_wpn_burndmg", weapon);
        return Plugin_Changed;
    }
    return Plugin_Continue;
}

public Action PostInventoryApplication(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    PlayerData[client].m_flStartFiringTime = 0.00;
    PlayerData[client].m_flNextPrimaryAttackAnim = 0.00;
    PlayerData[client].m_flAmmoUseRemainder = 0.00;
    return Plugin_Continue;
}

// pre-call CTFFlameThrower::PrimaryAttack();
// This is only just so I don't have to re-write ammo management with the flamethrowers.
MRESReturn Pre_PrimaryAttack(int entity)
{
    // Get the owner of this weapon.
    int pOwner = GetEntPropEnt(entity, Prop_Data, "m_hOwner");
    if (pOwner == -1)
        return MRES_Ignored;

    PlayerData[pOwner].m_iFlamethrowerAmmo = PlayerData[pOwner].GetAmmoCount(view_as<int>(TF_AMMO_PRIMARY));
    return MRES_Ignored;
}

// post-call CTFFlameThrower::PrimaryAttack();
// The route I'm taking is hacky; I'm srnot sure what would be the best way to get around with flame visuals otherwise. 
// Essentially, the original function will still be called. However, there'll be another layer to this function that 
// spawns the stream of tf_flame entities.
//
// This hook emits certain things, either things that I find unnecessary at this moment, or are already handled in the internal function.
MRESReturn Post_PrimaryAttack(int entity)
{
    if (notnheavy_flamethrower_enable.BoolValue)
    {
        // Get the pointer for this CTFFlameThrower entity.
        Pointer pEntity = Pointer(GetEntityAddress(entity));
        static int frame = 0;
        ++frame;
        
        // Get the owner of this weapon.
        int pOwner = GetEntPropEnt(entity, Prop_Data, "m_hOwner");
        if (pOwner == -1)
            return MRES_Ignored;
        
        // Revert ammo to pre-call.
        PlayerData[pOwner].SetAmmoCount(PlayerData[pOwner].m_iFlamethrowerAmmo, view_as<int>(TF_AMMO_PRIMARY));

        // Check for if we're capable of firing.
        if (PlayerData[pOwner].m_flNextPrimaryAttack > GetGameTime())
            return MRES_Ignored;
        
        if (!SDKCall(SDKCall_CTFWeaponBase_CanAttack, entity))
        {
            SetWeaponState(entity, FT_STATE_IDLE);
            return MRES_Ignored;
        }
        pEntity.Write(TF_WEAPON_PRIMARY_MODE, CTFWeaponBase_m_iWeaponMode);

        SDKCall(SDKCall_CTFWeaponBase_CalcIsAttackCritical, entity);

        // Because the muzzle is so long, it can stick through a wall if the player is right up against it.
        // Make sure the weapon can't fire in this condition by tracing a line between the eye point and the end of the muzzle.
        /*
        trace_t trace;	
        Vector vecEye = pOwner->EyePosition();
        Vector vecMuzzlePos = GetVisualMuzzlePos();
        CTraceFilterIgnoreObjects traceFilter( this, COLLISION_GROUP_NONE );
        UTIL_TraceLine( vecEye, vecMuzzlePos, MASK_SOLID, &traceFilter, &trace );
        if ( trace.fraction < 1.0 && ( !trace.m_pEnt || trace.m_pEnt->m_takedamage == DAMAGE_NO ) )
        {
            // there is something between the eye and the end of the muzzle, most likely a wall, don't fire, and stop firing if we already are
            if ( m_iWeaponState > FT_STATE_IDLE )
            {
                SetWeaponState( FT_STATE_IDLE );
            }
            return;
        }
        */
        // See OnPlayerRunCmd().

        // Deal with weapon animations.
        switch (view_as<FlameThrowerState_t>(GetEntProp(entity, Prop_Send, "m_iWeaponState")))
        {
            case FT_STATE_IDLE:
            {
                DoAnimationEvent(pOwner, PLAYERANIMEVENT_ATTACK_PRE);
                SendWeaponAnim(entity, ACT_VM_PRIMARYATTACK);
                PlayerData[pOwner].m_flStartFiringTime = GetGameTime() + 0.16;
                SetWeaponState(entity, FT_STATE_STARTFIRING);
            }
            case FT_STATE_STARTFIRING:
            {
                if (GetGameTime() > PlayerData[pOwner].m_flStartFiringTime)
                {
                    SetWeaponState(entity, FT_STATE_FIRING);
                    PlayerData[pOwner].m_flNextPrimaryAttackAnim = GetGameTime();
                }
            }
            case FT_STATE_FIRING:
            {
                if (GetGameTime() >= PlayerData[pOwner].m_flNextPrimaryAttackAnim)
                {
                    DoAnimationEvent(pOwner, PLAYERANIMEVENT_ATTACK_PRIMARY);
                    PlayerData[pOwner].m_flNextPrimaryAttackAnim = GetGameTime() + 1.40;
                }
            }
        }

        // Check if we're not underwater, in that case, fire!
        float flFiringInterval = 0.044;
        if (GetEntProp(pOwner, Prop_Send, "m_nWaterLevel") != WL_Eyes)
        {
            int iDmgType = DMGTYPE;
            if (GetEntProp(entity, Prop_Send, "m_bCritFire"))
                iDmgType |= DMG_CRIT;

            // Create the flame entity.
            float flDamage = notnheavy_flamethrower_damage.FloatValue; // 6.80 by default
            flDamage = TF2Attrib_HookValueFloat(flDamage, "mult_dmg", entity);

            int iCritFromBehind = 0;
            iCritFromBehind = TF2Attrib_HookValueInt(iCritFromBehind, "set_flamethrower_back_crit", entity);

            CreateFlameEntity(GetFlameOriginPos(entity), EyeAngles(pOwner), entity, tf_flamethrower_velocity.FloatValue, iDmgType, flDamage, iCritFromBehind == 1);
        }

        // Figure how much ammo we're using.
        float flAmmoPerSecond = TF_FLAMETHROWER_AMMO_PER_SECOND_PRIMARY_ATTACK;
        flAmmoPerSecond = TF2Attrib_HookValueFloat(flAmmoPerSecond, "mult_flame_ammopersec", entity);
        PlayerData[pOwner].m_flAmmoUseRemainder += flAmmoPerSecond * flFiringInterval;
        
        int iAmmoToSubtract = RoundToFloor(PlayerData[pOwner].m_flAmmoUseRemainder); // basically (int)m_flAmmoUseRemainder.
        if (iAmmoToSubtract > 0)
        {
            PlayerData[pOwner].m_iFlamethrowerAmmo -= iAmmoToSubtract;
            PlayerData[pOwner].m_flAmmoUseRemainder -= iAmmoToSubtract;

            // round to 2 digits of precision
            PlayerData[pOwner].m_flAmmoUseRemainder = RoundToFloor(PlayerData[pOwner].m_flAmmoUseRemainder * 100) / 100.00;
        }

        // Finish this detour.
        PlayerData[pOwner].m_flNextPrimaryAttack = GetGameTime() + flFiringInterval;
        PlayerData[pOwner].SetAmmoCount(PlayerData[pOwner].m_iFlamethrowerAmmo, view_as<int>(TF_AMMO_PRIMARY));
    }
    return MRES_Ignored;
}

// CTFFlameThrower::FireAirblast();
// Fix the next primary attack timer in this detour.
MRESReturn FireAirBlast(int entity, DHookParam parameters)
{
    // Get the owner of this weapon.
    int pOwner = GetEntPropEnt(entity, Prop_Data, "m_hOwner");
    if (pOwner == -1)
        return MRES_Ignored;

    float fAirblastRefireTimeScale = 1.00;
    fAirblastRefireTimeScale = TF2Attrib_HookValueFloat(fAirblastRefireTimeScale, "mult_airblast_refire_time", entity);
    if (fAirblastRefireTimeScale <= 0.00)
        fAirblastRefireTimeScale = 1.00;

    float fAirblastPrimaryRefireTimeScale = 1.00;
    fAirblastPrimaryRefireTimeScale = TF2Attrib_HookValueFloat(fAirblastPrimaryRefireTimeScale, "mult_airblast_primary_refire_time", entity);
    if (fAirblastPrimaryRefireTimeScale <= 0.00)
        fAirblastPrimaryRefireTimeScale = 1.00;

    // Haste Powerup Rune adds multiplier to fire delay time
    if (GetCarryingRuneType(pOwner) == RUNE_HASTE)
        fAirblastRefireTimeScale *= 0.50;

    PlayerData[pOwner].m_flNextPrimaryAttack = GetGameTime() + (1.00 * fAirblastRefireTimeScale * fAirblastPrimaryRefireTimeScale);
    return MRES_Ignored;
}

// CTFFlameManager::OnCollide();
// Supercede this just to prevent damage-dealing.
MRESReturn OnCollide(int entity, DHookParam parameters)
{
    if (notnheavy_flamethrower_enable.BoolValue)
        return MRES_Supercede;
    return MRES_Ignored;
}

// post-call CTFPlayerShared::Burn();
// Adjust afterburn duration, if notnheavy_flamethrower_oldafterburn_duration is on.
MRESReturn Burn(Address aThis, DHookParam parameters)
{
    if (notnheavy_flamethrower_enable.BoolValue && notnheavy_flamethrower_oldafterburn_duration.BoolValue)
    {
        Pointer pThis = view_as<Pointer>(aThis);
        int m_pOuter = view_as<Pointer>(pThis.Dereference(CTFPlayerShared_m_pOuter)).DereferenceEntity();
        int pWeapon = parameters.Get(2);
        float flBurningTime = parameters.Get(3);
        if (!IsPlayerAlive(m_pOuter) || TF2_IsPlayerInCondition(m_pOuter, view_as<TFCond>(TF_COND_PHASE)) || TF2_IsPlayerInCondition(m_pOuter, view_as<TFCond>(TF_COND_PASSTIME_INTERCEPTION)))
            return MRES_Ignored;

        bool bVictimIsPyro = TF2_GetPlayerClass(m_pOuter) == TFClass_Pyro;

        int nAfterburnImmunity = 0;

        int pMyWeapon = GetEntPropEnt(m_pOuter, Prop_Send, "m_hActiveWeapon");
        if (IsValidEntity(pMyWeapon))
            nAfterburnImmunity = TF2Attrib_HookValueInt(nAfterburnImmunity, "afterburn_immunity", pMyWeapon);

        if (TF2_IsPlayerInCondition(m_pOuter, view_as<TFCond>(TF_COND_AFTERBURN_IMMUNE)))
        {
            nAfterburnImmunity = 1;
            pThis.Write(0, CTFPlayerShared_m_flBurnDuration);
        }

        int shield = GetEquippedDemoShield(m_pOuter);
        if (IsValidEntity(shield) && !GetEntProp(shield, Prop_Send, "m_bDisguiseWearable"))
            nAfterburnImmunity = TF2Attrib_HookValueInt(nAfterburnImmunity, "afterburn_immunity", shield);

        float flFlameLife;
        if (bVictimIsPyro || nAfterburnImmunity)
        {
            flFlameLife = TF_BURNING_FLAME_LIFE;
            PlayerData[m_pOuter].m_flRemoveBurn = GetGameTime() + TF_BURNING_FLAME_LIFE_PYRO;
        }
        else if (flBurningTime > 0.00)
            flFlameLife = flBurningTime;
        else
        {
            float length = TF_BURNING_FLAME_LIFE;
            if (IsValidEntity(pMyWeapon))
            {
                char class[MAX_NAME_LENGTH];
                GetEntityClassname(pMyWeapon, class, sizeof(class));
                if (StrEqual(class, "tf_weapon_particle_cannon"))
                    length = TF_BURNING_FLAME_LIFE_PLASMA;
            }
            flFlameLife = length;
        }
        flFlameLife = TF2Attrib_HookValueFloat(flFlameLife, "mult_wpn_burntime", pWeapon);

        if (flFlameLife > pThis.Dereference(CTFPlayerShared_m_flBurnDuration))
            pThis.Write(flFlameLife, CTFPlayerShared_m_flBurnDuration);
    }

    return MRES_Ignored;
}

static int LaserBeamIndex = 0;

public void OnMapStart()
{
    LaserBeamIndex = PrecacheModel("sprites/laser.vmt");
}

static Vector GetAbsOrigin(int pThis)
{
    if (IsEFlagSet(pThis, EFL_DIRTY_ABSTRANSFORM))
        SDKCall(SDKCall_CBaseEntity_CalcAbsolutePosition, pThis);
    return view_as<Vector>(GetEntityAddress(pThis) + FindDataMapInfo(pThis, "m_vecAbsOrigin"));
}

stock void TE_SendBeamBoxToAll(const float uppercorner[3], const float bottomcorner[3], int ModelIndex, int HaloIndex, int StartFrame, int FrameRate, float Life, float Width, float EndWidth, int FadeLength, float Amplitude, const int Color[4], int Speed) {
    // Create the additional corners of the box
    float tc1[3];
    AddVectors(tc1, uppercorner, tc1);
    tc1[0] = bottomcorner[0];

    float tc2[3];
    AddVectors(tc2, uppercorner, tc2);
    tc2[1] = bottomcorner[1];

    float tc3[3];
    AddVectors(tc3, uppercorner, tc3);
    tc3[2] = bottomcorner[2];

    float tc4[3];
    AddVectors(tc4, bottomcorner, tc4);
    tc4[0] = uppercorner[0];

    float tc5[3];
    AddVectors(tc5, bottomcorner, tc5);
    tc5[1] = uppercorner[1];

    float tc6[3];
    AddVectors(tc6, bottomcorner, tc6);
    tc6[2] = uppercorner[2];

    // Draw all the edges
    TE_SetupBeamPoints(uppercorner, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(uppercorner, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(uppercorner, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc6, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc6, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc6, bottomcorner, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc4, bottomcorner, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc5, bottomcorner, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc5, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc5, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc4, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
    TE_SetupBeamPoints(tc4, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToAll();
}

public void OnGameFrame_2()
{
    static int frame = 0;
    ++frame;
    for (int entity = MAXPLAYERS + 1; entity < 2048; ++entity)
    {
        if (IsValidEntity(entity))
        {
            char class[128];
            GetEntityClassname(entity, class, sizeof(class));
            if (StrEqual(class, "tf_flame") && frame % 4 == 0)
            {
                float mins[3];
                float maxs[3];
                float origin[3];
                Vector originVector = GetAbsOrigin(entity);
                originVector.GetBuffer(origin);
                GetAbsVelocity(entity);
                GetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
                GetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs);
                AddVectors(mins, origin, mins);
                AddVectors(maxs, origin, maxs);
                TE_SendBeamBoxToAll(mins, maxs, LaserBeamIndex, 0, 0, 1, 0.06, 1.00, 1.00, 0, 0.00, {255, 255, 255, 255}, 10);
            }
        }
    }
}