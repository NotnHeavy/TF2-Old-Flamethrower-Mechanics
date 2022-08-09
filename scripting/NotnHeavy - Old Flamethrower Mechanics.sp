//////////////////////////////////////////////////////////////////////////////
// MADE BY NOTNHEAVY. USES GPL-3, AS PER REQUEST OF SOURCEMOD               //
//////////////////////////////////////////////////////////////////////////////

// For dynamic memory allocation, this uses Scags' SM-Memory extension.
// https://forums.alliedmods.net/showthread.php?t=327729#

// For TF2 attributes, this uses nosoop's tf2attributes plugin, which is a fork of FlaminSarge's.

// Requires the following from SMTC:
// SMTC.inc
// Pointer.inc
// Vector.inc
// QAngle.inc
// tf_shareddefs.inc

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

//////////////////////////////////////////////////////////////////////////////
// GLOBALS                                                                  //
//////////////////////////////////////////////////////////////////////////////

int max(int x, int y)
{
    return x > y ? x : y;
}

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
    int m_iFlamethrowerAmmo;

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

static Handle SDKCall_CBaseEntity_Create;
static Handle SDKCall_CBaseEntity_CalcAbsoluteVelocity;
static Handle SDKCall_CBaseEntity_SetAbsVelocity;
static Handle SDKCall_CBaseEntity_SetAbsAngles;
static Handle SDKCall_CBaseEntity_CalcAbsolutePosition;
static Handle SDKCall_CBaseEntity_EyeAngles;
static Handle SDKCall_CBaseCombatCharacter_Weapon_ShootPosition;
static Handle SDKCall_CTFWeaponBase_CanAttack;
static Handle SDKCall_CTFWeaponBase_CalcIsAttackCritical;
static Handle SDKCall_CTFWeaponBase_SendWeaponAnim;
static Handle SDKCall_CTFPlayer_DoAnimationEvent;

static int CTFFlameEntity_Base;

static Address CTFWeaponBase_m_iWeaponMode;

static ConVar tf_flamethrower_velocity;
static ConVar tf_flamethrower_vecrand;

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

    delete config;

    // Load ConVars.
    tf_flamethrower_velocity = FindConVar("tf_flamethrower_velocity");
    tf_flamethrower_vecrand = FindConVar("tf_flamethrower_vecrand");

    // Setup hooks for each client.
    for (int i = 1; i <= MaxClients; ++i)
    {
        if (IsClientInGame(i))
            SetupPlayerHooks(i);
    }

    PrintToServer("--------------------------------------------------------\n\"%s\" has loaded.\n--------------------------------------------------------", PLUGIN_NAME);
}

//////////////////////////////////////////////////////////////////////////////
// CBASEENTITY                                                              //
//////////////////////////////////////////////////////////////////////////////

// Not gonna use my own methodmap here, I don't think it matters so much with this project.
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

static Vector GetAbsOrigin(int pThis)
{
    if (IsEFlagSet(pThis, EFL_DIRTY_ABSVELOCITY))
        SDKCall(SDKCall_CBaseEntity_CalcAbsoluteVelocity, pThis);
    return view_as<Vector>(GetEntityAddress(pThis) + FindDataMapInfo(pThis, "m_vecAbsOrigin"));
}

static QAngle GetAbsAngles(int pThis)
{
    if (IsEFlagSet(pThis, EFL_DIRTY_ABSTRANSFORM))
        SDKCall(SDKCall_CBaseEntity_CalcAbsolutePosition, pThis);
    return view_as<QAngle>(GetEntityAddress(pThis) + FindDataMapInfo(pThis, "m_angAbsRotation"));
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
static Vector GetFlameOriginPos(int pThis, bool allocate = false)
{
    return GetMuzzlePosHelper(pThis, false, allocate);
}

static void SetWeaponState(int pThis, FlameThrowerState_t nWeaponState)
{
    // todo: attribute hooks
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

//////////////////////////////////////////////////////////////////////////////
// HOOKS                                                                    //
//////////////////////////////////////////////////////////////////////////////

static void SetupPlayerHooks(int entity)
{
    PlayerData[entity].index = entity; // dumb shortcut but whatever
    PlayerData[client].m_flNextPrimaryAttack = 0.00;
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

    // TODO: implement trace_t/CTraceFilterIgnoreObjects methodmaps in SMTC before working on this.
    /*
    // Because the muzzle is so long, it can stick through a wall if the player is right up against it.
	// Make sure the weapon can't fire in this condition by tracing a line between the eye point and the end of the muzzle.
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
    float flFiringInterval = 0.044; // todo: make this a convar
    if (GetEntProp(pOwner, Prop_Send, "m_nWaterLevel") != WL_Eyes)
    {
        int iDmgType = DMGTYPE;
        if (GetEntProp(entity, Prop_Send, "m_bCritFire"))
            iDmgType |= DMG_CRIT;

        // Create the flame entity.
        float flDamage = 6.80; // todo: make this a convar
        flDamage = TF2Attrib_HookValueFloat(flDamage, "mult_dmg", entity);

        int iCritFromBehind = 0;
        iCritFromBehind = TF2Attrib_HookValueInt(iCritFromBehind, "set_flamethrower_back_crit", entity);

        CreateFlameEntity(GetFlameOriginPos(entity), EyeAngles(pOwner), entity, tf_flamethrower_velocity.FloatValue /* this may need tuning */, iDmgType, flDamage, iCritFromBehind == 1);
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

    // TODO: implement this, alongside GetCarryingRuneType()
    /*
    // Haste Powerup Rune adds multiplier to fire delay time
	if ( pOwner->m_Shared.GetCarryingRuneType() == RUNE_HASTE )
	{
		fAirblastRefireTimeScale *= 0.5f;
	}
    */

    PlayerData[pOwner].m_flNextPrimaryAttack = GetGameTime() + (1.00 * fAirblastRefireTimeScale * fAirblastPrimaryRefireTimeScale);
    return MRES_Ignored;
}

// CTFFlameManager::OnCollide();
// Supercede this just to prevent damage-dealing.
MRESReturn OnCollide(int entity, DHookParam parameters)
{
    return MRES_Supercede;
}