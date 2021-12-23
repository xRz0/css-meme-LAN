/*
 * shavit's Timer - Miscellaneous
 * by: shavit
 *
 * This file is part of shavit's Timer.
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
*/

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <convar_class>
#include <unixtime_sourcemod>

#undef REQUIRE_EXTENSIONS
#include <dhooks>
#include <SteamWorks>
#include <cstrike>
#include <tf2>
#include <tf2_stocks>

#undef REQUIRE_PLUGIN
#include <shavit>
#include <eventqueuefix>

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 524288

#define CP_ANGLES				(1 << 0)
#define CP_VELOCITY				(1 << 1)

#define CP_DEFAULT				(CP_ANGLES|CP_VELOCITY)

enum struct persistent_data_t
{
	int iSteamID;
	float fDisconnectTime;
	float fPosition[3];
	float fAngles[3];
	MoveType iMoveType;
	float fGravity;
	float fSpeed;
	timer_snapshot_t aSnapshot;
	ArrayList aFrames;
	int iPreFrames;
	int iTimerPreFrames;
	bool bPractice;
	char sTargetname[64];
	char sClassname[64];
}

typedef StopTimerCallback = function void (int data);

// game specific
EngineVersion gEV_Type = Engine_Unknown;
int gI_Ammo = -1;

char gS_RadioCommands[][] = { "coverme", "takepoint", "holdpos", "regroup", "followme", "takingfire", "go", "fallback", "sticktog",
	"getinpos", "stormfront", "report", "roger", "enemyspot", "needbackup", "sectorclear", "inposition", "reportingin",
	"getout", "negative", "enemydown", "compliment", "thanks", "cheer", "go_a", "go_b", "sorry", "needrop" };

bool gB_Hide[MAXPLAYERS+1];
bool gB_Silencer[MAXPLAYERS+1];
bool gB_Late = false;
int gI_GroundEntity[MAXPLAYERS+1];
int gI_LastShot[MAXPLAYERS+1];
char gS_CurrentMap[192];
int gI_Style[MAXPLAYERS+1];
Function gH_AfterWarningMenu[MAXPLAYERS+1];
bool gB_ClosedKZCP[MAXPLAYERS+1];

char pathFull[PLATFORM_MAX_PATH];
char path[PLATFORM_MAX_PATH];

ArrayList gA_Checkpoints[MAXPLAYERS+1];
int gI_CurrentCheckpoint[MAXPLAYERS+1];

int gI_CheckpointsSettings[MAXPLAYERS+1];

// save states
bool gB_SaveStatesSegmented[MAXPLAYERS+1];
float gF_SaveStateData[MAXPLAYERS+1][3][3];
timer_snapshot_t gA_SaveStates[MAXPLAYERS+1];
bool gB_SaveStates[MAXPLAYERS+1];
char gS_SaveStateTargetname[MAXPLAYERS+1][32];
ArrayList gA_SaveFrames[MAXPLAYERS+1];
ArrayList gA_PersistentData = null;
int gI_SavePreFrames[MAXPLAYERS+1];
int gI_TimerFrames[MAXPLAYERS+1];

// cookies
Handle gH_SilencerCookie = null;
Handle gH_HideCookie = null;
Handle gH_CheckpointsCookie = null;

bool gB_Eventqueuefix = false;

// cvars
Convar gCV_GodMode = null;
Convar gCV_PreSpeed = null;
Convar gCV_HideTeamChanges = null;
Convar gCV_RespawnOnTeam = null;
Convar gCV_RespawnOnRestart = null;
Convar gCV_StartOnSpawn = null;
Convar gCV_PrestrafeLimit = null;
Convar gCV_HideRadar = null;
Convar gCV_TeleportCommands = null;
Convar gCV_NoWeaponDrops = null;
Convar gCV_NoBlock = null;
Convar gCV_NoBlood = null;
Convar gCV_AutoRespawn = null;
Convar gCV_DisableRadio = null;
Convar gCV_Scoreboard = null;
Convar gCV_WeaponCommands = null;
Convar gCV_PlayerOpacity = null;
Convar gCV_StaticPrestrafe = null;
Convar gCV_NoclipMe = null;
Convar gCV_Checkpoints = null;
Convar gCV_RemoveRagdolls = null;
Convar gCV_ClanTag = null;
Convar gCV_DropAll = null;
Convar gCV_ResetTargetname = null;
Convar gCV_RestoreStates = null;
Convar gCV_JointeamHook = null;
Convar gCV_SpectatorList = null;
Convar gCV_MaxCP = null;
Convar gCV_MaxCP_Segmented = null;
Convar gCV_HideChatCommands = null;
Convar gCV_PersistData = null;
Convar gCV_StopTimerWarning = null;
Convar gCV_WRMessages = null;
Convar gCV_BhopSounds = null;
Convar gCV_RestrictNoclip = null;

// external cvars
ConVar sv_disable_immunity_alpha = null;
ConVar mp_humanteam = null;

// forwards
Handle gH_Forwards_OnClanTagChangePre = null;
Handle gH_Forwards_OnClanTagChangePost = null;
Handle gH_Forwards_OnSave = null;
Handle gH_Forwards_OnTeleport = null;
Handle gH_Forwards_OnDelete = null;
Handle gH_Forwards_OnCheckpointMenuMade = null;
Handle gH_Forwards_OnCheckpointMenuSelect = null;

// dhooks
Handle gH_GetPlayerMaxSpeed = null;

// modules
bool gB_Rankings = false;
bool gB_Replay = false;
bool gB_Zones = false;

// timer settings
stylestrings_t gS_StyleStrings[STYLE_LIMIT];
stylesettings_t gA_StyleSettings[STYLE_LIMIT];

// chat settings
chatstrings_t gS_ChatStrings;


int g_BeamSprite;

ArrayList GhostData2[MAXPLAYERS + 1];
int GhostLength;

bool c_finished;
bool c_restart;
bool ghost;

int cmdNum;
int beamColor[4];
int c_style;
int cmdpos;
int ownstyle;
int pretime;

Handle g_MainMenu = INVALID_HANDLE;

Handle g_hGhostCookie;
Handle g_hTrailCookie;
Handle h_hRestartCookie;
Handle h_hStyleCookie;

public Plugin myinfo =
{
	name = "[shavit] Miscellaneous",
	author = "shavit",
	description = "Miscellaneous features for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_GetCheckpoint", Native_GetCheckpoint);
	CreateNative("Shavit_SetCheckpoint", Native_SetCheckpoint);
	CreateNative("Shavit_ClearCheckpoints", Native_ClearCheckpoints);
	CreateNative("Shavit_TeleportToCheckpoint", Native_TeleportToCheckpoint);
	CreateNative("Shavit_GetTotalCheckpoints", Native_GetTotalCheckpoints);
	CreateNative("Shavit_OpenCheckpointMenu", Native_OpenCheckpointMenu);
	CreateNative("Shavit_SaveCheckpoint", Native_SaveCheckpoint);
	CreateNative("Shavit_GetCurrentCheckpoint", Native_GetCurrentCheckpoint);
	CreateNative("Shavit_SetCurrentCheckpoint", Native_SetCurrentCheckpoint);

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	// forwards
	gH_Forwards_OnClanTagChangePre = CreateGlobalForward("Shavit_OnClanTagChangePre", ET_Event, Param_Cell, Param_String, Param_Cell);
	gH_Forwards_OnClanTagChangePost = CreateGlobalForward("Shavit_OnClanTagChangePost", ET_Event, Param_Cell, Param_String, Param_Cell);
	gH_Forwards_OnSave = CreateGlobalForward("Shavit_OnSave", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnTeleport = CreateGlobalForward("Shavit_OnTeleport", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnCheckpointMenuMade = CreateGlobalForward("Shavit_OnCheckpointMenuMade", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnCheckpointMenuSelect = CreateGlobalForward("Shavit_OnCheckpointMenuSelect", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnDelete = CreateGlobalForward("Shavit_OnDelete", ET_Event, Param_Cell, Param_Cell);

	// cache
	gEV_Type = GetEngineVersion();

	sv_disable_immunity_alpha = FindConVar("sv_disable_immunity_alpha");

	// spectator list
	RegConsoleCmd("sm_specs", Command_Specs, "Show a list of spectators.");
	RegConsoleCmd("sm_spectators", Command_Specs, "Show a list of spectators.");

	// spec
	RegConsoleCmd("sm_spec", Command_Spec, "Moves you to the spectators' team. Usage: sm_spec [target]");
	RegConsoleCmd("sm_spectate", Command_Spec, "Moves you to the spectators' team. Usage: sm_spectate [target]");

	// hide
	RegConsoleCmd("sm_hide", Command_Hide, "Toggle players' hiding.");
	RegConsoleCmd("sm_unhide", Command_Hide, "Toggle players' hiding.");
	gH_HideCookie = RegClientCookie("shavit_hide", "Hide settings", CookieAccess_Protected);

	// silencer
	RegConsoleCmd("sm_silencer", Command_Silencer, "Toggle players' silencer on the USP.");
	RegConsoleCmd("sm_uspsl", Command_Silencer, "Toggle players' silencer on the USP.");
	gH_SilencerCookie = RegClientCookie("shavit_silencer", "Silencer settings", CookieAccess_Protected);

	// tpto
	RegConsoleCmd("sm_tpto", Command_Teleport, "Teleport to another player. Usage: sm_tpto [target]");
	RegConsoleCmd("sm_goto", Command_Teleport, "Teleport to another player. Usage: sm_goto [target]");

	// weapons
	RegConsoleCmd("sm_usp", Command_Weapon, "Spawn a USP.");
	RegConsoleCmd("sm_glock", Command_Weapon, "Spawn a Glock.");
	RegConsoleCmd("sm_knife", Command_Weapon, "Spawn a knife.");

	// checkpoints
	RegConsoleCmd( "sm_exportcps", Cmd_ExportCP );
	RegConsoleCmd( "sm_loadcps", Cmd_ImportCP );
	RegConsoleCmd( "sm_savecps", Cmd_ExportCP );
	RegConsoleCmd( "sm_importcps", Cmd_ImportCP );

	RegConsoleCmd("sm_cpmenu", Command_Checkpoints, "Opens the checkpoints menu.");
	RegConsoleCmd("sm_cp", Command_Checkpoints, "Opens the checkpoints menu. Alias for sm_cpmenu.");
	RegConsoleCmd("sm_checkpoint", Command_Checkpoints, "Opens the checkpoints menu. Alias for sm_cpmenu.");
	RegConsoleCmd("sm_checkpoints", Command_Checkpoints, "Opens the checkpoints menu. Alias for sm_cpmenu.");
	RegConsoleCmd("sm_save", Command_Save, "Saves checkpoint.");
	RegConsoleCmd("sm_tele", Command_Tele, "Teleports to checkpoint. Usage: sm_tele [number]");
	gH_CheckpointsCookie = RegClientCookie("shavit_checkpoints", "Checkpoints settings", CookieAccess_Protected);
	gA_PersistentData = new ArrayList(sizeof(persistent_data_t));

	gI_Ammo = FindSendPropInfo("CCSPlayer", "m_iAmmo");

	// noclip
	RegConsoleCmd("sm_p", Command_Noclip, "Toggles noclip.");
	RegConsoleCmd("sm_prac", Command_Noclip, "Toggles noclip. (sm_p alias)");
	RegConsoleCmd("sm_practice", Command_Noclip, "Toggles noclip. (sm_p alias)");
	RegConsoleCmd("sm_nc", Command_Noclip, "Toggles noclip. (sm_p alias)");
	RegConsoleCmd("sm_noclipme", Command_Noclip, "Toggles noclip. (sm_p alias)");
	AddCommandListener(CommandListener_Noclip, "+noclip");
	AddCommandListener(CommandListener_Noclip, "-noclip");

	g_hGhostCookie = RegClientCookie("GhostTrail", "Ghost Trails", CookieAccess_Protected);
	g_hTrailCookie = RegClientCookie("TrailColor", "Ghost Trail Color", CookieAccess_Protected);
	h_hRestartCookie = RegClientCookie("GhostRestart", "Ghost Restart", CookieAccess_Protected);
	h_hStyleCookie = RegClientCookie("GhostStyle", "Ghost Style", CookieAccess_Protected);

	RegConsoleCmd("sm_ghost", ghostToggle);
	RegConsoleCmd("sm_beam", BeamMenu);

	// hook teamjoins
	AddCommandListener(Command_Jointeam, "jointeam");

	// hook radio commands instead of a global listener
	for(int i = 0; i < sizeof(gS_RadioCommands); i++)
	{
		AddCommandListener(Command_Radio, gS_RadioCommands[i]);
	}

	// hooks
	HookEvent("player_spawn", Player_Spawn);
	HookEvent("player_team", Player_Notifications, EventHookMode_Pre);
	HookEvent("player_death", Player_Notifications, EventHookMode_Pre);
	HookEventEx("weapon_fire", Weapon_Fire);
	AddCommandListener(Command_Drop, "drop");
	AddTempEntHook("EffectDispatch", EffectDispatch);
	AddTempEntHook("World Decal", WorldDecal);
	AddTempEntHook((gEV_Type != Engine_TF2)? "Shotgun Shot":"Fire Bullets", Shotgun_Shot);
	AddNormalSoundHook(NormalSound);

	// phrases
	LoadTranslations("common.phrases");
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-misc.phrases");

	// cvars and stuff
	gCV_GodMode = new Convar("shavit_misc_godmode", "3", "Enable godmode for players?\n0 - Disabled\n1 - Only prevent fall/world damage.\n2 - Only prevent damage from other players.\n3 - Full godmode.", 0, true, 0.0, true, 3.0);
	gCV_PreSpeed = new Convar("shavit_misc_prespeed", "1", "Stop prespeeding in the start zone?\n0 - Disabled, fully allow prespeeding.\n1 - Limit relatively to prestrafelimit.\n2 - Block bunnyhopping in startzone.\n3 - Limit to prestrafelimit and block bunnyhopping.\n4 - Limit to prestrafelimit but allow prespeeding. Combine with shavit_core_nozaxisspeed 1 for SourceCode timer's behavior.", 0, true, 0.0, true, 4.0);
	gCV_HideTeamChanges = new Convar("shavit_misc_hideteamchanges", "1", "Hide team changes in chat?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_RespawnOnTeam = new Convar("shavit_misc_respawnonteam", "1", "Respawn whenever a player joins a team?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_RespawnOnRestart = new Convar("shavit_misc_respawnonrestart", "1", "Respawn a dead player if they use the timer restart command?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_StartOnSpawn = new Convar("shavit_misc_startonspawn", "1", "Restart the timer for a player after they spawn?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_PrestrafeLimit = new Convar("shavit_misc_prestrafelimit", "30", "Prestrafe limitation in startzone.\nThe value used internally is style run speed + this.\ni.e. run speed of 250 can prestrafe up to 278 (+28) with regular settings.", 0, true, 0.0, false);
	gCV_HideRadar = new Convar("shavit_misc_hideradar", "1", "Should the plugin hide the in-game radar?", 0, true, 0.0, true, 1.0);
	gCV_TeleportCommands = new Convar("shavit_misc_tpcmds", "1", "Enable teleport-related commands? (sm_goto/sm_tpto)\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoWeaponDrops = new Convar("shavit_misc_noweapondrops", "1", "Remove every dropped weapon.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoBlock = new Convar("shavit_misc_noblock", "1", "Disable player collision?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoBlood = new Convar("shavit_misc_noblood", "0", "Hide blood decals and particles?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_AutoRespawn = new Convar("shavit_misc_autorespawn", "1.5", "Seconds to wait before respawning player?\n0 - Disabled", 0, true, 0.0, true, 10.0);
	gCV_DisableRadio = new Convar("shavit_misc_disableradio", "0", "Block radio commands.\n0 - Disabled (radio commands work)\n1 - Enabled (radio commands are blocked)", 0, true, 0.0, true, 1.0);
	gCV_Scoreboard = new Convar("shavit_misc_scoreboard", "1", "Manipulate scoreboard so score is -{time} and deaths are {rank})?\nDeaths part requires shavit-rankings.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_WeaponCommands = new Convar("shavit_misc_weaponcommands", "2", "Enable sm_usp, sm_glock and sm_knife?\n0 - Disabled\n1 - Enabled\n2 - Also give infinite reserved ammo.", 0, true, 0.0, true, 2.0);
	gCV_PlayerOpacity = new Convar("shavit_misc_playeropacity", "-1", "Player opacity (alpha) to set on spawn.\n-1 - Disabled\nValue can go up to 255. 0 for invisibility.", 0, true, -1.0, true, 255.0);
	gCV_StaticPrestrafe = new Convar("shavit_misc_staticprestrafe", "1", "Force prestrafe for every pistol.\n250 is the default value and some styles will have 260.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoclipMe = new Convar("shavit_misc_noclipme", "1", "Allow +noclip, sm_p and all the noclip commands?\n0 - Disabled\n1 - Enabled\n2 - requires 'admin_noclipme' override or ADMFLAG_CHEATS flag.", 0, true, 0.0, true, 2.0);
	gCV_Checkpoints = new Convar("shavit_misc_checkpoints", "1", "Allow players to save and teleport to checkpoints.", 0, true, 0.0, true, 1.0);
	gCV_RemoveRagdolls = new Convar("shavit_misc_removeragdolls", "1", "Remove ragdolls after death?\n0 - Disabled\n1 - Only remove replay bot ragdolls.\n2 - Remove all ragdolls.", 0, true, 0.0, true, 2.0);
	gCV_ClanTag = new Convar("shavit_misc_clantag", "{tr}{styletag} :: {time}", "Custom clantag for players.\n0 - Disabled\n{styletag} - style tag.\n{style} - style name.\n{time} - formatted time.\n{tr} - first letter of track.\n{rank} - player rank.", 0);
	gCV_DropAll = new Convar("shavit_misc_dropall", "1", "Allow all weapons to be dropped?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_ResetTargetname = new Convar("shavit_misc_resettargetname", "0", "Reset the player's targetname upon timer start?\nRecommended to leave disabled. Enable via per-map configs when necessary.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_RestoreStates = new Convar("shavit_misc_restorestates", "0", "Save the players' timer/position etc.. when they die/change teams,\nand load the data when they spawn?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_JointeamHook = new Convar("shavit_misc_jointeamhook", "1", "Hook `jointeam`?\n0 - Disabled\n1 - Enabled, players can instantly change teams.", 0, true, 0.0, true, 1.0);
	gCV_SpectatorList = new Convar("shavit_misc_speclist", "1", "Who to show in !specs?\n0 - everyone\n1 - all admins (admin_speclisthide override to bypass)\n2 - players you can target", 0, true, 0.0, true, 2.0);
	gCV_MaxCP = new Convar("shavit_misc_maxcp", "1000", "Maximum amount of checkpoints.\nNote: Very high values will result in high memory usage!", 0, true, 1.0, true, 10000.0);
	gCV_MaxCP_Segmented = new Convar("shavit_misc_maxcp_seg", "10", "Maximum amount of segmented checkpoints. Make this less or equal to shavit_misc_maxcp.\nNote: Very high values will result in HUGE memory usage!", 0, true, 1.0, true, 50.0);
	gCV_HideChatCommands = new Convar("shavit_misc_hidechatcmds", "1", "Hide commands from chat?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_PersistData = new Convar("shavit_misc_persistdata", "300", "How long to persist timer data for disconnected users in seconds?\n-1 - Until map change\n0 - Disabled");
	gCV_StopTimerWarning = new Convar("shavit_misc_stoptimerwarning", "900", "Time in seconds to display a warning before stopping the timer with noclip or !stop.\n0 - Disabled");
	gCV_WRMessages = new Convar("shavit_misc_wrmessages", "3", "How many \"NEW <style> WR!!!\" messages to print?\n0 - Disabled", 0,  true, 0.0, true, 100.0);
	gCV_BhopSounds = new Convar("shavit_misc_bhopsounds", "0", "Should bhop (landing and jumping) sounds be muted?\n0 - Disabled\n1 - Blocked while !hide is enabled\n2 - Always blocked", 0,  true, 0.0, true, 3.0);
	gCV_RestrictNoclip = new Convar("shavit_misc_restrictnoclip", "1", "Should noclip be be restricted\n0 - Disabled\n1 - No vertical velocity while in noclip in start zone\n2 - No noclip in start zone", 0, true, 0.0, true, 2.0);

	Convar.AutoExecConfig();

	mp_humanteam = FindConVar("mp_humanteam");

	if(mp_humanteam == null)
	{
		mp_humanteam = FindConVar("mp_humans_must_join_team");
	}

	// crons
	CreateTimer(10.0, Timer_Cron, 0, TIMER_REPEAT);
	CreateTimer(0.5, Timer_PersistKZCP, 0, TIMER_REPEAT);

	if(gEV_Type != Engine_TF2)
	{
		CreateTimer(1.0, Timer_Scoreboard, 0, TIMER_REPEAT);

		if(LibraryExists("dhooks"))
		{
			Handle hGameData = LoadGameConfigFile("shavit.games");

			if(hGameData != null)
			{
				int iOffset = GameConfGetOffset(hGameData, "CCSPlayer::GetPlayerMaxSpeed");

				if(iOffset != -1)
				{
					gH_GetPlayerMaxSpeed = DHookCreate(iOffset, HookType_Entity, ReturnType_Float, ThisPointer_CBaseEntity, CCSPlayer__GetPlayerMaxSpeed);
				}

				else
				{
					SetFailState("Couldn't get the offset for \"CCSPlayer::GetPlayerMaxSpeed\" - make sure your gamedata is updated!");
				}
			}

			delete hGameData;
		}
	}

	gB_Eventqueuefix = LibraryExists("eventqueuefix");

	// late load
	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);
				delete GhostData2[i];
				GhostData2[i] = new ArrayList(4);
				ghost = false;
				cmdNum = 0;
				beamColor =  { 255, 255, 255, 255 };
				if(AreClientCookiesCached(i))
				{
					OnClientCookiesCached(i);
				}
			}
		}
	}

	// modules
	gB_Rankings = LibraryExists("shavit-rankings");
	gB_Replay = LibraryExists("shavit-replay");
	gB_Zones = LibraryExists("shavit-zones");
}

public void OnClientCookiesCached(int client)
{
	if(IsFakeClient(client))
	{
		return;
	}
	char cookieValue[32];
	GetClientCookie(client, g_hGhostCookie, cookieValue, sizeof(cookieValue));
	ghost = view_as<bool>(StringToInt(cookieValue));
	
	char cookieValue2[32];
	GetClientCookie(client, g_hTrailCookie, cookieValue2, sizeof(cookieValue2));
	
	if(StrEqual(cookieValue2, "Red"))
		beamColor =  { 255, 0, 0, 255 };
	else if(StrEqual(cookieValue2, "Green"))
		beamColor =  { 0, 255, 0, 255 };
	else if(StrEqual(cookieValue2, "Blue"))
		beamColor =  { 0, 0, 255, 255 };
	else
		beamColor =  { 255, 255, 255, 255 };
	
	char cookieValue3[32];
	GetClientCookie(client, h_hRestartCookie, cookieValue3, sizeof(cookieValue3));
	c_restart = view_as<bool>(StringToInt(cookieValue3));

	char cookieValue4[8];
	GetClientCookie(client, h_hStyleCookie, cookieValue4, sizeof(cookieValue4));
	c_style = StringToInt(cookieValue4);

	char sSetting[8];
	GetClientCookie(client, gH_HideCookie, sSetting, 8);

	if(strlen(sSetting) == 0)
	{
		SetClientCookie(client, gH_HideCookie, "0");
		gB_Hide[client] = false;
	}

	else
	{
		gB_Hide[client] = view_as<bool>(StringToInt(sSetting));
	}

	GetClientCookie(client, gH_SilencerCookie, sSetting, 8);

	if(strlen(sSetting) == 0)
	{
		SetClientCookie(client, gH_SilencerCookie, "0");
		gB_Silencer[client] = false;
	}

	else
	{
		gB_Silencer[client] = view_as<bool>(StringToInt(sSetting));
		if(gB_Silencer[client])
		{
			if(IsClientInGame(client))
			{
				if(IsPlayerAlive(client))
				{
					int iWeapon = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);

					if(iWeapon != -1)
					{
						char pewpew[48];
						GetEdictClassname(iWeapon, pewpew, sizeof(pewpew));
						if(StrEqual(pewpew, "weapon_usp"))
						{
							RemovePlayerItem(client, iWeapon);
							AcceptEntityInput(iWeapon, "Kill");
							iWeapon = GivePlayerItem(client, "weapon_usp");
							FakeClientCommand(client, "use weapon_usp");
						}
					}
				}
			}
		}
	}

	GetClientCookie(client, gH_CheckpointsCookie, sSetting, 8);

	if(strlen(sSetting) == 0)
	{
		IntToString(CP_DEFAULT, sSetting, 8);
		SetClientCookie(client, gH_CheckpointsCookie, sSetting);
		gI_CheckpointsSettings[client] = CP_DEFAULT;
	}

	else
	{
		gI_CheckpointsSettings[client] = StringToInt(sSetting);
	}

	gI_Style[client] = Shavit_GetBhopStyle(client);
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	if(styles == -1)
	{
		styles = Shavit_GetStyleCount();
	}

	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleSettings(i, gA_StyleSettings[i]);
		Shavit_GetStyleStrings(i, sStyleName, gS_StyleStrings[i].sStyleName, sizeof(stylestrings_t::sStyleName));
		Shavit_GetStyleStrings(i, sClanTag, gS_StyleStrings[i].sClanTag, sizeof(stylestrings_t::sClanTag));
		Shavit_GetStyleStrings(i, sSpecialString, gS_StyleStrings[i].sSpecialString, sizeof(stylestrings_t::sSpecialString));
	}
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStrings(sMessagePrefix, gS_ChatStrings.sPrefix, sizeof(chatstrings_t::sPrefix));
	Shavit_GetChatStrings(sMessageText, gS_ChatStrings.sText, sizeof(chatstrings_t::sText));
	Shavit_GetChatStrings(sMessageWarning, gS_ChatStrings.sWarning, sizeof(chatstrings_t::sWarning));
	Shavit_GetChatStrings(sMessageVariable, gS_ChatStrings.sVariable, sizeof(chatstrings_t::sVariable));
	Shavit_GetChatStrings(sMessageVariable2, gS_ChatStrings.sVariable2, sizeof(chatstrings_t::sVariable2));
	Shavit_GetChatStrings(sMessageStyle, gS_ChatStrings.sStyle, sizeof(chatstrings_t::sStyle));
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	gI_Style[client] = newstyle;

	if(StrContains(gS_StyleStrings[newstyle].sSpecialString, "segments") != -1)
	{
		// Gammacase somehow had this callback fire before OnClientPutInServer.
		// OnClientPutInServer will still fire but we need a valid arraylist in the mean time.
		if(gA_Checkpoints[client] == null)
		{
			gA_Checkpoints[client] = new ArrayList(sizeof(cp_cache_t));	
		}

		OpenCheckpointsMenu(client);
		Shavit_PrintToChat(client, "%T", "MiscSegmentedCommand", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}
	
	if(ghost && ownstyle == 255)
	{				
		c_finished = false;

		ArrayList ar = Shavit_GetReplayFrames(newstyle, 0);
	
		GhostData2[client] = ar.Clone();

		GhostLength = 0;

		if(GhostData2[client] != null)
			GhostLength = GhostData2[client].Length;
	}

}

public void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity, int data)
{
	cmdpos = pretime;
	if(type == Zone_Start && ghost)
	{
		c_finished = false;
		cmdNum = 0;
	}
}

public void Shavit_OnEnterZone(int client, int type, int track, int id, int entity, int data)
{
	cmdpos = pretime;
	if(type == Zone_Start && ghost)
	{
		cmdNum = pretime;
		
		//ArrayList ar = Shavit_GetReplayFrames(Shavit_GetBhopStyle(client), Shavit_GetClientTrack(client));
	
		//GhostData2[client] = ar.Clone();
	}
}
public void OnConfigsExecuted()
{
	g_BeamSprite = PrecacheModel("sprites/laserbeam.vmt");
	if(!DirExists("SaveFiles"))
	{
		CreateDirectory("SaveFiles", 511);
	}
	if(!DirExists("SaveFiles/CPs"))
	{
		CreateDirectory("SaveFiles/CPs", 511);
	}
	char mapname[128];
	GetCurrentMap(mapname, sizeof(mapname));
	FormatEx(path, sizeof(path), "SaveFiles/CPs/%s",mapname);
	FormatEx(pathFull, sizeof(pathFull), "%s/%s.txt",path,mapname);

	if(sv_disable_immunity_alpha != null)
	{
		sv_disable_immunity_alpha.BoolValue = true;
	}
	ConVar precon = FindConVar( "shavit_replay_preruntime" );
	float prefloat = GetConVarFloat(precon);
	int tickrate = RoundToZero(1.0 / GetTickInterval());
	pretime = RoundToZero(prefloat*tickrate);
}

public void OnMapStart()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		ResetCheckpoints(i);
	}

	int iLength = gA_PersistentData.Length;

	for(int i = iLength - 1; i >= 0; i--)
	{
		persistent_data_t aData;
		gA_PersistentData.GetArray(i, aData);

		delete aData.aFrames;
	}

	gA_PersistentData.Clear();

	GetCurrentMap(gS_CurrentMap, 192);
	GetMapDisplayName(gS_CurrentMap, gS_CurrentMap, 192);

	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(-1);
		Shavit_OnChatConfigLoaded();
	}
}

public void OnMapEnd()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		ResetCheckpoints(i);
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = true;
	}

	else if(StrEqual(name, "shavit-replay"))
	{
		gB_Replay = true;
	}

	else if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = true;
	}
	else if (StrEqual(name, "eventqueuefix"))
	{
		gB_Eventqueuefix = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = false;
	}

	else if(StrEqual(name, "shavit-replay"))
	{
		gB_Replay = false;
	}

	else if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = false;
	}
	else if (StrEqual(name, "eventqueuefix"))
	{
		gB_Eventqueuefix = false;
	}
}

int GetHumanTeam()
{
	char sTeam[8];
	mp_humanteam.GetString(sTeam, 8);

	if(StrEqual(sTeam, "t", false) || StrEqual(sTeam, "red", false))
	{
		return 2;
	}

	else if(StrEqual(sTeam, "ct", false) || StrContains(sTeam, "blu", false) != -1)
	{
		return 3;
	}

	return 0;
}

public Action Command_Jointeam(int client, const char[] command, int args)
{
	if(!IsValidClient(client) || !gCV_JointeamHook.BoolValue)
	{
		return Plugin_Continue;
	}

	if(!gB_SaveStates[client])
	{
		SaveState(client);
	}

	char arg1[8];
	GetCmdArg(1, arg1, 8);

	int iTeam = StringToInt(arg1);
	int iHumanTeam = GetHumanTeam();

	if(iHumanTeam != 0 && iTeam != 0)
	{
		iTeam = iHumanTeam;
	}

	bool bRespawn = false;

	switch(iTeam)
	{
		case 2:
		{
			// if T spawns are available in the map
			if(gEV_Type == Engine_TF2 || FindEntityByClassname(-1, "info_player_terrorist") != -1)
			{
				bRespawn = true;
				CleanSwitchTeam(client, 2, true);
			}
		}

		case 3:
		{
			// if CT spawns are available in the map
			if(gEV_Type == Engine_TF2 || FindEntityByClassname(-1, "info_player_counterterrorist") != -1)
			{
				bRespawn = true;
				CleanSwitchTeam(client, 3, true);
			}
		}

		// if they chose to spectate, i'll force them to join the spectators
		case 1:
		{
			CleanSwitchTeam(client, 1, false);
		}

		default:
		{
			bRespawn = true;
			CleanSwitchTeam(client, GetRandomInt(2, 3), true);
		}
	}

	if(gCV_RespawnOnTeam.BoolValue && bRespawn)
	{
		if(gEV_Type == Engine_TF2)
		{
			TF2_RespawnPlayer(client);
		}

		else
		{
			CS_RespawnPlayer(client);
		}

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void CleanSwitchTeam(int client, int team, bool change = false)
{
	if(gEV_Type == Engine_TF2)
	{
		TF2_ChangeClientTeam(client, view_as<TFTeam>(team));
	}

	else if(change)
	{
		CS_SwitchTeam(client, team);
	}

	else
	{
		ChangeClientTeam(client, team);
	}
}

public Action Command_Radio(int client, const char[] command, int args)
{
	if(gCV_DisableRadio.BoolValue)
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public MRESReturn CCSPlayer__GetPlayerMaxSpeed(int pThis, Handle hReturn)
{
	if(!gCV_StaticPrestrafe.BoolValue || !IsValidClient(pThis, true))
	{
		return MRES_Ignored;
	}

	DHookSetReturn(hReturn, view_as<float>(gA_StyleSettings[gI_Style[pThis]].fRunspeed));

	return MRES_Override;
}

public Action Timer_Cron(Handle Timer)
{
	if(gCV_HideRadar.BoolValue)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				RemoveRadarBase(i);
			}
		}
	}

	if(gCV_PersistData.FloatValue < 0.0)
	{
		return Plugin_Continue;

	}

	int iLength = gA_PersistentData.Length;
	float fTime = GetEngineTime();

	for(int i = iLength - 1; i >= 0; i--)
	{
		persistent_data_t aData;
		gA_PersistentData.GetArray(i, aData);

		if(fTime - aData.fDisconnectTime >= gCV_PersistData.FloatValue)
		{
			DeletePersistentData(i, aData);
		}
	}

	return Plugin_Continue;
}

public Action Timer_PersistKZCP(Handle Timer)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!gB_ClosedKZCP[i] &&
			gA_StyleSettings[gI_Style[i]].bKZCheckpoints
			&& GetClientMenu(i) == MenuSource_None &&
			IsClientInGame(i) && IsPlayerAlive(i))
		{
			OpenKZCPMenu(i);
		}
	}

	return Plugin_Continue;
}

public Action Timer_Scoreboard(Handle Timer)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || IsFakeClient(i))
		{
			continue;
		}

		if(gCV_Scoreboard.BoolValue)
		{
			UpdateScoreboard(i);
		}

		UpdateClanTag(i);
	}

	return Plugin_Continue;
}

void UpdateScoreboard(int client)
{
	// this doesn't work on tf2 for some reason
	if(gEV_Type == Engine_TF2)
	{
		return;
	}

	float fPB = Shavit_GetClientPB(client, 0, Track_Main);

	int iScore = (fPB != 0.0 && fPB < 2000)? -RoundToFloor(fPB):-2000;

	if(gEV_Type == Engine_CSGO)
	{
		CS_SetClientContributionScore(client, iScore);
	}

	else
	{
		SetEntProp(client, Prop_Data, "m_iFrags", iScore);
	}

	if(gB_Rankings)
	{
		SetEntProp(client, Prop_Data, "m_iDeaths", Shavit_GetRank(client));
	}
}

void UpdateClanTag(int client)
{
	// no clan tags in tf2
	char sTag[32];
	gCV_ClanTag.GetString(sTag, 32);

	if(gEV_Type == Engine_TF2 || StrEqual(sTag, "0"))
	{
		return;
	}

	char sTime[16];

	float fTime = Shavit_GetClientTime(client);

	if(Shavit_GetTimerStatus(client) == Timer_Stopped || fTime < 1.0)
	{
		strcopy(sTime, 16, "N/A");
	}

	else
	{
		int time = RoundToFloor(fTime);

		if(time < 60)
		{
			IntToString(time, sTime, 16);
		}

		else
		{
			int minutes = (time / 60);
			int seconds = (time % 60);

			if(time < 3600)
			{
				FormatEx(sTime, 16, "%d:%s%d", minutes, (seconds < 10)? "0":"", seconds);
			}

			else
			{
				minutes %= 60;

				FormatEx(sTime, 16, "%d:%s%d:%s%d", (time / 3600), (minutes < 10)? "0":"", minutes, (seconds < 10)? "0":"", seconds);
			}
		}
	}

	int track = Shavit_GetClientTrack(client);
	char sTrack[3];

	if(track != Track_Main)
	{
		GetTrackName(client, track, sTrack, 3);
	}

	char sRank[8];

	if(gB_Rankings)
	{
		IntToString(Shavit_GetRank(client), sRank, 8);
	}

	char sCustomTag[32];
	strcopy(sCustomTag, 32, sTag);
	ReplaceString(sCustomTag, 32, "{style}", gS_StyleStrings[gI_Style[client]].sStyleName);
	ReplaceString(sCustomTag, 32, "{styletag}", gS_StyleStrings[gI_Style[client]].sClanTag);
	ReplaceString(sCustomTag, 32, "{time}", sTime);
	ReplaceString(sCustomTag, 32, "{tr}", sTrack);
	ReplaceString(sCustomTag, 32, "{rank}", sRank);

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnClanTagChangePre);
	Call_PushCell(client);
	Call_PushStringEx(sTag, 32, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(32);
	Call_Finish(result);
	
	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return;
	}

	CS_SetClientClanTag(client, sCustomTag);

	Call_StartForward(gH_Forwards_OnClanTagChangePost);
	Call_PushCell(client);
	Call_PushStringEx(sCustomTag, 32, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(32);
	Call_Finish();
}

void RemoveRagdoll(int client)
{
	int iEntity = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");

	if(iEntity != INVALID_ENT_REFERENCE)
	{
		AcceptEntityInput(iEntity, "Kill");
	}
}

public Action Shavit_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int style, stylesettings_t stylesettings)
{
	bool bNoclip = (GetEntityMoveType(client) == MOVETYPE_NOCLIP);
	bool bInStart = Shavit_InsideZone(client, Zone_Start, track);

	// i will not be adding a setting to toggle this off
	if(bNoclip)
	{
		if(status == Timer_Running)
		{
			Shavit_StopTimer(client);
		}
		if(bInStart && gCV_RestrictNoclip.BoolValue)
		{
			if(gCV_RestrictNoclip.IntValue == 1)
			{
				float fSpeed[3];
				GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed);
				fSpeed[2] = 0.0;
				TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fSpeed);
			}
			else if(gCV_RestrictNoclip.IntValue == 2)
			{
				SetEntityMoveType(client, MOVETYPE_ISOMETRIC);
			}
		}
	}

	int iGroundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");

	// prespeed
	if(!bNoclip && gA_StyleSettings[gI_Style[client]].iPrespeed == 0 && bInStart)
	{
		if((gCV_PreSpeed.IntValue == 2 || gCV_PreSpeed.IntValue == 3) && gI_GroundEntity[client] == -1 && iGroundEntity != -1 && (buttons & IN_JUMP) > 0)
		{
			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
			Shavit_PrintToChat(client, "%T", "BHStartZoneDisallowed", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

			gI_GroundEntity[client] = iGroundEntity;

			return Plugin_Continue;
		}

		if(gCV_PreSpeed.IntValue == 1 || gCV_PreSpeed.IntValue >= 3)
		{
			float fSpeed[3];
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed);

			float fLimit = (gA_StyleSettings[gI_Style[client]].fRunspeed + gCV_PrestrafeLimit.FloatValue);

			// if trying to jump, add a very low limit to stop prespeeding in an elegant way
			// otherwise, make sure nothing weird is happening (such as sliding at ridiculous speeds, at zone enter)
			if(gCV_PreSpeed.IntValue < 4 && fSpeed[2] > 0.0)
			{
				fLimit /= 3.0;
			}

			float fSpeedXY = (SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0)));
			float fScale = (fLimit / fSpeedXY);

			if(fScale < 1.0)
			{
				ScaleVector(fSpeed, fScale);
			}

			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fSpeed);
		}
	}

	gI_GroundEntity[client] = iGroundEntity;

	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_SetTransmit, OnSetTransmit);
	SDKHook(client, SDKHook_WeaponDrop, OnWeaponDrop);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_WeaponEquip, OnWeaponEquip);
	if(gEV_Type == Engine_TF2)
	{
		SDKHook(client, SDKHook_PreThinkPost, OnPreThink);
	}

	if(IsFakeClient(client))
	{
		return;
	}

	delete GhostData2[client];
	GhostData2[client] = new ArrayList(4);
	cmdNum = 0;
	cmdpos = 100;
	c_finished = false;
	if(!AreClientCookiesCached(client))
	{
		gI_Style[client] = Shavit_GetBhopStyle(client);
		gB_Hide[client] = false;
		gB_Silencer[client] = false;
		gI_CheckpointsSettings[client] = CP_DEFAULT;
	}

	if(gH_GetPlayerMaxSpeed != null)
	{
		DHookEntity(gH_GetPlayerMaxSpeed, true, client);
	}

	if(gA_Checkpoints[client] == null)
	{
		gA_Checkpoints[client] = new ArrayList(sizeof(cp_cache_t));	
	}
	else 
	{
		gA_Checkpoints[client].Clear();
	}

	gB_SaveStates[client] = false;
	delete gA_SaveFrames[client];

	gB_ClosedKZCP[client] = false;
}

public void OnClientDisconnect(int client)
{
	if(gCV_NoWeaponDrops.BoolValue)
	{
		int entity = -1;

		while((entity = FindEntityByClassname(entity, "weapon_*")) != -1)
		{
			if(GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client)
			{
				RequestFrame(RemoveWeapon, EntIndexToEntRef(entity));
			}
		}
	}

	if(IsFakeClient(client))
	{
		return;
	}

	delete GhostData2[client];
	GhostData2[client] = new ArrayList(4);
	ghost = false;
	cmdNum = 0;

	ResetCheckpoints(client);
	delete gA_Checkpoints[client];

	gB_SaveStates[client] = false;
	delete gA_SaveFrames[client];

	PersistData(client);
}

void PersistData(int client)
{
	persistent_data_t aData;

	if(!IsClientInGame(client) ||
		!IsPlayerAlive(client) ||
		(aData.iSteamID = GetSteamAccountID((client))) == 0 ||
		Shavit_GetTimerStatus(client) == Timer_Stopped ||
		gCV_PersistData.IntValue == 0)
	{
		return;
	}

	if(gB_Replay)
	{
		aData.aFrames = Shavit_GetReplayData(client);
		aData.iPreFrames = Shavit_GetPlayerPreFrame(client);
		aData.iTimerPreFrames = Shavit_GetPlayerTimerFrame(client);
	}

	aData.fDisconnectTime = GetEngineTime();
	aData.iMoveType = GetEntityMoveType(client);
	aData.fGravity = GetEntityGravity(client);
	aData.fSpeed = GetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue");
	aData.bPractice = Shavit_IsPracticeMode(client);

	float fPosition[3];
	GetClientAbsOrigin(client, fPosition);
	CopyArray(fPosition, aData.fPosition, 3);

	float fAngles[3];
	GetClientEyeAngles(client, fAngles);
	CopyArray(fAngles, aData.fAngles, 3);

	timer_snapshot_t aSnapshot;
	Shavit_SaveSnapshot(client, aSnapshot);
	CopyArray(aSnapshot, aData.aSnapshot, sizeof(timer_snapshot_t));

	char sTargetname[64];
	GetEntPropString(client, Prop_Data, "m_iName", sTargetname, 64);

	char sClassname[64];
	GetEntityClassname(client, sClassname, 64);

	strcopy(aData.sTargetname, 64, sTargetname);
	strcopy(aData.sClassname, 64, sClassname);

	gA_PersistentData.PushArray(aData);
}

void DeletePersistentData(int index, persistent_data_t data)
{
	delete data.aFrames;
	gA_PersistentData.Erase(index);
}

public Action Timer_LoadPersistentData(Handle Timer, any data)
{
	int iSteamID = 0;
	int client = GetClientFromSerial(data);

	if(client == 0 ||
		(iSteamID = GetSteamAccountID(client)) == 0 ||
		GetClientTeam(client) < 2 ||
		!IsPlayerAlive(client))
	{
		return Plugin_Stop;
	}

	persistent_data_t aData;
	int iIndex = -1;
	int iLength = gA_PersistentData.Length;

	for(int i = 0; i < iLength; i++)
	{
		gA_PersistentData.GetArray(i, aData);

		if(iSteamID == aData.iSteamID)
		{
			iIndex = i;

			break;
		}
	}

	if(iIndex == -1)
	{
		return Plugin_Stop;
	}

	Shavit_StopTimer(client);

	float fPosition[3];
	CopyArray(aData.fPosition, fPosition, 3);

	float fAngles[3];
	CopyArray(aData.fAngles, fAngles, 3);

	SetEntityMoveType(client, aData.iMoveType);
	SetEntityGravity(client, aData.fGravity);
	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", aData.fSpeed);

	timer_snapshot_t aSnapshot;
	CopyArray(aData.aSnapshot, aSnapshot, sizeof(timer_snapshot_t));
	Shavit_LoadSnapshot(client, aSnapshot);

	SetEntPropString(client, Prop_Data, "m_iName", aData.sTargetname);
	SetEntPropString(client, Prop_Data, "m_iClassname", aData.sClassname);

	TeleportEntity(client, fPosition, fAngles, view_as<float>({ 0.0, 0.0, 0.0 }));

	if(gB_Replay && aData.aFrames != null)
	{
		Shavit_SetReplayData(client, aData.aFrames);
		Shavit_SetPlayerPreFrame(client, aData.iPreFrames);
		Shavit_SetPlayerTimerFrame(client, aData.iTimerPreFrames);
	}

	if(aData.bPractice)
	{
		Shavit_SetPracticeMode(client, true, false);
	}

	delete aData.aFrames;
	gA_PersistentData.Erase(iIndex);

	return Plugin_Stop;
}

void RemoveWeapon(any data)
{
	if(IsValidEntity(data))
	{
		AcceptEntityInput(data, "Kill");
	}
}

void ResetCheckpoints(int client)
{
	if(gA_Checkpoints[client])
	{
		gA_Checkpoints[client].Clear();
	}

	gI_CurrentCheckpoint[client] = 0;
}

public Action OnTakeDamage(int victim, int attacker)
{
	if(gB_Hide[victim])
	{
		if(gEV_Type == Engine_CSGO)
		{
			SetEntPropVector(victim, Prop_Send, "m_viewPunchAngle", NULL_VECTOR);
			SetEntPropVector(victim, Prop_Send, "m_aimPunchAngle", NULL_VECTOR);
			SetEntPropVector(victim, Prop_Send, "m_aimPunchAngleVel", NULL_VECTOR);
		}

		else
		{
			SetEntPropVector(victim, Prop_Send, "m_vecPunchAngle", NULL_VECTOR);
			SetEntPropVector(victim, Prop_Send, "m_vecPunchAngleVel", NULL_VECTOR);
		}
	}

	switch(gCV_GodMode.IntValue)
	{
		case 0:
		{
			return Plugin_Continue;
		}

		case 1:
		{
			// 0 - world/fall damage
			if(attacker == 0)
			{
				return Plugin_Handled;
			}
		}

		case 2:
		{
			if(IsValidClient(attacker, true))
			{
				return Plugin_Handled;
			}
		}

		// else
		default:
		{
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public void OnWeaponDrop(int client, int entity)
{
	if(gCV_NoWeaponDrops.BoolValue && IsValidEntity(entity))
	{
		AcceptEntityInput(entity, "Kill");
	}
}

//hehe
public Action OnWeaponEquip(int client, int weapon)
{
	char item[20]; item[0] = '\0';
	GetEdictClassname(weapon, item, sizeof(item));

	if (StrEqual(item, "weapon_usp") && gB_Silencer[client])
	{
		SetEntProp(weapon, Prop_Send, "m_bSilencerOn", 1);
		SetEntProp(weapon, Prop_Send, "m_weaponMode", 1);
	}
}

// hide
public Action OnSetTransmit(int entity, int client)
{
	if(gB_Hide[client] && client != entity && (!IsClientObserver(client) || (GetEntProp(client, Prop_Send, "m_iObserverMode") != 6 &&
		GetEntPropEnt(client, Prop_Send, "m_hObserverTarget") != entity)))
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public void OnPreThink(int client)
{
	if(IsPlayerAlive(client))
	{
		// not the best method, but only one i found for tf2
		SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", gA_StyleSettings[gI_Style[client]].fRunspeed);
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if(IsChatTrigger() && gCV_HideChatCommands.BoolValue)
	{
		// hide commands
		return Plugin_Handled;
	}

	if(sArgs[0] == '!' || sArgs[0] == '/')
	{
		bool bUpper = false;

		for(int i = 0; i < strlen(sArgs); i++)
		{
			if(IsCharUpper(sArgs[i]))
			{
				bUpper = true;

				break;
			}
		}

		if(bUpper)
		{
			char sCopy[32];
			strcopy(sCopy, 32, sArgs[1]);

			FakeClientCommandEx(client, "sm_%s", sCopy);

			return Plugin_Stop;
		}
	}

	return Plugin_Continue;
}

public Action Command_Silencer(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	gB_Silencer[client] = !gB_Silencer[client];

	char sCookie[4];
	IntToString(view_as<int>(gB_Silencer[client]), sCookie, 4);
	SetClientCookie(client, gH_SilencerCookie, sCookie);

	if(gB_Silencer[client])
	{
		Shavit_PrintToChat(client, "%T", "SilencerEnabled", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}

	else
	{
		Shavit_PrintToChat(client, "%T", "SilencerDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}

	int iWeapon = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);

	if(iWeapon != -1)
	{
		RemovePlayerItem(client, iWeapon);
		AcceptEntityInput(iWeapon, "Kill");
	}

	iWeapon = GivePlayerItem(client, "weapon_usp");
	FakeClientCommand(client, "use weapon_usp");

	return Plugin_Handled;
}

public Action Command_Hide(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	gB_Hide[client] = !gB_Hide[client];

	char sCookie[4];
	IntToString(view_as<int>(gB_Hide[client]), sCookie, 4);
	SetClientCookie(client, gH_HideCookie, sCookie);

	if(gB_Hide[client])
	{
		Shavit_PrintToChat(client, "%T", "HideEnabled", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}

	else
	{
		Shavit_PrintToChat(client, "%T", "HideDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}

	return Plugin_Handled;
}

public Action Command_Spec(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	CleanSwitchTeam(client, 1, false);

	int target = -1;

	if(args > 0)
	{
		char sArgs[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		target = FindTarget(client, sArgs, false, false);

		if(target == -1)
		{
			return Plugin_Handled;
		}
	}

	else if(gB_Replay)
	{
		target = Shavit_GetReplayBotIndex(0);
	}

	if(IsValidClient(target, true))
	{
		SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", target);
	}

	return Plugin_Handled;
}

public Action Command_Teleport(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!gCV_TeleportCommands.BoolValue)
	{
		Shavit_PrintToChat(client, "%T", "CommandDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(args > 0)
	{
		char sArgs[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		int iTarget = FindTarget(client, sArgs, false, false);

		if(iTarget == -1)
		{
			return Plugin_Handled;
		}

		Teleport(client, GetClientSerial(iTarget));
	}

	else
	{
		Menu menu = new Menu(MenuHandler_Teleport);
		menu.SetTitle("%T", "TeleportMenuTitle", client);

		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsValidClient(i, true) || i == client)
			{
				continue;
			}

			char serial[16];
			IntToString(GetClientSerial(i), serial, 16);

			char sName[MAX_NAME_LENGTH];
			GetClientName(i, sName, MAX_NAME_LENGTH);

			menu.AddItem(serial, sName);
		}

		menu.ExitButton = true;
		menu.Display(client, 60);
	}

	return Plugin_Handled;
}

public int MenuHandler_Teleport(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		if(!Teleport(param1, StringToInt(sInfo)))
		{
			Command_Teleport(param1, 0);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

bool Teleport(int client, int targetserial)
{
	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "TeleportAlive", client);

		return false;
	}

	int iTarget = GetClientFromSerial(targetserial);

	if(Shavit_InsideZone(client, Zone_Start, -1) || Shavit_InsideZone(client, Zone_End, -1))
	{
		Shavit_PrintToChat(client, "%T", "TeleportInZone", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return false;
	}

	if(iTarget == 0)
	{
		Shavit_PrintToChat(client, "%T", "TeleportInvalidTarget", client);

		return false;
	}

	float vecPosition[3];
	GetClientAbsOrigin(iTarget, vecPosition);

	Shavit_StopTimer(client);

	TeleportEntity(client, vecPosition, NULL_VECTOR, NULL_VECTOR);

	return true;
}

public Action Command_Weapon(int client, int args)
{
	if(!IsValidClient(client) || gEV_Type == Engine_TF2)
	{
		return Plugin_Handled;
	}

	if(gCV_WeaponCommands.IntValue == 0)
	{
		Shavit_PrintToChat(client, "%T", "CommandDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "WeaponAlive", client, gS_ChatStrings.sVariable2, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	char sCommand[16];
	GetCmdArg(0, sCommand, 16);

	int iSlot = CS_SLOT_SECONDARY;
	char sWeapon[32];

	if(StrContains(sCommand, "usp", false) != -1)
	{
		strcopy(sWeapon, 32, (gEV_Type == Engine_CSS)? "weapon_usp":"weapon_usp_silencer");
	}

	else if(StrContains(sCommand, "glock", false) != -1)
	{
		strcopy(sWeapon, 32, "weapon_glock");
	}

	else
	{
		strcopy(sWeapon, 32, "weapon_knife");
		iSlot = CS_SLOT_KNIFE;
	}

	int iWeapon = GetPlayerWeaponSlot(client, iSlot);

	if(iWeapon != -1)
	{
		RemovePlayerItem(client, iWeapon);
		AcceptEntityInput(iWeapon, "Kill");
	}

	iWeapon = GivePlayerItem(client, sWeapon);
	FakeClientCommand(client, "use %s", sWeapon);

	if(iSlot != CS_SLOT_KNIFE)
	{
		SetWeaponAmmo(client, iWeapon);
	}

	return Plugin_Handled;
}

void SetWeaponAmmo(int client, int weapon)
{
	int iAmmo = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	SetEntData(client, gI_Ammo + (iAmmo * 4), 255, 4, true);

	if(gEV_Type == Engine_CSGO)
	{
		SetEntProp(weapon, Prop_Send, "m_iPrimaryReserveAmmoCount", 255);
	}
}

public Action Command_Checkpoints(int client, int args)
{
	if(client == 0)
	{
		//ReplyToCommand(client, "This command may be only performed in-game.");

		return Plugin_Handled;
	}

	if(gA_StyleSettings[gI_Style[client]].bKZCheckpoints)
	{
		gB_ClosedKZCP[client] = false;
	}

	return OpenCheckpointsMenu(client);
}

public Action Command_Save(int client, int args)
{
	if(client == 0)
	{
		//ReplyToCommand(client, "This command may be only performed in-game.");

		return Plugin_Handled;
	}

	int iMaxCPs = GetMaxCPs(client);
	bool bSegmenting = CanSegment(client);

	if(!gCV_Checkpoints.BoolValue && !bSegmenting)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	bool bOverflow = gA_Checkpoints[client].Length >= iMaxCPs;
	int index = gA_Checkpoints[client].Length;

	if(!bSegmenting)
	{
		if(index > iMaxCPs)
		{
			index = iMaxCPs;
		}

		if(bOverflow)
		{
			Shavit_PrintToChat(client, "%T", "MiscCheckpointsOverflow", client, index, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

			return Plugin_Handled;
		}

		if(SaveCheckpoint(client, index))
		{
			gI_CurrentCheckpoint[client] = gA_Checkpoints[client].Length;
			Shavit_PrintToChat(client, "%T", "MiscCheckpointsSaved", client, gI_CurrentCheckpoint[client], gS_ChatStrings.sVariable, gS_ChatStrings.sText);
		}
	}
	
	else if(SaveCheckpoint(client, index, bOverflow))
	{
		gI_CurrentCheckpoint[client] = (bOverflow)? iMaxCPs: gA_Checkpoints[client].Length;
		Shavit_PrintToChat(client, "%T", "MiscCheckpointsSaved", client, gI_CurrentCheckpoint[client], gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}

	return Plugin_Handled;
}

public Action Command_Tele(int client, int args)
{
	if(client == 0)
	{
		//ReplyToCommand(client, "This command may be only performed in-game.");

		return Plugin_Handled;
	}

	if(!gCV_Checkpoints.BoolValue)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	int index = gI_CurrentCheckpoint[client];

	if(args > 0)
	{
		char arg[4];
		GetCmdArg(1, arg, 4);

		int parsed = StringToInt(arg);

		if(0 < parsed <= gCV_MaxCP.IntValue)
		{
			index = parsed;
		}
	}

	TeleportToCheckpoint(client, index, true);

	return Plugin_Handled;
}

public Action OpenCheckpointsMenu(int client)
{
	if(gA_StyleSettings[gI_Style[client]].bKZCheckpoints)
	{
		OpenKZCPMenu(client);
	}

	else
	{
		OpenNormalCPMenu(client);
	}

	return Plugin_Handled;
}

void OpenKZCPMenu(int client)
{
	// if we're segmenting, resort to the normal checkpoints instead
	if(CanSegment(client))
	{
		OpenNormalCPMenu(client);

		return;
	}
	Menu menu = new Menu(MenuHandler_KZCheckpoints, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);
	menu.SetTitle("%T\n", "MiscCheckpointMenu", client);

	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "MiscCheckpointSave", client, (gA_Checkpoints[client].Length + 1));
	menu.AddItem("save", sDisplay, (gA_Checkpoints[client].Length < gCV_MaxCP.IntValue)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	if(gA_Checkpoints[client].Length > 0)
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointTeleport", client, gI_CurrentCheckpoint[client]);
		menu.AddItem("tele", sDisplay, ITEMDRAW_DEFAULT);
	}

	else
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointTeleport", client, 1);
		menu.AddItem("tele", sDisplay, ITEMDRAW_DISABLED);
	}

	FormatEx(sDisplay, 64, "%T", "MiscCheckpointPrevious", client);
	menu.AddItem("prev", sDisplay);

	FormatEx(sDisplay, 64, "%T", "MiscCheckpointNext", client);
	menu.AddItem("next", sDisplay);

	if((Shavit_CanPause(client) & CPR_ByConVar) == 0)
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointPause", client);
		menu.AddItem("pause", sDisplay);
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_KZCheckpoints(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		if(CanSegment(param1) || !gA_StyleSettings[gI_Style[param1]].bKZCheckpoints)
		{
			return 0;
		}

		int iCurrent = gI_CurrentCheckpoint[param1];
		int iMaxCPs = GetMaxCPs(param1);

		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		if(StrEqual(sInfo, "save"))
		{
			if(gA_Checkpoints[param1].Length < iMaxCPs &&
				SaveCheckpoint(param1, gA_Checkpoints[param1].Length))
			{
				gI_CurrentCheckpoint[param1] = gA_Checkpoints[param1].Length;
			}
		}

		else if(StrEqual(sInfo, "tele"))
		{
			TeleportToCheckpoint(param1, iCurrent, true);
		}

		else if(StrEqual(sInfo, "prev"))
		{
			if(iCurrent > 1)
			{
				gI_CurrentCheckpoint[param1]--;
			}
		}

		else if(StrEqual(sInfo, "next"))
		{
			if(iCurrent++ < gA_Checkpoints[param1].Length - 1)
				gI_CurrentCheckpoint[param1]++;
		}

		else if(StrEqual(sInfo, "pause"))
		{
			if(Shavit_CanPause(param1) == 0)
			{
				if(Shavit_IsPaused(param1))
				{
					Shavit_ResumeTimer(param1, true);
				}

				else
				{
					Shavit_PauseTimer(param1);
				}
			}
		}

		OpenCheckpointsMenu(param1);
	}

	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_Exit)
		{
			gB_ClosedKZCP[param1] = true;
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenNormalCPMenu(int client)
{
	bool bSegmented = CanSegment(client);

	if(!gCV_Checkpoints.BoolValue && !bSegmented)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return;
	}

	Menu menu = new Menu(MenuHandler_Checkpoints, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);

	if(!bSegmented)
	{
		menu.SetTitle("%T\n%T\n ", "MiscCheckpointMenu", client, "MiscCheckpointWarning", client);
	}

	else
	{
		menu.SetTitle("%T\n ", "MiscCheckpointMenuSegmented", client);
	}

	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "MiscCheckpointSave", client, (gA_Checkpoints[client].Length + 1));
	menu.AddItem("save", sDisplay, (gA_Checkpoints[client].Length < gCV_MaxCP.IntValue)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	if(gA_Checkpoints[client].Length > 0)
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointTeleport", client, gI_CurrentCheckpoint[client]);
		menu.AddItem("tele", sDisplay, ITEMDRAW_DEFAULT);
	}

	else
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointTeleport", client, 1);
		menu.AddItem("tele", sDisplay, ITEMDRAW_DISABLED);
	}

	FormatEx(sDisplay, 64, "%T", "MiscCheckpointPrevious", client);
	menu.AddItem("prev", sDisplay, (gI_CurrentCheckpoint[client] > 1)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	FormatEx(sDisplay, 64, "%T\n ", "MiscCheckpointNext", client);
	menu.AddItem("next", sDisplay, (gI_CurrentCheckpoint[client] < gA_Checkpoints[client].Length)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	menu.AddItem("spacer", "", ITEMDRAW_NOTEXT);

	FormatEx(sDisplay, 64, "%T", "MiscCheckpointDeleteCurrent", client);
	menu.AddItem("del", sDisplay, (gA_Checkpoints[client].Length > 0) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	FormatEx(sDisplay, 64, "%T", "MiscCheckpointReset", client);
	menu.AddItem("reset", sDisplay);
	if(!bSegmented)
	{
		char sInfo[16];
		IntToString(CP_ANGLES, sInfo, 16);
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointUseAngles", client);
		menu.AddItem(sInfo, sDisplay);

		IntToString(CP_VELOCITY, sInfo, 16);
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointUseVelocity", client);
		menu.AddItem(sInfo, sDisplay);
	}

	menu.Pagination = MENU_NO_PAGINATION;
	menu.ExitButton = true;

	Call_StartForward(gH_Forwards_OnCheckpointMenuMade);
	Call_PushCell(client);
	Call_PushCell(bSegmented);

	Action result = Plugin_Continue;
	Call_Finish(result);

	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return;
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Checkpoints(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		int iMaxCPs = GetMaxCPs(param1);
		int iCurrent = gI_CurrentCheckpoint[param1];

		Call_StartForward(gH_Forwards_OnCheckpointMenuSelect);
		Call_PushCell(param1);
		Call_PushCell(param2);
		Call_PushStringEx(sInfo, 16, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
		Call_PushCell(16); 
		Call_PushCell(iCurrent);
		Call_PushCell(iMaxCPs);

		Action result = Plugin_Continue;
		Call_Finish(result);

		if(result != Plugin_Continue)
		{
			return 0;
		}

		if(StrEqual(sInfo, "save"))
		{
			bool bSegmenting = CanSegment(param1);
			bool bOverflow = gA_Checkpoints[param1].Length >= iMaxCPs;

			if(!bSegmenting)
			{
				// fight an exploit
				if(bOverflow)
				{
					return 0;
				}

				if(SaveCheckpoint(param1, gA_Checkpoints[param1].Length))
				{
					gI_CurrentCheckpoint[param1] = gA_Checkpoints[param1].Length;
				}
			}
			
			else
			{
				if(SaveCheckpoint(param1, gA_Checkpoints[param1].Length, bOverflow))
				{
					gI_CurrentCheckpoint[param1] = (bOverflow)? iMaxCPs: gA_Checkpoints[param1].Length;
				}
			}
		}

		else if(StrEqual(sInfo, "tele"))
		{
			TeleportToCheckpoint(param1, iCurrent, true);
		}

		else if(StrEqual(sInfo, "prev"))
		{
			gI_CurrentCheckpoint[param1]--;
		}

		else if(StrEqual(sInfo, "next"))
		{
			gI_CurrentCheckpoint[param1]++;
		}
		else if(StrEqual(sInfo, "del"))
		{
			if(DeleteCheckpoint(param1, gI_CurrentCheckpoint[param1] - 1))
			{				
				if(gI_CurrentCheckpoint[param1] > gA_Checkpoints[param1].Length)
				{
					gI_CurrentCheckpoint[param1]--;
				}
			}
		}
		else if(StrEqual(sInfo, "reset"))
		{
			ConfirmCheckpointsDeleteMenu(param1);

			return 0;
		}

		else if(!StrEqual(sInfo, "spacer"))
		{
			char sCookie[8];
			gI_CheckpointsSettings[param1] ^= StringToInt(sInfo);
			IntToString(gI_CheckpointsSettings[param1], sCookie, 16);

			SetClientCookie(param1, gH_CheckpointsCookie, sCookie);
		}

		OpenCheckpointsMenu(param1);
	}

	else if(action == MenuAction_DisplayItem)
	{
		char sInfo[16];
		char sDisplay[64];
		int style = 0;
		menu.GetItem(param2, sInfo, 16, style, sDisplay, 64);

		if(StringToInt(sInfo) == 0)
		{
			return 0;
		}

		Format(sDisplay, 64, "[%s] %s", ((gI_CheckpointsSettings[param1] & StringToInt(sInfo)) > 0)? "x":" ", sDisplay);

		return RedrawMenuItem(sDisplay);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void ConfirmCheckpointsDeleteMenu(int client)
{
	Menu hMenu = new Menu(MenuHandler_CheckpointsDelete);
	hMenu.SetTitle("%T\n ", "ClearCPWarning", client);

	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "ClearCPYes", client);
	hMenu.AddItem("yes", sDisplay);

	FormatEx(sDisplay, 64, "%T", "ClearCPNo", client);
	hMenu.AddItem("no", sDisplay);

	hMenu.ExitButton = true;
	hMenu.Display(client, 60);
}

public int MenuHandler_CheckpointsDelete(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		if(StrEqual(sInfo, "yes"))
		{
			ResetCheckpoints(param1);
		}

		OpenCheckpointsMenu(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

bool SaveCheckpoint(int client, int index, bool overflow = false)
{
	// ???
	// nairda somehow triggered an error that requires this
	if(!IsValidClient(client))
	{
		return false;
	}

	int target = client;

	int iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
	int iObserverTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
	int iFlags = GetEntityFlags(client);

	if(IsClientObserver(client) && IsValidClient(iObserverTarget) && 3 <= iObserverMode <= 5)
	{
		target = iObserverTarget;
	}

	else if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "CommandAliveSpectate", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return false;
	}

	else if(Shavit_IsPaused(client) || Shavit_IsPaused(target))
	{
		Shavit_PrintToChat(client, "%T", "CommandNoPause", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return false;
	}

	if(gA_StyleSettings[gI_Style[client]].bKZCheckpoints)
	{
		if((iFlags & FL_ONGROUND) == 0 || client != target)
		{
			Shavit_PrintToChat(client, "%T", "CommandSaveCPKZInvalid", client);

			return false;
		}

		else if(Shavit_InsideZone(client, Zone_Start, -1))
		{
			Shavit_PrintToChat(client, "%T", "CommandSaveCPKZZone", client);
			
			return false;
		}
	}

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnSave);
	Call_PushCell(client);
	Call_PushCell(index);
	Call_PushCell(overflow);
	Call_Finish(result);
	
	if(result != Plugin_Continue)
	{
		return false;
	}

	gI_CurrentCheckpoint[client] = index;

	cp_cache_t cpcache;
	float temp[3];

	GetClientAbsOrigin(target, temp);
	CopyArray(temp, cpcache.fPosition, 3);

	GetClientEyeAngles(target, temp);
	CopyArray(temp, cpcache.fAngles, 3);

	GetEntPropVector(target, Prop_Data, "m_vecVelocity", temp);
	CopyArray(temp, cpcache.fVelocity, 3);

	GetEntPropVector(target, Prop_Data, "m_vecBaseVelocity", temp);
	CopyArray(temp, cpcache.fBaseVelocity, 3);

	char sTargetname[64];
	GetEntPropString(target, Prop_Data, "m_iName", sTargetname, 64);

	char sClassname[64];
	GetEntityClassname(target, sClassname, 64);

	strcopy(cpcache.sTargetname, 64, sTargetname);
	strcopy(cpcache.sClassname, 64, sClassname);

	cpcache.iMoveType = GetEntityMoveType(target);
	cpcache.fGravity = GetEntityGravity(target);
	cpcache.fSpeed = GetEntPropFloat(target, Prop_Send, "m_flLaggedMovementValue");
	if(cmdpos>GhostLength)
		cmdpos = cmdNum;

	cpcache.curcmds = cmdpos;

	if(IsFakeClient(target))
	{
		iFlags |= FL_CLIENT;
		iFlags |= FL_AIMTARGET;
		iFlags &= ~FL_ATCONTROLS;
		iFlags &= ~FL_FAKECLIENT;

		cpcache.fStamina = 0.0;
		cpcache.iGroundEntity = -1;
	}

	else
	{
		cpcache.fStamina = (gEV_Type != Engine_TF2)? GetEntPropFloat(target, Prop_Send, "m_flStamina"):0.0;
		cpcache.iGroundEntity = GetEntPropEnt(target, Prop_Data, "m_hGroundEntity");
	}

	cpcache.iFlags = iFlags;

	if(gEV_Type != Engine_TF2)
	{
		cpcache.bDucked = view_as<bool>(GetEntProp(target, Prop_Send, "m_bDucked"));
		cpcache.bDucking = view_as<bool>(GetEntProp(target, Prop_Send, "m_bDucking"));
	}

	if(gEV_Type == Engine_CSS)
	{
		cpcache.fDucktime = GetEntPropFloat(target, Prop_Send, "m_flDucktime");
	}

	else if(gEV_Type == Engine_CSGO)
	{
		cpcache.fDucktime = GetEntPropFloat(target, Prop_Send, "m_flDuckAmount");
		cpcache.fDuckSpeed = GetEntPropFloat(target, Prop_Send, "m_flDuckSpeed");
	}

	timer_snapshot_t snapshot;

	if(IsFakeClient(target))
	{
		// unfortunately replay bots don't have a snapshot, so we can generate a fake one
		int style = Shavit_GetReplayBotStyle(target);
		int track = Shavit_GetReplayBotTrack(target);

		if(style < 0 || track < 0)
		{
			Shavit_PrintToChat(client, "%T", "CommandAliveSpectate", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
			
			return false;
		}

		snapshot.bTimerEnabled = true;
		snapshot.fCurrentTime = Shavit_GetReplayTime(style, track);
		snapshot.bClientPaused = false;
		snapshot.bsStyle = style;
		snapshot.iJumps = 0;
		snapshot.iStrafes = 0;
		snapshot.iTotalMeasures = 0;
		snapshot.iGoodGains = 0;
		snapshot.fServerTime = GetEngineTime();
		snapshot.iSHSWCombination = -1;
		snapshot.iTimerTrack = track;
	}

	else
	{
		Shavit_SaveSnapshot(target, snapshot);
	}

	CopyArray(snapshot, cpcache.aSnapshot, sizeof(timer_snapshot_t));

	if(CanSegment(target))
	{
		if(gB_Replay)
		{
			cpcache.aFrames = Shavit_GetReplayData(target);
			cpcache.iPreFrames = Shavit_GetPlayerPreFrame(target);
			cpcache.iTimerPreFrames = Shavit_GetPlayerTimerFrame(target);
		}

		cpcache.bSegmented = true;
	}

	else
	{
		cpcache.aFrames = null;
		cpcache.bSegmented = false;
	}

	if (gB_Eventqueuefix && !IsFakeClient(target))
	{
		eventpack_t ep;

		if (GetClientEvents(target, ep))
		{
			cpcache.aEvents = ep.playerEvents;
			cpcache.aOutputWaits = ep.outputWaits;
		}
	}

	cpcache.iSerial = GetClientSerial(target);
	cpcache.bPractice = Shavit_IsPracticeMode(target);


	if(overflow)
	{
		int iMaxCPs = GetMaxCPs(client);

		if(gA_Checkpoints[client].Length >= iMaxCPs)
		{
			gA_Checkpoints[client].Erase(0);
			gI_CurrentCheckpoint[client] = gA_Checkpoints[client].Length;
		}

		gA_Checkpoints[client].Push(0);
		gA_Checkpoints[client].SetArray(gI_CurrentCheckpoint[client], cpcache);
	}
	else 
	{
		gA_Checkpoints[client].Push(0);
		gA_Checkpoints[client].SetArray(index, cpcache);
	}

	return true;
}

void TeleportToCheckpoint(int client, int index, bool suppressMessage)
{
	if(index < 1 || index > gCV_MaxCP.IntValue || (!gCV_Checkpoints.BoolValue && !CanSegment(client)))
	{
		return;
	}

	if(Shavit_IsPaused(client))
	{
		Shavit_PrintToChat(client, "%T", "CommandNoPause", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return;
	}

	cp_cache_t cpcache;

	if(index > gA_Checkpoints[client].Length)
	{
		Shavit_PrintToChat(client, "%T", "MiscCheckpointsEmpty", client, index, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		return;
	}

	gA_Checkpoints[client].GetArray(index - 1, cpcache, sizeof(cp_cache_t));

	timer_snapshot_t snapshot;
	CopyArray(cpcache.aSnapshot, snapshot, sizeof(timer_snapshot_t));

	if(gA_StyleSettings[gI_Style[client]].bKZCheckpoints != gA_StyleSettings[snapshot.bsStyle].bKZCheckpoints)
	{
		Shavit_PrintToChat(client, "%T", "CommandTeleCPInvalid", client);

		return;
	}

	float pos[3];
	CopyArray(cpcache.fPosition, pos, 3);

	if(IsNullVector(pos))
	{
		return;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "CommandAlive", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return;
	}

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnTeleport);
	Call_PushCell(client);
	Call_PushCell(index - 1);
	Call_Finish(result);
	
	if(result != Plugin_Continue)
	{
		return;
	}

	if(Shavit_InsideZone(client, Zone_Start, -1))
	{
		Shavit_StopTimer(client);
	}

	MoveType mt = cpcache.iMoveType;

	if(mt == MOVETYPE_LADDER || mt == MOVETYPE_WALK)
	{
		SetEntityMoveType(client, mt);
	}

	SetEntityFlags(client, cpcache.iFlags);
	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", cpcache.fSpeed);
	SetEntPropEnt(client, Prop_Data, "m_hGroundEntity", cpcache.iGroundEntity);
	cmdpos = cpcache.curcmds;
	if(cmdpos < GhostLength)
		cmdNum = cmdpos;

	if(gEV_Type != Engine_TF2)
	{
		SetEntPropFloat(client, Prop_Send, "m_flStamina", cpcache.fStamina);
		SetEntProp(client, Prop_Send, "m_bDucked", cpcache.bDucked);
		SetEntProp(client, Prop_Send, "m_bDucking", cpcache.bDucking);
	}

	if(gEV_Type == Engine_CSS)
	{
		SetEntPropFloat(client, Prop_Send, "m_flDucktime", cpcache.fDucktime);
	}

	else if(gEV_Type == Engine_CSGO)
	{
		SetEntPropFloat(client, Prop_Send, "m_flDuckAmount", cpcache.fDucktime);
		SetEntPropFloat(client, Prop_Send, "m_flDuckSpeed", cpcache.fDuckSpeed);
	}

	float ang[3];
	CopyArray(cpcache.fAngles, ang, 3);

	// this is basically the same as normal checkpoints except much less data is used
	if(gA_StyleSettings[gI_Style[client]].bKZCheckpoints)
	{
		TeleportEntity(client, pos, ang, view_as<float>({ 0.0, 0.0, 0.0 }));

		return;
	}

	Shavit_LoadSnapshot(client, snapshot);
	Shavit_ResumeTimer(client);

	float vel[3];

	if((gI_CheckpointsSettings[client] & CP_VELOCITY) > 0 || cpcache.bSegmented)
	{
		float basevel[3];
		CopyArray(cpcache.fVelocity, vel, 3);
		CopyArray(cpcache.fBaseVelocity, basevel, 3);

		AddVectors(vel, basevel, vel);
	}

	else
	{
		vel = NULL_VECTOR;
	}

	SetEntPropString(client, Prop_Data, "m_iName", cpcache.sTargetname);
	SetEntPropString(client, Prop_Data, "m_iClassname", cpcache.sClassname);

	if (gB_Eventqueuefix && cpcache.aEvents != null && cpcache.aOutputWaits != null)
	{
		eventpack_t ep;
		ep.playerEvents = cpcache.aEvents;
		ep.outputWaits = cpcache.aOutputWaits;
		SetClientEvents(client, ep);
	}

	TeleportEntity(client, pos,
		((gI_CheckpointsSettings[client] & CP_ANGLES) > 0 || cpcache.bSegmented)? ang:NULL_VECTOR,
		vel);

	if(cpcache.bPractice || !cpcache.bSegmented)
	{
		Shavit_SetPracticeMode(client, true, true);
	}

	if(!cpcache.bPractice || cpcache.bSegmented)
	{
		Shavit_SetPracticeMode(client, false, true);
	}
	SetEntityGravity(client, cpcache.fGravity);
	
	if(cpcache.bSegmented && gB_Replay)
	{
		if(cpcache.aFrames == null)
		{
			LogError("SetReplayData for %L failed, recorded frames are null.", client);
		}

		else
		{
			Shavit_SetReplayData(client, cpcache.aFrames);
			Shavit_SetPlayerPreFrame(client, cpcache.iPreFrames);
			Shavit_SetPlayerTimerFrame(client, cpcache.iTimerPreFrames);
		}
	}
	
	if(!suppressMessage)
	{
		Shavit_PrintToChat(client, "%T", "MiscCheckpointsTeleported", client, index, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}
}

bool DeleteCheckpoint(int client, int index)
{
	Action result = Plugin_Continue;

	Call_StartForward(gH_Forwards_OnDelete);
	Call_PushCell(client);
	Call_PushCell(index);
	Call_Finish(result);

	if(result != Plugin_Continue)
	{
		return false;
	}

	gA_Checkpoints[client].Erase(index);

	return true;
}

bool ShouldDisplayStopWarning(int client)
{
	return (gCV_StopTimerWarning.BoolValue && Shavit_GetTimerStatus(client) != Timer_Stopped && Shavit_GetClientTime(client) > gCV_StopTimerWarning.FloatValue);
}

void DoNoclip(int client)
{
	Shavit_StopTimer(client);
	SetEntityMoveType(client, MOVETYPE_NOCLIP);
}

void DoStopTimer(int client)
{
	Shavit_StopTimer(client);
}

void OpenStopWarningMenu(int client, StopTimerCallback after)
{
	gH_AfterWarningMenu[client] = after;

	Menu hMenu = new Menu(MenuHandler_StopWarning);
	hMenu.SetTitle("%T\n ", "StopTimerWarning", client);

	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "StopTimerYes", client);
	hMenu.AddItem("yes", sDisplay);

	FormatEx(sDisplay, 64, "%T", "StopTimerNo", client);
	hMenu.AddItem("no", sDisplay);

	hMenu.ExitButton = true;
	hMenu.Display(client, 30);
}

public int MenuHandler_StopWarning(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		if(StrEqual(sInfo, "yes"))
		{
			Call_StartFunction(null, gH_AfterWarningMenu[param1]);
			Call_PushCell(param1);
			Call_Finish();
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public bool Shavit_OnStopPre(int client, int track)
{
	if(ShouldDisplayStopWarning(client))
	{
		OpenStopWarningMenu(client, DoStopTimer);

		return false;
	}

	return true;
}

public Action Command_Noclip(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(gCV_NoclipMe.IntValue == 0)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	else if(gCV_NoclipMe.IntValue == 2 && !CheckCommandAccess(client, "admin_noclipme", ADMFLAG_CHEATS))
	{
		Shavit_PrintToChat(client, "%T", "LackingAccess", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "CommandAlive", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(GetEntityMoveType(client) != MOVETYPE_NOCLIP)
	{
		if(!ShouldDisplayStopWarning(client))
		{
			Shavit_StopTimer(client);
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
		}

		else
		{
			OpenStopWarningMenu(client, DoNoclip);
		}
	}

	else
	{
		SetEntityMoveType(client, MOVETYPE_WALK);
	}

	return Plugin_Handled;
}

public Action CommandListener_Noclip(int client, const char[] command, int args)
{
	if(!IsValidClient(client, true))
	{
		return Plugin_Handled;
	}

	if((gCV_NoclipMe.IntValue == 1 || (gCV_NoclipMe.IntValue == 2 && CheckCommandAccess(client, "noclipme", ADMFLAG_CHEATS))) && command[0] == '+')
	{
		if(!ShouldDisplayStopWarning(client))
		{
			Shavit_StopTimer(client);
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
		}

		else
		{
			OpenStopWarningMenu(client, DoNoclip);
		}
	}

	else if(GetEntityMoveType(client) == MOVETYPE_NOCLIP)
	{
		SetEntityMoveType(client, MOVETYPE_WALK);
	}

	return Plugin_Handled;
}

public Action Command_Specs(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client) && !IsClientObserver(client))
	{
		Shavit_PrintToChat(client, "%T", "SpectatorInvalid", client);

		return Plugin_Handled;
	}

	int iObserverTarget = client;

	if(IsClientObserver(client))
	{
		iObserverTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
	}

	if(args > 0)
	{
		char sTarget[MAX_TARGET_LENGTH];
		GetCmdArgString(sTarget, MAX_TARGET_LENGTH);

		int iNewTarget = FindTarget(client, sTarget, false, false);

		if(iNewTarget == -1)
		{
			return Plugin_Handled;
		}

		if(!IsPlayerAlive(iNewTarget))
		{
			Shavit_PrintToChat(client, "%T", "SpectateDead", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

			return Plugin_Handled;
		}

		iObserverTarget = iNewTarget;
	}

	int iCount = 0;
	bool bIsAdmin = CheckCommandAccess(client, "admin_speclisthide", ADMFLAG_KICK);
	char sSpecs[192];

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || IsFakeClient(i) || !IsClientObserver(i) || GetClientTeam(i) < 1)
		{
			continue;
		}

		if((gCV_SpectatorList.IntValue == 1 && !bIsAdmin && CheckCommandAccess(i, "admin_speclisthide", ADMFLAG_KICK)) ||
			(gCV_SpectatorList.IntValue == 2 && !CanUserTarget(client, i)))
		{
			continue;
		}

		if(GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") == iObserverTarget)
		{
			iCount++;

			if(iCount == 1)
			{
				FormatEx(sSpecs, 192, "%s%N", gS_ChatStrings.sVariable2, i);
			}

			else
			{
				Format(sSpecs, 192, "%s%s, %s%N", sSpecs, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, i);
			}
		}
	}

	if(iCount > 0)
	{
		Shavit_PrintToChat(client, "%T", "SpectatorCount", client, gS_ChatStrings.sVariable2, iObserverTarget, gS_ChatStrings.sText, gS_ChatStrings.sVariable, iCount, gS_ChatStrings.sText, sSpecs);
	}

	else
	{
		Shavit_PrintToChat(client, "%T", "SpectatorCountZero", client, gS_ChatStrings.sVariable2, iObserverTarget, gS_ChatStrings.sText);
	}

	return Plugin_Handled;
}

public Action Shavit_OnStart(int client)
{
	if(gA_StyleSettings[gI_Style[client]].iPrespeed == 0 && GetEntityMoveType(client) == MOVETYPE_NOCLIP)
	{
		return Plugin_Stop;
	}

	if(gCV_ResetTargetname.BoolValue || Shavit_IsPracticeMode(client)) // practice mode can be abused to break map triggers
	{
		DispatchKeyValue(client, "targetname", "");
		SetEntPropString(client, Prop_Data, "m_iClassname", "player");
	}

	if(gA_StyleSettings[gI_Style[client]].bKZCheckpoints)
	{
		ResetCheckpoints(client);
	}

	return Plugin_Continue;
}

void GetTrackName(int client, int track, char[] output, int size)
{
	if(track < 0 || track >= TRACKS_SIZE)
	{
		FormatEx(output, size, "%T", "Track_Unknown", client);

		return;
	}

	static char sTrack[16];
	FormatEx(sTrack, 16, "Track_%d", track);
	FormatEx(output, size, "%T", sTrack, client);
}

public void Shavit_OnWorldRecord(int client, int style, float time, int jumps, int strafes, float sync, int track)
{
	char sUpperCase[64];
	strcopy(sUpperCase, 64, gS_StyleStrings[style].sStyleName);

	for(int i = 0; i < strlen(sUpperCase); i++)
	{
		if(!IsCharUpper(sUpperCase[i]))
		{
			sUpperCase[i] = CharToUpper(sUpperCase[i]);
		}
	}

	char sTrack[32];
	GetTrackName(LANG_SERVER, track, sTrack, 32);

	for(int i = 1; i <= gCV_WRMessages.IntValue; i++)
	{
		if(track == Track_Main)
		{
			Shavit_PrintToChatAll("%t", "WRNotice", gS_ChatStrings.sWarning, sUpperCase);
		}

		else
		{
			Shavit_PrintToChatAll("%s[%s]%s %t", gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText, "WRNotice", gS_ChatStrings.sWarning, sUpperCase);
		}
	}
}

public void Shavit_OnRestart(int client, int track)
{
	if(gEV_Type != Engine_TF2)
	{
		SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
	}

	if(!gB_ClosedKZCP[client] &&
		gA_StyleSettings[gI_Style[client]].bKZCheckpoints &&
		GetClientMenu(client, null) == MenuSource_None &&
		IsPlayerAlive(client) && GetClientTeam(client) >= 2)
	{
		OpenKZCPMenu(client);
	}
	
	if(!gCV_RespawnOnRestart.BoolValue)
	{
		return;
	}

	if(!IsPlayerAlive(client))
	{
		if(gEV_Type == Engine_TF2)
		{
			TF2_ChangeClientTeam(client, view_as<TFTeam>(3));
		}
		
		else
		{
			if(FindEntityByClassname(-1, "info_player_terrorist") != -1)
			{
				CS_SwitchTeam(client, 2);
			}

			else
			{
				CS_SwitchTeam(client, 3);
			}
		}

		if(gEV_Type == Engine_TF2)
		{
			TF2_RespawnPlayer(client);
		}

		else
		{
			CS_RespawnPlayer(client);
		}

		if(gCV_RespawnOnRestart.BoolValue)
		{
			RestartTimer(client, track);
		}
	}
}

public Action Respawn(Handle Timer, any data)
{
	int client = GetClientFromSerial(data);

	if(IsValidClient(client) && !IsPlayerAlive(client) && GetClientTeam(client) >= 2)
	{
		if(gEV_Type == Engine_TF2)
		{
			TF2_RespawnPlayer(client);
		}

		else
		{
			CS_RespawnPlayer(client);
		}

		if(gCV_RespawnOnRestart.BoolValue)
		{
			RestartTimer(client, Track_Main);
		}
	}

	return Plugin_Handled;
}

void RestartTimer(int client, int track)
{
	if((gB_Zones && Shavit_ZoneExists(Zone_Start, track)) || Shavit_IsKZMap())
	{
		Shavit_RestartTimer(client, track);
	}
}

public void Player_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(!IsFakeClient(client))
	{
		int serial = GetClientSerial(client);

		RequestFrame(LoadGhost, serial);

		if(gCV_HideRadar.BoolValue)
		{
			RequestFrame(RemoveRadar, serial);
		}

		if(gCV_StartOnSpawn.BoolValue)
		{
			RestartTimer(client, Track_Main);
		}

		if(gB_SaveStates[client])
		{
			if(gCV_RestoreStates.BoolValue)
			{
				RequestFrame(RestoreState, serial);
			}

			else
			{
				gB_SaveStates[client] = false;
			}
		}

		else
		{
			CreateTimer(0.10, Timer_LoadPersistentData, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		}

		if(gCV_Scoreboard.BoolValue)
		{
			UpdateScoreboard(client);
		}

		UpdateClanTag(client);

		// refreshes kz cp menu if there is nothing open
		if(!gB_ClosedKZCP[client] &&
			gA_StyleSettings[gI_Style[client]].bKZCheckpoints &&
			GetClientMenu(client, null) == MenuSource_None &&
			IsPlayerAlive(client) && GetClientTeam(client) >= 2)
		{
			OpenKZCPMenu(client);
		}
	}

	if(gCV_NoBlock.BoolValue)
	{
		SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);
	}

	if(gCV_PlayerOpacity.IntValue != -1)
	{
		SetEntityRenderMode(client, RENDER_TRANSCOLOR);
		SetEntityRenderColor(client, 255, 255, 255, gCV_PlayerOpacity.IntValue);
	}
}

void LoadGhost(any data)
{
	int client = GetClientFromSerial(data);
	if(client == 0)
	{
		return;
	}
	if(gB_Silencer[client])
	{
		char weapon[32];
		GetClientWeapon(client,weapon,sizeof(weapon));
		if(StrEqual(weapon,"weapon_usp"))
		{
			int iWeapon = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);

			if(iWeapon != -1)
			{
				RemovePlayerItem(client, iWeapon);
				AcceptEntityInput(iWeapon, "Kill");
			}

			iWeapon = GivePlayerItem(client, "weapon_usp");
			FakeClientCommand(client, "use weapon_usp");
		}
	}

	bool own = false;
	if(c_style == 255)
	{
		ownstyle = c_style;
		c_style = Shavit_GetBhopStyle(client);
		own = true;
	}

	bool X_X = true;
	if(Shavit_GetBhopStyle(client)!=c_style)
		if(Shavit_GetReplayFrameCount(c_style, 0) < 1)
		{
			c_style = Shavit_GetBhopStyle(client);
			ArrayList ar = Shavit_GetReplayFrames(c_style, 0);
			
			GhostData2[client] = ar.Clone();
			GhostLength = 0;

			if(GhostData2[client] != null)
				GhostLength = GhostData2[client].Length;
				
			cmdNum = 0;
			CreateTimer(0.7, Spawn, INVALID_HANDLE, TIMER_FLAG_NO_MAPCHANGE);
			X_X = false;
		}

	if(X_X)
	{
		if(own)
		{
			ArrayList ar = Shavit_GetReplayFrames(Shavit_GetBhopStyle(client), 0);
			GhostData2[client] = ar.Clone();
			GhostLength = 0;

			if(GhostData2[client] != null)
				GhostLength = GhostData2[client].Length;
			cmdNum = 0;
		}
		
		else
		{
			if(ownstyle<255)
				ownstyle = c_style;

			ArrayList ar = Shavit_GetReplayFrames(c_style, 0);
			GhostData2[client] = ar.Clone();
			GhostLength = 0;

			if(GhostData2[client] != null)
				GhostLength = GhostData2[client].Length;
			cmdNum = 0;
		}
	}
}

public Action Spawn(Handle Timer)
{
	if(c_style==0)
		Shavit_PrintToChatAll("%sNo Custom Ghost Data Found, setting it to:%s Normal", gS_ChatStrings.sText,gS_ChatStrings.sVariable);

	else	
		Shavit_PrintToChatAll("%sNo Custom Ghost Data Found, setting it to:%s %s", gS_ChatStrings.sText,gS_ChatStrings.sVariable,gS_StyleStrings[c_style].sStyleName);
}	

void RemoveRadarBase(int client)
{
	if(client == 0 || !IsPlayerAlive(client))
	{
		return;
	}

	if(gEV_Type == Engine_CSGO)
	{
		SetEntProp(client, Prop_Send, "m_iHideHUD", GetEntProp(client, Prop_Send, "m_iHideHUD") | (1 << 12)); // disables player radar
	}

	else if(gEV_Type == Engine_CSS)
	{
		SetEntPropFloat(client, Prop_Send, "m_flFlashDuration", 3600.0 + GetURandomFloat());
		SetEntPropFloat(client, Prop_Send, "m_flFlashMaxAlpha", 0.5);
	}
}

void RemoveRadar(any data)
{
	int client = GetClientFromSerial(data);
	RemoveRadarBase(client);
}

void RestoreState(any data)
{
	int client = GetClientFromSerial(data);

	if(client == 0 || !IsPlayerAlive(client))
	{
		return;
	}

	if(gA_SaveStates[client].bsStyle != Shavit_GetBhopStyle(client) ||
		gA_SaveStates[client].iTimerTrack != Shavit_GetClientTrack(client))
	{
		gB_SaveStates[client] = false;

		return;
	}

	LoadState(client);
}

public Action Player_Notifications(Event event, const char[] name, bool dontBroadcast)
{
	if(gCV_HideTeamChanges.BoolValue)
	{
		event.BroadcastDisabled = true;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));

	if(!IsFakeClient(client))
	{
		if(!gB_SaveStates[client])
		{
			SaveState(client);
		}

		if(gCV_AutoRespawn.FloatValue > 0.0 && StrEqual(name, "player_death"))
		{
			CreateTimer(gCV_AutoRespawn.FloatValue, Respawn, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	switch(gCV_RemoveRagdolls.IntValue)
	{
		case 0:
		{
			return Plugin_Continue;
		}

		case 1:
		{
			if(IsFakeClient(client))
			{
				RemoveRagdoll(client);
			}
		}

		case 2:
		{
			RemoveRagdoll(client);
		}

		default:
		{
			return Plugin_Continue;
		}
	}

	return Plugin_Continue;
}

public void Weapon_Fire(Event event, const char[] name, bool dB)
{
	if(gCV_WeaponCommands.IntValue < 2)
	{
		return;
	}

	char sWeapon[16];
	event.GetString("weapon", sWeapon, 16);

	if(StrContains(sWeapon, "usp") != -1 || StrContains(sWeapon, "hpk") != -1 || StrContains(sWeapon, "glock") != -1)
	{
		int client = GetClientOfUserId(event.GetInt("userid"));
		SetWeaponAmmo(client, GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon"));
	}
}

public Action Shotgun_Shot(const char[] te_name, const int[] Players, int numClients, float delay)
{
	int client = (TE_ReadNum("m_iPlayer") + 1);

	if(!(1 <= client <= MaxClients) || !IsClientInGame(client))
	{
		return Plugin_Continue;
	}

	int ticks = GetGameTickCount();

	if(gI_LastShot[client] == ticks)
	{
		return Plugin_Continue;
	}

	gI_LastShot[client] = ticks;

	int[] clients = new int[MaxClients];
	int count = 0;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || i == client)
		{
			continue;
		}

		if(!gB_Hide[i] ||
			(IsClientObserver(i) && GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") == client && 3 <= GetEntProp(i, Prop_Send, "m_iObserverMode") <= 5))
		{
			clients[count++] = i;
		}
	}

	if(numClients == count)
	{
		return Plugin_Continue;
	}

	TE_Start((gEV_Type != Engine_TF2)? "Shotgun Shot":"Fire Bullets");

	float temp[3];
	TE_ReadVector("m_vecOrigin", temp);
	TE_WriteVector("m_vecOrigin", temp);

	TE_WriteFloat("m_vecAngles[0]", TE_ReadFloat("m_vecAngles[0]"));
	TE_WriteFloat("m_vecAngles[1]", TE_ReadFloat("m_vecAngles[1]"));
	TE_WriteNum("m_iMode", TE_ReadNum("m_iMode"));
	TE_WriteNum("m_iSeed", TE_ReadNum("m_iSeed"));
	TE_WriteNum("m_iPlayer", (client - 1));

	if(gEV_Type == Engine_CSS)
	{
		TE_WriteNum("m_iWeaponID", TE_ReadNum("m_iWeaponID"));
		TE_WriteFloat("m_fInaccuracy", TE_ReadFloat("m_fInaccuracy"));
		TE_WriteFloat("m_fSpread", TE_ReadFloat("m_fSpread"));
	}

	else if(gEV_Type == Engine_CSGO)
	{
		TE_WriteNum("m_weapon", TE_ReadNum("m_weapon"));
		TE_WriteFloat("m_fInaccuracy", TE_ReadFloat("m_fInaccuracy"));
		TE_WriteFloat("m_flRecoilIndex", TE_ReadFloat("m_flRecoilIndex"));
		TE_WriteFloat("m_fSpread", TE_ReadFloat("m_fSpread"));
		TE_WriteNum("m_nItemDefIndex", TE_ReadNum("m_nItemDefIndex"));
		TE_WriteNum("m_iSoundType", TE_ReadNum("m_iSoundType"));
	}

	else if(gEV_Type == Engine_TF2)
	{
		TE_WriteNum("m_iWeaponID", TE_ReadNum("m_iWeaponID"));
		TE_WriteFloat("m_flSpread", TE_ReadFloat("m_flSpread"));
		TE_WriteNum("m_bCritical", TE_ReadNum("m_bCritical"));
	}
	
	TE_Send(clients, count, delay);

	return Plugin_Stop;
}

public Action EffectDispatch(const char[] te_name, const Players[], int numClients, float delay)
{
	if(!gCV_NoBlood.BoolValue)
	{
		return Plugin_Continue;
	}

	int iEffectIndex = TE_ReadNum("m_iEffectName");
	int nHitBox = TE_ReadNum("m_nHitBox");

	char sEffectName[32];
	GetEffectName(iEffectIndex, sEffectName, 32);

	if(StrEqual(sEffectName, "csblood"))
	{
		return Plugin_Handled;
	}

	if(StrEqual(sEffectName, "ParticleEffect"))
	{
		char sParticleEffectName[32];
		GetParticleEffectName(nHitBox, sParticleEffectName, 32);

		if(StrEqual(sParticleEffectName, "impact_helmet_headshot") || StrEqual(sParticleEffectName, "impact_physics_dust"))
		{
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action WorldDecal(const char[] te_name, const Players[], int numClients, float delay)
{
	if(!gCV_NoBlood.BoolValue)
	{
		return Plugin_Continue;
	}

	float vecOrigin[3];
	TE_ReadVector("m_vecOrigin", vecOrigin);

	int nIndex = TE_ReadNum("m_nIndex");

	char sDecalName[32];
	GetDecalName(nIndex, sDecalName, 32);

	if(StrContains(sDecalName, "decals/blood") == 0 && StrContains(sDecalName, "_subrect") != -1)
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action NormalSound(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if(!gCV_BhopSounds.BoolValue)
	{
		return Plugin_Continue;
	}

	if(StrContains(sample, "physics/") != -1 || StrContains(sample, "weapons/") != -1 || StrContains(sample, "player/") != -1 || StrContains(sample, "items/") != -1)
	{
		if(gCV_BhopSounds.IntValue == 2)
		{
			numClients = 0;
		}

		else
		{
			for(int i = 0; i < numClients; ++i)
			{
				if(IsValidClient(clients[i]) && gB_Hide[clients[i]])
				{
					for (int j = i; j < numClients-1; j++)
					{
						clients[j] = clients[j+1];
					}
					
					numClients--;
					i--;
				}
			}
		}

		return Plugin_Changed;
	}
   
	return Plugin_Continue;
}

int GetParticleEffectName(int index, char[] sEffectName, int maxlen)
{
	static int table = INVALID_STRING_TABLE;

	if(table == INVALID_STRING_TABLE)
	{
		table = FindStringTable("ParticleEffectNames");
	}

	return ReadStringTable(table, index, sEffectName, maxlen);
}

int GetEffectName(int index, char[] sEffectName, int maxlen)
{
	static int table = INVALID_STRING_TABLE;

	if(table == INVALID_STRING_TABLE)
	{
		table = FindStringTable("EffectDispatch");
	}

	return ReadStringTable(table, index, sEffectName, maxlen);
}

int GetDecalName(int index, char[] sDecalName, int maxlen)
{
	static int table = INVALID_STRING_TABLE;

	if(table == INVALID_STRING_TABLE)
	{
		table = FindStringTable("decalprecache");
	}

	return ReadStringTable(table, index, sDecalName, maxlen);
}

public void Shavit_OnFinish(int client)
{
	if(!gCV_Scoreboard.BoolValue)
	{
		return;
	}

	UpdateScoreboard(client);
	UpdateClanTag(client);
}

public void Shavit_OnPause(int client, int track)
{
	if(!GetClientEyeAngles(client, gF_SaveStateData[client][1]))
	{
		gF_SaveStateData[client][1] = NULL_VECTOR;
	}
}

public void Shavit_OnResume(int client, int track)
{
	if(!IsNullVector(gF_SaveStateData[client][1]))
	{
		TeleportEntity(client, NULL_VECTOR, gF_SaveStateData[client][1], NULL_VECTOR);
	}
}

public Action Command_Drop(int client, const char[] command, int argc)
{
	if(!gCV_DropAll.BoolValue || !IsValidClient(client) || gEV_Type == Engine_TF2)
	{
		return Plugin_Continue;
	}

	int iWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");

	if(iWeapon != -1 && IsValidEntity(iWeapon) && GetEntPropEnt(iWeapon, Prop_Send, "m_hOwnerEntity") == client)
	{
		CS_DropWeapon(client, iWeapon, true);
	}

	return Plugin_Handled;
}

void LoadState(int client)
{
	TeleportEntity(client, gF_SaveStateData[client][0], gF_SaveStateData[client][1], gF_SaveStateData[client][2]);
	DispatchKeyValue(client, "targetname", gS_SaveStateTargetname[client]);

	Shavit_LoadSnapshot(client, gA_SaveStates[client]);
	Shavit_SetPracticeMode(client, gB_SaveStatesSegmented[client], false);

	if(gB_Replay && gA_SaveFrames[client] != null)
	{
		Shavit_SetReplayData(client, gA_SaveFrames[client]);
		Shavit_SetPlayerPreFrame(client, gI_SavePreFrames[client]);
		Shavit_SetPlayerTimerFrame(client, gI_TimerFrames[client]);
	}

	delete gA_SaveFrames[client];
	gB_SaveStates[client] = false;
}

void SaveState(int client)
{
	if(Shavit_GetTimerStatus(client) == Timer_Stopped)
	{
		return;
	}
	
	GetClientAbsOrigin(client, gF_SaveStateData[client][0]);
	GetClientEyeAngles(client, gF_SaveStateData[client][1]);
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", gF_SaveStateData[client][2]);
	GetEntPropString(client, Prop_Data, "m_iName", gS_SaveStateTargetname[client], 32);

	Shavit_SaveSnapshot(client, gA_SaveStates[client]);
	gB_SaveStatesSegmented[client] = Shavit_IsPracticeMode(client);

	if(gB_Replay)
	{
		delete gA_SaveFrames[client];
		gA_SaveFrames[client] = Shavit_GetReplayData(client);
		gI_SavePreFrames[client] = Shavit_GetPlayerPreFrame(client);
		gI_TimerFrames[client] = Shavit_GetPlayerTimerFrame(client);
	}

	gB_SaveStates[client] = true;
}


void CopyArray(const any[] from, any[] to, int size)
{
	for(int i = 0; i < size; i++)
	{
		to[i] = from[i];
	}
}

bool CanSegment(int client)
{
	return StrContains(gS_StyleStrings[gI_Style[client]].sSpecialString, "segments") != -1;
}

int GetMaxCPs(int client)
{
	return CanSegment(client)? gCV_MaxCP_Segmented.IntValue:gCV_MaxCP.IntValue;
}

public any Native_GetCheckpoint(Handle plugin, int numParams)
{
	if(GetNativeCell(4) != sizeof(cp_cache_t))
	{
		return ThrowNativeError(200, "cp_cache_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins",
			GetNativeCell(4), sizeof(cp_cache_t));
	}
	int client = GetNativeCell(1);
	int index = GetNativeCell(2);

	cp_cache_t cpcache;
	if(gA_Checkpoints[client].GetArray(index, cpcache, sizeof(cp_cache_t)))
	{
		SetNativeArray(3, cpcache, sizeof(cp_cache_t));
		return true;
	}

	return false;
}

public any Native_SetCheckpoint(Handle plugin, int numParams)
{
	if(GetNativeCell(4) != sizeof(cp_cache_t))
	{
		return ThrowNativeError(200, "cp_cache_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins",
			GetNativeCell(4), sizeof(cp_cache_t));
	}
	int client = GetNativeCell(1);
	int position = GetNativeCell(2);

	cp_cache_t cpcache;
	GetNativeArray(3, cpcache, sizeof(cp_cache_t));

	if(position == -1)
	{
		position = gI_CurrentCheckpoint[client];
	}

	if(position >= gA_Checkpoints[client].Length)
	{
		position = gA_Checkpoints[client].Length - 1;
	}

	gA_Checkpoints[client].SetArray(position, cpcache, sizeof(cp_cache_t));
	
	return true;
}

public any Native_ClearCheckpoints(Handle plugin, int numParams)
{
	ResetCheckpoints(GetNativeCell(1));
	return 0;
}

public any Native_TeleportToCheckpoint(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int position = GetNativeCell(2);
	bool suppress = GetNativeCell(3);

	TeleportToCheckpoint(client, position, suppress);
	return 0;
}

public any Native_GetTotalCheckpoints(Handle plugin, int numParams)
{
	return gA_Checkpoints[GetNativeCell(1)].Length;
}

public any Native_GetCurrentCheckpoint(Handle plugin, int numParams)
{
	return gI_CurrentCheckpoint[GetNativeCell(1)];
}

public any Native_SetCurrentCheckpoint(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int index = GetNativeCell(2);
	
	gI_CurrentCheckpoint[client] = index;
	return 0;
}

public any Native_OpenCheckpointMenu(Handle plugin, int numParams)
{
	OpenNormalCPMenu(GetNativeCell(1));
	return 0;
}

public any Native_SaveCheckpoint(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int iMaxCPs = GetMaxCPs(client);

	bool bSegmenting = CanSegment(client);
	bool bOverflow = gA_Checkpoints[client].Length >= iMaxCPs;

	if(!bSegmenting)
	{
		// fight an exploit
		if(bOverflow)
		{
			return -1;
		}

		if(SaveCheckpoint(client, gA_Checkpoints[client].Length))
		{
			gI_CurrentCheckpoint[client] = gA_Checkpoints[client].Length;
		}
	}
	
	else
	{
		if(SaveCheckpoint(client, gA_Checkpoints[client].Length, bOverflow))
		{
			gI_CurrentCheckpoint[client] = (bOverflow)? iMaxCPs:gA_Checkpoints[client].Length;
		}
	}

	return gI_CurrentCheckpoint[client];
}



public Action Cmd_ImportCP(int client, int args)
{
	if(client != 0)
	{
		if(!FileExists(pathFull))
			PrintToChat( client, "\x01You \x04don't have \x01a saved cp file on this map!");

		else
			LoadCps( client );
	}

	return Plugin_Handled;
}

public Action Cmd_ExportCP(int client, int args)
{
	if(client != 0)
	{
		if(FileExists(pathFull))
			OpenExportMenu( client );

		else
		{
			if(!DirExists(path))
				CreateDirectory(path, 511);

			SaveCPs( client );
		}
	}

	return Plugin_Handled;
}

void OpenExportMenu( int client )
{
	Menu menu = new Menu( OpenExportMenu_Handler );

	char buffer[356];
	int iTime, iYear, iMonth, iDay, iHour, iMinute, iSecond;
	iTime =  GetFileTime(pathFull, FileTime_LastChange);
	UnixToTime( iTime , iYear , iMonth , iDay , iHour , iMinute , iSecond );

	Format( buffer, sizeof(buffer), "You already have a saved cpfile\n( From:%02d/%02d/%d %02d:%02d:%02d )\nWill you overwrite it?\n \n" , iMonth , iDay , iYear , iHour , iMinute , iSecond );
	menu.SetTitle( buffer );

	menu.AddItem( "yes", "Yes" );

	menu.AddItem( "no", "No" );

	menu.Display( client, MENU_TIME_FOREVER );
}

public int OpenExportMenu_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		switch( param2 )
		{
			case 0:
			{
				char fileBuffer[215];
				DirectoryListing dL = OpenDirectory(path);
				while (dL.GetNext(fileBuffer, sizeof(fileBuffer))) 
				{
					if(strlen(fileBuffer)>3)
					{
						char TempBuffer[264];
						Format(TempBuffer, sizeof(TempBuffer), "%s/%s",path,fileBuffer);
						DeleteFile(TempBuffer);
					}
				} 
				delete dL;

				SaveCPs(param1);
			}
			case 1:
			{
				delete menu;
			}
		}
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

#define CELLS_PER_FRAME 8 
void SaveCPs( int client )
{ 
	int endindex = Shavit_GetTotalCheckpoints(client) - 1;
	Handle fileHandle = OpenFile(pathFull, "w");
	cp_cache_t cpcache;
	timer_snapshot_t snapshot;
	cpcache.aSnapshot = snapshot;
	for(int i = 0; i <= endindex; i++)
	{
		Shavit_GetCheckpoint(client, i, cpcache, sizeof(cpcache));
		int preframe = 0;
		int timerframe = 0;
		if(cpcache.bSegmented)
		{
			preframe = Shavit_GetPlayerPreFrame(client);
			timerframe = Shavit_GetPlayerTimerFrame(client);
			char filename[256];
			FormatEx(filename, sizeof(filename), "%s/s%d.frames", path, i);
			File fFile = OpenFile(filename, "wb");
			int iSize = cpcache.aFrames.Length;
			any aFrameData[CELLS_PER_FRAME];
			any aWriteData[CELLS_PER_FRAME * 100];
			int iFramesWritten = 0;
			fFile.WriteInt32( iSize );
			for(int z = 0; z < iSize; z++)
			{
				cpcache.aFrames.GetArray(z, aFrameData, CELLS_PER_FRAME);
				for(int j = 0; j < CELLS_PER_FRAME; j++)
				{
					aWriteData[(CELLS_PER_FRAME * iFramesWritten) + j] = aFrameData[j];
				}

				if(++iFramesWritten == 100 || z == iSize - 1)
				{
					fFile.Write(aWriteData, CELLS_PER_FRAME * iFramesWritten, 4);

					iFramesWritten = 0;
				}
			}
			delete fFile;
		}
		char sInfoString[512];
		Format(sInfoString, sizeof(sInfoString), "%d;;%f;;%f;;%f;;%f;;%f;;%f;;%f;;%f;;%f;;%d;;%d;;%d;;%d;;%d;;%d;;%d;;%f;;%d;;%d;;%d;;%d;;%f;;%f;;%f;;%f;;%f;;%f;;%d;;%d;;%f;;%d;;%d;;%d;;%d;;%i;;%d;;%d;;%s;;%s;;%d", 
			i, cpcache.fPosition[0],cpcache.fPosition[1],cpcache.fPosition[2],cpcache.fAngles[0],cpcache.fAngles[1],
			cpcache.fVelocity[0],cpcache.fVelocity[1],cpcache.fVelocity[2],cpcache.aSnapshot.fCurrentTime,
			cpcache.aSnapshot.bTimerEnabled,cpcache.aSnapshot.bClientPaused,
			cpcache.aSnapshot.iJumps,cpcache.aSnapshot.bsStyle,cpcache.aSnapshot.iStrafes,
			cpcache.aSnapshot.iTotalMeasures,cpcache.aSnapshot.iGoodGains,cpcache.aSnapshot.fServerTime,
			cpcache.aSnapshot.iSHSWCombination,cpcache.aSnapshot.iTimerTrack,cpcache.aSnapshot.iMeasuredJumps,cpcache.aSnapshot.iPerfectJumps,
			cpcache.fBaseVelocity[0],cpcache.fBaseVelocity[1],cpcache.fBaseVelocity[2],cpcache.fGravity,cpcache.fSpeed,cpcache.fStamina,
			cpcache.bDucked,cpcache.bDucking,cpcache.fDucktime,cpcache.iGroundEntity,cpcache.iMoveType,cpcache.curcmds,cpcache.bSegmented,preframe,timerframe,
			cpcache.bPractice,cpcache.sTargetname,cpcache.sClassname,cpcache.iFlags);
		WriteFileLine(fileHandle,sInfoString);

		if (gB_Eventqueuefix && cpcache.aEvents != null && cpcache.aOutputWaits != null)
		{
			char filenameNames[256];
			char sInfoString2[256];
			FormatEx(filenameNames, sizeof(filenameNames), "%s/eq%d.eq", path,i);
			File fFileNames = OpenFile(filenameNames, "wb");
			if(cpcache.aEvents.Length!=0)
			{
				for (int u = 0; u < cpcache.aEvents.Length; u++)
				{
					event_t e;
					cpcache.aEvents.GetArray(u, e);
					int HID = e.caller;
					if(IsValidEntity(HID))
						HID = Entity_GetHammerId(e.caller);


					if(cpcache.aOutputWaits.Length!=0)
						Format(sInfoString2, sizeof(sInfoString2),"%i;;%s;;%s;;%s;;%f;;%i;;%i;;%i",i, e.target, e.targetInput, e.variantValue, e.delay, e.activator, HID, e.outputID);

					else
						Format(sInfoString2, sizeof(sInfoString2),"%i;;%s;;%s;;%s;;%f;;%i;;%i;;%i;;0.0;;0",i, e.target, e.targetInput, e.variantValue, e.delay, e.activator, HID, e.outputID);

				}
			}
			if(cpcache.aOutputWaits.Length!=0)
			{
				for (int u = 0; u < cpcache.aOutputWaits.Length; u++)
				{
					entity_t t;
					cpcache.aOutputWaits.GetArray(u, t);
					Format(sInfoString2, sizeof(sInfoString2),"%s;;%f;;%i",sInfoString2, t.waitTime, t.caller);
				}
			}
			WriteFileLine(fFileNames,sInfoString2);
			delete fFileNames;
		}
	}
	CloseHandle(fileHandle);
	PrintToChat( client,"\x01Saved \x04%i\x01 CP-s.", endindex+1);
}

void LoadCps( int client )
{
	char sBuffer[512];
	int index = 0;
	Handle fileHandle = OpenFile(pathFull, "r");
	bool validfile = true;
	if (fileHandle == INVALID_HANDLE)
		validfile = false;

	if(validfile)
	{
		ResetCheckpoints(client);
		while(ReadFileLine(fileHandle, sBuffer, sizeof(sBuffer)))
		{
			cp_cache_t cpcache;
			timer_snapshot_t snapshot;
			cpcache.aSnapshot = snapshot;
			ReplaceString(sBuffer, sizeof(sBuffer), "\n", "", false);
			char bufs[41][64];
			ExplodeString( sBuffer, ";;", bufs, sizeof( bufs ), sizeof( bufs[] ) );
			index = StringToInt(bufs[0]);
			cpcache.fPosition[0] = StringToFloat(bufs[1]);
			cpcache.fPosition[1] = StringToFloat(bufs[2]);
			cpcache.fPosition[2] = StringToFloat(bufs[3]);
			cpcache.fAngles[0] = StringToFloat(bufs[4]);
			cpcache.fAngles[1] = StringToFloat(bufs[5]);
			cpcache.fVelocity[0] = StringToFloat(bufs[6]);
			cpcache.fVelocity[1] = StringToFloat(bufs[7]);
			cpcache.fVelocity[2] = StringToFloat(bufs[8]);
			cpcache.aSnapshot.fCurrentTime = StringToFloat(bufs[9]);
			cpcache.aSnapshot.bTimerEnabled = view_as<bool>(StringToInt(bufs[10]));
			cpcache.aSnapshot.bClientPaused = view_as<bool>(StringToInt(bufs[11]));
			cpcache.aSnapshot.iJumps = StringToInt(bufs[12]);
			cpcache.aSnapshot.bsStyle = StringToInt(bufs[13]);
			cpcache.aSnapshot.iStrafes = StringToInt(bufs[14]);
			cpcache.aSnapshot.iTotalMeasures = StringToInt(bufs[15]);
			cpcache.aSnapshot.iGoodGains = StringToInt(bufs[16]);
			cpcache.aSnapshot.fServerTime =StringToFloat(bufs[17]);
			cpcache.aSnapshot.iSHSWCombination = StringToInt(bufs[18]);
			cpcache.aSnapshot.iTimerTrack = StringToInt(bufs[19]);
			cpcache.aSnapshot.iMeasuredJumps = StringToInt(bufs[20]);
			cpcache.aSnapshot.iPerfectJumps = StringToInt(bufs[21]);
			cpcache.fBaseVelocity[0] = StringToFloat(bufs[22]);
			cpcache.fBaseVelocity[1] = StringToFloat(bufs[23]);
			cpcache.fBaseVelocity[2] = StringToFloat(bufs[24]);
			cpcache.fGravity = StringToFloat(bufs[25]);
			cpcache.fSpeed = StringToFloat(bufs[26]);
			cpcache.fStamina = StringToFloat(bufs[27]);
			cpcache.bDucked = view_as<bool>(StringToInt(bufs[28]));
			cpcache.bDucking = view_as<bool>(StringToInt(bufs[29]));
			cpcache.fDucktime = StringToFloat(bufs[30]);
			cpcache.iGroundEntity = StringToInt(bufs[31]);
			cpcache.iMoveType = view_as<MoveType>(StringToInt(bufs[32]));
			cpcache.curcmds = StringToInt(bufs[33]);
			cpcache.bSegmented = view_as<bool>(StringToInt(bufs[34]));
			cpcache.iPreFrames = StringToInt(bufs[35]);
			cpcache.iTimerPreFrames = StringToInt(bufs[36]);
			cpcache.bPractice = view_as<bool>(StringToInt(bufs[37]));
			strcopy(cpcache.sTargetname, 64, bufs[38]);
			strcopy(cpcache.sClassname, 64, bufs[39]);
			cpcache.iFlags = StringToInt(bufs[40]);
			char filename[256];
			FormatEx(filename, sizeof(filename), "%s/s%d.frames", path, index);
			if(FileExists(filename))
			{
				File fFile = OpenFile(filename, "rb");
				int iTemp = 0;
				fFile.ReadInt32(iTemp);
				int cells = CELLS_PER_FRAME;
				any[] aReplayData = new any[cells];
				if(cpcache.aFrames == null)
				{
					cpcache.aFrames = new ArrayList(CELLS_PER_FRAME);
				}

				cpcache.aFrames.Resize(iTemp);
				for(int i = 0; i < iTemp; i++)
				{
					if(fFile.Read(aReplayData, cells, 4) >= 0)
					{
						cpcache.aFrames.Set(i, view_as<float>(aReplayData[0]), 0);
						cpcache.aFrames.Set(i, view_as<float>(aReplayData[1]), 1);
						cpcache.aFrames.Set(i, view_as<float>(aReplayData[2]), 2);
						cpcache.aFrames.Set(i, view_as<float>(aReplayData[3]), 3);
						cpcache.aFrames.Set(i, view_as<float>(aReplayData[4]), 4);
						cpcache.aFrames.Set(i, view_as<int>(aReplayData[5]), 5);
						cpcache.aFrames.Set(i, view_as<int>(aReplayData[6]), 6);
						cpcache.aFrames.Set(i, view_as<int>(aReplayData[7]), 7);
					}
				}
				delete fFile;
				if (gB_Eventqueuefix)
				{
					char filenameNames[256];
					FormatEx(filenameNames, sizeof(filenameNames), "%s/eq%d.eq", path, index);
					File fileHandleEF = OpenFile(filenameNames, "r");
					int nE;
					while(ReadFileLine(fileHandleEF, sBuffer, sizeof(sBuffer)))
					{
						char bufz[10][64];
						ExplodeString( sBuffer, ";;", bufz, sizeof( bufz ), sizeof( bufz[] ) );
						nE = StringToInt(bufz[0]);
						if(index==nE)
						{
							event_t e;
							strcopy(e.target, 64, bufz[1]);
							strcopy(e.targetInput, 64, bufz[2]);
							strcopy(e.variantValue, 64, bufz[3]);
							e.delay = StringToFloat(bufz[4]);
							e.caller = Entity_FindByHammerId(StringToInt(bufz[5]));
							e.activator = StringToInt(bufz[6]);
							e.outputID = StringToInt(bufz[7]);
							float fidk = StringToFloat(bufz[8]);
							int idk = StringToInt(bufz[9]);
							if(cpcache.aOutputWaits == null)
							{
								cpcache.aOutputWaits = new ArrayList(sizeof(entity_t));
							}
							entity_t t;
							t.caller = idk;
							t.waitTime = fidk;
							if(idk>0 || fidk>0.0)
							{
								t.caller = idk;
								t.waitTime = fidk;
							}
							cpcache.aOutputWaits.PushArray(t);
							if(cpcache.aEvents == null)
							{
								cpcache.aEvents = new ArrayList(sizeof(event_t));
							}
							cpcache.aEvents.PushArray(e);
						}
					}
					delete fileHandleEF;
				}
			}
			gA_Checkpoints[client].Push(0);
			gA_Checkpoints[client].SetArray(index, cpcache);
		}
		gI_CurrentCheckpoint[client] = gA_Checkpoints[client].Length;
	}
	CloseHandle(fileHandle);
	/*
	if (gB_Eventqueuefix)
	{
		char filenameNames[256];
		FormatEx(filenameNames, sizeof(filenameNames), "%s/names.txt", path);
		Handle fileHandleEF = OpenFile(filenameNames, "r");
		cp_cache_t cpcache;
		int nE;
		while(ReadFileLine(fileHandleEF, sBuffer, sizeof(sBuffer)))
		{
			char bufz[9][64];
			ExplodeString( sBuffer, ";;", bufz, sizeof( bufz ), sizeof( bufz[] ) );
			nE = StringToInt(bufz[0]);
			event_t e;
			strcopy(e.target, 64, bufz[1]);
			strcopy(e.targetInput, 64, bufz[2]);
			strcopy(e.variantValue, 64, bufz[3]);
			e.delay = StringToFloat(bufz[4]);
			e.caller = StringToInt(bufz[5]);
			e.activator = client;
			e.outputID = StringToInt(bufz[6]);
			int idk = StringToInt(bufz[8]);
			if(idk>0)
			{
				entity_t t;
				t.caller = StringToInt(bufz[8]);
				t.waitTime = StringToFloat(bufz[7]);
				cpcache.aOutputWaits.SetArray(nE, t);
			}
			ArrayList g_aPlayerEvents;
			g_aPlayerEvents = new ArrayList(sizeof(event_t));
			//g_aPlayerEvents.PushArray(g_aPlayerEvents);
			cpcache.aEvents.SetArray(nE, e);
			delete g_aPlayerEvents;
			cpcache.aEvents = g_aPlayerEvents;
		}
		CloseHandle(fileHandleEF);
	}*/
	if(validfile && index > 0)
	{
		OpenCheckpointsMenu(client);
		PrintToChat( client,"\x01Loaded \x04%i\x01 CP-s.", index+1);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(IsValidClient(client, true))
	{
		if(Shavit_InsideZone(client, Zone_Start, -1) || Shavit_InsideZone(client, Zone_End, -1))
			return Plugin_Continue;
	
		if(GhostData2[client] == null)
			return Plugin_Continue;

		cmdpos++;
		if(ghost && GhostLength > 1)
		{
			if(cmdNum == 0)
				cmdNum = pretime;
			
			if(cmdNum > GhostData2[client].Length - 1)
			{
				if(c_restart)
					cmdNum = pretime;

				else
				{
					if(!c_finished)
					{
						c_finished = true;
						Shavit_PrintToChat(client, "%sGhost Replay %sFinished%s.", gS_ChatStrings.sText,gS_ChatStrings.sWarning,gS_ChatStrings.sText);
					}
				}
			}
				
			if(cmdNum > pretime && cmdNum < GhostLength)
			{
				float info[8];
				GhostData2[client].GetArray(cmdNum, info, sizeof(info));
				
				float pos[3];
				pos[0] = info[0];
				pos[1] = info[1];
				pos[2] = info[2];
				
				// Last Info
				float info2[8];
				GhostData2[client].GetArray(cmdNum - 1, info2, sizeof(info2));
				
				float last_pos[3];
				last_pos[0] = info2[0];
				last_pos[1] = info2[1];
				last_pos[2] = info2[2];
				
				// SET ORB TO LOCATION		
				BeamEffect(client, last_pos, pos, 0.7, 1.0, 1.0, beamColor, 0.0, 0);
				
				
				// If on ground draw square
				//if((info[6] & FL_ONGROUND) && !(info2[6] & FL_ONGROUND))
				if(info2[6]<info[6])
				{
					float square[4][3];
					
					square[0][0] = pos[0] + 14.0;
					square[0][1] = pos[1] + 14.0;
					square[0][2] = pos[2];
					
					square[1][0] = pos[0] + 14.0;
					square[1][1] = pos[1] - 14.0;
					square[1][2] = pos[2];
					
					square[2][0] = pos[0] - 14.0;
					square[2][1] = pos[1] - 14.0;
					square[2][2] = pos[2];
					
					square[3][0] = pos[0] - 14.0;
					square[3][1] = pos[1] + 14.0;
					square[3][2] = pos[2];
					
					BeamEffect(client, square[0], square[1], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
					BeamEffect(client, square[1], square[2], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
					BeamEffect(client, square[2], square[3], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
					BeamEffect(client, square[3], square[0], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
				}
			}
			
			cmdNum++;
		}
	}
	
	return Plugin_Continue;
}

public void BeamEffect(int client, float startvec[3], float endvec[3], float life, float width, float endwidth, const color[4], float amplitude, int speed)
{
	TE_SetupBeamPoints(startvec, endvec, g_BeamSprite, 0, 0, 66, life, width, endwidth, 0, amplitude, color, speed);
	TE_SendToClient(client);
}


public Action ghostToggle(int client, int args)
{
	Menu m = new Menu(ghostMenu);
	m.SetTitle("Ghost Menu");

	m.AddItem("Enable/Disable", (ghost) ? "On/Off ( On )":"On/Off ( Off )");
	m.AddItem("Beam Color", "Beam Color");
	m.AddItem("Restart", (c_restart) ? "Restart On Finish ( Yes )":"Restart On Finish ( No )");
	m.AddItem("c_stylr", "Select a style to compare with");

	m.ExitButton = true;
	m.Display(client, 0);
	
	return Plugin_Handled;
}

public int ghostMenu(Menu menu, MenuAction action, int client, int param2)
{
	switch (action)
	{		
		case MenuAction_Select:
		{
			char info[16];
			if(menu.GetItem(param2, info, sizeof(info)))
			{
				if(StrEqual(info, "Enable/Disable"))
				{
					ghost = !ghost;
					
					SetClientCookie(client, g_hGhostCookie, (ghost ? "1" : "0"));
					
					if(!ghost)
					{
						Shavit_PrintToChat(client, "%sGhost Replay: %sDisabled", gS_ChatStrings.sText,gS_ChatStrings.sWarning);
						cmdNum = 0;
					}
					else
					{
						if(ownstyle==255)
						{
							ArrayList ar = Shavit_GetReplayFrames(Shavit_GetBhopStyle(client), 0);
							c_finished = false;
							GhostData2[client] = ar.Clone();

							GhostLength = 0;

							if(GhostData2[client] != null)
								GhostLength = GhostData2[client].Length;

						}
						//cmdNum = 0;
						Shavit_PrintToChat(client, "%sGhost Replay: %sEnabled", gS_ChatStrings.sText,gS_ChatStrings.sVariable);
					}
				}
				else if(StrEqual(info, "Beam Color"))
				{
					BeamMenu(client, 0);
					return;
				}
				else if(StrEqual(info, "Restart"))
				{
					c_restart = !c_restart;
					
					SetClientCookie(client, h_hRestartCookie, (c_restart ? "1" : "0"));
					if(!c_restart)
					{
						Shavit_PrintToChat(client, "%sGhost Replay Restart On Finish: %sDisabled", gS_ChatStrings.sText,gS_ChatStrings.sWarning);
						cmdNum = 0;
					}
					else
					{
						Shavit_PrintToChat(client, "%sGhost Replay Restart On Finish: %sEnabled", gS_ChatStrings.sText,gS_ChatStrings.sVariable);
					}
				}
				else if(StrEqual(info, "c_stylr"))
				{
					StyleMenu(client, 0);
					return;
				}
				ghostToggle(client, 0);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
}
public Action StyleMenu(int client, int args)
{
	int stylez = Shavit_GetStyleCount();

	g_MainMenu = CreateMenu(StyleMenuHandler);
	SetMenuTitle(g_MainMenu, "Ghost Style");
	if(ownstyle==255)
		AddMenuItem(g_MainMenu, "255", "Own Style ( Selected )", ITEMDRAW_DISABLED);

	else
		AddMenuItem(g_MainMenu, "255", "Own Style", ITEMDRAW_DEFAULT);

	for(int i = 0; i < stylez; i++)
	{
		Shavit_GetStyleStrings(i, sStyleName, gS_StyleStrings[i].sStyleName, sizeof(stylestrings_t::sStyleName));
		char stl[3];
		Format(stl, sizeof(stl), "%i",i);
		if(Shavit_GetReplayFrameCount(i, 0) > 1)
		{
			if(ownstyle==i)
			{
				char stlname[52];
				Format(stlname, sizeof(stlname), "%s ( Selected )",gS_StyleStrings[i].sStyleName);
				AddMenuItem(g_MainMenu, stl, stlname, ITEMDRAW_DISABLED);
			}
			else
				AddMenuItem(g_MainMenu, stl, gS_StyleStrings[i].sStyleName, ITEMDRAW_DEFAULT);
		}

		else
			AddMenuItem(g_MainMenu, stl, gS_StyleStrings[i].sStyleName, ITEMDRAW_DISABLED);
	}

	SetMenuExitButton(g_MainMenu, true);
	DisplayMenu(g_MainMenu, client, 0);
	
	return Plugin_Handled;
}

public int StyleMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
	switch (action)
	{		
		case MenuAction_Select:
		{
			char info[16];
			if(menu.GetItem(param2, info, sizeof(info)))
			{
				if(StrEqual(info, "255"))
				{
					c_style = StringToInt(info);
					ownstyle = c_style;
					ArrayList ar = Shavit_GetReplayFrames(Shavit_GetBhopStyle(client), 0);
		
					GhostData2[client] = ar.Clone();

					cmdNum = 0;

					Shavit_PrintToChat(client, "%sGhost Replay Style: %sOwn", gS_ChatStrings.sText,gS_ChatStrings.sVariable);
					
					SetClientCookie(client, h_hStyleCookie, info);
					StyleMenu(client, 0);
				}
				else
				{
					c_style = StringToInt(info);
					ownstyle = c_style;
					ArrayList ar = Shavit_GetReplayFrames(c_style, 0);
		
					GhostData2[client] = ar.Clone();
					cmdNum = 0;
					Shavit_PrintToChat(client, "%sGhost Replay Style: %s%s", gS_ChatStrings.sText,gS_ChatStrings.sVariable,gS_StyleStrings[c_style].sStyleName);
					
					SetClientCookie(client, h_hStyleCookie, info);
					StyleMenu(client, 0);
				}
			}
		}
	}
}
public Action BeamMenu(int client, int args)
{
	Menu m = new Menu(beamColorMenu);
	m.SetTitle("Ghost Beam Color");
	m.AddItem("Red", "Red");
	m.AddItem("Green", "Green");
	m.AddItem("Blue", "Blue");
	m.AddItem("White", "White");
	m.ExitButton = true;
	m.Display(client, 0);
	
	return Plugin_Handled;
}

public int beamColorMenu(Menu menu, MenuAction action, int client, int param2)
{
	switch (action)
	{		
		case MenuAction_Select:
		{
			char info[16];
			if(menu.GetItem(param2, info, sizeof(info)))
			{
				char text[32];
				if(StrEqual(info, "Red"))
				{
					beamColor =  { 255, 0, 0, 255 };
					Format(text, sizeof(text), "\x02Red");
				}
				else if(StrEqual(info, "Green"))
				{
					beamColor =  { 0, 255, 0, 255 };
					Format(text, sizeof(text), "\x04Green");
				}
				else if(StrEqual(info, "Blue"))
				{
					beamColor =  { 0, 0, 255, 255 };
					Format(text, sizeof(text), "\x0CBlue");
				}
				else if(StrEqual(info, "White"))
				{
					beamColor =  { 255, 255, 255, 255 };
					Format(text, sizeof(text), "White");
				}
				
				Shavit_PrintToChat(client, "%sGhost Replay Trail Color: %s%s", gS_ChatStrings.sText,gS_ChatStrings.sVariable,text);
				
				SetClientCookie(client, g_hTrailCookie, info);
				ghostToggle(client, 0);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
}

//https://github.com/bcserv/smlib/blob/transitional_syntax/scripting/include/smlib/entities.inc
stock int Entity_GetHammerId(int entity)
{
	return GetEntProp(entity, Prop_Data, "m_iHammerID");
}
stock int Entity_FindByHammerId(int hammerId, const char[] className="")
{
	if (className[0] == '\0') {
		// Hack: Double the limit to gets none-networked entities too.
		int realMaxEntities = GetMaxEntities() * 2;
		for (int entity=0; entity < realMaxEntities; entity++) {

			if (!IsValidEntity(entity)) {
				continue;
			}

			if (Entity_GetHammerId(entity) == hammerId) {
				return entity;
			}
		}
	}
	else {
		int entity = INVALID_ENT_REFERENCE;
		while ((entity = FindEntityByClassname(entity, className)) != INVALID_ENT_REFERENCE) {

			if (Entity_GetHammerId(entity) == hammerId) {
				return entity;
			}
		}
	}

	return INVALID_ENT_REFERENCE;
}