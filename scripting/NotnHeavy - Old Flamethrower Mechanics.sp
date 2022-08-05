//////////////////////////////////////////////////////////////////////////////
// MADE BY NOTNHEAVY. USES GPL-3, AS PER REQUEST OF SOURCEMOD               //
//////////////////////////////////////////////////////////////////////////////

// For dynamic memory allocation, this uses Scags' SM-Memory extension.
// https://forums.alliedmods.net/showthread.php?t=327729#

// Requires the following from SMTC:
// SMTC.inc
// Pointer.inc
// Vector.inc
// QAngle.inc

#pragma semicolon true 
#pragma newdecls required

#include <sourcemod>
#include <smmem>
#include <dhooks>
#include <sdkhooks>

#include "SMTC/SMTC"
#include "SMTC/Pointer"
#include "SMTC/Vector"
#include "SMTC/QAngle"

#define PLUGIN_NAME "NotnHeavy - Old Flamethrower Mechanics"

#define TF_FLAMETHROWER_MUZZLEPOS_FORWARD		70.00
#define TF_FLAMETHROWER_MUZZLEPOS_RIGHT			12.00
#define TF_FLAMETHROWER_MUZZLEPOS_UP			-12.00

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

static Handle SDKCall_CBaseEntity_Create;
static Handle SDKCall_CBaseEntity_CalcAbsoluteVelocity;
static Handle SDKCall_CBaseEntity_SetAbsVelocity;
static Handle SDKCall_CBaseEntity_SetAbsAngles;
static Handle SDKCall_CBaseEntity_CalcAbsolutePosition;
static Handle SDKCall_CBaseCombatCharacter_Weapon_ShootPosition;

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
    PrintToServer("help! %f", buffer[0]);
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
    return GetMuzzlePosHelper(pThis, false);
}

//////////////////////////////////////////////////////////////////////////////
// CTFFLAMEENTITY                                                           //
//////////////////////////////////////////////////////////////////////////////

static void SetCritFromBehind(Pointer pThis, bool bState)
{
    pThis.Write(bState, 944 /*964*/, NumberType_Int8);
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
    if (HasEntProp(pOwner, Prop_Send, "m_hOwnerEntity") && GetEntPropEnt(pOwner, Prop_Send, "m_hOwnerEntity") != -1)
        flamePointer.WriteEHandle(GetEntPropEnt(pOwner, Prop_Send, "m_hOwnerEntity"), 940 /*960*/); // pFlame->m_hAttacker = pOwner->GetOwnerEntity();
    else
        flamePointer.WriteEHandle(pOwner, 940 /*960*/); // pFlame->m_hAttacker = pOwner;
    if (flamePointer.DereferenceEHandle(940 /*960*/) != -1)
        flamePointer.Write(GetEntProp(flamePointer.DereferenceEHandle(940 /*960*/), Prop_Send, "m_iTeamNum"), 944 /*964*/); // pFlame->m_iAttackerTeam = pAttacker->GetTeamNumber();

    // Set team.
    SetEntProp(pFlame, Prop_Send, "m_iTeamNum", GetEntProp(pOwner, Prop_Send, "m_iTeamNum")); // pFlame->ChangeTeam( pOwner->GetTeamNumber() );
    flamePointer.Write(iDmgType, 912 /*932*/); // pFlame->m_iDmgType = iDmgType;
    flamePointer.Write(m_flDmgAmount, 916 /*936*/); // pFlame->m_flDmgAmount = flDmgAmount;

    // Setip the initial velocity.
    STACK_ALLOC(vecForward, Vector, VECTOR_SIZE);
    AngleVectors(vecAngles, vecForward);

    memcpy(flamePointer.Get(884 /*904*/, 1), vecForward * flSpeed, VECTOR_SIZE); // pFlame->m_vecBaseVelocity = vecForward * velocity;

    /*
    if ( bRandomize )
	{
		pFlame->m_vecBaseVelocity += RandomVector( -velocity * iFlameSizeMult * tf_flamethrower_vecrand.GetFloat(), velocity * iFlameSizeMult * tf_flamethrower_vecrand.GetFloat() );
	}
    */

    if (HasEntProp(pOwner, Prop_Send, "m_hOwnerEntity") && GetEntPropEnt(pOwner, Prop_Send, "m_hOwnerEntity") != -1)
        memcpy(flamePointer.Get(896 /*916*/, 1), GetAbsVelocity(GetEntPropEnt(pOwner, Prop_Send, "m_hOwnerEntity")), VECTOR_SIZE); // pFlame->m_vecAttackerVelocity = pOwner->GetOwnerEntity()->GetAbsVelocity();
    SDKCall(SDKCall_CBaseEntity_SetAbsVelocity, pFlame, flamePointer.Get(884 /*904*/, 1)); // pFlame->SetAbsVelocity( pFlame->m_vecBaseVelocity );	

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
        
        if (frame % 66 == 0)
        {
            STACK_ALLOC(a, Vector, VECTOR_SIZE);
            a.Assign(Weapon_ShootPosition(client));
            PrintToChatAll("Weapon_ShootPosition(): %f: %f: %f", a.X, a.Y, a.Z);
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