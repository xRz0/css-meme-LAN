#include <socket>
#include <morecolors>
#include <clientprefs>
#include <json>
#include <SteamWorks>

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 131000

public Plugin myinfo =
{
	name		= "Twitch Chat",
	author	  = "celly ~ GameConnect",
	description = "",
	version	 = "1.3.3.7",
	url		 = ""
};

bool connected = false;
bool ready;
int viewerz;
bool fromclient = false;

ConVar g_hBots;
ConVar g_hAuthUsername;
ConVar g_hPassword;
ConVar g_hAdvertTimer;
ConVar g_hAdvertPrefix;
char pathcvar[128];

float lasttime;

ArrayList g_hCommands;
ArrayList g_hResponse;
ArrayList g_hQueue;
ArrayList g_hBotArray;

int showttv[MAXPLAYERS+1];

float advertTimer;
char AdvPre[512];

char sUserName[64];
char sPassword[64];

Handle g_hSocket = INVALID_HANDLE;
Handle AdvTimer = INVALID_HANDLE;

int cid;

Handle ViewerMenu = INVALID_HANDLE;


//so fancy :flushed:
char g_sPath[PLATFORM_MAX_PATH];
char g_sColorName[255][255];
char g_sColorHex[255][255];
int g_iColorCount;
Handle g_hCookieTagColor = INVALID_HANDLE;
Handle g_hCookieTTV = INVALID_HANDLE;
char g_sTagColor[7];
Handle g_hRegexHex;
Handle hMenu = INVALID_HANDLE;

public void OnPluginStart()
{
	connected = false;
	g_hAuthUsername = CreateConVar("ttv_auth_username", "", "Twitch chanel name.", FCVAR_PROTECTED);
	g_hAuthUsername.AddChangeHook(OnCvarChange);

	g_hPassword = CreateConVar("ttv_oauth_password", "", "Twitch oauth key.", FCVAR_PROTECTED);
	g_hPassword.AddChangeHook(OnCvarChange);

	g_hBots = CreateConVar("ttv_bots", "Nightbot,Streamelements", "The bots names you use ( Seperated via comma ).", FCVAR_PROTECTED);
	g_hBots.AddChangeHook(OnCvarChange);

	g_hAdvertTimer = CreateConVar("ttv_advert", "300", "Twitch advert timer ( 0 to disable it ).", _, true, 0.0, true, 13337.0);
	g_hAdvertTimer.AddChangeHook(OnCvarChange);

	g_hAdvertPrefix = CreateConVar("ttv_advertprefix", "My cool commands are:", "Twitch advert prefix..");
	g_hAdvertPrefix.AddChangeHook(OnCvarChange);

	g_hBotArray = new ArrayList(ByteCountToCells(128));
	g_hCommands	  = new ArrayList(ByteCountToCells(64));
	g_hResponse	  = new ArrayList(ByteCountToCells(256));
	g_hQueue		 = new ArrayList(ByteCountToCells(1024));

	RegConsoleCmd("sm_ttv", Command_Twitch, "Twitch Settings.");
	RegConsoleCmd("sm_twitch", Command_Twitch, "Twitch Settings.");
	RegConsoleCmd("sm_ttw", Command_Twitch, "Twitch Settings.");
	RegConsoleCmd("sm_viewers", Command_TwitchV, "Twitch Viewers.");
	RegConsoleCmd("sm_tviewers", Command_TwitchV, "Twitch Viewers.");
	RegConsoleCmd("sm_ttvcolor", Command_TTVCOL, "TTVCOL");
	RegConsoleCmd("sm_ttvc", Command_TTVCOL, "TTVCOL");
	RegConsoleCmd("sm_ttvcol", Command_TTVCOL, "TTVCOL");
	RegConsoleCmd("sm_follow", Command_TTVFol, "Follow age");
	RegConsoleCmd("sm_followage", Command_TTVFol, "Follow age");
	RegConsoleCmd("sm_tagcolor", Command_TagColor, "Change tag color to a specified hexadecimal value.");

	g_hCookieTagColor = RegClientCookie("TTVColorz", "TTVColorz", CookieAccess_Protected);
	g_hCookieTTV = RegClientCookie("TTVPrint", "TTVPrint", CookieAccess_Protected);

	CreateTimer(0.5, Timer_ProcessQueue, _, TIMER_REPEAT);
	CreateTimer(2.0, Timer_Retry, _, TIMER_REPEAT);
	CreateTimer(2.0, Timer_Hide, _, TIMER_REPEAT);

	for(int i = 1; i < MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			OnClientCookiesCached(i);
		}
	}
}

public void OnMapStart()
{
	ready = false;
	Format(pathcvar, sizeof(pathcvar), "cfg/sourcemod/ttv.cfg");
	BuildPath(Path_SM, g_sPath, sizeof(g_sPath), "configs/ttv_colors.cfg");
	g_hRegexHex = CompileRegex("([A-Fa-f0-9]{6})");
}

public void OnConfigsExecuted()
{
	if (!FileExists(pathcvar))
	{
		PrintToServer("HERE");
		File fileHandle = OpenFile(pathcvar, "w");
		WriteFileLine(fileHandle,"ttv_auth_username \"\" // Default \"\"");
		WriteFileLine(fileHandle,"ttv_oauth_password \"\" // Default \"\"");
		WriteFileLine(fileHandle,"ttv_advert \"300.0\" // Default \"300.0\"");
		WriteFileLine(fileHandle,"ttv_advertprefix \"My cool commands are:\" // Default \"My cool commands are:\"");
		WriteFileLine(fileHandle,"ttv_bots \"Nightbot,Streamelements\" // Default \"Nightbot,Streamelements\"");
		CloseHandle(fileHandle);
		g_hAdvertTimer.FloatValue = 300.0;
	}
	else
	{
		ServerCommand("exec sourcemod/ttv.cfg");
	}

	strcopy(sUserName,  sizeof(sUserName),  "");

	LoadColorCfg();
	LoadChatCommands();

	CreateTimer(2.0, Timer_Retry, _, TIMER_REPEAT);
	CreateTimer(2.0, Timer_Hide, _, TIMER_REPEAT);
}

public void OnCvarChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(connected)
	{
		if (convar == g_hAuthUsername) 
		{
			if(strlen(newValue)<2)
				return;

			strcopy(sUserName,  sizeof(sUserName),  newValue);
			if(strlen(sPassword)<6 || strlen(sUserName)<2)
				return;

			Connect();
		}

		else if (convar == g_hPassword) 
		{
			if(strlen(newValue)<6)
				return;

			if(!StrEqual(newValue, "SECRET"))
			{
				strcopy(sPassword,  sizeof(sPassword),  newValue);
				if(strlen(sPassword)<6 || strlen(sUserName)<2)
					return;

				Connect();
			}
		}

		else if (convar == g_hAdvertTimer) 
		{
			if(AdvTimer!=null)
				CloseHandle(AdvTimer);

			advertTimer = g_hAdvertTimer.FloatValue;
			if(advertTimer>=1.0)
				AdvTimer = CreateTimer(advertTimer, Timer_Advertisement, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );
		}

		else if (convar == g_hAdvertPrefix) 
		{
			strcopy(AdvPre,  sizeof(AdvPre),  newValue);
		}

		else if (convar == g_hBots) 
		{
			g_hBotArray.Clear();
			char xCvar[512];
			strcopy(xCvar,  sizeof(xCvar),  newValue);
			while(StrContains(xCvar,",")!=-1)
			{
				char xBot[128];
				SplitString(xCvar, ",", xBot, 128);
				strcopy(xCvar, sizeof(xCvar), xCvar[strlen(xBot)]);
				if(strlen(xBot)>1)
				{
					strcopy(xCvar, sizeof(xCvar), xCvar[1]);
					g_hBotArray.PushString(xBot);
					if(strlen(xCvar)>1)
					{
						if(StrContains(xCvar,",")!=-1)
							continue;

						g_hBotArray.PushString(xCvar);
					}
				}
			}
		}
		char sBuffer[64];
		File fileHandle = OpenFile(pathcvar, "w");
		g_hAuthUsername.GetString(sBuffer, sizeof(sBuffer));
		WriteFileLine(fileHandle,"ttv_auth_username \"%s\" // Default \"\"",sBuffer);
		WriteFileLine(fileHandle,"ttv_oauth_password \"%s\" // Default \"\"",sPassword);
		g_hAdvertTimer.GetString(sBuffer, sizeof(sBuffer));
		WriteFileLine(fileHandle,"ttv_advert \"%s\" // Default \"300.0\"",sBuffer);
		g_hAdvertPrefix.GetString(sBuffer, sizeof(sBuffer));
		WriteFileLine(fileHandle,"ttv_advertprefix \"%s\" // Default \"My cool commands are:\"",sBuffer);
		g_hBots.GetString(sBuffer, sizeof(sBuffer));
		WriteFileLine(fileHandle,"ttv_bots \"%s\" // Default \"Nightbot,Streamelements\"",sBuffer);
		CloseHandle(fileHandle);
	}
}

public int OnSocketConnect(Handle socket, any arg)
{
	char hostname[256];
	char ServerIp[16];
	SocketGetHostName(hostname, sizeof(hostname));

	int iIp = GetConVarInt(FindConVar("hostip"));
	Format(ServerIp, sizeof(ServerIp), "%i.%i.%i.%i", (iIp >> 24) & 0x000000FF,
														  (iIp >> 16) & 0x000000FF,
														  (iIp >>  8) & 0x000000FF,
														  iIp		 & 0x000000FF);

	SendMsg("PASS %s",sPassword);
	SendMsg("NICK %s",sUserName);
	SendMsg("USER %s %s %s :%s",sUserName, hostname, ServerIp, sUserName);
}

public int OnSocketDisconnect(Handle socket, any arg)
{
	if(g_hSocket!=INVALID_HANDLE)
		CloseHandle(g_hSocket);

	g_hSocket = INVALID_HANDLE;
}

public int OnSocketError(Handle socket, const int errorType, const int errorNum, any arg)
{
	//LogError("Socket error %i (%i)", errorType, errorNum);
	CreateTimer(5.0, ReConnect);
}

public Action ReConnect(Handle timer) 
{
	Connect();
}

public int OnSocketReceive(Handle socket, char[] receiveData, const int dataSize, any arg)
{
	char sLines[16][1024];
	for (int i = 0, iLines = ExplodeString(receiveData, "\r\n", sLines, sizeof(sLines), sizeof(sLines[])); i <= iLines; i++) {
		if (!sLines[i][0]) {
			continue;
		}

		char sData[4][512], sName[2][128];
		ExplodeString(sLines[i],   " ", sData, sizeof(sData), sizeof(sData[]),true);
		ExplodeString(sData[0], "!", sName, sizeof(sName), sizeof(sName[]));

		if (StrEqual(sData[0], "PING")) 
			SendMsg("PONG %s", sData[1]);

		else if (StrEqual(sData[1], "PRIVMSG")) 
		{
			if (sData[3][1] == '\001' && sData[3][strlen(sData[3]) - 1] == '\001')
				continue;

			char name[128],txt[512];
			strcopy(name, sizeof(name), sName[0]);
			strcopy(name, sizeof(name), name[1]);
			strcopy(txt, sizeof(txt), sData[3]);
			strcopy(txt, sizeof(txt), txt[1]);

			int iCommand = g_hCommands.FindString(txt);
			if (iCommand != -1) 
			{
				char reply[512];
				g_hResponse.GetString(iCommand, reply,512);
				SendMsg("PRIVMSG #%s :%s", sUserName,reply);
				continue;
			}

			iCommand = g_hBotArray.FindString(name);
			if (iCommand != -1) 
			{
				continue;
			}

			for (int z=1; z<=MaxClients; z++) 
			{
				if (IsClientInGame(z) && !IsFakeClient(z)) 
				{
					if(showttv[z]==1)
					{
						if((strlen(txt)+strlen(name))>200)
						{
							int iStrParags = RoundToCeil(float((strlen(txt)+strlen(name)))/128);
							char LongDescr[4][129];
							char BackupDescr[2][512];
							for(int str; str<iStrParags; str++)
							{
								if( str == 0 )
								{
									Format(LongDescr[str], 129, txt);
								
									ExplodeString(txt, LongDescr[str], BackupDescr, 2, 512, true);
								}
								else {
									Format(LongDescr[str], 129, BackupDescr[1]);
									
									ExplodeString(BackupDescr[1], LongDescr[str], BackupDescr, 2, 512, true);
								}
							}
							switch( iStrParags )
								{
									case 2: 
									{ 
										CPrintToChat(z, "\x07FFFFFF[ \x07800080TTV \x07FFFFFF] »\x07%s %s: %s",g_sTagColor, name, LongDescr[0]);
										CPrintToChat(z, "\x07%s %s",g_sTagColor, LongDescr[1]);
									}
									case 3: 
									{ 
										CPrintToChat(z, "\x07FFFFFF[ \x07800080TTV \x07FFFFFF] »\x07%s %s: %s",g_sTagColor, name, LongDescr[0]);
										CPrintToChat(z, "\x07%s %s",g_sTagColor, LongDescr[1]);
										CPrintToChat(z, "\x07%s %s",g_sTagColor, LongDescr[2]);
									}
									case 4: 
									{ 
										CPrintToChat(z, "\x07FFFFFF[ \x07800080TTV \x07FFFFFF] »\x07%s %s: %s",g_sTagColor, name, LongDescr[0]);
										CPrintToChat(z, "\x07%s %s",g_sTagColor, LongDescr[1]);
										CPrintToChat(z, "\x07%s %s",g_sTagColor, LongDescr[2]);
										CPrintToChat(z, "\x07%s %s",g_sTagColor, LongDescr[3]);
									}
								}
						}

						else
							CPrintToChat(z, "\x07FFFFFF[ \x07800080TTV \x07FFFFFF] »\x07%s %s: %s",g_sTagColor, name, txt);

					}
					if(showttv[z]==2)
						PrintToConsole(z, "[ TTV ] > %s: %s", name, txt);
				}
			}
		}
		else 
		{
			switch (StringToInt(sData[1])) 
			{
				case 376, 422:
				{
					if(advertTimer>=1.0)
					{
						if(AdvTimer!=null)
							CloseHandle(AdvTimer);

						AdvTimer = CreateTimer(advertTimer, Timer_Advertisement, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );
					}
					SendMsg("JOIN #%s", sUserName);
					SendMsg("PRIVMSG #%s :TTV BOT IS ONLINE", sUserName);
					CPrintToChatAll("\x07FFFFFF[ \x07800080TTV \x07FFFFFF] » \x07%sConnected to %s.",g_sTagColor,sUserName);
					fromclient = false;
					Getviewers();
				}
			}
		}
	}
}

public Action Timer_Advertisement( Handle timer )
{
	if(IsConnected())
	{
		char adv[650];
		strcopy(adv, sizeof(adv), "");
		for(int i = 0; i < g_hCommands.Length; i++)
		{
			char reply[512];
			g_hCommands.GetString(i, reply,512);
			Format(adv, sizeof(adv), " %s %s",adv,reply);
		}
		SendMsg("PRIVMSG #%s :%s %s", sUserName,AdvPre,adv);
	}
}

stock bool IsConnected()
{
	return g_hSocket && SocketIsConnected(g_hSocket);
}

stock void SendMsg(const char[] msg, any...)
{
	char buffer[1024];
	VFormat(buffer, sizeof(buffer), msg, 2);
	
	g_hQueue.PushString(buffer);
}

public Action Timer_ProcessQueue(Handle timer)
{
	if (!IsConnected() || !g_hQueue.Length) {
		return;
	}

	char sData[4096];
	g_hQueue.GetString(0, sData, sizeof(sData));
	g_hQueue.Erase(0);

	Format(sData, sizeof(sData), "%s\r\n", sData);
	SocketSend(g_hSocket, sData);
}



void LoadColorCfg()
{
	if(!FileExists(g_sPath))
	{
		SetFailState("Configuration file %s not found!", g_sPath);
		return;
	}

	Handle hKeyValues = CreateKeyValues("TTV Colors");
	if(!FileToKeyValues(hKeyValues, g_sPath))
	{
		SetFailState("Improper structure for configuration file %s!", g_sPath);
		return;
	}

	if(!KvGotoFirstSubKey(hKeyValues))
	{
		SetFailState("Can't find configuration file %s!", g_sPath);
		return;
	}

	for(int i = 0; i < 255; i++)
	{
		strcopy(g_sColorName[i], sizeof(g_sColorName[]), "");
		strcopy(g_sColorHex[i], sizeof(g_sColorHex[]), "");
	}

	g_iColorCount = 0;
	do
	{
		KvGetString(hKeyValues, "name", g_sColorName[g_iColorCount], sizeof(g_sColorName[]));
		KvGetString(hKeyValues, "hex",	g_sColorHex[g_iColorCount], sizeof(g_sColorHex[]));
		ReplaceString(g_sColorHex[g_iColorCount], sizeof(g_sColorHex[]), "#", "", false);


		g_iColorCount++;
	}
	while(KvGotoNextKey(hKeyValues));
	CloseHandle(hKeyValues);
	hMenu = CreateMenu(MenuHandler_TagColor);
	SetMenuTitle(hMenu, "TTV Color");
	SetMenuExitBackButton(hMenu, true);

	AddMenuItem(hMenu, "Reset", "Reset");
	AddMenuItem(hMenu, "SetManually", "Define Your Own Color");

	char sColorIndex[4];
	for(int i = 0; i < g_iColorCount; i++)
	{
		IntToString(i, sColorIndex, sizeof(sColorIndex));
		AddMenuItem(hMenu, sColorIndex, g_sColorName[i]);
	}
}

public int MenuHandler_TagColor(Menu xhMenu, MenuAction iAction, int iParam1,int iParam2)
{
	if(iAction == MenuAction_End)
	{
		return 0;
	}

	if(iAction == MenuAction_Select)
	{
		char sBuffer[32];
		GetMenuItem(hMenu, iParam2, sBuffer, sizeof(sBuffer));

		if(StrEqual(sBuffer, "Reset"))
		{
			CPrintToChat(iParam1, "\x07FFFFFF[ \x07800080TTV \x07FFFFFF] Your TTV color is now reset to default ( White ).");
			g_sTagColor = "FFFFFF";
			SetClientCookie(iParam1, g_hCookieTagColor, "FFFFFF");
		}
		else if(StrEqual(sBuffer, "SetManually"))
		{
			CPrintToChat(iParam1, "\x07FFFFFF[ \x07800080TTV \x07FFFFFF] To define your own TTV color, type !tagcolor <hexcode> (e.g. !tagcolor FFFFFF).");
		}
		else
		{
			int iColorIndex = StringToInt(sBuffer);
			CPrintToChat(iParam1, "\x07FFFFFF[ \x07800080TTV \x07FFFFFF] Your TTV color is now set to:\x07%s %s", g_sColorHex[iColorIndex], g_sColorName[iColorIndex]);
			strcopy(g_sTagColor, 7, g_sColorHex[iColorIndex]);
			SetClientCookie(iParam1, g_hCookieTagColor, g_sColorHex[iColorIndex]);
		}

		DisplayMenuAtItem(xhMenu, iParam1, GetMenuSelectionPosition(), MENU_TIME_FOREVER);
	}
	return 0;
}

public void OnClientDisconnect(int client)
{
	if(!IsFakeClient(client))
	{
		connected = false;
		if(g_hSocket!=INVALID_HANDLE)
			CloseHandle(g_hSocket);

		g_hSocket = INVALID_HANDLE;
		g_hQueue.Clear();

		if(AdvTimer!=INVALID_HANDLE)
			CloseHandle(AdvTimer);

		AdvTimer = INVALID_HANDLE;
	}
}

public Action Command_TTVFol(int client, int args)
{
	if(client!=0 && ready)
	{
		cid = client;
		if (args != 1)
		{
			ReplyToCommand(client,"!followage <username>");
			return Plugin_Handled;
		}
		char tuser[128];
		GetCmdArg(1, tuser, sizeof(tuser));
		FollowAge(tuser);
	}
	return Plugin_Handled;
}

public Action Command_TwitchV(int client, int args)
{
	if(client!=0 && ready)
	{
		cid = client;
		if (lasttime < (GetEngineTime() - 15.0))
		{
			fromclient = true;
			Getviewers();
			return Plugin_Handled;
		}

		if(viewerz>0)
			DisplayMenu(ViewerMenu, client, 0);

		else
			CPrintToChat(client, "\x07FFFFFF[ \x07800080TTV \x07FFFFFF] » \x07%sNobody is watching you yet:(",g_sTagColor);
	}
	return Plugin_Handled;
}

public Action Command_Twitch(int client, int args)
{
	if(client!=0)
	{
		if ( ++showttv[client] >= 4 || showttv[client] < 0 )
		{
			showttv[client] = 1;
		}
		char val[8];
		IntToString(showttv[client], val, sizeof(val));
		SetClientCookie(client, g_hCookieTTV, val);

		if (showttv[client] == 1)
			ReplyToCommand(client, "[TTV] Now listening to TTV in chat and console.");
		else if (showttv[client] == 2)
			ReplyToCommand(client, "[TTV] Now listening to TTV in console.");
		else if (showttv[client] == 3)
			ReplyToCommand(client, "[TTV] Not listening to TTV anymore.");
		else
			ReplyToCommand(client, "[TTV] Something went wrong.");
	}
	return Plugin_Handled;
}

public void OnClientCookiesCached(int client)
{
	//XDDDDDD
	char sBuffer[20] = "";
	GetClientCookie(client, g_hCookieTagColor, sBuffer, sizeof(sBuffer));
	if(StrEqual(sBuffer, "", false))
	{
		strcopy(g_sTagColor, 7, "FFFFFF");
	}
	else
	{
		strcopy(g_sTagColor, 7, sBuffer);
	}

	GetClientCookie(client, g_hCookieTTV, sBuffer, sizeof(sBuffer));
	if(StrEqual(sBuffer, "", false))
	{
		showttv[client] = 1;
	}
	else
	{
		showttv[client] = StringToInt(sBuffer);
	}
	if(!IsFakeClient(client))
		CreateTimer(3.0, Timer_Cache);
}

public Action Command_TTVCOL(int client, int args)
{
	if(client!=0)
	{
		DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	}
	return Plugin_Handled;
}

public Action Command_TagColor(int client, int args)
{
	if(client!=0)
	{
		if(args != 1)
		{
			ReplyToCommand(client, "[TTV] Usage: sm_tagcolor <hex>");
			return Plugin_Handled;
		}

		char sArg[32];
		GetCmdArgString(sArg, sizeof(sArg));
		ReplaceString(sArg, sizeof(sArg), "#", "", false);

		if(!IsValidHex(sArg))
		{
			ReplyToCommand(client, "[TTV] Usage: sm_tagcolor <hex>");
			return Plugin_Handled;
		}

		CPrintToChat(client, "\x07FFFFFF[ \x07800080TTV \x07FFFFFF] Your tag is now set to:\x07%s %s", sArg, sArg);
		strcopy(g_sTagColor[client], sizeof(g_sTagColor[]), sArg);
		SetClientCookie(client, g_hCookieTagColor, sArg);
	}

	return Plugin_Handled;
}

stock bool IsValidHex(const char[] strHex)
{
	if(strlen(strHex) == 6 && MatchRegex(g_hRegexHex, strHex))
		return true;
	return false;
}

public Action OnClientSayCommand( int client, const char[] szCommand, const char[] szMsg )
{
	if ( !IsConnected() ) return Plugin_Continue;

	if ( !client ) return Plugin_Continue;
	
	if ( !IsClientInGame( client ) ) return Plugin_Continue;

	if( showttv[client] > 2 || showttv[client] < 1 ) return Plugin_Continue;

	if( !IsChatTrigger() )
		SendMsg("PRIVMSG #%s :%s", sUserName, szMsg );

	return Plugin_Continue;
} 

void LoadChatCommands()
{
	g_hCommands.Clear();
	g_hResponse.Clear();
	g_hBotArray.Clear();

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/ttv_commands.cfg");

	if (!FileExists(sPath)) 
		SetFailState("File Not Found: %s", sPath);
	
	KeyValues hConfig = new KeyValues("TTV Commands");
	hConfig.SetEscapeSequences(true);
	hConfig.ImportFromFile(sPath);
	hConfig.GotoFirstSubKey();

	do 
	{
		char trigger[512];
		char response[512];
		hConfig.GetString("trigger", trigger, sizeof(trigger));
		hConfig.GetString("response",   response, sizeof(response));
		g_hCommands.PushString(trigger);
		g_hResponse.PushString(response);
	} 
	while (hConfig.GotoNextKey());


	delete hConfig;

	char xCvar[512];
	g_hBots.GetString(xCvar, sizeof(xCvar));
	
	while(StrContains(xCvar,",")!=-1)
	{
		char xBot[128];
		SplitString(xCvar, ",", xBot, 128);
		strcopy(xCvar, sizeof(xCvar), xCvar[strlen(xBot)]);
		if(strlen(xBot)>1)
		{
			strcopy(xCvar, sizeof(xCvar), xCvar[1]);
			g_hBotArray.PushString(xBot);
			if(strlen(xCvar)>1)
			{
				if(StrContains(xCvar,",")!=-1)
					continue;

				g_hBotArray.PushString(xCvar);
			}
		}
	}
}

//wrsj + GAMMACASE with some nice info here hehe
void Getviewers()
{
	char twitchurl[312];
	Format(twitchurl, sizeof(twitchurl), "https://tmi.twitch.tv/group/user/%s/chatters",sUserName);

	Handle request;
	if (!(request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, twitchurl))
	  || !SteamWorks_SetHTTPRequestAbsoluteTimeoutMS(request, 4000)
	  || !SteamWorks_SetHTTPCallbacks(request, RequestCompletedCallback)
	  || !SteamWorks_SendHTTPRequest(request)
	)
	{
		CloseHandle(request);
		LogError("TTV Viewers: failed to setup & send HTTP request");
		return;
	}
}

public void RequestCompletedCallback(Handle request, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, DataPack pack)
{
	if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		LogError("TTV Viewers: request failed");
		return;
	}

	SteamWorks_GetHTTPResponseBodyCallback(request, ResponseBodyCallback);
}

void ResponseBodyCallback(const char[] data, DataPack pack, int datalen)
{
	if(ViewerMenu != INVALID_HANDLE)
	{
		CloseHandle(ViewerMenu);
		ViewerMenu = INVALID_HANDLE;
	}
	ViewerMenu = CreateMenu(ViewerMenuHandler);

	JSON_Object json =json_decode(data);
	if (json == null)
	{
		LogError("TTV Viewers: RIP data");
		return;
	}

	viewerz = 0;

	JSON_Object chatters = json.GetObject("chatters");
	JSON_Array viewers = view_as<JSON_Array>(chatters.GetObject("viewers"));
	int Viewers_Length = viewers.Length;

	JSON_Array mods = view_as<JSON_Array>(chatters.GetObject("moderators"));
	int CMods_Length = mods.Length;

	JSON_Array vips = view_as<JSON_Array>(chatters.GetObject("vips"));
	int Vips_Length = vips.Length;

	JSON_Array staff = view_as<JSON_Array>(chatters.GetObject("staff"));
	int Staff_Length = staff.Length;

	JSON_Array admins = view_as<JSON_Array>(chatters.GetObject("admins"));
	int Admins_Length = admins.Length;

	JSON_Array global_mods = view_as<JSON_Array>(chatters.GetObject("global_mods"));
	int Gmods_Length = global_mods.Length;

	//viewerz = chatters.GetInt("chatter_count");sadge gives -1 XD fk it
	viewerz = Viewers_Length + CMods_Length + Vips_Length + Staff_Length + Admins_Length + Gmods_Length;

	char Vtitle[156];
	Format(Vtitle,sizeof(Vtitle),"%s visible viewer list (%d):\n",sUserName, viewerz);
	if(viewerz<1 && fromclient)
		CPrintToChatAll( "\x07FFFFFF[ \x07800080TTV \x07FFFFFF] »\x07%s Nobody is watching you yet:(",g_sTagColor);

	SetMenuTitle(ViewerMenu, Vtitle);

	if(Staff_Length>0)
	{
		AddMenuItem(ViewerMenu, "!Useless!", "->   Staff:",ITEMDRAW_DISABLED);
		for (int i = 0; i < Staff_Length; i++)
		{
			char strval[128];
			staff.GetString(i, strval, sizeof(strval));
			AddMenuItem(ViewerMenu, strval, strval);
		}
	}

	if(Admins_Length>0)
	{
		AddMenuItem(ViewerMenu, "!Useless!", "->   Admins:",ITEMDRAW_DISABLED);
		for (int i = 0; i < Admins_Length; i++)
		{
			char strval[128];
			admins.GetString(i, strval, sizeof(strval));
			AddMenuItem(ViewerMenu, strval, strval);
		}
	}

	if(Gmods_Length>0)
	{
		AddMenuItem(ViewerMenu, "!Useless!", "->   Global Mods:",ITEMDRAW_DISABLED);
		for (int i = 0; i < Gmods_Length; i++)
		{
			char strval[128];
			global_mods.GetString(i, strval, sizeof(strval));
			AddMenuItem(ViewerMenu, strval, strval);
		}
	}

	if(CMods_Length>0)
	{
		AddMenuItem(ViewerMenu, "!Useless!", "->   Mods:",ITEMDRAW_DISABLED);
		for (int i = 0; i < CMods_Length; i++)
		{
			char strval[128];
			mods.GetString(i, strval, sizeof(strval));
			AddMenuItem(ViewerMenu, strval, strval);
		}
	}

	if(Vips_Length>0)
	{
		AddMenuItem(ViewerMenu, "!Useless!", "->   Vips:",ITEMDRAW_DISABLED);
		for (int i = 0; i < Vips_Length; i++)
		{
			char strval[128];
			vips.GetString(i, strval, sizeof(strval));
			AddMenuItem(ViewerMenu, strval, strval);
		}
	}

	if(Viewers_Length>0)
	{
		AddMenuItem(ViewerMenu, "!Useless!", "->   Viewers:",ITEMDRAW_DISABLED);
		for (int i = 0; i < Viewers_Length; i++)
		{
			char strval[128];
			viewers.GetString(i, strval, sizeof(strval));
			AddMenuItem(ViewerMenu, strval, strval);
		}
	}

	delete staff;
	delete admins;
	delete global_mods;
	delete mods;
	delete vips;
	delete viewers;
	delete chatters;
	ready = true;
	lasttime = GetEngineTime();
	if(fromclient)
		DisplayMenu(ViewerMenu, cid, 0);
}

public int ViewerMenuHandler(Handle menu, MenuAction action,int param1,int param2)
{
	if (action == MenuAction_Select)
	{
		DisplayMenuAtItem(ViewerMenu, cid, GetMenuSelectionPosition(), 0);
		char sFname[128];
		GetMenuItem(menu, param2, sFname, sizeof(sFname));
		FollowAge(sFname);
	}
}

public Action Timer_Cache(Handle timer)
{
	connected = true;
}

public Action Timer_Hide( Handle timer )
{
	if(!IsConnected())
		return Plugin_Continue;

	if(!connected)
		return Plugin_Continue;

	static int Checked = 0;
	char pw[32];
	g_hPassword.GetString(pw, sizeof(pw));
	if(StrEqual(sPassword, "SECRET"))
	{
		Checked++;
		if (Checked >= 3) 
		{
			Checked = 0;
			return Plugin_Stop;
		}
	}
	else
		g_hPassword.SetString("SECRET");
 
	return Plugin_Continue;
}

public Action Timer_Retry( Handle timer )
{
	if(IsConnected())
		return Plugin_Stop;

	if(!connected)
		return Plugin_Continue;


	strcopy(sUserName,  sizeof(sUserName),  "");

	g_hPassword.GetString(sPassword, sizeof(sPassword));
	if(StrEqual(sPassword, "SECRET"))
		ServerCommand("exec sourcemod/ttv.cfg");
	g_hAuthUsername.GetString(sUserName, sizeof(sUserName));
	advertTimer = g_hAdvertTimer.FloatValue;
	g_hAdvertPrefix.GetString(AdvPre, sizeof(AdvPre));
	if(strlen(sPassword)<6 || strlen(sUserName)<2)
		return Plugin_Continue;

	g_hPassword.SetString("SECRET");

	Connect();

	return Plugin_Continue;
}

void Connect()
{
	if(g_hSocket!=INVALID_HANDLE)
		CloseHandle(g_hSocket);

	g_hSocket = INVALID_HANDLE;
	g_hSocket = SocketCreate(SOCKET_TCP, OnSocketError);

	if (!g_hSocket) 
	{
		LogError("Unable to create socket.");
		return;
	}

	SocketConnect(g_hSocket, OnSocketConnect, OnSocketReceive, OnSocketDisconnect, "irc.chat.twitch.tv", 6667);
}

void FollowAge(char[] ttvuser)
{
	char followlink[512];
	DataPack pack = new DataPack();
	Format(followlink, sizeof(followlink), "https://decapi.me/twitch/followage/%s/%s",sUserName,ttvuser);
	pack.WriteString(ttvuser);

	Handle request;
	if (!(request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, followlink))
	  || !SteamWorks_SetHTTPRequestContextValue(request, pack)
	  || !SteamWorks_SetHTTPRequestAbsoluteTimeoutMS(request, 4000)
	  || !SteamWorks_SetHTTPCallbacks(request, RequestCompletedCallbackLookup)
	  || !SteamWorks_SendHTTPRequest(request)
	)
	{
		CloseHandle(pack);
		CloseHandle(request);
		LogError("TTV Viewers: failed to setup & send HTTP request");
		return;
	}
}

public void RequestCompletedCallbackLookup(Handle request, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, DataPack pack)
{
	pack.Reset();
	if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		LogError("TTV Viewers: Follow age request failed");
		return;
	}

	SteamWorks_GetHTTPResponseBodyCallback(request, ResponseBodyCallbackFollowAge, pack);
}

void ResponseBodyCallbackFollowAge(const char[] data, DataPack pack, int datalen)
{
	pack.Reset();

	char sFname[128];
	pack.ReadString(sFname, sizeof(sFname));

	CloseHandle(pack);

	if(StrContains(data,"does not follow") != -1)  
		CPrintToChat(cid, "\x07FFFFFF[ \x07800080TTV \x07FFFFFF] »%s \x07FF0000doesn't follow \x07FFFFFF%s!", sFname,sUserName);
	
	else
		CPrintToChat(cid, "\x07FFFFFF[ \x07800080TTV \x07FFFFFF] »%s \x0700FF00does follow \x07FFFFFF%s for \x0700FF00%s\x07FFFFFF!", sFname,sUserName,data);
}