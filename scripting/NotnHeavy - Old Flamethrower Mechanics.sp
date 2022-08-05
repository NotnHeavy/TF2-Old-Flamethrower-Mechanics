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

#pragma semicolon true 
#pragma newdecls required

#include <sourcemod>
#include <smmem>
#include <tf2attributes>
#include <dhooks>
#include <sdkhooks>
#include <tf2>

#include "SMTC/SMTC"
#include "SMTC/Pointer"
#include "SMTC/Vector"
#include "SMTC/QAngle"

#define PLUGIN_NAME "NotnHeavy - Old Flamethrower Mechanics"

#define TF_FLAMETHROWER_MUZZLEPOS_FORWARD		70.00
#define TF_FLAMETHROWER_MUZZLEPOS_RIGHT			12.00
#define TF_FLAMETHROWER_MUZZLEPOS_UP			-12.00

#define OFM_CUTLVECTOR_SIZE 20 // in case cutlvector.inc isn't included from SMTC.

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
    CTFFLAMEENTITY_OFFSET_M_IATTACKERTEAM = CTFFLAMEENTITY_OFFSET_M_HATTACKER + 4,                       // int m_iAttackerTeam;
    CTFFLAMEENTITY_OFFSET_M_BCRiTFROMBEHIND = CTFFLAMEENTITY_OFFSET_M_IATTACKERTEAM + 4,                 // bool m_bCritFromBehind;
    CTFFLAMEENTITY_OFFSET_M_BBURNEDENEMY = CTFFLAMEENTITY_OFFSET_M_BCRiTFROMBEHIND + 1,                  // bool m_bBurnedEnemy;
    CTFFLAMEENTITY_OFFSET_M_HFLAMETHROWER = CTFFLAMEENTITY_OFFSET_M_BBURNEDENEMY + 2,                    // CHandle<CTFFlameThrower> m_hFlameThrower;

    CTFFLAMEENTITY_SIZE = CTFFLAMEENTITY_OFFSET_M_HFLAMETHROWER + 4
};

static Handle SDKCall_CBaseEntity_Create;
static Handle SDKCall_CBaseEntity_CalcAbsoluteVelocity;
static Handle SDKCall_CBaseEntity_SetAbsVelocity;
static Handle SDKCall_CBaseEntity_SetAbsAngles;
static Handle SDKCall_CBaseEntity_CalcAbsolutePosition;
static Handle SDKCall_CBaseCombatCharacter_Weapon_ShootPosition;

static ConVar tf_flamethrower_velocity;
static ConVar tf_flamethrower_vecrand;

static int CTFFlameEntity_Base;

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

    // Load config data!
    GameData config = LoadGameConfigFile(PLUGIN_NAME);

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
    PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "CBaseCombatCharacter::Weapon_ShootPosition()");
    PrepSDKCall_SetReturnInfo(SDKType_Vector, SDKPass_ByValue); // Vector
    SDKCall_CBaseCombatCharacter_Weapon_ShootPosition = EndPrepSDKCall();

    CTFFlameEntity_Base = config.GetOffset("CTFFlameEntity::m_vecInitialPos");

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
        AngleVectors(GetAbsAngles(pOwner), vecForward, vecRight);
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
    return GetMuzzlePosHelper(pThis, allocate);
}

//////////////////////////////////////////////////////////////////////////////
// CTFFLAMEENTITY                                                           //
//////////////////////////////////////////////////////////////////////////////

static void SetCritFromBehind(Pointer pThis, bool bState)
{
    pThis.Write(bState, CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_BCRiTFROMBEHIND, NumberType_Int8);
}

static int CreateFlameEntity(Vector vecOrigin, QAngle vecAngles, int pOwner, float flSpeed, int iDmgType, float m_flDmgAmount, bool bAlwaysCritFromBehind, bool bRandomize = true)
{
    // MUST RE-CREATE FUNCTION FOR WINDOWS SUPPORT
    /*
    SDKCall(SDKCall_CFFlameEntity_Create, vecOrigin, vecAngles, pOwner, flSpeed, iDmgType, m_flDmgAmount, bAlwaysCritFromBehind, bRandomize);
    */

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
    if (flamePointer.DereferenceEHandle(CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_HATTACKER) != -1)
        flamePointer.Write(GetEntProp(flamePointer.DereferenceEHandle(CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_HATTACKER), Prop_Send, "m_iTeamNum"), CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_IATTACKERTEAM);

    // Set team.
    SetEntProp(pFlame, Prop_Send, "m_iTeamNum", GetEntProp(pOwner, Prop_Send, "m_iTeamNum")); // pFlame->ChangeTeam( pOwner->GetTeamNumber() );
    flamePointer.Write(iDmgType, CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_IDMGTYPE); // pFlame->m_iDmgType = iDmgType;
    flamePointer.Write(m_flDmgAmount, CTFFlameEntity_Base + CTFFLAMEENTITY_OFFSET_M_FLDMGAMOUNT); // pFlame->m_flDmgAmount = flDmgAmount;

    // Setup the initial velocity.
    STACK_ALLOC(vecForward, Vector, VECTOR_SIZE);
    AngleVectors(vecAngles, vecForward);

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

public void OnGameFrame()
{
    static int frame = 0;
    ++frame;
    int client = 1;
    if (IsClientInGame(client) && GetClientButtons(client) & IN_ATTACK)
    {
        int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
        char name[128];
        GetEntityClassname(weapon, name, sizeof(name));
        if (weapon != -1 && frame % 3 == 0 && StrEqual(name, "tf_weapon_flamethrower"))
        {
            float buffer[3];
            STACK_ALLOC(eyeAngles, QAngle, QANGLE_SIZE);
            GetClientEyeAngles(client, buffer);
            eyeAngles.SetFromBuffer(buffer);

            CreateFlameEntity(GetFlameOriginPos(weapon), eyeAngles, weapon, tf_flamethrower_velocity.FloatValue, DMG_IGNITE | DMG_PREVENT_PHYSICS_FORCE | DMG_PREVENT_PHYSICS_FORCE, 6.82 * 8.00, false);
        }
    }
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (1 <= entity <= MaxClients)
        SetupPlayerHooks(entity);
}

//////////////////////////////////////////////////////////////////////////////
// SDKHOOKS                                                                 //
//////////////////////////////////////////////////////////////////////////////

static void SetupPlayerHooks(int entity)
{
    SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    // Make the old flame manager not deal any damage.
    if (IsValidEntity(weapon))
    {
        // TEMP, MUST FIGURE OUT ANOTHER WAY
        char name[MAX_NAME_LENGTH];
        GetEntityClassname(weapon, name, sizeof(name));
        if (StrEqual(name, "tf_weapon_flamethrower"))
        {
            if (damage < 14.00)
                return Plugin_Stop;
            damage = damage / 8;
            return Plugin_Changed;
        }
    }

    return Plugin_Continue;
}