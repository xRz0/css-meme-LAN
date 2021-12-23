/*
 * shavit's Timer - HUD
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
#include <clientprefs>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <convar_class>
#include <adt_trie> // StringMap

#undef REQUIRE_PLUGIN
#include <shavit>
#include <bhopstats>

#define USE_RIPEXT 0
#if USE_RIPEXT
#include <ripext> // https://github.com/ErikMinekus/sm-ripext
#else
#include <json> // https://github.com/clugg/sm-json
#include <SteamWorks> // HTTP stuff
#endif

#pragma newdecls required
#pragma semicolon 1

// HUD2 - these settings will *disable* elements for the main hud
#define HUD2_TIME				(1 << 0)
#define HUD2_SPEED				(1 << 1)
#define HUD2_JUMPS				(1 << 2)
#define HUD2_STRAFE				(1 << 3)
#define HUD2_SYNC				(1 << 4)
#define HUD2_STYLE				(1 << 5)
#define HUD2_RANK				(1 << 6)
#define HUD2_TRACK				(1 << 7)
#define HUD2_SPLITPB			(1 << 8)
#define HUD2_MAPTIER			(1 << 9)
#define HUD2_TIMEDIFFERENCE		(1 << 10)
#define HUD2_PERFS				(1 << 11)
#define HUD2_TOPLEFT_RANK		(1 << 12)

#define HUD_DEFAULT				(HUD_MASTER|HUD_CENTER|HUD_ZONEHUD|HUD_OBSERVE|HUD_TOPLEFT|HUD_SYNC|HUD_TIMELEFT|HUD_2DVEL|HUD_SPECTATORS)
#define HUD_DEFAULT2			(HUD2_PERFS)

#define MAX_HINT_SIZE 225

enum ZoneHUD
{
	ZoneHUD_None,
	ZoneHUD_Start,
	ZoneHUD_End
};

enum struct huddata_t
{
	int iTarget;
	float fTime;
	int iSpeed;
	int iStyle;
	int iTrack;
	int iJumps;
	int iStrafes;
	int iRank;
	float fSync;
	float fPB;
	float fWR;
	bool bReplay;
	bool bPractice;
	TimerStatus iTimerStatus;
	ZoneHUD iZoneHUD;
}

enum struct color_t
{
	int r;
	int g;
	int b;
}

// game type (CS:S/CS:GO/TF2)
EngineVersion gEV_Type = Engine_Unknown;

// forwards
//Handle gH_Forwards_OnTopLeftHUD = null;

// modules
bool gB_Replay = false;
bool gB_Zones = false;
bool gB_Sounds = false;
bool gB_Rankings = false;
bool gB_BhopStats = false;

// cache
int gI_Cycle = 0;
color_t gI_Gradient;
int gI_GradientDirection = -1;
int gI_Styles = 0;
char gS_Map[160];

Handle gH_HUDCookie = null;
Handle gH_HUDCookieMain = null;
int gI_HUDSettings[MAXPLAYERS+1];
int gI_HUD2Settings[MAXPLAYERS+1];
int gI_LastScrollCount[MAXPLAYERS+1];
int gI_ScrollCount[MAXPLAYERS+1];
int gI_Buttons[MAXPLAYERS+1];
float gF_ConnectTime[MAXPLAYERS+1];
bool gB_FirstPrint[MAXPLAYERS+1];
int gI_PreviousSpeed[MAXPLAYERS+1];
int gI_ZoneSpeedLimit[MAXPLAYERS+1];

bool gB_Late = false;

// hud handle
//Handle gH_HUD = null;

// plugin cvars
Convar gCV_GradientStepSize = null;
Convar gCV_TicksPerUpdate = null;
Convar gCV_UseHUDFix = null;
Convar gCV_DefaultHUD = null;
Convar gCV_DefaultHUD2 = null;
Convar gCV_EnableDynamicTimeDifference = null;

enum struct RecordInfo {
	int id;
	char name[MAX_NAME_LENGTH];
	//char country[];
	//char mapname[90]; // longest map name I've seen is bhop_pneumonoultramicroscopicsilicovolcanoconiosis_v3_001.bsp
	char hostname[111];
	char time[13];
	char wrDif[13];
	char steamid[20];
	int tier;
	char date[11]; // eventually increase?
	float sync;
	int strafes;
	int jumps;
}

Convar gCV_SourceJumpAPIKey;
char apikey[40];
char sjtext[80];

StringMap gS_Maps;
StringMap gS_MapsCachedTime;

int gI_CurrentPagePosition[MAXPLAYERS + 1];
char gS_ClientMap[MAXPLAYERS + 1][PLATFORM_MAX_PATH];
char gS_CurrentMap[PLATFORM_MAX_PATH];

//https://developer.valvesoftware.com/wiki/Game_text
#define MAX_CHANELS 6

Handle GameTextTimer[MAX_CHANELS] = INVALID_HANDLE;
Handle g_AcceptInput;

bool g_dHooks = false;
bool blockchanel[MAX_CHANELS];
bool allowblock;

float xcrd[MAX_CHANELS];
float ycrd[MAX_CHANELS];
char sMessage[256];
bool updatedjhud = false;
int showticks = 0;
int rgb[3];
char sTopLeft[256];
char sTopLeftOld[128];
float JhudPos;
int colour[8][3];
char constspeed[7];
char constspeed_gain[7];
char constspeed_loss[7];
char c60_gain[7];
char c70_gain[7];
char c80_gain[7];
char c90_gain[7];
char TopLeftHex[7];
char ColorSelection[9];
char ColorHex[9];
char sMessageS[256];
int drawcolor;
float speedpos;
int jhudfinish;

#define M_PI 3.14159265358979323846264338327950288
#define BHOP_TIME 10

Handle g_hCookieConstantSpeed;
Handle g_hCookieJHUD;
Handle g_hCookieJHUDPosition;
Handle g_hCookieSPEEDPosition;
Handle g_hCookieStrafeSpeed;
Handle g_hCookieExtraJumps;
Handle g_hCookieSpeedDisplay;
Handle g_hCookie60;
Handle g_hCookie6070;
Handle g_hCookie7080;
Handle g_hCookie80;
Handle g_hCookieDefaultsSet;
Handle g_hCookieHUDBlock;
Handle g_hCookieSpeedColor;
Handle g_hCookieSpeedColorGain;
Handle g_hCookieSpeedColorLoss;
Handle g_hCookieTopLeft;
Handle g_hCookieFinishInterval;

bool g_bConstSpeed[MAXPLAYERS + 1];
bool g_bJHUD[MAXPLAYERS + 1];
bool g_bStrafeSpeed[MAXPLAYERS + 1];
bool g_bExtraJumps[MAXPLAYERS + 1];
bool g_bSpeedDisplay[MAXPLAYERS + 1];
int g_iJHUDPosition[MAXPLAYERS + 1];
int g_iJSpeedPosition[MAXPLAYERS + 1];

char lastChoice[MAXPLAYERS + 1];

bool g_bSpeedDiff[MAXPLAYERS + 1];
bool g_bTouchesWall[MAXPLAYERS + 1];

int g_iPrevSpeed[MAXPLAYERS + 1];
int g_iTicksOnGround[MAXPLAYERS + 1];
int g_iTouchTicks[MAXPLAYERS + 1];
int g_strafeTick[MAXPLAYERS + 1];
int g_iJump[MAXPLAYERS + 1];

float g_flRawGain[MAXPLAYERS + 1];

float g_vecLastAngle[MAXPLAYERS + 1][3];
float g_fTotalNormalDelta[MAXPLAYERS + 1];
float g_fTotalPerfectDelta[MAXPLAYERS + 1];

#define TRAINER_TICK_INTERVAL 10


float gF_LastAngle[MAXPLAYERS + 1][3];
int gI_ClientTickCount[MAXPLAYERS + 1];
float gF_ClientPercentages[MAXPLAYERS + 1][TRAINER_TICK_INTERVAL];

Handle gH_StrafeTrainerCookie;
bool gB_StrafeTrainer[MAXPLAYERS + 1] = {false, ...};

int values[][3] = {
	{},  				// null
	{280, 282, 287},  	// 1
	{366, 370, 375},  	// 2
	{438, 442, 450},  	// 3
	{500, 505, 515},  	// 4
	{555, 560, 570},  	// 5
	{605, 610, 620},  	// 6
	{655, 665, 675},  	// 7
	{700, 710, 725}, 	// 8
	{740, 750, 765},  	// 9
	{780, 790, 805},  	// 10
	{810, 820, 840},  	// 11
	{850, 860, 875},  	// 12
	{880, 900, 900},  	// 13
	{910, 920, 935},  	// 14
	{945, 955, 965},  	// 15
	{970, 980, 1000} 	// 16
};
// timer settings
stylestrings_t gS_StyleStrings[STYLE_LIMIT];
stylesettings_t gA_StyleSettings[STYLE_LIMIT];
chatstrings_t gS_ChatStrings;

public Plugin myinfo =
{
	name = "[shavit] HUD",
	author = "shavit, Blank, rtldg, PaxPlay, Vauff",
	description = "HUD for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// forwards
	//gH_Forwards_OnTopLeftHUD = CreateGlobalForward("Shavit_OnTopLeftHUD", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell);

	// natives
	CreateNative("Shavit_ForceHUDUpdate", Native_ForceHUDUpdate);
	CreateNative("Shavit_GetHUDSettings", Native_GetHUDSettings);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-hud");

	gB_Late = late;

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	HookEvent("player_jump", OnPlayerJump);
	if (LibraryExists("dhooks"))
	{
		g_dHooks = true;

		g_AcceptInput = DHookCreate(36, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity, AcceptInput);
		DHookAddParam(g_AcceptInput, HookParamType_CharPtr);
		DHookAddParam(g_AcceptInput, HookParamType_CBaseEntity);
		DHookAddParam(g_AcceptInput, HookParamType_CBaseEntity);
		DHookAddParam(g_AcceptInput, HookParamType_Object, 20, DHookPass_ByVal|DHookPass_ODTOR|DHookPass_OCTOR|DHookPass_OASSIGNOP); //varaint_t is a union of 12 (float[3]) plus two int type params 12 + 8 = 20
		DHookAddParam(g_AcceptInput, HookParamType_Int);
	
		DHookAddEntityListener(ListenType_Created, OnEntityCreated);
	}
}

public void OnPluginStart()
{
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-hud.phrases");

	// game-specific
	gEV_Type = GetEngineVersion();

	if(gEV_Type == Engine_TF2)
	{
		HookEvent("player_changeclass", Player_ChangeClass);
		HookEvent("player_team", Player_ChangeClass);
		HookEvent("teamplay_round_start", Teamplay_Round_Start);
	}

	// prevent errors in case the replay bot isn't loaded
	gB_Replay = LibraryExists("shavit-replay");
	gB_Zones = LibraryExists("shavit-zones");
	gB_Sounds = LibraryExists("shavit-sounds");
	gB_Rankings = LibraryExists("shavit-rankings");
	gB_BhopStats = LibraryExists("bhopstats");

	// HUD handle
	//gH_HUD = CreateHudSynchronizer();

	// plugin convars
	gCV_GradientStepSize = new Convar("shavit_hud_gradientstepsize", "15", "How fast should the start/end HUD gradient be?\nThe number is the amount of color change per 0.1 seconds.\nThe higher the number the faster the gradient.", 0, true, 1.0, true, 255.0);
	gCV_TicksPerUpdate = new Convar("shavit_hud_ticksperupdate", "5", "How often (in ticks) should the HUD update?\nPlay around with this value until you find the best for your server.\nThe maximum value is your tickrate.", 0, true, 1.0, true, (1.0 / GetTickInterval()));
	gCV_UseHUDFix = new Convar("shavit_hud_csgofix", "1", "Apply the csgo color fix to the center hud?\nThis will add a dollar sign and block sourcemod hooks to hint message", 0, true, 0.0, true, 1.0);
	gCV_EnableDynamicTimeDifference = new Convar("shavit_hud_timedifference", "0", "Enabled dynamic time differences in the hud", 0, true, 0.0, true, 1.0);
	
	char defaultHUD[8];
	IntToString(HUD_DEFAULT, defaultHUD, 8);
	gCV_DefaultHUD = new Convar("shavit_hud_default", defaultHUD, "Default HUD settings as a bitflag\n"
		..."HUD_MASTER				1\n"
		..."HUD_CENTER				2\n"
		..."HUD_ZONEHUD				4\n"
		..."HUD_OBSERVE				8\n"
		..."HUD_SPECTATORS			16\n"
		..."HUD_KEYOVERLAY			32\n"
		..."HUD_HIDEWEAPON			64\n"
		..."HUD_TOPLEFT				128\n"
		..."HUD_SYNC					256\n"
		..."HUD_TIMELEFT				512\n"
		..."HUD_2DVEL				1024\n"
		..."HUD_NOSOUNDS				2048\n"
		..."HUD_NOPRACALERT			4096\n");
		
	IntToString(HUD_DEFAULT2, defaultHUD, 8);
	gCV_DefaultHUD2 = new Convar("shavit_hud2_default", defaultHUD, "Default HUD2 settings as a bitflag\n"
		..."HUD2_TIME				1\n"
		..."HUD2_SPEED				2\n"
		..."HUD2_JUMPS				4\n"
		..."HUD2_STRAFE				8\n"
		..."HUD2_SYNC				16\n"
		..."HUD2_STYLE				32\n"
		..."HUD2_RANK				64\n"
		..."HUD2_TRACK				128\n"
		..."HUD2_SPLITPB				256\n"
		..."HUD2_MAPTIER				512\n"
		..."HUD2_TIMEDIFFERENCE		1024\n"
		..."HUD2_PERFS				2048\n"
		..."HUD2_TOPLEFT_RANK				4096");

	Convar.AutoExecConfig();

	// commands
	RegConsoleCmd("sm_hud", Command_HUD, "Opens the HUD settings menu.");
	RegConsoleCmd("sm_options", Command_HUD, "Opens the HUD settings menu. (alias for sm_hud)");

	// hud togglers
	RegConsoleCmd("sm_keys", Command_Keys, "Toggles key display.");
	RegConsoleCmd("sm_showkeys", Command_Keys, "Toggles key display. (alias for sm_keys)");
	RegConsoleCmd("sm_showmykeys", Command_Keys, "Toggles key display. (alias for sm_keys)");

	RegConsoleCmd("sm_master", Command_Master, "Toggles HUD.");
	RegConsoleCmd("sm_masterhud", Command_Master, "Toggles HUD. (alias for sm_master)");

	RegConsoleCmd("sm_center", Command_Center, "Toggles center text HUD.");
	RegConsoleCmd("sm_centerhud", Command_Center, "Toggles center text HUD. (alias for sm_center)");

	RegConsoleCmd("sm_zonehud", Command_ZoneHUD, "Toggles zone HUD.");

	RegConsoleCmd("sm_hideweapon", Command_HideWeapon, "Toggles weapon hiding.");
	RegConsoleCmd("sm_hideweap", Command_HideWeapon, "Toggles weapon hiding. (alias for sm_hideweapon)");
	RegConsoleCmd("sm_hidewep", Command_HideWeapon, "Toggles weapon hiding. (alias for sm_hideweapon)");

	RegConsoleCmd("sm_truevel", Command_TrueVel, "Toggles 2D ('true') velocity.");
	RegConsoleCmd("sm_truvel", Command_TrueVel, "Toggles 2D ('true') velocity. (alias for sm_truevel)");
	RegConsoleCmd("sm_2dvel", Command_TrueVel, "Toggles 2D ('true') velocity. (alias for sm_truevel)");
	RegConsoleCmd("sm_jhud", Command_JHUD, "Opens the JHUD main menu");
	RegConsoleCmd("sm_speedcolor", Command_JHUDColor, "Set your own color!");
	RegConsoleCmd("sm_speedgain", Command_JHUDColor, "Set your own color!");
	RegConsoleCmd("sm_speedloss", Command_JHUDColor, "Set your own color!");
	RegConsoleCmd("sm_under60", Command_JHUDColor, "Set your own color!");
	RegConsoleCmd("sm_under70", Command_JHUDColor, "Set your own color!");
	RegConsoleCmd("sm_under80", Command_JHUDColor, "Set your own color!");
	RegConsoleCmd("sm_over80", Command_JHUDColor, "Set your own color!");
	RegConsoleCmd("sm_topleft", Command_JHUDColor, "Set your own color!");

	g_hCookieConstantSpeed = 	RegClientCookie("jhud_constspeed", "jhud_constspeed", CookieAccess_Protected);
	g_hCookieJHUD = 			RegClientCookie("jhud_enabled", "jhud_enabled", CookieAccess_Protected);
	g_hCookieJHUDPosition = 	RegClientCookie("jhud_position", "jhud_position", CookieAccess_Protected);
	g_hCookieSPEEDPosition = 	RegClientCookie("jhud_speedpos", "jhud_speedpos", CookieAccess_Protected);
	g_hCookieStrafeSpeed = 		RegClientCookie("jhud_strafespeed", "jhud_strafespeed", CookieAccess_Protected);
	g_hCookieExtraJumps = 		RegClientCookie("jhud_extrajumps", "jhud_extrajumps", CookieAccess_Protected);
	g_hCookieSpeedDisplay = 	RegClientCookie("jhud_speeddisp", "jhud_speeddisp", CookieAccess_Protected);
	g_hCookie60 = 				RegClientCookie("jhud_60", "jhud_60", CookieAccess_Protected);
	g_hCookie6070 = 			RegClientCookie("jhud_6070", "jhud_6070", CookieAccess_Protected);
	g_hCookie7080 = 			RegClientCookie("jhud_7080", "jhud_7080", CookieAccess_Protected);
	g_hCookie80 = 				RegClientCookie("jhud_80", "jhud_80", CookieAccess_Protected);
	g_hCookieDefaultsSet = 		RegClientCookie("jhud_defaultz", "jhud_defaultz", CookieAccess_Protected);
	g_hCookieHUDBlock = 		RegClientCookie("jhud_block", "jhud_block", CookieAccess_Protected);
	g_hCookieSpeedColor = 		RegClientCookie("jhud_speed", "jhud_speed", CookieAccess_Protected);
	g_hCookieSpeedColorGain = 	RegClientCookie("jhud_speedgain", "jhud_speedgain", CookieAccess_Protected);
	g_hCookieSpeedColorLoss = 	RegClientCookie("jhud_speedloss", "jhud_speedloss", CookieAccess_Protected);
	g_hCookieTopLeft = 			RegClientCookie("jhud_topleft", "jhud_topleft", CookieAccess_Protected);
	g_hCookieFinishInterval = 	RegClientCookie("jhud_finish", "jhud_finish", CookieAccess_Protected);

	RegConsoleCmd("sm_strafetrainer", Command_StrafeTrainer, "Toggles the Strafe trainer.");
	
	gH_StrafeTrainerCookie = RegClientCookie("strafetrainer_enabled", "strafetrainer_enabled", CookieAccess_Protected);

	gCV_SourceJumpAPIKey = new Convar("sj_api_key", "", "Replace with your unique api key.", FCVAR_PROTECTED);
	gCV_SourceJumpAPIKey.AddChangeHook(OnCvarChange);

	RegConsoleCmd("sm_wrsj", Command_WRSJ, "View global world records from Sourcejump's API.");
	RegConsoleCmd("sm_sjwr", Command_WRSJ, "View global world records from Sourcejump's API.");

	gS_Maps = new StringMap();
	gS_MapsCachedTime = new StringMap();

	// cookies
	gH_HUDCookie = RegClientCookie("shavit_hud_setting", "HUD settings", CookieAccess_Protected);
	gH_HUDCookieMain = RegClientCookie("shavit_hud_settingmain", "HUD settings for hint text.", CookieAccess_Protected);
	HookEvent("player_spawn", Player_Spawn);
	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);
				OnClientPostAdminCheck(i);
				if(AreClientCookiesCached(i) && !IsFakeClient(i))
				{
					OnClientCookiesCached(i);
				}
			}
		}
	}
}

public void OnMapStart()
{
	ServerCommand("exec sourcemod/sjapi.cfg");
	GetCurrentMap(gS_CurrentMap, sizeof(gS_CurrentMap));
	GetMapDisplayName(gS_CurrentMap, gS_CurrentMap, sizeof(gS_CurrentMap));

	GetCurrentMap(gS_Map, 160);
	GetMapDisplayName(gS_Map, gS_Map, 160);
	strcopy(sjtext,sizeof(sjtext),"");

	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(-1);
		Shavit_OnChatConfigLoaded();
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-replay"))
	{
		gB_Replay = true;
	}

	else if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = true;
	}

	else if(StrEqual(name, "shavit-sounds"))
	{
		gB_Sounds = true;
	}

	else if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = true;
	}

	else if(StrEqual(name, "bhopstats"))
	{
		gB_BhopStats = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-replay"))
	{
		gB_Replay = false;
	}

	else if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = false;
	}

	else if(StrEqual(name, "shavit-sounds"))
	{
		gB_Sounds = false;
	}

	else if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = false;
	}

	else if(StrEqual(name, "bhopstats"))
	{
		gB_BhopStats = false;
	}
}

public void OnConfigsExecuted()
{
	ConVar sv_hudhint_sound = FindConVar("sv_hudhint_sound");

	if(sv_hudhint_sound != null)
	{
		sv_hudhint_sound.SetBool(false);
	}
}

public void OnCvarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	if(!StrEqual(newValue, "SECRET"))
	{
		char pathcvar[PLATFORM_MAX_PATH];
		FormatEx(pathcvar, sizeof(pathcvar), "cfg/sourcemod/sjapi.cfg");
		File fileHandle = OpenFile(pathcvar, "w");
		gCV_SourceJumpAPIKey.GetString(apikey, sizeof(apikey));
		WriteFileLine(fileHandle,"sj_api_key  \"%s\" // Your SJ API key\"",apikey);
		CloseHandle(fileHandle);
		if(strlen(apikey)>1)
			RetrieveWRSJ(0, gS_CurrentMap);
	}
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	if(styles == -1)
	{
		styles = Shavit_GetStyleCount();
	}

	gI_Styles = styles;

	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleSettings(i, gA_StyleSettings[i]);
		Shavit_GetStyleStrings(i, sStyleName, gS_StyleStrings[i].sStyleName, sizeof(stylestrings_t::sStyleName));
		Shavit_GetStyleStrings(i, sHTMLColor, gS_StyleStrings[i].sHTMLColor, sizeof(stylestrings_t::sHTMLColor));
	}
}

public Action Shavit_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int style, stylesettings_t stylsettings)
{
	gI_Buttons[client] = buttons;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(i == client || (IsValidClient(i) && GetHUDTarget(i) == client))
		{
			TriggerHUDUpdate(i, true);
		}
	}

	return Plugin_Continue;
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

public void OnClientPutInServer(int client)
{
	gI_LastScrollCount[client] = 0;
	gI_ScrollCount[client] = 0;
	gB_FirstPrint[client] = false;
	if(IsFakeClient(client))
	{
		SDKHook(client, SDKHook_PostThinkPost, PostThinkPost);
	}
}

public void PostThinkPost(int client)
{
	int buttons = GetClientButtons(client);

	if(gI_Buttons[client] != buttons)
	{
		gI_Buttons[client] = buttons;

		for(int i = 1; i <= MaxClients; i++)
		{
			if(i != client && (IsValidClient(i) && GetHUDTarget(i) == client))
			{
				TriggerHUDUpdate(i, true);
			}
		}
	}
}

public void OnClientCookiesCached(int client)
{
	char sHUDSettings[8];
	GetClientCookie(client, gH_HUDCookie, sHUDSettings, 8);

	if(strlen(sHUDSettings) == 0)
	{
		gCV_DefaultHUD.GetString(sHUDSettings, 8);

		SetClientCookie(client, gH_HUDCookie, sHUDSettings);
		gI_HUDSettings[client] = gCV_DefaultHUD.IntValue;
	}

	else
	{
		gI_HUDSettings[client] = StringToInt(sHUDSettings);
	}

	GetClientCookie(client, gH_HUDCookieMain, sHUDSettings, 8);

	if(strlen(sHUDSettings) == 0)
	{
		gCV_DefaultHUD2.GetString(sHUDSettings, 8);

		SetClientCookie(client, gH_HUDCookieMain, sHUDSettings);
		gI_HUD2Settings[client] = gCV_DefaultHUD2.IntValue;
	}

	else
	{
		gI_HUD2Settings[client] = StringToInt(sHUDSettings);
	}

	char strCookie[8];
	
	GetClientCookie(client, g_hCookieDefaultsSet, strCookie, sizeof(strCookie));
	if(StringToInt(strCookie) == 0)
	{
		SetCookie(client, g_hCookieConstantSpeed, true);
		SetCookie(client, g_hCookieJHUD, false);
		SetCookie(client, g_hCookieStrafeSpeed, false);
		SetCookie(client, g_hCookieExtraJumps, false);
		SetCookie(client, g_hCookieSpeedDisplay, false);
		SetCookie(client, g_hCookieJHUDPosition, 1);
		SetCookie(client, g_hCookieSPEEDPosition, 2);
		SetClientCookie(client, g_hCookie60, "ff0000");
		SetClientCookie(client, g_hCookie6070, "ffa024");
		SetClientCookie(client, g_hCookie7080, "00ff00");
		SetClientCookie(client, g_hCookie80, "00ffff");
		SetCookie(client, g_hCookieHUDBlock, true);
		SetClientCookie(client, g_hCookieSpeedColor, "ffffff");
		SetClientCookie(client, g_hCookieSpeedColorGain, "00ffff");
		SetClientCookie(client, g_hCookieSpeedColorLoss, "ffa024");
		SetClientCookie(client, g_hCookieTopLeft, "ffffff");
		SetCookie(client, g_hCookieDefaultsSet, true);
		SetCookie(client, g_hCookieFinishInterval, 16);
	}
	GetClientCookie(client, g_hCookie60, strCookie, sizeof(strCookie));
	//if(strlen(strCookie)<4)
		//JHUD_ResetValues(client,false);

	strcopy(c60_gain, sizeof(c60_gain), strCookie);
	HexStringToRGB(c60_gain, _, colour[3][0], colour[3][1], colour[3][2]);

	GetClientCookie(client, g_hCookieConstantSpeed, strCookie, sizeof(strCookie));
	g_bConstSpeed[client] = view_as<bool>(StringToInt(strCookie));

	GetClientCookie(client, g_hCookieJHUD, strCookie, sizeof(strCookie));
	g_bJHUD[client] = view_as<bool>(StringToInt(strCookie));

	GetClientCookie(client, g_hCookieStrafeSpeed, strCookie, sizeof(strCookie));
	g_bStrafeSpeed[client] = view_as<bool>(StringToInt(strCookie));
	
	GetClientCookie(client, g_hCookieExtraJumps, strCookie, sizeof(strCookie));
	g_bExtraJumps[client] = view_as<bool>(StringToInt(strCookie));
	
	GetClientCookie(client, g_hCookieSpeedDisplay, strCookie, sizeof(strCookie));
	g_bSpeedDisplay[client] = view_as<bool>(StringToInt(strCookie));
	
	GetClientCookie(client, g_hCookieJHUDPosition, strCookie, sizeof(strCookie));
	g_iJHUDPosition[client] = StringToInt(strCookie);
	
	GetClientCookie(client, g_hCookieSPEEDPosition, strCookie, sizeof(strCookie));
	g_iJSpeedPosition[client] = StringToInt(strCookie);
	GetSpeedPos(client);

	GetClientCookie(client, g_hCookie6070, strCookie, sizeof(strCookie));
	strcopy(c70_gain, sizeof(c70_gain), strCookie);
	HexStringToRGB(c70_gain, _, colour[4][0], colour[4][1], colour[4][2]);

	GetClientCookie(client, g_hCookie7080, strCookie, sizeof(strCookie));
	strcopy(c80_gain, sizeof(c80_gain), strCookie);
	HexStringToRGB(c80_gain, _, colour[5][0], colour[5][1], colour[5][2]);

	GetClientCookie(client, g_hCookie80, strCookie, sizeof(strCookie));
	strcopy(c90_gain, sizeof(c90_gain), strCookie);
	HexStringToRGB(c90_gain, _, colour[6][0], colour[6][1], colour[6][2]);

	GetClientCookie(client, g_hCookieHUDBlock, strCookie, sizeof(strCookie));
	allowblock = view_as<bool>(StringToInt(strCookie));
	
	GetClientCookie(client, g_hCookieSpeedColor, strCookie, sizeof(strCookie));
	strcopy(constspeed, sizeof(constspeed), strCookie);
	HexStringToRGB(constspeed, _, colour[0][0], colour[0][1], colour[0][2]);

	GetClientCookie(client, g_hCookieSpeedColorGain, strCookie, sizeof(strCookie));
	strcopy(constspeed_gain, sizeof(constspeed_gain), strCookie);
	HexStringToRGB(constspeed_gain, _, colour[1][0], colour[1][1], colour[1][2]);

	GetClientCookie(client, g_hCookieSpeedColorLoss, strCookie, sizeof(strCookie));
	strcopy(constspeed_loss, sizeof(constspeed_loss), strCookie);
	HexStringToRGB(constspeed_loss, _, colour[2][0], colour[2][1], colour[2][2]);

	GetClientCookie(client, g_hCookieTopLeft, strCookie, sizeof(strCookie));
	strcopy(TopLeftHex, sizeof(TopLeftHex), strCookie);
	HexStringToRGB(TopLeftHex, _, colour[7][0], colour[7][1], colour[7][2]);

	GetClientCookie(client, g_hCookieFinishInterval, strCookie, sizeof(strCookie));
	jhudfinish = StringToInt(strCookie);

	gB_StrafeTrainer[client] = GetClientCookieBool(client, gH_StrafeTrainerCookie);
	FormatEx(sTopLeftOld, 128, "");
	GetTimerClr(client);
}

public void Player_ChangeClass(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if((gI_HUDSettings[client] & HUD_MASTER) > 0 && (gI_HUDSettings[client] & HUD_CENTER) > 0)
	{
		CreateTimer(0.5, Timer_FillerHintText, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void Teamplay_Round_Start(Event event, const char[] name, bool dontBroadcast)
{
	CreateTimer(0.5, Timer_FillerHintTextAll, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_FillerHintTextAll(Handle timer, any data)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientConnected(i) && IsClientInGame(i))
		{
			FillerHintText(i);
		}
	}

	return Plugin_Stop;
}

public Action Timer_FillerHintText(Handle timer, any data)
{
	int client = GetClientFromSerial(data);

	if(client != 0)
	{
		FillerHintText(client);
	}

	return Plugin_Stop;
}

void FillerHintText(int client)
{
	PrintHintText(client, "...");
	gF_ConnectTime[client] = GetEngineTime();
	gB_FirstPrint[client] = true;
}

void ToggleHUD(int client, int hud, bool chat)
{
	if(!(1 <= client <= MaxClients))
	{
		return;
	}

	char sCookie[16];
	gI_HUDSettings[client] ^= hud;
	IntToString(gI_HUDSettings[client], sCookie, 16);
	SetClientCookie(client, gH_HUDCookie, sCookie);

	if(chat)
	{
		char sHUDSetting[64];

		switch(hud)
		{
			case HUD_MASTER: FormatEx(sHUDSetting, 64, "%T", "HudMaster", client);
			case HUD_CENTER: FormatEx(sHUDSetting, 64, "%T", "HudCenter", client);
			case HUD_ZONEHUD: FormatEx(sHUDSetting, 64, "%T", "HudZoneHud", client);
			case HUD_OBSERVE: FormatEx(sHUDSetting, 64, "%T", "HudObserve", client);
			//case HUD_SPECTATORS: FormatEx(sHUDSetting, 64, "%T", "HudSpectators", client);
			case HUD_KEYOVERLAY: FormatEx(sHUDSetting, 64, "%T", "HudKeyOverlay", client);
			case HUD_HIDEWEAPON: FormatEx(sHUDSetting, 64, "%T", "HudHideWeapon", client);
			case HUD_TOPLEFT: FormatEx(sHUDSetting, 64, "%T", "HudTopLeft", client);
			case HUD_SYNC: FormatEx(sHUDSetting, 64, "%T", "HudSync", client);
			case HUD_TIMELEFT: FormatEx(sHUDSetting, 64, "%T", "HudTimeLeft", client);
			case HUD_2DVEL: FormatEx(sHUDSetting, 64, "%T", "Hud2dVel", client);
			case HUD_NOSOUNDS: FormatEx(sHUDSetting, 64, "%T", "HudNoRecordSounds", client);
			case HUD_NOPRACALERT: FormatEx(sHUDSetting, 64, "%T", "HudPracticeModeAlert", client);
		}

		if((gI_HUDSettings[client] & hud) > 0)
		{
			Shavit_PrintToChat(client, "%T", "HudEnabledComponent", client,
				gS_ChatStrings.sVariable, sHUDSetting, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, gS_ChatStrings.sText);
		}

		else
		{
			Shavit_PrintToChat(client, "%T", "HudDisabledComponent", client,
				gS_ChatStrings.sVariable, sHUDSetting, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		}
	}
}

public Action Command_Master(int client, int args)
{
	ToggleHUD(client, HUD_MASTER, true);

	return Plugin_Handled;
}

public Action Command_Center(int client, int args)
{
	ToggleHUD(client, HUD_CENTER, true);

	return Plugin_Handled;
}

public Action Command_ZoneHUD(int client, int args)
{
	ToggleHUD(client, HUD_ZONEHUD, true);

	return Plugin_Handled;
}

public Action Command_HideWeapon(int client, int args)
{
	ToggleHUD(client, HUD_HIDEWEAPON, true);

	return Plugin_Handled;
}

public Action Command_TrueVel(int client, int args)
{
	ToggleHUD(client, HUD_2DVEL, true);

	return Plugin_Handled;
}

public Action Command_Keys(int client, int args)
{
	ToggleHUD(client, HUD_KEYOVERLAY, true);

	return Plugin_Handled;
}

public Action Command_HUD(int client, int args)
{
	return ShowHUDMenu(client, 0);
}

Action ShowHUDMenu(int client, int item)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(MenuHandler_HUD, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);
	menu.SetTitle("%T", "HUDMenuTitle", client);

	menu.AddItem("Jhud", "Jhud");
	char sInfo[16];
	char sHudItem[64];
	FormatEx(sInfo, 16, "!%d", HUD_MASTER);
	FormatEx(sHudItem, 64, "%T", "HudMaster", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_CENTER);
	FormatEx(sHudItem, 64, "%T", "HudCenter", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_ZONEHUD);
	FormatEx(sHudItem, 64, "%T", "HudZoneHud", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_OBSERVE);
	FormatEx(sHudItem, 64, "%T", "HudObserve", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_KEYOVERLAY);
	FormatEx(sHudItem, 64, "%T", "HudKeyOverlay", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_HIDEWEAPON);
	FormatEx(sHudItem, 64, "%T", "HudHideWeapon", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_TOPLEFT);
	FormatEx(sHudItem, 64, "%T", "HudTopLeft", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_SPECTATORS);
	menu.AddItem(sInfo, "Top Left SJ WR", strlen(apikey)<1 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

	menu.AddItem("TCol", "Top Left Hud Color");

	if(IsSource2013(gEV_Type))
	{
		FormatEx(sInfo, 16, "!%d", HUD_SYNC);
		FormatEx(sHudItem, 64, "%T", "HudSync", client);
		menu.AddItem(sInfo, sHudItem);

		FormatEx(sInfo, 16, "!%d", HUD_TIMELEFT);
		FormatEx(sHudItem, 64, "%T", "HudTimeLeft", client);
		menu.AddItem(sInfo, sHudItem);
	}

	FormatEx(sInfo, 16, "!%d", HUD_2DVEL);
	FormatEx(sHudItem, 64, "%T", "Hud2dVel", client);
	menu.AddItem(sInfo, sHudItem);

	if(gB_Sounds)
	{
		FormatEx(sInfo, 16, "!%d", HUD_NOSOUNDS);
		FormatEx(sHudItem, 64, "%T", "HudNoRecordSounds", client);
		menu.AddItem(sInfo, sHudItem);
	}

	FormatEx(sInfo, 16, "!%d", HUD_NOPRACALERT);
	FormatEx(sHudItem, 64, "%T", "HudPracticeModeAlert", client);
	menu.AddItem(sInfo, sHudItem);

	// HUD2 - disables selected elements
	FormatEx(sInfo, 16, "@%d", HUD2_TIME);
	FormatEx(sHudItem, 64, "%T", "HudTimeText", client);
	menu.AddItem(sInfo, sHudItem);

	if(gB_Replay)
	{
		FormatEx(sInfo, 16, "@%d", HUD2_TIMEDIFFERENCE);
		FormatEx(sHudItem, 64, "%T", "HudTimeDifference", client);
		menu.AddItem(sInfo, sHudItem);
	}

	FormatEx(sInfo, 16, "@%d", HUD2_SPEED);
	FormatEx(sHudItem, 64, "%T", "HudSpeedText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_JUMPS);
	FormatEx(sHudItem, 64, "%T", "HudJumpsText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_STRAFE);
	FormatEx(sHudItem, 64, "%T", "HudStrafeText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_SYNC);
	FormatEx(sHudItem, 64, "%T", "HudSync", client);
	menu.AddItem(sInfo, sHudItem);
	
	FormatEx(sInfo, 16, "@%d", HUD2_PERFS);
	FormatEx(sHudItem, 64, "%T", "HudPerfs", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_STYLE);
	FormatEx(sHudItem, 64, "%T", "HudStyleText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_RANK);
	FormatEx(sHudItem, 64, "%T", "HudRankText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_TRACK);
	FormatEx(sHudItem, 64, "%T", "HudTrackText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_SPLITPB);
	FormatEx(sHudItem, 64, "%T", "HudSplitPbText", client);
	menu.AddItem(sInfo, sHudItem);

	//FormatEx(sInfo, 16, "@%d", HUD2_TOPLEFT_RANK);
	//FormatEx(sHudItem, 64, "%T", "HudTopLeftRankText", client);
	//menu.AddItem(sInfo, sHudItem);

	if(gB_Rankings)
	{
		FormatEx(sInfo, 16, "@%d", HUD2_MAPTIER);
		FormatEx(sHudItem, 64, "%T", "HudMapTierText", client);
		menu.AddItem(sInfo, sHudItem);
	}

	menu.ExitButton = true;
	menu.DisplayAt(client, item, 60);

	return Plugin_Handled;
}

public int MenuHandler_HUD(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sCookie[16];
		menu.GetItem(param2, sCookie, 16);
		if(StrEqual(sCookie, "Jhud"))
			ShowJHUDMenu(param1);

		else if(StrEqual(sCookie, "TCol"))
			OpenColorsMenu(param1,7);

		else
		{
			int type = (sCookie[0] == '!')? 1:2;
			ReplaceString(sCookie, 16, "!", "");
			ReplaceString(sCookie, 16, "@", "");

			int iSelection = StringToInt(sCookie);

			if(type == 1)
			{
				gI_HUDSettings[param1] ^= iSelection;
				IntToString(gI_HUDSettings[param1], sCookie, 16);
				SetClientCookie(param1, gH_HUDCookie, sCookie);
				FormatEx(sTopLeftOld, 128, "");
				GetTimerClr(param1);
			}

			else
			{
				gI_HUD2Settings[param1] ^= iSelection;
				IntToString(gI_HUD2Settings[param1], sCookie, 16);
				SetClientCookie(param1, gH_HUDCookieMain, sCookie);
			}

			if(gEV_Type == Engine_TF2 && iSelection == HUD_CENTER && (gI_HUDSettings[param1] & HUD_MASTER) > 0)
			{
				FillerHintText(param1);
			}
			ShowHUDMenu(param1, GetMenuSelectionPosition());
		}
	}

	else if(action == MenuAction_DisplayItem)
	{
		char sInfo[16];
		char sDisplay[64];
		int style = 0;
		menu.GetItem(param2, sInfo, 16, style, sDisplay, 64);

		int type = (sInfo[0] == '!')? 1:2;
		ReplaceString(sInfo, 16, "!", "");
		ReplaceString(sInfo, 16, "@", "");

		if(type == 1)
		{
			Format(sDisplay, 64, "[%s] %s", ((gI_HUDSettings[param1] & StringToInt(sInfo)) > 0)? "＋":"－", sDisplay);
		}

		else
		{
			Format(sDisplay, 64, "[%s] %s", ((gI_HUD2Settings[param1] & StringToInt(sInfo)) == 0)? "＋":"－", sDisplay);
		}

		return RedrawMenuItem(sDisplay);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void OnGameFrame()
{
	if((GetGameTickCount() % gCV_TicksPerUpdate.IntValue) == 0)
	{
		Cron();
	}
}

void Cron()
{
	if(++gI_Cycle >= 65535)
	{
		gI_Cycle = 0;
	}

	switch(gI_GradientDirection)
	{
		case 0:
		{
			gI_Gradient.b += gCV_GradientStepSize.IntValue;

			if(gI_Gradient.b >= 255)
			{
				gI_Gradient.b = 255;
				gI_GradientDirection = 1;
			}
		}

		case 1:
		{
			gI_Gradient.r -= gCV_GradientStepSize.IntValue;

			if(gI_Gradient.r <= 0)
			{
				gI_Gradient.r = 0;
				gI_GradientDirection = 2;
			}
		}

		case 2:
		{
			gI_Gradient.g += gCV_GradientStepSize.IntValue;

			if(gI_Gradient.g >= 255)
			{
				gI_Gradient.g = 255;
				gI_GradientDirection = 3;
			}
		}

		case 3:
		{
			gI_Gradient.b -= gCV_GradientStepSize.IntValue;

			if(gI_Gradient.b <= 0)
			{
				gI_Gradient.b = 0;
				gI_GradientDirection = 4;
			}
		}

		case 4:
		{
			gI_Gradient.r += gCV_GradientStepSize.IntValue;

			if(gI_Gradient.r >= 255)
			{
				gI_Gradient.r = 255;
				gI_GradientDirection = 5;
			}
		}

		case 5:
		{
			gI_Gradient.g -= gCV_GradientStepSize.IntValue;

			if(gI_Gradient.g <= 0)
			{
				gI_Gradient.g = 0;
				gI_GradientDirection = 0;
			}
		}

		default:
		{
			gI_Gradient.r = 255;
			gI_GradientDirection = 0;
		}
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || IsFakeClient(i) || (gI_HUDSettings[i] & HUD_MASTER) == 0)
		{
			continue;
		}

		if((gI_Cycle % 50) == 0)
		{
			float fSpeed[3];
			GetEntPropVector(GetHUDTarget(i), Prop_Data, "m_vecVelocity", fSpeed);
			gI_PreviousSpeed[i] = RoundToNearest(((gI_HUDSettings[i] & HUD_2DVEL) == 0)? GetVectorLength(fSpeed):(SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0))));
		}
		
		TriggerHUDUpdate(i);
	}
}

void TriggerHUDUpdate(int client, bool keysonly = false) // keysonly because CS:S lags when you send too many usermessages
{
	if(!keysonly)
	{
		UpdateMainHUD(client);
		SetEntProp(client, Prop_Data, "m_bDrawViewmodel", ((gI_HUDSettings[client] & HUD_HIDEWEAPON) > 0)? 0:1);
		//UpdateTopLeftHUD(client, true);
	}

	if(IsSource2013(gEV_Type))
	{
		if(!keysonly)
		{
			UpdateKeyHint(client);
		}

		//UpdateCenterKeys(client);
	}
	/*
	else if(((gI_HUDSettings[client] & HUD_KEYOVERLAY) > 0)
	{
		bool bShouldDraw = false;
		Panel pHUD = new Panel();

		//UpdateKeyOverlay(client, pHUD, bShouldDraw);
		pHUD.DrawItem("", ITEMDRAW_RAWLINE);

		UpdateSpectatorList(client, pHUD, bShouldDraw);

		if(bShouldDraw)
		{
			pHUD.Send(client, PanelHandler_Nothing, 1);
		}

		delete pHUD;
	}*/
}

void AddHUDLine(char[] buffer, int maxlen, const char[] line, int lines)
{
	if(lines > 0)
	{
		Format(buffer, maxlen, "%s\n%s", buffer, line);
	}
	else
	{
		StrCat(buffer, maxlen, line);
	}
}

void GetRGB(int color, color_t arr)
{
	arr.r = ((color >> 16) & 0xFF);
	arr.g = ((color >> 8) & 0xFF);
	arr.b = (color & 0xFF);
}

int GetHex(color_t color)
{
	return (((color.r & 0xFF) << 16) + ((color.g & 0xFF) << 8) + (color.b & 0xFF));
}

int GetGradient(int start, int end, int steps)
{
	color_t aColorStart;
	GetRGB(start, aColorStart);

	color_t aColorEnd;
	GetRGB(end, aColorEnd);

	color_t aColorGradient;
	aColorGradient.r = (aColorStart.r + RoundToZero((aColorEnd.r - aColorStart.r) * steps / 100.0));
	aColorGradient.g = (aColorStart.g + RoundToZero((aColorEnd.g - aColorStart.g) * steps / 100.0));
	aColorGradient.b = (aColorStart.b + RoundToZero((aColorEnd.b - aColorStart.b) * steps / 100.0));

	return GetHex(aColorGradient);
}

public void Shavit_OnEnterZone(int client, int type, int track, int id, int entity)
{
	if(type == Zone_CustomSpeedLimit)
	{
		gI_ZoneSpeedLimit[client] = Shavit_GetZoneData(id);
	}
}


int AddHUDToBuffer_Source2013(int client, huddata_t data, char[] buffer, int maxlen)
{
	int iLines = 0;
	char sLine[128];

	if(data.bReplay)
	{
		if(data.iStyle != -1 && Shavit_GetReplayStatus(data.iStyle) != Replay_Idle && data.fTime <= data.fWR && Shavit_IsReplayDataLoaded(data.iStyle, data.iTrack))
		{
			if(data.iStyle!=187)
			{
				char sTrack[32];
				if(data.iTrack != Track_Main && (gI_HUD2Settings[client] & HUD2_TRACK) == 0)
				{
					GetTrackName(client, data.iTrack, sTrack, 32);
					Format(sTrack, 32, "(%s) ", sTrack);
				}

				if((gI_HUD2Settings[client] & HUD2_STYLE) == 0)
				{
					FormatEx(sLine, 128, "%s %s%T", gS_StyleStrings[data.iStyle].sStyleName, sTrack, "ReplayText", client);
					AddHUDLine(buffer, maxlen, sLine, iLines);
					iLines++;
				}
			}
			else
			{
				if((gI_HUD2Settings[client] & HUD2_STYLE) == 0)
				{
					FormatEx(sLine, 128, "Own %T", "ReplayText", client);
					AddHUDLine(buffer, maxlen, sLine, iLines);
					iLines++;
				}
			}
			char sPlayerName[MAX_NAME_LENGTH];
			Shavit_GetReplayName(data.iStyle, data.iTrack, sPlayerName, MAX_NAME_LENGTH);
			AddHUDLine(buffer, maxlen, sPlayerName, iLines);
			iLines++;

			if((gI_HUD2Settings[client] & HUD2_TIME) == 0)
			{
				char sTime[32];
				FormatSeconds(data.fTime, sTime, 32, false);

				char sWR[32];
				FormatSeconds(data.fWR, sWR, 32, false);

				FormatEx(sLine, 128, "%s / %s\n(%.1f％)", sTime, sWR, ((data.fTime < 0.0 ? 0.0 : data.fTime / data.fWR) * 100));
				AddHUDLine(buffer, maxlen, sLine, iLines);
				iLines++;
			}

			if((gI_HUD2Settings[client] & HUD2_SPEED) == 0)
			{
				FormatEx(sLine, 128, "%d u/s", data.iSpeed);
				AddHUDLine(buffer, maxlen, sLine, iLines);
				iLines++;
			}
		}

		else
		{
			FormatEx(sLine, 128, "%T", (gEV_Type == Engine_TF2)? "NoReplayDataTF2":"NoReplayData", client);
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		return iLines;
	}

	if((gI_HUDSettings[client] & HUD_ZONEHUD) > 0 && data.iZoneHUD != ZoneHUD_None)
	{
		if(gB_Rankings && (gI_HUD2Settings[client] & HUD2_MAPTIER) == 0)
		{
			FormatEx(sLine, 128, "%T", "HudZoneTier", client, Shavit_GetMapTier(gS_Map));
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		if(data.iZoneHUD == ZoneHUD_Start)
		{
			FormatEx(sLine, 128, "%T ", "HudInStartZone", client, data.iSpeed);
		}

		else
		{
			FormatEx(sLine, 128, "%T ", "HudInEndZone", client, data.iSpeed);
		}

		AddHUDLine(buffer, maxlen, sLine, iLines);

		return ++iLines;
	}

	if(data.iTimerStatus != Timer_Stopped)
	{
		if((gI_HUD2Settings[client] & HUD2_STYLE) == 0)
		{
			AddHUDLine(buffer, maxlen, gS_StyleStrings[data.iStyle].sStyleName, iLines);
			iLines++;
		}

		if(data.bPractice || data.iTimerStatus == Timer_Paused)
		{
			FormatEx(sLine, 128, "%T", (data.iTimerStatus == Timer_Paused)? "HudPaused":"HudPracticeMode", client);
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		if((gI_HUD2Settings[client] & HUD2_TIME) == 0)
		{
			char sTime[32];
			FormatSeconds(data.fTime, sTime, 32, false);

			char sTimeDiff[32];
			
			if(gB_Replay && gCV_EnableDynamicTimeDifference.BoolValue && Shavit_GetReplayFrameCount(data.iStyle, data.iTrack) != 0 && (gI_HUD2Settings[client] & HUD2_TIMEDIFFERENCE) == 0)
			{
				float fClosestReplayTime = Shavit_GetClosestReplayTime(data.iTarget, data.iStyle, data.iTrack);

				if(fClosestReplayTime != -1.0)
				{
					float fDifference = data.fTime - fClosestReplayTime;
					FormatSeconds(fDifference, sTimeDiff, 32, false);
					Format(sTimeDiff, 32, " (%s%s)", (fDifference >= 0.0)? "+":"", sTimeDiff);
				}
			}

			if((gI_HUD2Settings[client] & HUD2_RANK) == 0)
			{
				FormatEx(sLine, 128, "%T: %s%s (%d)", "HudTimeText", client, sTime, sTimeDiff, data.iRank);
			}

			else
			{
				FormatEx(sLine, 128, "%T: %s%s", "HudTimeText", client, sTime, sTimeDiff);
			}
			
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		if((gI_HUD2Settings[client] & HUD2_JUMPS) == 0)
		{
			FormatEx(sLine, 128, "%T: %d", "HudJumpsText", client, data.iJumps);
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		if((gI_HUD2Settings[client] & HUD2_STRAFE) == 0)
		{
			FormatEx(sLine, 128, "%T: %d", "HudStrafeText", client, data.iStrafes);
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}
	}

	if((gI_HUD2Settings[client] & HUD2_SPEED) == 0)
	{
		// timer: Speed: %d
		// no timer: straight up number
		if(data.iTimerStatus != Timer_Stopped)
		{
			FormatEx(sLine, 128, "%T: %d", "HudSpeedText", client, data.iSpeed);
		}

		else
		{
			IntToString(data.iSpeed, sLine, 128);
		}

		AddHUDLine(buffer, maxlen, sLine, iLines);
		iLines++;

		if(gA_StyleSettings[data.iStyle].fVelocityLimit > 0.0 && Shavit_InsideZone(data.iTarget, Zone_CustomSpeedLimit, -1))
		{
			if(gI_ZoneSpeedLimit[data.iTarget] == 0)
			{
				FormatEx(sLine, 128, "%T", "HudNoSpeedLimit", data.iTarget);
			}

			else
			{
				FormatEx(sLine, 128, "%T", "HudCustomSpeedLimit", client, gI_ZoneSpeedLimit[data.iTarget]);
			}

			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}
	}

	if(data.iTimerStatus != Timer_Stopped && data.iTrack != Track_Main && (gI_HUD2Settings[client] & HUD2_TRACK) == 0)
	{
		char sTrack[32];
		GetTrackName(client, data.iTrack, sTrack, 32);

		AddHUDLine(buffer, maxlen, sTrack, iLines);
		iLines++;
	}

	return iLines;
}

int AddHUDToBuffer_CSGO(int client, huddata_t data, char[] buffer, int maxlen)
{
	int iLines = 0;
	char sLine[128];

	if(data.bReplay)
	{
		StrCat(buffer, maxlen, "<span class='fontSize-l'>");

		if(data.iStyle != -1 && data.fTime <= data.fWR && Shavit_IsReplayDataLoaded(data.iStyle, data.iTrack))
		{
			char sPlayerName[MAX_NAME_LENGTH];
			Shavit_GetReplayName(data.iStyle, data.iTrack, sPlayerName, MAX_NAME_LENGTH);

			char sTrack[32];

			if(data.iTrack != Track_Main && (gI_HUD2Settings[client] & HUD2_TRACK) == 0)
			{
				GetTrackName(client, data.iTrack, sTrack, 32);
				Format(sTrack, 32, "(%s) ", sTrack);
			}

			FormatEx(sLine, 128, "<u><span color='#%s'>%s %s%T</span></u> <span color='#DB88C2'>%s</span>", gS_StyleStrings[data.iStyle].sHTMLColor, gS_StyleStrings[data.iStyle].sStyleName, sTrack, "ReplayText", client, sPlayerName);
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;

			if((gI_HUD2Settings[client] & HUD2_TIME) == 0)
			{	
				char sTime[32];
				FormatSeconds(data.fTime, sTime, 32, false);

				char sWR[32];
				FormatSeconds(data.fWR, sWR, 32, false);

				FormatEx(sLine, 128, "%s / %s (%.1f％)", sTime, sWR, ((data.fTime < 0.0 ? 0.0 : data.fTime / data.fWR) * 100));
				AddHUDLine(buffer, maxlen, sLine, iLines);
				iLines++;
			}

			if((gI_HUD2Settings[client] & HUD2_SPEED) == 0)
			{
				FormatEx(sLine, 128, "%d u/s", data.iSpeed);
				AddHUDLine(buffer, maxlen, sLine, iLines);
				iLines++;
			}
		}

		else
		{
			FormatEx(sLine, 128, "%T", "NoReplayData", client);
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		StrCat(buffer, maxlen, "</span>");

		return iLines;
	}

	if((gI_HUDSettings[client] & HUD_ZONEHUD) > 0 && data.iZoneHUD != ZoneHUD_None)
	{
		char sZoneHUD[64];
		FormatEx(sZoneHUD, 64, "<span class='fontSize-xxl' color='#%06X'>", ((gI_Gradient.r << 16) + (gI_Gradient.g << 8) + (gI_Gradient.b)));
		StrCat(buffer, maxlen, sZoneHUD);

		if(data.iZoneHUD == ZoneHUD_Start)
		{
			if(gB_Rankings && (gI_HUD2Settings[client] & HUD2_MAPTIER) == 0)
			{
				if(data.iTrack == Track_Main)
				{
					FormatEx(sZoneHUD, 32, "%T", "HudZoneTier", client, Shavit_GetMapTier(gS_Map));
				}

				else
				{
					GetTrackName(client, data.iTrack, sZoneHUD, 32);
				}

				Format(sZoneHUD, 32, "\t\t%s\n\n", sZoneHUD);
				AddHUDLine(buffer, maxlen, sZoneHUD, iLines);
				iLines++;
			}
			
			FormatEx(sZoneHUD, 64, "%T</span>", "HudInStartZoneCSGO", client, data.iSpeed);
		}

		else
		{
			FormatEx(sZoneHUD, 64, "%T</span>", "HudInEndZoneCSGO", client, data.iSpeed);
		}
		
		StrCat(buffer, maxlen, sZoneHUD);

		return ++iLines;
	}

	StrCat(buffer, maxlen, "<span class='fontSize-l'>");

	if(data.iTimerStatus != Timer_Stopped)
	{
		if(data.bPractice || data.iTimerStatus == Timer_Paused)
		{
			FormatEx(sLine, 128, "%T", (data.iTimerStatus == Timer_Paused)? "HudPaused":"HudPracticeMode", client);
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		if(data.iTimerStatus != Timer_Stopped && data.iTrack != Track_Main && (gI_HUD2Settings[client] & HUD2_TRACK) == 0)
		{
			char sTrack[32];
			GetTrackName(client, data.iTrack, sTrack, 32);

			AddHUDLine(buffer, maxlen, sTrack, iLines);
			iLines++;
		}

		if((gI_HUD2Settings[client] & HUD2_TIME) == 0)
		{
			int iColor = 0xFF0000; // red, worse than both pb and wr
			
			if(data.iTimerStatus == Timer_Paused) iColor = 0xA9C5E8; // blue sky
			else if(data.fTime < data.fWR || data.fWR == 0.0) iColor = GetGradient(0x00FF00, 0x96172C, RoundToZero((data.fTime / data.fWR) * 100));
			else if(data.fPB != 0.0 && data.fTime < data.fPB) iColor = 0xFFA500; // orange

			char sTime[32];
			FormatSeconds(data.fTime, sTime, 32, false);
			
			char sTimeDiff[32];
			
			if(gB_Replay && gCV_EnableDynamicTimeDifference.BoolValue && Shavit_GetReplayFrameCount(data.iStyle, data.iTrack) != 0 && (gI_HUD2Settings[client] & HUD2_TIMEDIFFERENCE) == 0)
			{
				float fClosestReplayTime = Shavit_GetClosestReplayTime(data.iTarget, data.iStyle, data.iTrack);

				if(fClosestReplayTime != -1.0)
				{
					float fDifference = data.fTime - fClosestReplayTime;
					FormatSeconds(fDifference, sTimeDiff, 32, false);
					Format(sTimeDiff, 32, " (%s%s)", (fDifference >= 0.0)? "+":"", sTimeDiff);
				}
			}

			if((gI_HUD2Settings[client] & HUD2_RANK) == 0)
			{
				FormatEx(sLine, 128, "<span color='#%06X'>%s%s</span> (#%d)", iColor, sTime, sTimeDiff, data.iRank);
			}

			else
			{
				FormatEx(sLine, 128, "<span color='#%06X'>%s%s</span>", iColor, sTime, sTimeDiff);
			}
			
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}
	}

	if((gI_HUD2Settings[client] & HUD2_SPEED) == 0)
	{
		int iColor = 0xA0FFFF;
		
		if((data.iSpeed - gI_PreviousSpeed[client]) < 0)
		{
			iColor = 0xFFC966;
		}

		FormatEx(sLine, 128, "<span color='#%06X'>%d u/s</span>", iColor, data.iSpeed);
		AddHUDLine(buffer, maxlen, sLine, iLines);
		iLines++;
	}

	if(data.iTimerStatus != Timer_Stopped)
	{
		if((gI_HUD2Settings[client] & HUD2_JUMPS) == 0)
		{
			FormatEx(sLine, 128, "%d %T", data.iJumps, "HudJumpsText", client);
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		if((gI_HUD2Settings[client] & HUD2_STRAFE) == 0)
		{
			if((gI_HUD2Settings[client] & HUD2_SYNC) == 0)
			{
				FormatEx(sLine, 128, "%d %T (%.1f%%)", data.iStrafes, "HudStrafeText", client, data.fSync);
			}

			else
			{
				FormatEx(sLine, 128, "%d %T", data.iStrafes, "HudStrafeText", client);
			}

			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}
	}

	if((gI_HUD2Settings[client] & HUD2_STYLE) == 0)
	{
		FormatEx(sLine, 128, "<span color='#%s'>%s</span>", gS_StyleStrings[data.iStyle].sHTMLColor, gS_StyleStrings[data.iStyle].sStyleName);
		AddHUDLine(buffer, maxlen, sLine, iLines);
		iLines++;
	}

	StrCat(buffer, maxlen, "</span>");

	return iLines;
}

void UpdateMainHUD(int client)
{
	int target = GetHUDTarget(client);

	if((gI_HUDSettings[client] & HUD_CENTER) == 0 ||
		((gI_HUDSettings[client] & HUD_OBSERVE) == 0 && client != target) ||
		(gEV_Type == Engine_TF2 && (!gB_FirstPrint[target] || GetEngineTime() - gF_ConnectTime[target] < 1.5))) // TF2 has weird handling for hint text
	{
		return;
	}

	float fSpeed[3];
	GetEntPropVector(target, Prop_Data, "m_vecVelocity", fSpeed);

	float fSpeedHUD = ((gI_HUDSettings[client] & HUD_2DVEL) == 0)? GetVectorLength(fSpeed):(SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0)));
	bool bReplay = (gB_Replay && IsFakeClient(target));
	ZoneHUD iZoneHUD = ZoneHUD_None;
	int iReplayStyle = 0;
	int iReplayTrack = 0;
	float fReplayTime = 0.0;
	float fReplayLength = 0.0;

	if(!bReplay)
	{
		if(Shavit_InsideZone(target, Zone_Start, -1))
		{
			iZoneHUD = ZoneHUD_Start;
		}
		
		else if(Shavit_InsideZone(target, Zone_End, -1))
		{
			iZoneHUD = ZoneHUD_End;
		}
	}

	else
	{
		iReplayStyle = Shavit_GetReplayBotStyle(target);
		iReplayTrack = Shavit_GetReplayBotTrack(target);

		if(iReplayStyle != -1)
		{
			fReplayTime = Shavit_GetReplayTime(iReplayStyle, iReplayTrack);
			fReplayLength = Shavit_GetReplayLength(iReplayStyle, iReplayTrack);

			if(iReplayStyle!=187)
			{
				if(gA_StyleSettings[iReplayStyle].fSpeedMultiplier != 1.0)
				{
					fSpeedHUD /= gA_StyleSettings[iReplayStyle].fSpeedMultiplier;
				}
			}
		}
	}
	
	huddata_t huddata;
	huddata.iTarget = target;
	huddata.iSpeed = RoundToNearest(fSpeedHUD);
	huddata.iZoneHUD = iZoneHUD;
	huddata.iStyle = (bReplay)? iReplayStyle:Shavit_GetBhopStyle(target);
	huddata.iTrack = (bReplay)? iReplayTrack:Shavit_GetClientTrack(target);
	huddata.fTime = (bReplay)? fReplayTime:Shavit_GetClientTime(target);
	huddata.iJumps = (bReplay)? 0:Shavit_GetClientJumps(target);
	huddata.iStrafes = (bReplay)? 0:Shavit_GetStrafeCount(target);
	huddata.iRank = (bReplay)? 0:Shavit_GetRankForTime(huddata.iStyle, huddata.fTime, huddata.iTrack);
	huddata.fSync = (bReplay)? 0.0:Shavit_GetSync(target);
	huddata.fPB = (bReplay)? 0.0:Shavit_GetClientPB(target, huddata.iStyle, huddata.iTrack);
	huddata.fWR = (bReplay)? fReplayLength:Shavit_GetWorldRecord(huddata.iStyle, huddata.iTrack);
	huddata.iTimerStatus = (bReplay)? Timer_Running:Shavit_GetTimerStatus(target);
	huddata.bReplay = bReplay;
	huddata.bPractice = (bReplay)? false:Shavit_IsPracticeMode(target);

	char sBuffer[512];
	
	if(IsSource2013(gEV_Type))
	{
		if(AddHUDToBuffer_Source2013(client, huddata, sBuffer, 512) > 0)
		{
			PrintHintText(client, "%s", sBuffer);
		}
	}
	
	else
	{
		StrCat(sBuffer, 512, "<pre>");
		int iLines = AddHUDToBuffer_CSGO(client, huddata, sBuffer, 512);
		StrCat(sBuffer, 512, "</pre>");

		if(iLines > 0)
		{
			if(gCV_UseHUDFix.BoolValue)
			{
				PrintCSGOHUDText(client, "%s", sBuffer);
			}
			else
			{
				PrintHintText(client, "%s", sBuffer);
			}
		}
	}
}
/*
void UpdateKeyOverlay(int client, Panel panel, bool &draw)
{
	if((gI_HUDSettings[client] & HUD_KEYOVERLAY) == 0)
	{
		return;
	}

	int target = GetHUDTarget(client);

	if(((gI_HUDSettings[client] & HUD_OBSERVE) == 0 && client != target) || !IsValidClient(target) || IsClientObserver(target))
	{
		return;
	}

	// to make it shorter
	int buttons = gI_Buttons[target];
	int style = (IsFakeClient(target))? Shavit_GetReplayBotStyle(target):Shavit_GetBhopStyle(target);

	if(!(0 <= style < gI_Styles))
	{
		style = 0;
	}

	char sPanelLine[128];

	if(gB_BhopStats && !gA_StyleSettings[style].bAutobhop)
	{
		FormatEx(sPanelLine, 64, " %d%s%d\n", gI_ScrollCount[target], (gI_ScrollCount[target] > 9)? "   ":"	 ", gI_LastScrollCount[target]);
	}

	Format(sPanelLine, 128, "%s［%s］　［%s］\n　　 %s\n%s　 %s 　%s\n　%s　　%s", sPanelLine,
		(buttons & IN_JUMP) > 0? "Ｊ":"ｰ", (buttons & IN_DUCK) > 0? "Ｃ":"ｰ",
		(buttons & IN_FORWARD) > 0? "Ｗ":"ｰ", (buttons & IN_MOVELEFT) > 0? "Ａ":"ｰ",
		(buttons & IN_BACK) > 0? "Ｓ":"ｰ", (buttons & IN_MOVERIGHT) > 0? "Ｄ":"ｰ",
		(buttons & IN_LEFT) > 0? "Ｌ":" ", (buttons & IN_RIGHT) > 0? "Ｒ":" ");

	panel.DrawItem(sPanelLine, ITEMDRAW_RAWLINE);

	draw = true;
}*/

public void Bunnyhop_OnTouchGround(int client)
{
	gI_LastScrollCount[client] = BunnyhopStats.GetScrollCount(client);
}

public void Bunnyhop_OnJumpPressed(int client)
{
	gI_ScrollCount[client] = BunnyhopStats.GetScrollCount(client);
}
/*
void UpdateCenterKeys(int client)
{
	if((gI_HUDSettings[client] & HUD_KEYOVERLAY) == 0)
	{
		return;
	}

	int target = GetHUDTarget(client);

	if(((gI_HUDSettings[client] & HUD_OBSERVE) == 0 && client != target) || !IsValidClient(target) || IsClientObserver(target))
	{
		return;
	}

	int buttons = gI_Buttons[target];

	char sCenterText[64];
	FormatEx(sCenterText, 64, "　%s　　%s\n　　 %s\n%s　 %s 　%s\n　%s　　%s",
		(buttons & IN_JUMP) > 0? "Ｊ":"ｰ", (buttons & IN_DUCK) > 0? "Ｃ":"ｰ",
		(buttons & IN_FORWARD) > 0? "Ｗ":"ｰ", (buttons & IN_MOVELEFT) > 0? "Ａ":"ｰ",
		(buttons & IN_BACK) > 0? "Ｓ":"ｰ", (buttons & IN_MOVERIGHT) > 0? "Ｄ":"ｰ",
		(buttons & IN_LEFT) > 0? "Ｌ":" ", (buttons & IN_RIGHT) > 0? "Ｒ":" ");

	int style = (IsFakeClient(target))? Shavit_GetReplayBotStyle(target):Shavit_GetBhopStyle(target);

	if(!(0 <= style < gI_Styles))
	{
		style = 0;
	}

	if(gB_BhopStats && !gA_StyleSettings[style].bAutobhop)
	{
		Format(sCenterText, 64, "%s\n　　%d　%d", sCenterText, gI_ScrollCount[target], gI_LastScrollCount[target]);
	}

	PrintCenterText(client, "%s", sCenterText);
}

void UpdateSpectatorList(int client, Panel panel, bool &draw)
{
	if((gI_HUDSettings[client] & HUD_SPECTATORS) == 0)
	{
		return;
	}

	int target = GetHUDTarget(client);

	if(((gI_HUDSettings[client] & HUD_OBSERVE) == 0 && client != target) || !IsValidClient(target))
	{
		return;
	}

	int[] iSpectatorClients = new int[MaxClients];
	int iSpectators = 0;
	bool bIsAdmin = CheckCommandAccess(client, "admin_speclisthide", ADMFLAG_KICK);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(i == client || !IsValidClient(i) || IsFakeClient(i) || !IsClientObserver(i) || GetClientTeam(i) < 1 || GetHUDTarget(i) != target)
		{
			continue;
		}

		if((gCV_SpectatorList.IntValue == 1 && !bIsAdmin && CheckCommandAccess(i, "admin_speclisthide", ADMFLAG_KICK)) ||
			(gCV_SpectatorList.IntValue == 2 && !CanUserTarget(client, i)))
		{
			continue;
		}

		iSpectatorClients[iSpectators++] = i;
	}

	if(iSpectators > 0)
	{
		char sName[MAX_NAME_LENGTH];
		char sSpectators[32];
		char sSpectatorsPersonal[32];
		char sSpectatorWatching[32];
		FormatEx(sSpectatorsPersonal, 32, "%T", "SpectatorPersonal", client);
		FormatEx(sSpectatorWatching, 32, "%T", "SpectatorWatching", client);
		FormatEx(sSpectators, 32, "%s (%d):", (client == target)? sSpectatorsPersonal:sSpectatorWatching, iSpectators);
		panel.DrawItem(sSpectators, ITEMDRAW_RAWLINE);

		for(int i = 0; i < iSpectators; i++)
		{
			if(i == 7)
			{
				panel.DrawItem("...", ITEMDRAW_RAWLINE);

				break;
			}

			GetClientName(iSpectatorClients[i], sName, sizeof(sName));
			ReplaceString(sName, sizeof(sName), "#", "?");
			TrimPlayerName(sName, sName, sizeof(sName));

			panel.DrawItem(sName, ITEMDRAW_RAWLINE);
		}

		draw = true;
	}
}

void UpdateTopLeftHUD(int client, bool wait)
{
	if((!wait || gI_Cycle % 25 == 0) && (gI_HUDSettings[client] & HUD_TOPLEFT) > 0)
	{
		int target = GetHUDTarget(client);

		int track = 0;
		int style = 0;

		if(!IsFakeClient(target))
		{
			style = Shavit_GetBhopStyle(target);
			track = Shavit_GetClientTrack(target);
		}

		else
		{
			style = Shavit_GetReplayBotStyle(target);
			track = Shavit_GetReplayBotTrack(target);
		}

		if(!(0 <= style < gI_Styles) || !(0 <= track <= TRACKS_SIZE))
		{
			return;
		}

		float fWRTime = Shavit_GetWorldRecord(style, track);

		if(fWRTime != 0.0)
		{
			char sWRTime[16];
			FormatSeconds(fWRTime, sWRTime, 16);

			char sWRName[MAX_NAME_LENGTH];
			Shavit_GetWRName(style, sWRName, MAX_NAME_LENGTH, track);

			char sTopLeft[128];
			FormatEx(sTopLeft, 128, "WR: %s (%s)", sWRTime, sWRName);

			float fTargetPB = Shavit_GetClientPB(target, style, track);
			char sTargetPB[64];
			FormatSeconds(fTargetPB, sTargetPB, 64);
			Format(sTargetPB, 64, "%T: %s", "HudBestText", client, sTargetPB);

			float fSelfPB = Shavit_GetClientPB(client, style, track);
			char sSelfPB[64];
			FormatSeconds(fSelfPB, sSelfPB, 64);
			Format(sSelfPB, 64, "%T: %s", "HudBestText", client, sSelfPB);

			if((gI_HUD2Settings[client] & HUD2_SPLITPB) == 0 && target != client)
			{
				if(fTargetPB != 0.0)
				{
					if((gI_HUD2Settings[client]& HUD2_TOPLEFT_RANK) == 0)
					{
						Format(sTopLeft, 128, "%s\n%s (#%d) (%N)", sTopLeft, sTargetPB, Shavit_GetRankForTime(style, fTargetPB, track), target);
					}
					else 
					{
						Format(sTopLeft, 128, "%s\n%s (%N)", sTopLeft, sTargetPB, target);
					}
				}

				if(fSelfPB != 0.0)
				{
					if((gI_HUD2Settings[client]& HUD2_TOPLEFT_RANK) == 0)
					{
						Format(sTopLeft, 128, "%s\n%s (#%d) (%N)", sTopLeft, sSelfPB, Shavit_GetRankForTime(style, fSelfPB, track), client);
					}
					else 
					{
						Format(sTopLeft, 128, "%s\n%s (%N)", sTopLeft, sSelfPB, client);
					}
				}
			}

			else if(fSelfPB != 0.0)
			{
				Format(sTopLeft, 128, "%s\n%s (#%d)", sTopLeft, sSelfPB, Shavit_GetRankForTime(style, fSelfPB, track));
			}

			Action result = Plugin_Continue;
			Call_StartForward(gH_Forwards_OnTopLeftHUD);
			Call_PushCell(client);
			Call_PushCell(target);
			Call_PushStringEx(sTopLeft, 128, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
			Call_PushCell(128);
			Call_Finish(result);
			
			if(result != Plugin_Continue && result != Plugin_Changed)
			{
				return;
			}

			SetHudTextParams(0.01, 0.01, 2.5, 255, 255, 255, 255, 0, 0.0, 0.0, 0.0);
			//ShowSyncHudText(client, gh_HUD, "%s", sTopLeft);
			ShowHudText(client, 3, sTopLeft);
		}
	}
}*/

void UpdateKeyHint(int client)
{
	if(((gI_HUDSettings[client] & HUD_SYNC) > 0 || (gI_HUDSettings[client] & HUD_TIMELEFT) > 0))
	{
		char sMessageHint[256];
		int iTimeLeft = -1;

		if((gI_HUDSettings[client] & HUD_TIMELEFT) > 0 && GetMapTimeLeft(iTimeLeft) && iTimeLeft > 0)
		{
			FormatEx(sMessageHint, 256, (iTimeLeft > 60)? "%T: %d minutes":"%T: <1 minute", "HudTimeLeft", client, (iTimeLeft / 60), "HudTimeLeft", client);
		}

		int target = GetHUDTarget(client);

		if(IsValidClient(target) && (target == client || (gI_HUDSettings[client] & HUD_OBSERVE) > 0))
		{
			int style = Shavit_GetBhopStyle(target);

			if((gI_HUDSettings[client] & HUD_SYNC) > 0 && Shavit_GetTimerStatus(target) == Timer_Running && gA_StyleSettings[style].bSync && !IsFakeClient(target) && (!gB_Zones || !Shavit_InsideZone(target, Zone_Start, -1)))
			{
				Format(sMessageHint, 256, "%s%s%T: %.01f", sMessageHint, (strlen(sMessageHint) > 0)? "\n\n":"", "HudSync", client, Shavit_GetSync(target));

				if(!gA_StyleSettings[style].bAutobhop && (gI_HUD2Settings[client] & HUD2_PERFS) == 0)
				{	
					Format(sMessageHint, 256, "%s\n%T: %.1f", sMessageHint, "HudPerfs", client, Shavit_GetPerfectJumps(target));
				}
			}

			if((gI_HUDSettings[client] & HUD_KEYOVERLAY) > 0)
			{

				int buttons = gI_Buttons[target];

				FormatEx(sMessageHint, 256, "%s\n\n　%s　　%s\n　　 %s\n%s　 %s 　%s\n　%s　　%s",sMessageHint,
					(buttons & IN_JUMP) > 0? "Ｊ":"ｰ", (buttons & IN_DUCK) > 0? "Ｃ":"ｰ",
					(buttons & IN_FORWARD) > 0? "Ｗ":"ｰ", (buttons & IN_MOVELEFT) > 0? "Ａ":"ｰ",
					(buttons & IN_BACK) > 0? "Ｓ":"ｰ", (buttons & IN_MOVERIGHT) > 0? "Ｄ":"ｰ",
					(buttons & IN_LEFT) > 0? "Ｌ":" ", (buttons & IN_RIGHT) > 0? "Ｒ":" ");

				int style2 = (IsFakeClient(target))? Shavit_GetReplayBotStyle(target):Shavit_GetBhopStyle(target);

				if(!(0 <= style2 < gI_Styles))
				{
					style2 = 0;
				}

				if(gB_BhopStats && !gA_StyleSettings[style2].bAutobhop)
				{
					Format(sMessageHint, 256, "%s\n　　%d　%d", sMessageHint, gI_ScrollCount[target], gI_LastScrollCount[target]);
				}
			}
			/*
			if((gI_HUDSettings[client] & HUD_SPECTATORS) > 0)
			{
				int[] iSpectatorClients = new int[MaxClients];
				int iSpectators = 0;
				bool bIsAdmin = CheckCommandAccess(client, "admin_speclisthide", ADMFLAG_KICK);

				for(int i = 1; i <= MaxClients; i++)
				{
					if(i == client || !IsValidClient(i) || IsFakeClient(i) || !IsClientObserver(i) || GetClientTeam(i) < 1 || GetHUDTarget(i) != target)
					{
						continue;
					}

					if((gCV_SpectatorList.IntValue == 1 && !bIsAdmin && CheckCommandAccess(i, "admin_speclisthide", ADMFLAG_KICK)) ||
						(gCV_SpectatorList.IntValue == 2 && !CanUserTarget(client, i)))
					{
						continue;
					}

					iSpectatorClients[iSpectators++] = i;
				}

				if(iSpectators > 0)
				{
					Format(sMessageHint, 256, "%s%s%spectators (%d):", sMessageHint, (strlen(sMessageHint) > 0)? "\n\n":"", (client == target)? "S":"Other S", iSpectators);
					char sName[MAX_NAME_LENGTH];
					
					for(int i = 0; i < iSpectators; i++)
					{
						if(i == 7)
						{
							Format(sMessageHint, 256, "%s\n...", sMessageHint);

							break;
						}

						GetClientName(iSpectatorClients[i], sName, sizeof(sName));
						ReplaceString(sName, sizeof(sName), "#", "?");
						TrimPlayerName(sName, sName, sizeof(sName));
						Format(sMessageHint, 256, "%s\n%s", sMessageHint, sName);
					}
				}
			}*/
		}

		if(strlen(sMessageHint) > 0)
		{
			Handle hKeyHintText = StartMessageOne("KeyHintText", client);
			BfWriteByte(hKeyHintText, 1);
			BfWriteString(hKeyHintText, sMessageHint);
			EndMessage();
		}
	}
}

int GetHUDTarget(int client)
{
	int target = client;

	if(IsClientObserver(client))
	{
		int iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

		if(iObserverMode >= 3 && iObserverMode <= 5)
		{
			int iTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

			if(IsValidClient(iTarget, true))
			{
				target = iTarget;
			}
		}
	}

	return target;
}

public int PanelHandler_Nothing(Menu m, MenuAction action, int param1, int param2)
{
	// i don't need anything here
	return 0;
}
/*
public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	if(IsClientInGame(client))
	{
		UpdateTopLeftHUD(client, false);
	}
}*/

public int Native_ForceHUDUpdate(Handle handler, int numParams)
{
	int[] clients = new int[MaxClients];
	int count = 0;

	int client = GetNativeCell(1);

	if(client < 0 || client > MaxClients || !IsClientInGame(client))
	{
		ThrowNativeError(200, "Invalid client index %d", client);

		return -1;
	}

	clients[count++] = client;

	if(view_as<bool>(GetNativeCell(2)))
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(i == client || !IsValidClient(i) || GetHUDTarget(i) != client)
			{
				continue;
			}

			clients[count++] = client;
		}
	}

	for(int i = 0; i < count; i++)
	{
		TriggerHUDUpdate(clients[i]);
	}

	return count;
}

public int Native_GetHUDSettings(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(200, "Invalid client index %d", client);

		return -1;
	}

	return gI_HUDSettings[client];
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

void PrintCSGOHUDText(int client, const char[] format, any ...)
{
	char buff[MAX_HINT_SIZE];
	VFormat(buff, sizeof(buff), format, 3);
	Format(buff, sizeof(buff), "</font>%s ", buff);
	
	for(int i = strlen(buff); i < sizeof(buff); i++)
	{
		buff[i] = '\n';
	}
	
	Protobuf pb = view_as<Protobuf>(StartMessageOne("TextMsg", client, USERMSG_RELIABLE | USERMSG_BLOCKHOOKS));
	pb.SetInt("msg_dst", 4);
	pb.AddString("params", "#SFUI_ContractKillStart");
	pb.AddString("params", buff);
	pb.AddString("params", NULL_STRING);
	pb.AddString("params", NULL_STRING);
	pb.AddString("params", NULL_STRING);
	pb.AddString("params", NULL_STRING);
	
	EndMessage();
}

// https://forums.alliedmods.net/showthread.php?t=216841
/*
void TrimPlayerName(const char[] name, char[] outname, int len)
{
	int count, finallen;
	for(int i = 0; name[i]; i++)
	{
		count += ((name[i] & 0xc0) != 0x80) ? 1 : 0;
		
		if(count <= gCV_SpecNameSymbolLength.IntValue)
		{
			outname[i] = name[i];
			finallen = i;
		}
	}
	
	outname[finallen + 1] = '\0';
	
	if(count > gCV_SpecNameSymbolLength.IntValue)
		Format(outname, len, "%s...", outname);
}*/


public void OnClientPostAdminCheck(int client)
{
	g_iJump[client] = 0;
	g_strafeTick[client] = 0;
	g_flRawGain[client] = 0.0;
	g_iTicksOnGround[client] = 0;
	SDKHook(client, SDKHook_Touch, onTouch);
	if(!IsFakeClient(client))
	{
		gCV_SourceJumpAPIKey.GetString(apikey, sizeof(apikey));
		if(strlen(apikey)>1)
			RetrieveWRSJ(0, gS_CurrentMap);

		gCV_SourceJumpAPIKey.SetString("SECRET");
		updatedjhud = false;
		showticks = 0;
		for(int i = 0; i < MAX_CHANELS; i++)
		{
			GameTextTimer[i] = null;
			blockchanel[i] = false;
		}
	}
}

public Action onTouch(int client, int entity)
{
	if(!(GetEntProp(entity, Prop_Data, "m_usSolidFlags") & 12))
	{
		g_bTouchesWall[client] = true;
	}
}

public Action OnPlayerJump(Event event, char[] name, bool dontBroadcast)
{
	int userid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(userid);
	
	if(IsFakeClient(client))
	{
		return;
	}

	if(jhudfinish > 0 && jhudfinish <= g_iJump[client])
	{
		return;
	}

	if(g_iJump[client] && g_strafeTick[client] <= 0)
	{
		return;
	}
	
	g_iJump[client]++;
	
	for(int i = 1; i < MaxClients; i++)
	{
		if(IsClientInGame(i) && ((!IsPlayerAlive(i) && GetEntPropEnt(i, Prop_Data, "m_hObserverTarget") == client && GetEntProp(i, Prop_Data, "m_iObserverMode") != 7 && g_bJHUD[i]) || ((i == client && g_bJHUD[i]))))
		{
			JHUD_DrawStats(i, client);
		}
	}
	
	g_flRawGain[client] = 0.0;
	g_strafeTick[client] = 0;
	g_fTotalNormalDelta[client] = 0.0;
	g_fTotalPerfectDelta[client] = 0.0;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(IsFakeClient(client))
	{
		return Plugin_Continue;
	}
	
	float g_vecAbsVelocity[3];
	float yaw = NormalizeAngle(angles[1] - g_vecLastAngle[client][1]);
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", g_vecAbsVelocity);
	float velocity = GetVectorLength(g_vecAbsVelocity);
	
	float wish_angle = FloatAbs(ArcSine(30.0 / velocity)) * 180 / M_PI;
	
	if(GetEntityFlags(client) & FL_ONGROUND)
	{
		if(g_iTicksOnGround[client] > BHOP_TIME)
		{
			g_iJump[client] = 0;
			g_strafeTick[client] = 0;
			g_flRawGain[client] = 0.0;
			g_fTotalNormalDelta[client] = 0.0;
			g_fTotalPerfectDelta[client] = 0.0;
		}
		
		g_iTicksOnGround[client]++;
		
		if(buttons & IN_JUMP && g_iTicksOnGround[client] == 1)
		{
			float totalDelta = g_fTotalNormalDelta[client] - g_fTotalPerfectDelta[client];
			GetStrafeEval(client, totalDelta);
			
			JHUD_GetStats(client, vel, angles);
			g_iTicksOnGround[client] = 0;
		}
	}
	else
	{
		g_fTotalNormalDelta[client] += FloatAbs(yaw);
		g_fTotalPerfectDelta[client] += wish_angle;
		
		if(GetEntityMoveType(client) != MOVETYPE_NONE && GetEntityMoveType(client) != MOVETYPE_NOCLIP && GetEntityMoveType(client) != MOVETYPE_LADDER && GetEntProp(client, Prop_Data, "m_nWaterLevel") < 2)
		{
			JHUD_GetStats(client, vel, angles);
		}
		g_iTicksOnGround[client] = 0;
	}
	
	if(g_bTouchesWall[client])
	{
		g_iTouchTicks[client]++;
		g_bTouchesWall[client] = false;
	}
	else
	{
		g_iTouchTicks[client] = 0;
	}
	
	g_vecLastAngle[client] = angles;

	showticks++;
	
	bool sTrainer = true;

	if (!gB_StrafeTrainer[client])
		sTrainer = false; // dont run when disabled
	if ((GetEntityFlags(client) & FL_ONGROUND) || (GetEntityMoveType(client) == MOVETYPE_NOCLIP) || (GetEntityMoveType(client) == MOVETYPE_LADDER))
		sTrainer = false;

	float Percentage;
	if(sTrainer)
	{
		float AngDiff[3];
		AngDiff[0] = NormalizeAngle(gF_LastAngle[client][0] - angles[0]); //not really used
		AngDiff[1] = NormalizeAngle(gF_LastAngle[client][1] - angles[1]);
		AngDiff[2] = NormalizeAngle(gF_LastAngle[client][2] - angles[2]); //not really used
		
		// get the perfect angle
		float PerfAngle = PerfStrafeAngle(GetClientVelocity(client));
		
		// calculate the current percentage
		Percentage = FloatAbs(AngDiff[1]) / PerfAngle;

		if (gI_ClientTickCount[client] >= TRAINER_TICK_INTERVAL) // only every 10th tick, not really usable otherwise
		{
			float AveragePercentage = 0.0;
			
			for (int i = 0; i < TRAINER_TICK_INTERVAL; i++) // calculate average from the last ticks
			{
				AveragePercentage += gF_ClientPercentages[client][i];
				gF_ClientPercentages[client][i] = 0.0;
			}
			AveragePercentage /= TRAINER_TICK_INTERVAL;
			
			char sVisualisation[32]; // get the visualisation string
			VisualisationString(sVisualisation, sizeof(sVisualisation), AveragePercentage);
			
			// format the message
			Format(sMessageS, sizeof(sMessageS), "%d\%", RoundFloat(AveragePercentage * 100));
			
			Format(sMessageS, sizeof(sMessageS), "%s\n══════^══════", sMessageS);
			Format(sMessageS, sizeof(sMessageS), "%s\n %s ", sMessageS, sVisualisation);
			Format(sMessageS, sizeof(sMessageS), "%s\n══════^══════", sMessageS);
			
			
			// get the text color
			//GetPercentageColor(AveragePercentage, strafergb[0], strafergb[1], strafergb[2]);
			PrintCenterText(client, "%s", sMessageS);
			gI_ClientTickCount[client] = 0;

		}
		else
		{
			// save the percentage to an array to calculate the average later
			gF_ClientPercentages[client][gI_ClientTickCount[client]] = Percentage;
			gI_ClientTickCount[client]++;
		}
	}
	gF_LastAngle[client] = angles;

	if(cmdnum % 7 == 0)
	{
		if(!blockchanel[3])
		{
			char sMessageSpeed[8];
			int clr[3];
			int speedo = RoundFloat( GetEntitySpeed( client ) );

			if(g_iPrevSpeed[client] < speedo)
				clr = colour[1];

			else if(g_iPrevSpeed[client] > speedo)
				clr = colour[2];

			else
				clr = colour[0];

			//Format( sMessageSpeed, sizeof( sMessageSpeed ), "%s%03.0f",sMessageSpeed,speedo );
			if(!g_bConstSpeed[client])
			{
				clr[0] = 0;
				clr[1] = 0;
				clr[2] = 0;
			}
			Format( sMessageSpeed, sizeof( sMessageSpeed ), "%i",speedo );
			//0.3
			SetHudTextParams(-1.0, speedpos, 1.0, clr[0], clr[1], clr[2], 255, 0, 1.0, 0.0, 0.0);
			ShowHudText(client, 3, sMessageSpeed);
			g_iPrevSpeed[client] = speedo; 
		}


		if(!blockchanel[4])
		{
			if(updatedjhud)
			{
				if(showticks > 79)
				{
					showticks = 0;
					updatedjhud = false;
					Format(sMessage, sizeof(sMessage),"");
				}
			}

			SetHudTextParams(-1.0, JhudPos, 1.0, rgb[0], rgb[1], rgb[2], 255, 0, 1.0, 0.0, 0.0);
			ShowHudText(client, 4, sMessage);
		}

		if(!blockchanel[5])
		{
			SetHudTextParams(0.01, 0.01, 1.0, colour[7][0], colour[7][1], colour[7][2], 255, 0, 1.0, 0.0, 0.0);
			ShowHudText(client, 5, sTopLeft);
		}

		//g_iPrevSpeed[client] = speedo; 
	}
	return Plugin_Continue;
}

stock float NormalizeAngle(float ang)
{
	if(ang > 180.0)
	{
		ang -= 360.0;
	}
	else if(ang < -180.0)
	{
		ang += 360.0;
	}
	
	return ang;
}

stock bool IsNaN(float x)
{
	return x != x;
}

public Action Command_JHUDColor(int client, int args)
{
	if(client != 0)
	{
		char info[18];
		char info1[18];
		int r;
		int g;
		int b;
		bool isrgb = false;
		bool ishex = false;
		bool isinvalid = false;
		if (args == 1)
		{
			ishex = true;
			GetCmdArg(1, info1, sizeof(info1));
			ReplaceString(info1, sizeof(info1), "#", "", false);
			if( !HexStringToRGB(info1, _, _, _, _) )
				isinvalid = true;
		}

		if(args == 3)
		{
			isrgb = true;
			GetCmdArg(1, info1, sizeof(info1));
			r = StringToInt(info1);
			GetCmdArg(2, info1, sizeof(info1));
			g = StringToInt(info1);
			GetCmdArg(3, info1, sizeof(info1));
			b = StringToInt(info1);
			if(!IsValidNumber(r) || !IsValidNumber(g) || !IsValidNumber(b))
				isinvalid = true;
		}

		GetCmdArg(0, info, sizeof(info));
		if(StrEqual(info, "sm_speedcolor"))
		{
			if(ishex)
			{
				if(!isinvalid)
				{
					Shavit_PrintToChat(client, "%sSetting speedcolor to:\x07%s %s%s!", gS_ChatStrings.sText,info1,info1,gS_ChatStrings.sText);
					strcopy(constspeed, sizeof(constspeed), info1);
					HexStringToRGB(constspeed, _, colour[0][0], colour[0][1], colour[0][2]);
					SetClientCookie(client, g_hCookieSpeedColor, constspeed);
					return Plugin_Handled;
				}
				else
				{
					Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !speedcolor \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !speedcolor \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
					return Plugin_Handled;
				}
			}
			else if(isrgb)
			{
				if(!isinvalid)
				{
					Shavit_PrintToChat(client, "%sSetting speedcolor to:\x07%02X%02X%02X %02X%02X%02X%s!", gS_ChatStrings.sText,r, g, b,r, g, b,gS_ChatStrings.sText);
					Format(constspeed, sizeof(constspeed), "%02X%02X%02X",r, g, b);
					HexStringToRGB(constspeed, _, colour[0][0], colour[0][1], colour[0][2]);
					SetClientCookie(client, g_hCookieSpeedColor, constspeed);
					return Plugin_Handled;
				}
				else
				{
					Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !speedcolor \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !speedcolor \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
					return Plugin_Handled;
				}
			}
			else
			{
				Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !speedcolor \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !speedcolor \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
				return Plugin_Handled;
			}
		}
		else if(StrEqual(info, "sm_speedgain"))
		{
			if(ishex)
			{
				if(!isinvalid)
				{
					Shavit_PrintToChat(client, "%sSetting speedgain to:\x07%s %s%s!", gS_ChatStrings.sText,info1,info1,gS_ChatStrings.sText);
					strcopy(constspeed_gain, sizeof(constspeed_gain), info1);
					HexStringToRGB(constspeed_gain, _, colour[1][0], colour[1][1], colour[1][2]);
					SetClientCookie(client, g_hCookieSpeedColorGain, constspeed_gain);
					return Plugin_Handled;
				}
				else
				{
					Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !speedgain \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !speedgain \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
					return Plugin_Handled;
				}
			}
			else if(isrgb)
			{
				if(!isinvalid)
				{
					Shavit_PrintToChat(client, "%sSetting speedgain to:\x07%02X%02X%02X %02X%02X%02X%s!", gS_ChatStrings.sText,r, g, b,r, g, b,gS_ChatStrings.sText);
					Format(constspeed_gain, sizeof(constspeed_gain), "%02X%02X%02X",r, g, b);
					HexStringToRGB(constspeed_gain, _, colour[1][0], colour[1][1], colour[1][2]);
					SetClientCookie(client, g_hCookieSpeedColorGain, constspeed_gain);
					return Plugin_Handled;
				}
				else
				{
					Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !speedgain \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !speedgain \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
					return Plugin_Handled;
				}
			}
			else
			{
				Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !speedgain \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !speedgain \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
				return Plugin_Handled;
			}
		}
		else if(StrEqual(info, "sm_speedloss"))
		{
			if(ishex)
			{
				if(!isinvalid)
				{
					Shavit_PrintToChat(client, "%sSetting speedloss to:\x07%s %s%s!", gS_ChatStrings.sText,info1,info1,gS_ChatStrings.sText);
					strcopy(constspeed_loss, sizeof(constspeed_loss), info1);
					HexStringToRGB(constspeed_loss, _, colour[2][0], colour[2][1], colour[2][2]);
					SetClientCookie(client, g_hCookieSpeedColorLoss, constspeed_loss);
					return Plugin_Handled;
				}
				else
				{
					Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !speedloss \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !speedloss \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
					return Plugin_Handled;
				}
			}
			else if(isrgb)
			{
				if(!isinvalid)
				{
					Shavit_PrintToChat(client, "%sSetting speedloss to:\x07%02X%02X%02X %02X%02X%02X%s!", gS_ChatStrings.sText,r, g, b,r, g, b,gS_ChatStrings.sText);
					Format(constspeed_loss, sizeof(constspeed_loss), "%02X%02X%02X",r, g, b);
					HexStringToRGB(constspeed_loss, _, colour[2][0], colour[2][1], colour[2][2]);
					SetClientCookie(client, g_hCookieSpeedColorLoss, constspeed_loss);
					return Plugin_Handled;
				}
				else
				{
					Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !speedloss \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !speedloss \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
					return Plugin_Handled;
				}
			}
			else
			{
				Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !speedloss \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !speedloss \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
				return Plugin_Handled;
			}
		}
		else if(StrEqual(info, "sm_under60"))
		{
			if(ishex)
			{
				if(!isinvalid)
				{
					Shavit_PrintToChat(client, "%sSetting under60 to:\x07%s %s%s!", gS_ChatStrings.sText,info1,info1,gS_ChatStrings.sText);
					strcopy(c60_gain, sizeof(c60_gain), info1);
					HexStringToRGB(c60_gain, _, colour[3][0], colour[3][1], colour[3][2]);
					SetClientCookie(client, g_hCookie60, c60_gain);
					return Plugin_Handled;
				}
				else
				{
					Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !under60 \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !under60 \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
					return Plugin_Handled;
				}
			}
			else if(isrgb)
			{
				if(!isinvalid)
				{
					Shavit_PrintToChat(client, "%sSetting under60 to:\x07%02X%02X%02X %02X%02X%02X%s!", gS_ChatStrings.sText,r, g, b,r, g, b,gS_ChatStrings.sText);
					Format(c60_gain, sizeof(c60_gain), "%02X%02X%02X",r, g, b);
					HexStringToRGB(c60_gain, _, colour[3][0], colour[3][1], colour[3][2]);
					SetClientCookie(client, g_hCookie60, c60_gain);
					return Plugin_Handled;
				}
				else
				{
					Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !under60 \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !under60 \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
					return Plugin_Handled;
				}
			}
			else
			{
				Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !under60 \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !under60 \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
				return Plugin_Handled;
			}
		}
		else if(StrEqual(info, "sm_under70"))
		{
			if(ishex)
			{
				if(!isinvalid)
				{
					Shavit_PrintToChat(client, "%sSetting under70 to:\x07%s %s%s!", gS_ChatStrings.sText,info1,info1,gS_ChatStrings.sText);
					strcopy(c70_gain, sizeof(c70_gain), info1);
					HexStringToRGB(c70_gain, _, colour[4][0], colour[4][1], colour[4][2]);
					SetClientCookie(client, g_hCookie6070, c70_gain);
					return Plugin_Handled;
				}
				else
				{
					Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !under70 \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !under70 \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
					return Plugin_Handled;
				}
			}
			else if(isrgb)
			{
				if(!isinvalid)
				{
					Shavit_PrintToChat(client, "%sSetting under70 to:\x07%02X%02X%02X %02X%02X%02X%s!", gS_ChatStrings.sText,r, g, b,r, g, b,gS_ChatStrings.sText);
					Format(c70_gain, sizeof(c70_gain), "%02X%02X%02X",r, g, b);
					HexStringToRGB(c70_gain, _, colour[4][0], colour[4][1], colour[4][2]);
					SetClientCookie(client, g_hCookie6070, c70_gain);
					return Plugin_Handled;
				}
				else
				{
					Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !under70 \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !under70 \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
					return Plugin_Handled;
				}
			}
			else
			{
				Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !under70 \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !under70 \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
				return Plugin_Handled;
			}
		}
		else if(StrEqual(info, "sm_under80"))
		{
			if(ishex)
			{
				if(!isinvalid)
				{
					Shavit_PrintToChat(client, "%sSetting under80 to:\x07%s %s%s!", gS_ChatStrings.sText,info1,info1,gS_ChatStrings.sText);
					strcopy(c80_gain, sizeof(c80_gain), info1);
					HexStringToRGB(c80_gain, _, colour[5][0], colour[5][1], colour[5][2]);
					SetClientCookie(client, g_hCookie7080, c80_gain);
					return Plugin_Handled;
				}
				else
				{
					Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !under80 \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !under80 \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
					return Plugin_Handled;
				}
			}
			else if(isrgb)
			{
				if(!isinvalid)
				{
					Shavit_PrintToChat(client, "%sSetting under80 to:\x07%02X%02X%02X %02X%02X%02X%s!", gS_ChatStrings.sText,r, g, b,r, g, b,gS_ChatStrings.sText);
					Format(c80_gain, sizeof(c80_gain), "%02X%02X%02X",r, g, b);
					HexStringToRGB(c80_gain, _, colour[5][0], colour[5][1], colour[5][2]);
					SetClientCookie(client, g_hCookie7080, c80_gain);
					return Plugin_Handled;
				}
				else
				{
					Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !under80 \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !under80 \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
					return Plugin_Handled;
				}
			}
			else
			{
				Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !under80 \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !under80 \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
				return Plugin_Handled;
			}
		}
		else if(StrEqual(info, "sm_over80"))
		{
			if(ishex)
			{
				if(!isinvalid)
				{
					Shavit_PrintToChat(client, "%sSetting over80 to:\x07%s %s%s!", gS_ChatStrings.sText,info1,info1,gS_ChatStrings.sText);
					strcopy(c90_gain, sizeof(c90_gain), info1);
					HexStringToRGB(c90_gain, _, colour[6][0], colour[6][1], colour[6][2]);
					SetClientCookie(client, g_hCookie80, c90_gain);
					return Plugin_Handled;
				}
				else
				{
					Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !over80 \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !over80 \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
					return Plugin_Handled;
				}
			}
			else if(isrgb)
			{
				if(!isinvalid)
				{
					Shavit_PrintToChat(client, "%sSetting over80 to:\x07%02X%02X%02X %02X%02X%02X%s!", gS_ChatStrings.sText,r, g, b,r, g, b,gS_ChatStrings.sText);
					Format(c90_gain, sizeof(c90_gain), "%02X%02X%02X",r, g, b);
					HexStringToRGB(c90_gain, _, colour[6][0], colour[6][1], colour[6][2]);
					SetClientCookie(client, g_hCookie80, c90_gain);
					return Plugin_Handled;
				}
				else
				{
					Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !over80 \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !over80 \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
					return Plugin_Handled;
				}
			}
			else
			{
				Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !over80 \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !over80 \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
				return Plugin_Handled;
			}
		}
		else if(StrEqual(info, "sm_topleft"))
		{
			if(ishex)
			{
				if(!isinvalid)
				{
					Shavit_PrintToChat(client, "%sSetting topleft to:\x07%s %s%s!", gS_ChatStrings.sText,info1,info1,gS_ChatStrings.sText);
					strcopy(TopLeftHex, sizeof(TopLeftHex), info1);
					HexStringToRGB(TopLeftHex, _, colour[7][0], colour[7][1], colour[7][2]);
					SetClientCookie(client, g_hCookieTopLeft, TopLeftHex);
					return Plugin_Handled;
				}
				else
				{
					Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !topleft \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !topleft \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
					return Plugin_Handled;
				}
			}
			else if(isrgb)
			{
				if(!isinvalid)
				{
					Shavit_PrintToChat(client, "%sSetting topleft to:\x07%02X%02X%02X %02X%02X%02X%s!", gS_ChatStrings.sText,r, g, b,r, g, b,gS_ChatStrings.sText);
					Format(TopLeftHex, sizeof(TopLeftHex), "%02X%02X%02X",r, g, b);
					HexStringToRGB(TopLeftHex, _, colour[7][0], colour[7][1], colour[7][2]);
					SetClientCookie(client, g_hCookieTopLeft, TopLeftHex);
					return Plugin_Handled;
				}
				else
				{
					Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !topleft \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !topleft \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
					return Plugin_Handled;
				}
			}
			else
			{
				Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !topleft \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !topleft \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
				return Plugin_Handled;
			}
		}
	}
	return Plugin_Handled;
}

bool IsValidNumber(int num)
{
	if(num > -1 && num < 256)
		return true;

	return false;
}

public Action Command_JHUD(int client, any args)
{
	if(client != 0)
	{
		ShowJHUDMenu(client);
	}
	return Plugin_Handled;
}

void ShowJHUDMenu(int client, int position = 0)
{
	Menu menu = CreateMenu(JHUD_Select);
	SetMenuTitle(menu, "JHUD - Main\n \n");
	
	if(g_bJHUD[client])
	{
		AddMenuItem(menu, "usage", "JHUD: [ON]");
	}
	else
	{
		AddMenuItem(menu, "usage", "JHUD: [OFF]");
	}
	
	if(g_bStrafeSpeed[client])
	{
		AddMenuItem(menu, "strafespeed", "JSS: [ON]");
	}
	else
	{
		AddMenuItem(menu, "strafespeed", "JSS: [OFF]");
	}

	if(g_bConstSpeed[client])
	{
		AddMenuItem(menu, "constspeed", "Constant Speed: [ON]");
	}
	else
	{
		AddMenuItem(menu, "constspeed", "Constant Speed: [OFF]");
	}
	if(gB_StrafeTrainer[client])
	{
		AddMenuItem(menu, "StrafeT", "Strafe trainer: [ON]");
	}
	else
	{
		AddMenuItem(menu, "StrafeT", "Strafe trainer: [OFF]");
	}
	AddMenuItem(menu, "settings", "Settings");

	AddMenuItem(menu, "SHud", "Back To HUD Settings");

	menu.DisplayAt(client, position, MENU_TIME_FOREVER);
}

public int JHUD_Select(Menu menu, MenuAction action, int client, int option)
{
	if(action == MenuAction_Select)
	{
		char info[32];
		GetMenuItem(menu, option, info, sizeof(info));
		lastChoice = info;
		
		if(StrEqual(info, "usage"))
		{
			g_bJHUD[client] = !g_bJHUD[client];
			SetCookie(client, g_hCookieJHUD, g_bJHUD[client]);
			ShowJHUDMenu(client, GetMenuSelectionPosition());
		}
		else if(StrEqual(info, "strafespeed"))
		{
			g_bStrafeSpeed[client] = !g_bStrafeSpeed[client];
			SetCookie(client, g_hCookieStrafeSpeed, g_bStrafeSpeed[client]);
			ShowJHUDMenu(client, GetMenuSelectionPosition());
		}
		else if(StrEqual(info, "constspeed"))
		{
			g_bConstSpeed[client] = !g_bConstSpeed[client];
			SetCookie(client, g_hCookieConstantSpeed, g_bConstSpeed[client]);
			ShowJHUDMenu(client, GetMenuSelectionPosition());
		}
		else if(StrEqual(info, "StrafeT"))
		{
			gB_StrafeTrainer[client] = !gB_StrafeTrainer[client];
			SetClientCookieBool(client, gH_StrafeTrainerCookie, gB_StrafeTrainer[client]);
			ShowJHUDMenu(client, GetMenuSelectionPosition());
		}
		else if(StrEqual(info, "settings"))
		{
			ShowJHUDDisplayOptionsMenu(client);
		}
		else if(StrEqual(info, "SHud"))
		{
			ShowHUDMenu(client,0);
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}
}

void ShowJHUDDisplayOptionsMenu(int client, int position = 0)
{
	Menu menu = CreateMenu(JHUDDisplayOptionsMenu_Handler);
	SetMenuTitle(menu, "JHUD - Settings\n \n");
	
	if(g_iJHUDPosition[client] == 0)
	{
		AddMenuItem(menu, "cyclepos", "JHUD Position: [CENTER]");
	}
	else if(g_iJHUDPosition[client] == 1)
	{
		AddMenuItem(menu, "cyclepos", "JHUD Position: [TOP]");
	}
	else if(g_iJHUDPosition[client] == 2)
	{
		AddMenuItem(menu, "cyclepos", "JHUD Position: [BOTTOM]");
	}

	if(g_iJSpeedPosition[client] == 0)
	{
		AddMenuItem(menu, "speedpos", "Speed Position: [CENTER]");
	}
	else if(g_iJSpeedPosition[client] == 1)
	{
		AddMenuItem(menu, "speedpos", "Speed Position: [TOP]");
	}
	else if(g_iJSpeedPosition[client] == 2)
	{
		AddMenuItem(menu, "speedpos", "Speed Position: [BOTTOM]");
	}
	else if(g_iJSpeedPosition[client] == 3)
	{
		AddMenuItem(menu, "speedpos", "Speed Position: [TIMER]");
	}

	if(g_bSpeedDisplay[client])
	{
		AddMenuItem(menu, "speeddisp", "Strafe Analyzer: [ON]");
	}
	else
	{
		AddMenuItem(menu, "speeddisp", "Strafe Analyzer: [OFF]");
	}
	
	if(g_bExtraJumps[client])
	{
		AddMenuItem(menu, "extrajumps", "Extra Jumps: [ON]\n \n");
	}
	else
	{
		AddMenuItem(menu, "extrajumps", "Extra Jumps: [OFF]\n \n");
	}

	if(allowblock)
	{
		AddMenuItem(menu, "blockz", "Block your HUD when a map HUD is shown: [ON]\n \n");
	}
	else
	{
		AddMenuItem(menu, "blockz", "Block your HUD when a map HUD is shown: [OFF]\n \n");
	}

	AddMenuItem(menu, "colors", "Color Settings\n \n");
	AddMenuItem(menu, "reset", "Reset to default values");

	char buffer[64];
	Format( buffer, sizeof(buffer), "++\nCount JHUD until ( 0 to alway count ): %i", jhudfinish );
	AddMenuItem(menu, "+", buffer );
	if(jhudfinish<1)
	{
		AddMenuItem(menu, "-", "--\n \n",ITEMDRAW_DISABLED );
	}
	else
	{
		AddMenuItem(menu, "-", "--\n \n" );
	}
	menu.ExitBackButton = true;
	menu.DisplayAt(client, position, MENU_TIME_FOREVER);
}

public int JHUDDisplayOptionsMenu_Handler(Menu menu, MenuAction action, int client, int option)
{
	if(action == MenuAction_Cancel && option == MenuCancel_ExitBack)
	{
		ShowJHUDMenu(client);
	}
	else if(action == MenuAction_Select)
	{
		char info[32];
		GetMenuItem(menu, option, info, sizeof(info));
		lastChoice = info;
		
		if(StrEqual(info, "cyclepos"))
		{
			if(++g_iJHUDPosition[client] < 3)
			{
				SetCookie(client, g_hCookieJHUDPosition, g_iJHUDPosition[client]);
				ShowJHUDDisplayOptionsMenu(client);
			}
			else
			{
				g_iJHUDPosition[client] = 0;
				SetCookie(client, g_hCookieJHUDPosition, g_iJHUDPosition[client]);
				ShowJHUDDisplayOptionsMenu(client);
			}
		}
		if(StrEqual(info, "speedpos"))
		{
			if(++g_iJSpeedPosition[client] < 4)
			{
				GetSpeedPos(client);
				SetCookie(client, g_hCookieSPEEDPosition, g_iJSpeedPosition[client]);
				ShowJHUDDisplayOptionsMenu(client);
			}
			else
			{
				g_iJSpeedPosition[client] = 0;
				GetSpeedPos(client);
				SetCookie(client, g_hCookieSPEEDPosition, g_iJSpeedPosition[client]);
				ShowJHUDDisplayOptionsMenu(client);
			}
		}
		else if(StrEqual(info, "speeddisp"))
		{
			g_bSpeedDisplay[client] = !g_bSpeedDisplay[client];
			SetCookie(client, g_hCookieSpeedDisplay, g_bSpeedDisplay[client]);
			ShowJHUDDisplayOptionsMenu(client);
		}
		else if(StrEqual(info, "extrajumps"))
		{
			g_bExtraJumps[client] = !g_bExtraJumps[client];
			SetCookie(client, g_hCookieExtraJumps, g_bExtraJumps[client]);
			ShowJHUDDisplayOptionsMenu(client, GetMenuSelectionPosition());
		}
		else if(StrEqual(info, "blockz"))
		{
			allowblock = !allowblock;
			SetCookie(client, g_hCookieHUDBlock, allowblock);
			ShowJHUDDisplayOptionsMenu(client, GetMenuSelectionPosition());
		}
		else if(StrEqual(info, "colors"))
		{
			ShowJHUDColorMenu(client);
		}
		else if(StrEqual(info, "reset"))
		{
			JHUD_ResetMenu(client);
		}
		else if(StrEqual(info, "+"))
		{
			jhudfinish++;
			SetCookie( client, g_hCookieFinishInterval, jhudfinish );
			ShowJHUDDisplayOptionsMenu(client, GetMenuSelectionPosition());
		}
		else if(StrEqual(info, "-"))
		{
			jhudfinish--;
			SetCookie( client, g_hCookieFinishInterval, jhudfinish );
			ShowJHUDDisplayOptionsMenu(client, GetMenuSelectionPosition());
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}
}

void ShowJHUDColorMenu(int client, int position = 0)
{
	Menu menu = CreateMenu(JHUDColorMenu_Handler);
	SetMenuTitle(menu, "JHUD - Settings - Color\n \n");

	AddMenuItem(menu, "0", "Constant Speed");
	AddMenuItem(menu, "1", "Constant Speed Gain");
	AddMenuItem(menu, "2", "Constant Speed Loss");
	AddMenuItem(menu, "3", "< 60 Gain");
	AddMenuItem(menu, "4", "60-70 Gain");
	AddMenuItem(menu, "5", "70-80 Gain");
	AddMenuItem(menu, "6", "> 80 Gain");
	//AddMenuItem(menu, "7", "Top Left");

	menu.ExitBackButton = true;
	menu.DisplayAt(client, position, MENU_TIME_FOREVER);
}

public int JHUDColorMenu_Handler(Menu menu, MenuAction action, int client, int option)
{
	if(action == MenuAction_Cancel && option == MenuCancel_ExitBack)
	{
		ShowJHUDDisplayOptionsMenu(client);
	}
	if(action == MenuAction_Select)
	{
		char info[32];
		GetMenuItem(menu, option, info, sizeof(info));
		int id = StringToInt(info);
		OpenColorsMenu(client,id);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

}

void OpenColorsMenu( int client, int id, int position = 0 )
{
	Menu menu = CreateMenu(OpenColorsMenu_Handler);
	//char Color[6]="00FFB3";
	int r, g, b;
	char Choice[32];
	char CTitle[32];
	char Choicebuffer[11][5];

	switch(id)
	{
		case 0: 
		{
			Format(CTitle, sizeof(CTitle), "Constant Speed");
			Format(Choice, sizeof(Choice), "%s", constspeed);
		}
		case 1: 
		{	
			Format(CTitle, sizeof(CTitle), "Constant Speed Gain");
			Format(Choice, sizeof(Choice), "%s", constspeed_gain);
		}
		case 2: 
		{
			Format(CTitle, sizeof(CTitle), "Constant Speed Loss");
			Format(Choice, sizeof(Choice), "%s", constspeed_loss);
		}
		case 3: 
		{
			Format(CTitle, sizeof(CTitle), "< 60 Gain");
			Format(Choice, sizeof(Choice), "%s", c60_gain);
		}
		case 4:
		{
			Format(CTitle, sizeof(CTitle), "60-70 Gain");
			Format(Choice, sizeof(Choice), "%s", c70_gain);
		}
		case 5: 
		{
			Format(CTitle, sizeof(CTitle), "70-80 Gain");
			Format(Choice, sizeof(Choice), "%s", c80_gain);
		}
		case 6: 
		{
			Format(CTitle, sizeof(CTitle), "> 80 Gain");
			Format(Choice, sizeof(Choice), "%s", c90_gain);
		}
		case 7: 
		{
			Format(CTitle, sizeof(CTitle), "Top Left");
			Format(Choice, sizeof(Choice), "%s", TopLeftHex);
		}
	}

	for(int i = 0; i < 11; i++)
		Format(Choicebuffer[i], 5, "%i_%i", id,i);

	HexStringToRGB(Choice, _, r, g, b);
	GetColorFromHex(Choice);

	SetMenuTitle(menu, "JHUD - Settings - Color\n%s: %s\n \n",CTitle,ColorSelection);

	AddMenuItem(menu, Choicebuffer[0], "White", drawcolor==0 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	AddMenuItem(menu, Choicebuffer[1], "Red", drawcolor==1 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	AddMenuItem(menu, Choicebuffer[2], "Cyan", drawcolor==2 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	AddMenuItem(menu, Choicebuffer[3], "Purple", drawcolor==3 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	AddMenuItem(menu, Choicebuffer[4], "Green", drawcolor==4 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	AddMenuItem(menu, Choicebuffer[5], "Blue", drawcolor==5 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	AddMenuItem(menu, Choicebuffer[6], "Yellow", drawcolor==6 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	AddMenuItem(menu, Choicebuffer[7], "Orange", drawcolor==7 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	AddMenuItem(menu, Choicebuffer[8], "Gray", drawcolor==8 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	AddMenuItem(menu, Choicebuffer[9], "Own", drawcolor==9 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

	if(id==7)
	{
		char bck[8];
		Format(bck, 8, "%i_bck", id);
		AddMenuItem(menu, bck, "Back");
	}

	if(id<7)
		menu.ExitBackButton = true;

	menu.DisplayAt(client, position, MENU_TIME_FOREVER);
}

public int OpenColorsMenu_Handler(Menu menu, MenuAction action, int client, int option)
{
	char info[8];
	GetMenuItem(menu, option, info, sizeof(info));
	char tempy[2][4];
	ExplodeString(info, "_", tempy, sizeof(tempy), sizeof(tempy[]));
	int id = StringToInt(tempy[0]);
	int selection = StringToInt(tempy[1]);
	if(option == MenuCancel_ExitBack)
	{
		ShowJHUDColorMenu(client);
	}
	if(action == MenuAction_Select)
	{
		if(StrEqual(tempy[1],"bck"))
			ShowHUDMenu(client, 7);

		else
		{
			if(selection == 9)
			{
				OwnSelection(client,id);
			}
			else
			{
				SelectionSave(client,id,selection);
				OpenColorsMenu(client,id, GetMenuSelectionPosition());
			}
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}
}

void OwnSelection(int client, int id)
{
	switch(id)
	{
		case 0: Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !speedcolor \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !speedcolor \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
		case 1: Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !speedgain \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !speedgain \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
		case 2: Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !speedloss \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !speedloss \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
		case 3: Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !under60 \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !under60 \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
		case 4: Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !under70 \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !under70 \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
		case 5: Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !under80 \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !under80 \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
		case 6: Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !over80 \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !over80 \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
		case 7: Shavit_PrintToChat(client, "%sUsage:\x07fc03e8 !topleft \x07fff700<HEX value> \x07ffffffor\x07fc03e8 !topleft \x07ff0000<red> \x0700ff00<green> \x070000ff<blue>\x07ffffff!", gS_ChatStrings.sText);
	}
}
void SelectionSave(int client, int id, int selection)
{
	SelectionToHex(selection);
	switch(id)
	{
		case 0: 
		{
			strcopy(constspeed, sizeof(constspeed), ColorHex);
			HexStringToRGB(constspeed, _, colour[id][0], colour[id][1], colour[id][2]);
			SetClientCookie(client, g_hCookieSpeedColor, constspeed);
		}
		case 1: 
		{	
			strcopy(constspeed_gain, sizeof(constspeed_gain), ColorHex);
			HexStringToRGB(constspeed_gain, _, colour[id][0], colour[id][1], colour[id][2]);
			SetClientCookie(client, g_hCookieSpeedColorGain, constspeed_gain);
		}
		case 2: 
		{
			strcopy(constspeed_loss, sizeof(constspeed_loss), ColorHex);
			HexStringToRGB(constspeed_loss, _, colour[id][0], colour[id][1], colour[id][2]);
			SetClientCookie(client, g_hCookieSpeedColorLoss, constspeed_loss);
		}
		case 3: 
		{
			strcopy(c60_gain, sizeof(c60_gain), ColorHex);
			HexStringToRGB(c60_gain, _, colour[id][0], colour[id][1], colour[id][2]);
			SetClientCookie(client, g_hCookie60, c60_gain);
		}
		case 4: 
		{
			strcopy(c70_gain, sizeof(c70_gain), ColorHex);
			HexStringToRGB(c70_gain, _, colour[id][0], colour[id][1], colour[id][2]);
			SetClientCookie(client, g_hCookie6070, c70_gain);
		}
		case 5: 
		{
			strcopy(c80_gain, sizeof(c80_gain), ColorHex);
			HexStringToRGB(c80_gain, _, colour[id][0], colour[id][1], colour[id][2]);
			SetClientCookie(client, g_hCookie7080, c80_gain);
		}
		case 6: 
		{
			strcopy(c90_gain, sizeof(c90_gain), ColorHex);
			HexStringToRGB(c90_gain, _, colour[id][0], colour[id][1], colour[id][2]);
			SetClientCookie(client, g_hCookie80, c90_gain);
		}
		case 7: 
		{
			strcopy(TopLeftHex, sizeof(TopLeftHex), ColorHex);
			HexStringToRGB(TopLeftHex, _, colour[id][0], colour[id][1], colour[id][2]);
			SetClientCookie(client, g_hCookieTopLeft, TopLeftHex);
		}
	}
}

void SelectionToHex(int selection)
{
	switch(selection)
	{
		case 0: Format(ColorHex, sizeof(ColorHex), "ffffff");
		case 1: Format(ColorHex, sizeof(ColorHex), "ff0000");
		case 2: Format(ColorHex, sizeof(ColorHex), "00ffff");
		case 3: Format(ColorHex, sizeof(ColorHex), "800080");
		case 4: Format(ColorHex, sizeof(ColorHex), "00ff00");
		case 5: Format(ColorHex, sizeof(ColorHex), "0000ff");
		case 6: Format(ColorHex, sizeof(ColorHex), "ffff00");
		case 7: Format(ColorHex, sizeof(ColorHex), "ffa024");
		case 8: Format(ColorHex, sizeof(ColorHex), "808080");
	}
}

void GetColorFromHex(const char[] Choice)
{
	if(StrEqual(Choice, "ffffff"))
	{
		drawcolor = 0;
		strcopy(ColorSelection, sizeof(ColorSelection), "White");
	}

	else if(StrEqual(Choice, "ff0000"))
	{
		drawcolor = 1;
		strcopy(ColorSelection, sizeof(ColorSelection), "Red");
	}

	else if(StrEqual(Choice, "00ffff"))
	{
		drawcolor = 2;
		strcopy(ColorSelection, sizeof(ColorSelection), "Cyan");
	}

	else if(StrEqual(Choice, "800080"))
	{
		drawcolor = 3;
		strcopy(ColorSelection, sizeof(ColorSelection), "Purple");
	}

	else if(StrEqual(Choice, "00ff00"))
	{
		drawcolor = 4;
		strcopy(ColorSelection, sizeof(ColorSelection), "Green");
	}

	else if(StrEqual(Choice, "0000ff"))
	{
		drawcolor = 5;
		strcopy(ColorSelection, sizeof(ColorSelection), "Blue");
	}

	else if(StrEqual(Choice, "ffff00"))
	{
		drawcolor = 6;
		strcopy(ColorSelection, sizeof(ColorSelection), "Yellow");
	}

	else if(StrEqual(Choice, "ffa024"))
	{
		drawcolor = 7;
		strcopy(ColorSelection, sizeof(ColorSelection), "Orange");
	}

	else if(StrEqual(Choice, "808080"))
	{
		drawcolor = 8;
		strcopy(ColorSelection, sizeof(ColorSelection), "Gray");
	}

	else
	{
		drawcolor = 9;
		strcopy(ColorSelection, sizeof(ColorSelection), "Own");
	}
}

//https://forums.alliedmods.net/showthread.php?t=187746
bool HexStringToRGB(const char[] ColorString,int &CHex=0,int &r=0,int &g=0,int &b=0)
{
	int length = strlen(ColorString);
	if(length != 6)
	{
		return false;
	}

	for(int i = 0; i < length; i++)
	{
		if(IsCharAlpha(ColorString[i]))
		{
			if( !(65 <= ColorString[i] <= 70 || 97 <= ColorString[i] <= 102) ) // Only letters ABCDEF
			{
				return false;
			}
		}
	}


	StringToIntEx(ColorString, CHex, 16);


	r = ((CHex >> 16) & 255);
	g = ((CHex >> 8) & 255);
	b = ((CHex >> 0) & 255);

	return true;
}

void JHUD_ResetMenu(int client, int position = 0)
{
	Menu menu = CreateMenu(JHUD_ResetMenu_Handler);
	SetMenuTitle(menu, "JHUD - Reset to Default\n \n");
	
	AddMenuItem(menu, "yes", "Confirm");
	AddMenuItem(menu, "no", "Cancel");
	
	menu.ExitBackButton = true;
	menu.DisplayAt(client, position, MENU_TIME_FOREVER);
}

public int JHUD_ResetMenu_Handler(Menu menu, MenuAction action, int client, int option)
{
	if(action == MenuAction_Cancel && option == MenuCancel_ExitBack)
	{
		ShowJHUDDisplayOptionsMenu(client);
	}
	if(action == MenuAction_Select)
	{
		char info[32];
		GetMenuItem(menu, option, info, sizeof(info));
		lastChoice = info;
		
		if(StrEqual(info, "yes"))
		{
			JHUD_ResetValues(client,true);
			ShowJHUDMenu(client);
		}
		else if(StrEqual(info, "no"))
		{
			ShowJHUDDisplayOptionsMenu(client);
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}
}

void GetTimerClr(int client)
{
	bool SJWR = true;
	if((gI_HUDSettings[client] & HUD_SPECTATORS) == 0)
		SJWR = false;

	if(SJWR && strlen(sjtext) < 2)
	{
		ArrayList records;

		if (!gS_Maps.GetValue(gS_CurrentMap, records) || !records || !records.Length)
		{
			CreateTimer(1.0, Retry, client, TIMER_REPEAT);
			SJWR = false;
		}

		int style = Shavit_GetBhopStyle(client);
		int track = Shavit_GetClientTrack(client);

		if ( style != 0 || track != 0)
		{
			CreateTimer(1.0, Retry, client, TIMER_REPEAT);
			SJWR = false;
		}

		if(SJWR)
		{
			RecordInfo info;
			records.GetArray(0, info);
			FormatEx(sjtext, sizeof(sjtext), "SJ: %s (%s) (T%d)", info.time, info.name, info.tier);
		}
	}

	if((gI_HUDSettings[client] & HUD_TOPLEFT) > 0)
	{
		if(SJWR)
		{
			int style = Shavit_GetBhopStyle(client);
			int track = Shavit_GetClientTrack(client);

			float fWRTime = Shavit_GetWorldRecord(style, track);

			if(fWRTime != 0.0)
			{
				char sWRTime[16];
				FormatSeconds(fWRTime, sWRTime, 16);

				char sWRName[MAX_NAME_LENGTH];
				Shavit_GetWRName(style, sWRName, MAX_NAME_LENGTH, track);

				FormatEx(sTopLeftOld, 128, "Best: %s (%s)", sWRTime, sWRName);
			}
			Format(sTopLeftOld,128,"%s \n%s",sTopLeftOld,sjtext);
			strcopy(sTopLeft, 256, sTopLeftOld);
		}
		else
		{
			int style = Shavit_GetBhopStyle(client);
			int track = Shavit_GetClientTrack(client);

			float fWRTime = Shavit_GetWorldRecord(style, track);

			if(fWRTime != 0.0)
			{
				char sWRTime[16];
				FormatSeconds(fWRTime, sWRTime, 16);

				char sWRName[MAX_NAME_LENGTH];
				Shavit_GetWRName(style, sWRName, MAX_NAME_LENGTH, track);

				FormatEx(sTopLeftOld, 128, "Best: %s (%s)", sWRTime, sWRName);
			}
			strcopy(sTopLeft, 256, sTopLeftOld);
		}
	}

	else
		FormatEx(sTopLeft, 256, "");
}

public Action Retry(Handle timer, int client)
{
	static int xtry = 0;
 
	if (xtry >= 5) 
	{
		xtry = 0;
		return Plugin_Stop;
	}
 
	bool SJWR = true;
	if((gI_HUDSettings[client] & HUD_SPECTATORS) == 0)
		SJWR = false;

	if(SJWR)
	{
		ArrayList records;

		if (!gS_Maps.GetValue(gS_CurrentMap, records) || !records || !records.Length)
			SJWR = false;

		int style = Shavit_GetBhopStyle(client);
		int track = Shavit_GetClientTrack(client);

		if ( style != 0 || track != 0)
			SJWR = false;

		if(SJWR)
		{
			RecordInfo info;
			records.GetArray(0, info);
			FormatEx(sjtext, sizeof(sjtext), "SJ: %s (%s) (T%d)", info.time, info.name, info.tier);
		}
	}
	xtry++;
 
	return Plugin_Continue;
}

void GetSpeedPos(int client)
{
	if(g_iJSpeedPosition[client] == 0)
	{
		speedpos = -1.0;
	}
	else if(g_iJSpeedPosition[client] == 1)
	{
		speedpos = 0.4;
	}
	else if(g_iJSpeedPosition[client] == 2)
	{
		speedpos = -0.4;
	}
	else if(g_iJSpeedPosition[client] == 3)
	{
		speedpos = 0.78;
	}
}

void JHUD_ResetValues(int client, bool frommenu)
{
	g_bConstSpeed[client] = true;
	g_bStrafeSpeed[client] = false;
	g_bExtraJumps[client] = false;
	g_bSpeedDisplay[client] = false;
	g_iJHUDPosition[client] = 1;
	g_iJSpeedPosition[client] = 2;
	speedpos = -0.4;
	jhudfinish = 16;

	if(frommenu)
	{
		FormatEx(sTopLeftOld, 128, "");
		int style = Shavit_GetBhopStyle(client);
		int track = Shavit_GetClientTrack(client);

		float fWRTime = Shavit_GetWorldRecord(style, track);

		if(fWRTime != 0.0)
		{
			char sWRTime[16];
			FormatSeconds(fWRTime, sWRTime, 16);

			char sWRName[MAX_NAME_LENGTH];
			Shavit_GetWRName(style, sWRName, MAX_NAME_LENGTH, track);

			FormatEx(sTopLeftOld, 128, "Best: %s (%s)", sWRTime, sWRName);
		}
		GetTimerClr(client);
	}

	strcopy(constspeed, sizeof(constspeed), "ffffff");
	strcopy(constspeed_gain, sizeof(constspeed_gain), "00ffff");
	strcopy(constspeed_loss, sizeof(constspeed_loss), "ffa024");
	strcopy(c60_gain, sizeof(c60_gain),"ff0000");
	strcopy(c70_gain, sizeof(c70_gain), "ffa024");
	strcopy(c80_gain, sizeof(c80_gain), "00ff00");
	strcopy(c90_gain, sizeof(c90_gain), "00ffff");
	strcopy(TopLeftHex, sizeof(TopLeftHex), "ffffff");

	HexStringToRGB(constspeed, _, colour[0][0], colour[0][1], colour[0][2]);
	HexStringToRGB(constspeed_gain, _, colour[1][0], colour[1][1], colour[1][2]);
	HexStringToRGB(constspeed_loss, _, colour[2][0], colour[2][1], colour[2][2]);
	HexStringToRGB(c60_gain, _, colour[3][0], colour[3][1], colour[3][2]);
	HexStringToRGB(c70_gain, _, colour[4][0], colour[4][1], colour[4][2]);
	HexStringToRGB(c80_gain, _, colour[5][0], colour[5][1], colour[5][2]);
	HexStringToRGB(c90_gain, _, colour[6][0], colour[6][1], colour[6][2]);
	HexStringToRGB(TopLeftHex, _, colour[7][0], colour[7][1], colour[7][2]);

	SetCookie(client, g_hCookieConstantSpeed, g_bConstSpeed[client]);
	SetCookie(client, g_hCookieStrafeSpeed, g_bStrafeSpeed[client]);
	SetCookie(client, g_hCookieExtraJumps, g_bExtraJumps[client]);
	SetCookie(client, g_hCookieSpeedDisplay, g_bSpeedDisplay[client]);
	SetCookie(client, g_hCookieJHUDPosition, g_iJHUDPosition[client]);
	SetCookie(client, g_hCookieSPEEDPosition, g_iJSpeedPosition[client]);
	SetCookie(client, g_hCookieFinishInterval, jhudfinish);

	SetClientCookie(client, g_hCookieSpeedColor, constspeed);
	SetClientCookie(client, g_hCookieSpeedColorGain, constspeed_gain);
	SetClientCookie(client, g_hCookieSpeedColorLoss, constspeed_loss);

	SetClientCookie(client, g_hCookie60, c60_gain);
	SetClientCookie(client, g_hCookie6070, c70_gain);
	SetClientCookie(client, g_hCookie7080, c80_gain);
	SetClientCookie(client, g_hCookie80, c90_gain);
	SetClientCookie(client, g_hCookieTopLeft, TopLeftHex);
}

void JHUD_GetStats(int client, float vel[3], float angles[3])
{
	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
	
	float gaincoeff;
	g_strafeTick[client]++;
	
	float fore[3], side[3], wishvel[3], wishdir[3];
	float wishspeed, wishspd, currentgain;
	
	GetAngleVectors(angles, fore, side, NULL_VECTOR);
	
	fore[2] = 0.0;
	side[2] = 0.0;
	NormalizeVector(fore, fore);
	NormalizeVector(side, side);
	
	for(int i = 0; i < 2; i++)
	{
		wishvel[i] = fore[i] * vel[0] + side[i] * vel[1];
	}
	
	wishspeed = NormalizeVector(wishvel, wishdir);
	if(wishspeed > GetEntPropFloat(client, Prop_Send, "m_flMaxspeed") && GetEntPropFloat(client, Prop_Send, "m_flMaxspeed") != 0.0)
	{
		wishspeed = GetEntPropFloat(client, Prop_Send, "m_flMaxspeed");
	}
	
	if(wishspeed)
	{
		wishspd = (wishspeed > 30.0) ? 30.0 : wishspeed;
		
		currentgain = GetVectorDotProduct(velocity, wishdir);
		if(currentgain < 30.0)
		{
			gaincoeff = (wishspd - FloatAbs(currentgain)) / wishspd;
		}
		
		if(g_bTouchesWall[client] && g_iTouchTicks[client] && gaincoeff > 0.5)
		{
			gaincoeff -= 1;
			gaincoeff = FloatAbs(gaincoeff);
		}
		
		g_flRawGain[client] += gaincoeff;
	}
}

void JHUD_DrawStats(int client, int target)
{
	float totalPercent = ((g_fTotalNormalDelta[target] / g_fTotalPerfectDelta[target]) * 100.0);
	
	float velocity[3];
	GetEntPropVector(target, Prop_Data, "m_vecAbsVelocity", velocity);
	velocity[2] = 0.0;
	
	float coeffsum = g_flRawGain[target];
	coeffsum /= g_strafeTick[target];
	coeffsum *= 100.0;
	
	coeffsum = RoundToFloor(coeffsum * 100.0 + 0.5) / 100.0;
	
	char slowbuffer[256], fastbuffer[256];
	if(g_bSpeedDisplay[client])
	{
		if(g_bSpeedDiff[client])
		{
			Format(fastbuffer, sizeof(fastbuffer), "▼ ");
			Format(slowbuffer, sizeof(slowbuffer), "");
		}
		else
		{
			Format(slowbuffer, sizeof(slowbuffer), " ▲");
			Format(fastbuffer, sizeof(fastbuffer), "");
		}
	}
	else
	{
		Format(fastbuffer, sizeof(fastbuffer), "");
		Format(slowbuffer, sizeof(slowbuffer), "");
	}
	
	if(g_bExtraJumps[client])
	{
		if(g_iJump[target] <= 16)
		{
			if(RoundToFloor(GetVectorLength(velocity)) < values[g_iJump[target]][0])
			{
				rgb = colour[3];
			}
			else if(RoundToFloor(GetVectorLength(velocity)) >= values[g_iJump[target]][0] && RoundToFloor(GetVectorLength(velocity)) < values[g_iJump[target]][1])
			{
				rgb = colour[4];
			}
			else if(RoundToFloor(GetVectorLength(velocity)) >= values[g_iJump[target]][1] && RoundToFloor(GetVectorLength(velocity)) < values[g_iJump[target]][2])
			{
				rgb = colour[5];
			}
			else
			{
				rgb = colour[6];
			}
			
			if(!IsNaN(totalPercent) && g_bStrafeSpeed[client])
			{
				Format(sMessage, sizeof(sMessage), "%i: %i (%.0f%%%%)\n%s%.2f%%%s", g_iJump[target], RoundToFloor(GetVectorLength(velocity)), totalPercent, fastbuffer, coeffsum, slowbuffer);
			}
			else
			{
				if(g_iJump[target] > 1)
				{
					Format(sMessage, sizeof(sMessage), "%i: %i\n%s%.2f%%%s", g_iJump[target], RoundToFloor(GetVectorLength(velocity)), fastbuffer, coeffsum, slowbuffer);
				}
				else
				{
					Format(sMessage, sizeof(sMessage), "%i: %i", g_iJump[target], RoundToFloor(GetVectorLength(velocity)));
				}
			}
		}
		else
		{
			if(coeffsum < 60)
			{
				rgb = colour[3];
			}
			else if(coeffsum >= 60 && coeffsum < 70)
			{
				rgb = colour[4];
			}
			else if(coeffsum >= 70 && coeffsum < 80)
			{
				rgb = colour[5];
			}
			else
			{
				rgb = colour[6];
			}
			
			if(!IsNaN(totalPercent) && g_bStrafeSpeed[client])
			{
				Format(sMessage, sizeof(sMessage), "%i: %i (%.0f%%%%)\n%s%.2f%%%s", g_iJump[target], RoundToFloor(GetVectorLength(velocity)), totalPercent, fastbuffer, coeffsum, slowbuffer);
			}
			else
			{
				Format(sMessage, sizeof(sMessage), "%i: %i\n%s%.2f%%%s", g_iJump[target], RoundToFloor(GetVectorLength(velocity)), fastbuffer, coeffsum, slowbuffer);
			}
		}
	}
	else
	{
		if(g_iJump[target] <= 6 || g_iJump[target] == 16)
		{
			if(RoundToFloor(GetVectorLength(velocity)) < values[g_iJump[target]][0])
			{
				rgb = colour[3];
			}
			else if(RoundToFloor(GetVectorLength(velocity)) >= values[g_iJump[target]][0] && RoundToFloor(GetVectorLength(velocity)) < values[g_iJump[target]][1])
			{
				rgb = colour[4];
			}
			else if(RoundToFloor(GetVectorLength(velocity)) >= values[g_iJump[target]][1] && RoundToFloor(GetVectorLength(velocity)) < values[g_iJump[target]][2])
			{
				rgb = colour[5];
			}
			else
			{
				rgb = colour[6];
			}
			
			if(!IsNaN(totalPercent) && g_bStrafeSpeed[client])
			{
				Format(sMessage, sizeof(sMessage), "%i: %i (%.0f%%%%)\n%s%.2f%%%s", g_iJump[target], RoundToFloor(GetVectorLength(velocity)), totalPercent, fastbuffer, coeffsum, slowbuffer);
			}
			else
			{
				if(g_iJump[target] > 1)
				{
					Format(sMessage, sizeof(sMessage), "%i: %i\n%s%.2f%%%s", g_iJump[target], RoundToFloor(GetVectorLength(velocity)), fastbuffer, coeffsum, slowbuffer);
				}
				else
				{
					Format(sMessage, sizeof(sMessage), "%i: %i", g_iJump[target], RoundToFloor(GetVectorLength(velocity)));
				}
			}
		}
		else
		{
			if(coeffsum < 60)
			{
				rgb = colour[3];
			}
			else if(coeffsum >= 60 && coeffsum < 70)
			{
				rgb = colour[4];
			}
			else if(coeffsum >= 70 && coeffsum < 80)
			{
				rgb = colour[5];
			}
			else
			{
				rgb = colour[6];
			}
			
			if(!IsNaN(totalPercent) && g_bStrafeSpeed[client])
			{
				Format(sMessage, sizeof(sMessage), "%i: %i (%.0f%%%%)\n%s%.2f%%%s", g_iJump[target], RoundToFloor(GetVectorLength(velocity)), totalPercent, fastbuffer, coeffsum, slowbuffer);
			}
			else
			{
				Format(sMessage, sizeof(sMessage), "%i: %i\n%s%.2f%%%s", g_iJump[target], RoundToFloor(GetVectorLength(velocity)), fastbuffer, coeffsum, slowbuffer);
			}
		}
	}
	
	if(g_iJHUDPosition[client] == 0)
	{
		JhudPos = -1.0;
		//SetHudTextParams(-1.0, -1.0, 1.0, rgb[0], rgb[1], rgb[2], 255, 0, 0.0, 0.0);
	}
	else if(g_iJHUDPosition[client] == 1)
	{
		JhudPos = 0.4;
		//SetHudTextParams(-1.0, 0.4, 1.0, rgb[0], rgb[1], rgb[2], 255, 0, 0.0, 0.0);
	}
	else if(g_iJHUDPosition[client] == 2)
	{
		JhudPos = -0.4;
		//SetHudTextParams(-1.0, -0.4, 1.0, rgb[0], rgb[1], rgb[2], 255, 0, 0.0, 0.0);
	}
	//ShowHudText(client, 2, sMessage);
	updatedjhud = true;
	showticks = 0;
}

stock void GetStrafeEval(int client, float x)
{
	if (x > 0.0)
	{
		g_bSpeedDiff[client] = true;
	}
	else if (x < 0.0)
	{
		g_bSpeedDiff[client] = false;
	}
}

stock int FormatSpeed(int client)
{
	float vel[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);

	return RoundToNearest(SquareRoot(vel[0] * vel[0] + vel[1] * vel[1]));
}

stock void SetCookie(int client, Handle hCookie, int n)
{
	char strCookie[64];
	IntToString(n, strCookie, sizeof(strCookie));
	SetClientCookie(client, hCookie, strCookie);
}

stock void GetEntityVelocity( int ent, float out[3] )
{
	GetEntPropVector( ent, Prop_Data, "m_vecVelocity", out );
}

stock float GetEntitySpeedSquared( int ent )
{
	float vec[3];
	GetEntityVelocity( ent, vec );
	
	return ( vec[0] * vec[0] + vec[1] * vec[1] );
}

stock float GetEntitySpeed( int ent )
{
	return SquareRoot( GetEntitySpeedSquared( ent ) );
}

public void OnClientDisconnect(int client)
{
	//gB_StrafeTrainer[client] = false;
	if(!IsFakeClient(client))
	{
		gCV_SourceJumpAPIKey.SetString(apikey);
		for(int i = 0; i < MAX_CHANELS; i++)
		{
			delete GameTextTimer[i];
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "game_text"))
	{
		if (g_dHooks)
			DHookEntity(g_AcceptInput, true, entity);
	}
}

public MRESReturn AcceptInput(int pThis, Handle hReturn, Handle hParams)
{
	int chanel = GetEntProp(pThis, Prop_Data, "m_textParms.channel");
	if(chanel<6&&chanel>-1 && allowblock)
	{
		if(GameTextTimer[chanel]!=null)
			delete GameTextTimer[chanel];

		float holdtime = GetEntPropFloat(pThis, Prop_Data, "m_textParms.holdTime");
		float fadeinTime = GetEntPropFloat(pThis, Prop_Data, "m_textParms.fadeinTime");
		float fadeoutTime = GetEntPropFloat(pThis, Prop_Data, "m_textParms.fadeoutTime");
		float finaltime = fadeinTime + holdtime + fadeoutTime;
		xcrd[chanel] = GetEntPropFloat(pThis, Prop_Data, "m_textParms.x");
		ycrd[chanel] = GetEntPropFloat(pThis, Prop_Data, "m_textParms.y");
		//char Callback[20];
		//Format(Callback, sizeof(Callback), "Timer_holdtime_%i",chanel);
		blockchanel[chanel] = true;
		//PrintToChatAll("game_text: %d, %f %f %f blocked",chanel,finaltime,xcrd[chanel],ycrd[chanel]);
		//GameTextTimer[chanel] = CreateTimer(holdtime, Callback);
		//xd
		switch(chanel)
		{
			case 0: GameTextTimer[chanel] = CreateTimer(finaltime, Timer_holdtime_0);
			case 1: GameTextTimer[chanel] = CreateTimer(finaltime, Timer_holdtime_1);
			case 2: GameTextTimer[chanel] = CreateTimer(finaltime, Timer_holdtime_2);
			case 3: GameTextTimer[chanel] = CreateTimer(finaltime, Timer_holdtime_3);
			case 4: GameTextTimer[chanel] = CreateTimer(finaltime, Timer_holdtime_4);
			case 5: GameTextTimer[chanel] = CreateTimer(finaltime, Timer_holdtime_5);
		}
	}
	return MRES_Ignored;
}

//??? idk
public Action Timer_holdtime_0(Handle timer)
{
	PrintToChatAll("game_text: 0 %f %f unblocked",xcrd[0],ycrd[0]);
	blockchanel[0] = false;
	GameTextTimer[0] = null;
}

public Action Timer_holdtime_1(Handle timer)
{
	//PrintToChatAll("game_text: 1 %f %f unblocked",xcrd[1],ycrd[1]);
	blockchanel[1] = false;
	GameTextTimer[1] = null;
}

public Action Timer_holdtime_2(Handle timer)
{
	PrintToChatAll("game_text: 2 %f %f unblocked",xcrd[2],ycrd[2]);
	blockchanel[2] = false;
	GameTextTimer[2] = null;
}

public Action Timer_holdtime_3(Handle timer)
{
	PrintToChatAll("game_text: 3 %f %f unblocked",xcrd[3],ycrd[3]);
	blockchanel[3] = false;
	GameTextTimer[3] = null;
}

public Action Timer_holdtime_4(Handle timer)
{
	PrintToChatAll("game_text: 4 %f %f unblocked",xcrd[4],ycrd[4]);
	blockchanel[4] = false;
	GameTextTimer[4] = null;
}

public Action Timer_holdtime_5(Handle timer)
{
	PrintToChatAll("game_text: 5 %f %f unblocked",xcrd[5],ycrd[5]);
	blockchanel[5] = false;
	GameTextTimer[5] = null;
}

public void Player_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(IsFakeClient(client))
	{
		return;
	}
	FormatEx(sTopLeftOld, 128, "");
	int style = Shavit_GetBhopStyle(client);
	int track = Shavit_GetClientTrack(client);

	float fWRTime = Shavit_GetWorldRecord(style, track);

	if(fWRTime != 0.0)
	{
		char sWRTime[16];
		FormatSeconds(fWRTime, sWRTime, 16);

		char sWRName[MAX_NAME_LENGTH];
		Shavit_GetWRName(style, sWRName, MAX_NAME_LENGTH, track);

		FormatEx(sTopLeftOld, 128, "Best: %s (%s)", sWRTime, sWRName);
	}
	GetTimerClr(client);
}

public void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs)
{
	FormatEx(sTopLeftOld, 128, "");
	float fWRTime = Shavit_GetWorldRecord(style, track);

	if(fWRTime != 0.0)
	{
		char sWRTime[16];
		FormatSeconds(fWRTime, sWRTime, 16);

		char sWRName[MAX_NAME_LENGTH];
		Shavit_GetWRName(style, sWRName, MAX_NAME_LENGTH, track);

		FormatEx(sTopLeftOld, 128, "Best: %s (%s)", sWRTime, sWRName);
	}
	GetTimerClr(client);
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	CreateTimer(1.0, StyleChange, client, TIMER_REPEAT);
	
}
public Action StyleChange(Handle timer, int client)
{
	FormatEx(sTopLeftOld, 128, "");
	int style = Shavit_GetBhopStyle(client);
	int track = Shavit_GetClientTrack(client);

	float fWRTime = Shavit_GetWorldRecord(style, track);
	FormatEx(sTopLeftOld, 128, "Best: N/A");
	if(fWRTime != 0.0)
	{
		char sWRTime[16];
		FormatSeconds(fWRTime, sWRTime, 16);

		char sWRName[MAX_NAME_LENGTH];
		Shavit_GetWRName(style, sWRName, MAX_NAME_LENGTH, track);

		FormatEx(sTopLeftOld, 128, "Best: %s (%s)", sWRTime, sWRName);
	}
	GetTimerClr(client);
}

public Action Command_StrafeTrainer(int client, int args)
{
	if (client != 0)
	{
		gB_StrafeTrainer[client] = !gB_StrafeTrainer[client];
		SetClientCookieBool(client, gH_StrafeTrainerCookie, gB_StrafeTrainer[client]);
		ReplyToCommand(client, "[SM] Strafe Trainer %s!", gB_StrafeTrainer[client] ? "enabled" : "disabled");
	}

	return Plugin_Handled;
}

float GetClientVelocity(int client)
{
	float vVel[3];
	
	vVel[0] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[0]");
	vVel[1] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[1]");
	
	
	return GetVectorLength(vVel);
}

float PerfStrafeAngle(float speed)
{
	return RadToDeg(ArcTangent(30 / speed));
}

void VisualisationString(char[] buffer, int maxlength, float percentage)
{
	
	if (0.5 <= percentage <= 1.5)
	{
		int Spaces = RoundFloat((percentage - 0.5) / 0.05);
		for (int i = 0; i <= Spaces + 1; i++)
		{
			FormatEx(buffer, maxlength, "%s ", buffer);
		}
		
		FormatEx(buffer, maxlength, "%s|", buffer);
		
		for (int i = 0; i <= (21 - Spaces); i++)
		{
			FormatEx(buffer, maxlength, "%s ", buffer);
		}
	}
	else
		Format(buffer, maxlength, "%s", percentage < 1.0 ? "|				   " : "					|");
}
/*
void GetPercentageColor(float percentage, int &r, int &g, int &b)
{
	float offset = FloatAbs(1 - percentage);
	
	if (offset < 0.05)
	{
		r = 0;
		g = 255;
		b = 0;
	}
	else if (0.05 <= offset < 0.1)
	{
		r = 128;
		g = 255;
		b = 0;
	}
	else if (0.1 <= offset < 0.25)
	{
		r = 255;
		g = 255;
		b = 0;
	}
	else if (0.25 <= offset < 0.5)
	{
		r = 255;
		g = 128;
		b = 0;
	}
	else
	{
		r = 255;
		g = 0;
		b = 0;
	}
}*/

stock bool GetClientCookieBool(int client, Handle cookie)
{
	char sValue[8];
	GetClientCookie(client, gH_StrafeTrainerCookie, sValue, sizeof(sValue));
	
	return (sValue[0] != '\0' && StringToInt(sValue));
}

stock void SetClientCookieBool(int client, Handle cookie, bool value)
{
	char sValue[8];
	IntToString(value, sValue, sizeof(sValue));
	
	SetClientCookie(client, cookie, sValue);
}


void BuildWRSJMenu(int client, char[] mapname, int first_item=0)
{
	ArrayList records;
	gS_Maps.GetValue(mapname, records);

	int maxrecords = 10;
	maxrecords = (maxrecords < records.Length) ? maxrecords : records.Length;

	Menu menu = new Menu(Handler_WRSJMenu, MENU_ACTIONS_ALL);
	menu.SetTitle("SourceJump WR\n%s - Showing %i best", mapname, maxrecords);

	for (int i = 0; i < maxrecords; i++)
	{
		RecordInfo record;
		records.GetArray(i, record, sizeof(record));

		char line[128];
		FormatEx(line, sizeof(line), "#%d - %s - %s (%d Jumps)", i+1, record.name, record.time, record.jumps);

		char info[PLATFORM_MAX_PATH*2];
		FormatEx(info, sizeof(info), "%d;%s", record.id, mapname);
		menu.AddItem(info, line);
	}

	if(menu.ItemCount == 0)
	{
		char sMenuItem[64];

		FormatEx(sMenuItem, 64, "No records");
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.DisplayAt(client, first_item, MENU_TIME_FOREVER);

	gI_CurrentPagePosition[client] = 0;
}

int Handler_WRSJMenu(Menu menu, MenuAction action, int client, int choice)
{
	if (action == MenuAction_Select)
	{
		int id;
		char info[PLATFORM_MAX_PATH*2];
		menu.GetItem(choice, info, sizeof(info));

		if (StringToInt(info) == -1)
		{
			delete menu;
			return 0;
		}

		char exploded[2][PLATFORM_MAX_PATH];
		ExplodeString(info, ";", exploded, 2, PLATFORM_MAX_PATH, true);

		id = StringToInt(exploded[0]);
		gS_ClientMap[client] = exploded[1];

		RecordInfo record;
		ArrayList records;
		gS_Maps.GetValue(gS_ClientMap[client], records);

		for (int i = 0; i < records.Length; i++)
		{
			records.GetArray(i, record, sizeof(record));
			if (record.id == id)
				break;
		}

		if (record.id != id)
		{
			delete menu;
			return 0;
		}

		Menu submenu = new Menu(SubMenu_Handler);

		char display[160];

		FormatEx(display, sizeof(display), "%s %s", record.name, record.steamid);
		submenu.SetTitle(display);

		FormatEx(display, sizeof(display), "Time: %s (%s)", record.time, record.wrDif);
		submenu.AddItem("-1", display, ITEMDRAW_DISABLED);
		FormatEx(display, sizeof(display), "Jumps: %d", record.jumps);
		submenu.AddItem("-1", display, ITEMDRAW_DISABLED);
		FormatEx(display, sizeof(display), "Strafes: %d (%.2f%%)", record.strafes, record.sync);
		submenu.AddItem("-1", display, ITEMDRAW_DISABLED);
		FormatEx(display, sizeof(display), "Server: %s", record.hostname);
		submenu.AddItem("-1", display, ITEMDRAW_DISABLED);
		FormatEx(display, sizeof(display), "Date: %s", record.date);
		submenu.AddItem("-1", display, ITEMDRAW_DISABLED);

		submenu.ExitBackButton = true;
		submenu.ExitButton = true;
		submenu.Display(client, MENU_TIME_FOREVER);

		gI_CurrentPagePosition[client] = GetMenuSelectionPosition();
	}

	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

int SubMenu_Handler(Menu menu, MenuAction action, int client, int choice)
{
	if (action == MenuAction_Cancel && choice == MenuCancel_ExitBack)
	{
		BuildWRSJMenu(client, gS_ClientMap[client], gI_CurrentPagePosition[client]);
		delete menu;
	}
}

#if USE_RIPEXT
void CacheMap(char[] mapname, JSONArray json)
#else
void CacheMap(char[] mapname, JSON_Array json)
#endif
{
	ArrayList records;

	if (gS_Maps.GetValue(mapname, records))
		delete records;

	records = new ArrayList(sizeof(RecordInfo));

	gS_MapsCachedTime.SetValue(mapname, GetEngineTime(), true);
	gS_Maps.SetValue(mapname, records, true);

	for (int i = 0; i < json.Length; i++)
	{
#if USE_RIPEXT
		JSONObject record = view_as<JSONObject>(json.Get(i));
#else
		JSON_Object record = json.GetObject(i);
#endif

		RecordInfo info;
		info.id = record.GetInt("id");
		record.GetString("name", info.name, sizeof(info.name));
		record.GetString("hostname", info.hostname, sizeof(info.hostname));
		record.GetString("time", info.time, sizeof(info.time));
		record.GetString("steamid", info.steamid, sizeof(info.steamid));
		record.GetString("date", info.date, sizeof(info.date));
		record.GetString("wrDif", info.wrDif, sizeof(info.wrDif));
		info.sync = record.GetFloat("sync");
		info.strafes = record.GetInt("strafes");
		info.jumps = record.GetInt("jumps");
		info.tier = record.GetInt("tier");

		records.PushArray(info, sizeof(info));

#if USE_RIPEXT
		delete record;
#else
		// we fully delete the json tree later
#endif
	}
}

#if USE_RIPEXT
void RequestCallback(HTTPResponse response, DataPack pack, const char[] error)
#else
void ResponseBodyCallback(const char[] data, DataPack pack, int datalen)
#endif
{
	pack.Reset();

	int client = GetClientFromSerial(pack.ReadCell());
	char mapname[PLATFORM_MAX_PATH];
	pack.ReadString(mapname, sizeof(mapname));

	CloseHandle(pack);

#if USE_RIPEXT
	//PrintToChat(client, "status = %d, error = '%s'", response.Status, error);
	if (response.Status != HTTPStatus_OK)
	{
		if (client != 0)
			PrintToChat(client, "WRSJ: Sourcejump API request failed");
		LogError("WRSJ: Sourcejump API request failed");
		return;
	}

	JSONArray records = view_as<JSONArray>(response.Data);
#else
	JSON_Array records = view_as<JSON_Array>(json_decode(data));
	if (records == null)
	{
		if (client != 0)
			ReplyToCommand(client, "WRSJ: bbb");
		LogError("WRSJ: bbb");
		return;
	}
#endif
	CacheMap(mapname, records);

#if USE_RIPEXT
	// the records handle is closed by ripext post-callback
#else
	json_cleanup(records);
#endif

	if (client != 0)
		BuildWRSJMenu(client, mapname);
}

#if !USE_RIPEXT
public void RequestCompletedCallback(Handle request, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, DataPack pack)
{
	pack.Reset();
	int client = GetClientFromSerial(pack.ReadCell());

	//ReplyToCommand(client, "bFailure = %d, bRequestSuccessful = %d, eStatusCode = %d", bFailure, bRequestSuccessful, eStatusCode);

	if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		if (client != 0)
			ReplyToCommand(client, "WRSJ: Sourcejump API request failed");
		LogError("WRSJ: Sourcejump API request failed");
		return;
	}

	SteamWorks_GetHTTPResponseBodyCallback(request, ResponseBodyCallback, pack);
}
#endif

void RetrieveWRSJ(int client, char[] mapname)
{
	int serial = client ? GetClientSerial(client) : 0;
	char apiurl[230];

	strcopy(apiurl, sizeof(apiurl), "https://sourcejump.net/api/records/");

	if (apikey[0] == 0)
	{
		ReplyToCommand(client, "WRSJ: Sourcejump API is not set.");
		LogError("WRSJ: Sourcejump API is not set.");
		return;
	}

	DataPack pack = new DataPack();
	pack.WriteCell(serial);
	pack.WriteString(mapname);

	StrCat(apiurl, sizeof(apiurl), mapname);
	//ReplyToCommand(client, "url = %s", apiurl);

#if USE_RIPEXT
	HTTPRequest http = new HTTPRequest(apiurl);
	http.SetHeader("api-key", "%s", apikey);
	//http.SetHeader("user-agent", USERAGENT); // doesn't work :(
	http.Get(RequestCallback, pack);
#else
	Handle request;
	if (!(request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, apiurl))
	  || !SteamWorks_SetHTTPRequestHeaderValue(request, "api-key", apikey)
	  || !SteamWorks_SetHTTPRequestHeaderValue(request, "accept", "application/json")
	//|| !SteamWorks_SetHTTPRequestHeaderValue(request, "user-agent", USERAGENT)
	  || !SteamWorks_SetHTTPRequestContextValue(request, pack)
	  || !SteamWorks_SetHTTPRequestAbsoluteTimeoutMS(request, 4000)
	//|| !SteamWorks_SetHTTPRequestRequiresVerifiedCertificate(request, true)
	  || !SteamWorks_SetHTTPCallbacks(request, RequestCompletedCallback)
	  || !SteamWorks_SendHTTPRequest(request)
	)
	{
		CloseHandle(pack);
		CloseHandle(request);
		ReplyToCommand(client, "WRSJ: failed to setup & send HTTP request");
		LogError("WRSJ: failed to setup & send HTTP request");
		return;
	}
#endif
}

Action Command_WRSJ(int client, int args)
{
	if (client == 0 || IsFakeClient(client))// || !IsClientAuthorized(client))
		return Plugin_Handled;

	if(strlen(apikey)<1)
	{
		ReplyToCommand(client,"SJ API key is required! ( sj_api_key <your key> )");
		return Plugin_Handled;
	}
	char mapname[PLATFORM_MAX_PATH];

	if (args < 1)
		mapname = gS_CurrentMap;
	else
		GetCmdArg(1, mapname, sizeof(mapname));

	float cached_time;
	if (gS_MapsCachedTime.GetValue(mapname, cached_time))
	{
		if (cached_time > (GetEngineTime() - 500.0))
		{
			BuildWRSJMenu(client, mapname);
			return Plugin_Handled;
		}
	}

	RetrieveWRSJ(client, mapname);
	return Plugin_Handled;
}

public void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity, int data)
{
	if(type == Zone_Start && strlen(sjtext) < 2)
	{
		FormatEx(sTopLeftOld, 128, "");
		GetTimerClr(client);
	}
}