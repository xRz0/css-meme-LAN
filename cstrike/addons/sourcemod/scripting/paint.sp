#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <shavit>
#include <closestpos>

#define PLUGIN_VERSION		"2.0"

#define PAINT_DISTANCE_SQ	1.0
#define DEFAULT_FLAG		ADMFLAG_CHAT
#define DECAL_LIMIT 4096
// XDDDD
public Plugin myinfo = 
{
	name = "Paint! with save for LAN",
	author = "SlidyBat <3,celly",
	description = "Allow players to paint on walls",
	version = PLUGIN_VERSION,
	url = ""
}

/* GLOBALS */
Menu	g_hPaintMenu;
Menu	g_hPaintSizeMenu;

int	 g_PlayerPaintColour[MAXPLAYERS + 1];
int	 g_PlayerPaintSize[MAXPLAYERS + 1];
int redglow;

bool added;
bool premovd;

int addDecal;
int 	dcl;
float 	Ppos[DECAL_LIMIT][3];
int 	Psize[DECAL_LIMIT];
int 	Pcol[DECAL_LIMIT];

float   g_fLastPaint[MAXPLAYERS + 1][3];
bool	g_bIsPainting[MAXPLAYERS + 1];
bool	g_bTryToRemove[MAXPLAYERS + 1];
bool removed;

char mapname[128];
char paintloc[PLATFORM_MAX_PATH];
bool paintsaved;
bool connected;
bool skipframe;
bool loaded;
bool deleted;
float LastPos[3];
int g_index;
float g_fCoords[3];

ArrayList g_hLocCoords;
ClosestPos gH_ClosestPos;
/* COOKIES */
Handle  g_hPlayerPaintColour;
Handle  g_hPlayerPaintSize;

/* COLOURS! */
/* Colour name, file name */
char g_cPaintColours[][][64] = // Modify this to add/change colours
{
	{ "Random", "random" },
	{ "White", "paint_white" },
	{ "Black", "paint_black" },
	{ "Blue", "paint_blue" },
	{ "Light Blue", "paint_lightblue" },
	{ "Brown", "paint_brown" },
	{ "Cyan", "paint_cyan" },
	{ "Green", "paint_green" },
	{ "Dark Green", "paint_darkgreen" },
	{ "Red", "paint_red" },
	{ "Orange", "paint_orange" },
	{ "Yellow", "paint_yellow" },
	{ "Pink", "paint_pink" },
	{ "Light Pink", "paint_lightpink" },
	{ "Purple", "paint_purple" },
};

/* Size name, size suffix */
char g_cPaintSizes[][][64] = // Modify this to add more sizes
{
	{ "Small", "" },
	{ "Medium", "_med" },
	{ "Large", "_large" },
};

int  g_Sprites[sizeof( g_cPaintColours ) - 1][sizeof( g_cPaintSizes )];

public void OnPluginStart()
{
	CreateConVar("paint_version", PLUGIN_VERSION, "Paint plugin version", FCVAR_NOTIFY);
	
	/* Register Cookies */
	g_hPlayerPaintColour = RegClientCookie( "paint_playerpaintcolour", "paint_playerpaintcolour", CookieAccess_Protected );
	g_hPlayerPaintSize = RegClientCookie( "paint_playerpaintsize", "paint_playerpaintsize", CookieAccess_Protected );
	
	/* COMMANDS */
	RegAdminCmd( "+paint", cmd_EnablePaint, DEFAULT_FLAG );
	RegConsoleCmd( "-paint", cmd_DisablePaint );
	RegConsoleCmd("sm_paint", Command_Paint);
	RegConsoleCmd( "sm_paintcolour", cmd_PaintColour );
	RegConsoleCmd( "sm_paintcolor", cmd_PaintColour );
	RegConsoleCmd( "sm_paintsize", cmd_PaintSize );
	RegConsoleCmd( "sm_removepaint", cmd_PaintReMove );
	RegConsoleCmd( "sm_removedraw", cmd_PaintReMove );
	RegConsoleCmd( "sm_paintremove", cmd_PaintReMove );
	RegConsoleCmd( "sm_deletepaint", cmd_PaintReMove );
	RegConsoleCmd( "sm_drawremove", cmd_PaintReMove );
	RegConsoleCmd( "sm_redraw", cmd_PaintReDraw );
	RegConsoleCmd( "sm_repaint", cmd_PaintReDraw );
	RegConsoleCmd( "sm_paintsave", cmd_PaintSave );
	RegConsoleCmd( "sm_savedraw", cmd_PaintSave );
	RegConsoleCmd( "sm_savepaint", cmd_PaintSave );
	RegConsoleCmd( "sm_paintload", cmd_PaintLoad );
	RegConsoleCmd( "sm_loaddraw", cmd_PaintLoad );
	RegConsoleCmd( "sm_loadpaint", cmd_PaintLoad );

	CreatePaintMenus();
	HookEvent("round_start", Event_RoundStart);
	g_hLocCoords = new ArrayList(ByteCountToCells(12));

	/* Late loading */
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame( i ) )
		{
			OnClientCookiesCached( i );
			OnClientPostAdminCheck( i );
		}
	}
}

public void OnClientCookiesCached( int client )
{
	char sValue[64];

	
	GetClientCookie( client, g_hPlayerPaintColour, sValue, sizeof( sValue ) );
	g_PlayerPaintColour[client] = StringToInt( sValue );
	
	GetClientCookie( client, g_hPlayerPaintSize, sValue, sizeof( sValue ) );
	g_PlayerPaintSize[client] = StringToInt( sValue );
}

public void OnMapStart()
{
	g_hLocCoords.Clear();
	GetCurrentMap(mapname, sizeof(mapname));
	added = false;
	premovd = false;
	paintsaved  = false;
	connected = false;
	deleted = false;
	removed = false;
	char buffer[PLATFORM_MAX_PATH];
	dcl = 1;
	redglow = PrecacheModel("sprites/redglow1.vmt");
	AddFileToDownloadsTable( "materials/decals/paint/paint_decal.vtf" );
	for( int colour = 1; colour < sizeof( g_cPaintColours ); colour++ )
	{
		for( int size = 0; size < sizeof( g_cPaintSizes ); size++ )
		{
			Format( buffer, sizeof( buffer ), "decals/paint/%s%s.vmt", g_cPaintColours[colour][1], g_cPaintSizes[size][1] );
			g_Sprites[colour - 1][size] = PrecachePaint( buffer ); // colour - 1 because starts from [1], [0] is reserved for random
		}
	}
	
	CreateTimer( 0.1, Timer_Paint, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE );

	CreateTimer( 0.1, Timer_Remove, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE );

	int limit = DECAL_LIMIT-1;
	for(int i = 0; i <= limit; i++)
	{
		Psize[i] = -1337;
	}
}

public void OnConfigsExecuted() 
{
	if(!DirExists("SaveFiles"))
	{
		CreateDirectory("SaveFiles", 511);
	}

	if(!DirExists("SaveFiles/paint"))
	{
		CreateDirectory("SaveFiles/paint", 511);
	}

	FormatEx(paintloc, sizeof(paintloc), "SaveFiles/paint/%s.txt",mapname);
}

void Event_RoundStart(Handle event, const char[] name , bool dontBroadcast)
{
	if(connected)
		LoadPaint();
}

public Action cmd_EnablePaint( int client, int args )
{
	if(client<1)
	{
		for( int i = 1; i <= MaxClients; i++ )
		{
			if( IsClientInGame( i ) && IsPlayerAlive( i ) && !IsFakeClient( i ) )
			{
				if(g_bTryToRemove[i])
					g_bTryToRemove[i]=false;

				TraceEye(i, g_fLastPaint[i]);
				g_bIsPainting[i] = true;
			}
		}
	}
	else
	{
		if(g_bTryToRemove[client])
			g_bTryToRemove[client]=false;

		TraceEye(client, g_fLastPaint[client]);
		g_bIsPainting[client] = true;
	}
	
	return Plugin_Handled;
}

public Action cmd_DisablePaint( int client, int args )
{
	if(client<1)
	{
		for( int i = 1; i <= MaxClients; i++ )
		{
			if( IsClientInGame( i ) && IsPlayerAlive( i ) && !IsFakeClient( i ) )
			{
				g_bIsPainting[i] = false;
			}
		}
	}
	else
	{
		g_bIsPainting[client] = false;
	}
	
	return Plugin_Handled;
}

public Action cmd_PaintSave( int client, int args )
{
	if(client!=0)
		SavePaint();

	return Plugin_Handled;
}

public Action cmd_PaintReMove( int client, int args )
{
	if(client!=0)
	{
		if (args < 1)
		{
			if (FileExists(paintloc))
			{
				g_index =-1;
				g_hLocCoords.Clear();
				int limit = DECAL_LIMIT-1;
				for(int i = 0; i <= limit; i++)
				{
					Psize[i] = -1337;
				}
				addDecal = 1;
				g_fLastPaint[client][0] = 0.0;
				g_fLastPaint[client][1] = 0.0;
				g_fLastPaint[client][2] = 0.0;
				dcl = 1;
				ClientCommand(client,"r_cleardecals");
				deleted = true;
				g_bTryToRemove[client] = false;
				DeleteFile(paintloc);
				PrintToChat(client,"\x01Deleted your saved decals on \x04%s\x01!", mapname);
			}
			else
				PrintToChat(client,"\x01You don't even have any saved decals on \x04%s\x01!", mapname);
		}
		else
		{
			char arg[128];
			GetCmdArg(1, arg, sizeof(arg));
			char tempPaintloc[PLATFORM_MAX_PATH];
			FormatEx(tempPaintloc, sizeof(tempPaintloc), "gauntlet/paint/%s.txt",arg);
			if (FileExists(tempPaintloc))
			{
				if (StrEqual(arg, mapname))
				{
					g_index =-1;
					g_hLocCoords.Clear();
					int limit = DECAL_LIMIT-1;
					for(int i = 0; i <= limit; i++)
					{
						Psize[i] = -1337;
					}
					addDecal = 1;
					g_fLastPaint[client][0] = 0.0;
					g_fLastPaint[client][1] = 0.0;
					g_fLastPaint[client][2] = 0.0;
					dcl = 1;
					ClientCommand(client,"r_cleardecals");
					deleted = true;
					g_bTryToRemove[client] = false;
				}

				DeleteFile(tempPaintloc);
				PrintToChat(client,"\x01Deleted your saved decals on \x04%s\x01!", arg);
			}
			else
				PrintToChat(client,"\x01You don't even have any saved decals on \x04%s\x01!", arg);
		}
	}
	return Plugin_Handled;
}

public Action cmd_PaintLoad( int client, int args )
{
	if(client!=0)
		LoadPaint();
		
	return Plugin_Handled;
}

public Action cmd_PaintReDraw( int client, int args )
{
	if(client!=0)
	{
		g_hLocCoords.Clear();
		ClientCommand(client,"r_cleardecals");
		loaded = true;
	}
	return Plugin_Handled;
}

public Action cmd_PaintColour( int client, int args )
{
	if( CheckCommandAccess( client, "+paint", DEFAULT_FLAG ) )
	{
		g_hPaintMenu.Display( client, MENU_TIME_FOREVER );
	}
	else
	{
		ReplyToCommand( client, "[SM] You do not have access to this command." );
	}
	
	return Plugin_Handled;
}

public Action cmd_PaintSize( int client, int args )
{
	if( CheckCommandAccess( client, "+paint", DEFAULT_FLAG ) )
	{
		g_hPaintSizeMenu.Display( client, MENU_TIME_FOREVER );
	}
	else
	{
		ReplyToCommand( client, "[SM] You do not have access to this command." );
	}
	
	return Plugin_Handled;
}

public Action Timer_Paint( Handle timer )
{
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame( i ) && IsPlayerAlive( i ) && g_bIsPainting[i] && !g_bTryToRemove[i] )
		{
			static float pos[3];
			TraceEye( i, pos );
			
			if( GetVectorDistance( pos, g_fLastPaint[i], true ) > PAINT_DISTANCE_SQ )
			{
				AddPaint( pos, g_PlayerPaintColour[i], g_PlayerPaintSize[i] );
				
				g_fLastPaint[i] = pos;
			}
		}
	}
}

void AddPaint( float pos[3], int paint = 0, int size = 0 )
{
	if(paintsaved)
		paintsaved = false;

	if(deleted)
		deleted = false;

	added = true;
	if(premovd)
	{
		if(dcl>1)
			dcl++;

		premovd = false;
	}
	if( paint == 0 )
	{
		paint = GetRandomInt( 1, sizeof( g_cPaintColours ) - 1 );
	}
	
	int limit = DECAL_LIMIT-1;
	if(dcl > limit)
		dcl = 1;

	g_hLocCoords.PushArray(pos);
	delete gH_ClosestPos;
	gH_ClosestPos = new ClosestPos(g_hLocCoords,0,0,g_hLocCoords.Length);
	Ppos[dcl] = pos;
	Psize[dcl] = size;
	Pcol[dcl] = paint-1;
	TE_SetupWorldDecal( pos, g_Sprites[paint - 1][size] );
	TE_SendToAll();
	dcl++;
}

int PrecachePaint( char[] filename )
{
	char tmpPath[PLATFORM_MAX_PATH];
	Format( tmpPath, sizeof( tmpPath ), "materials/%s", filename );
	AddFileToDownloadsTable( tmpPath );
	
	return PrecacheDecal( filename, true );
}

void CreatePaintMenus()
{
	/* COLOURS MENU */
	delete g_hPaintMenu;
	g_hPaintMenu = new Menu(PaintColourMenuHandle);
	
	g_hPaintMenu.SetTitle( "Select Paint Colour:" );
	
	for( int i = 0; i < sizeof( g_cPaintColours ); i++ )
	{
		g_hPaintMenu.AddItem( g_cPaintColours[i][0], g_cPaintColours[i][0] );
	}
	
	/* SIZE MENU */
	delete g_hPaintSizeMenu;
	g_hPaintSizeMenu = new Menu(PaintSizeMenuHandle);
	
	g_hPaintSizeMenu.SetTitle( "PaintMenu" );
	
	for( int i = 0; i < sizeof( g_cPaintSizes ); i++ )
	{
		g_hPaintSizeMenu.AddItem( g_cPaintSizes[i][0], g_cPaintSizes[i][0] );
	}
}

public int PaintColourMenuHandle( Menu menu, MenuAction menuAction, int param1, int param2 )
{
	if( menuAction == MenuAction_Select )
	{
		SetClientPaintColour( param1, param2 );
	}
}

public int PaintSizeMenuHandle( Menu menu, MenuAction menuAction, int param1, int param2 )
{
	if( menuAction == MenuAction_Select )
	{
		SetClientPaintSize( param1, param2 );
	}
}

void SetClientPaintColour( int client, int paint )
{
	char sValue[64];
	g_PlayerPaintColour[client] = paint;
	IntToString( paint, sValue, sizeof( sValue ) );
	SetClientCookie( client, g_hPlayerPaintColour, sValue );
	
	PrintToChat( client, "[SM] Paint colour now: \x10%s", g_cPaintColours[paint][0] );
}

void SetClientPaintSize( int client, int size )
{
	char sValue[64];
	g_PlayerPaintSize[client] = size;
	IntToString( size, sValue, sizeof( sValue ) );
	SetClientCookie( client, g_hPlayerPaintSize, sValue );
	
	PrintToChat( client, "[SM] Paint size now: \x10%s", g_cPaintSizes[size][0] );
}

stock void TE_SetupWorldDecal( const float vecOrigin[3], int index )
{	
	TE_Start( "Entity Decal" );
	TE_WriteVector( "m_vecOrigin", vecOrigin );
	TE_WriteNum( "m_nIndex", index );
	TE_WriteNum("m_nEntity",0);
}

stock void TraceEye( int client, float pos[3] )
{
	float vAngles[3], vOrigin[3];
	GetClientEyePosition( client, vOrigin );
	GetClientEyeAngles( client, vAngles );
	
	TR_TraceRayFilter( vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer );
	
	if( TR_DidHit() )
		TR_GetEndPosition( pos );
}

public bool TraceEntityFilterPlayer( int entity, int contentsMask )
{
	return ( entity > MaxClients || !entity );
}

void SavePaint( bool showmsg = true )
{
	char sBuffer[256];
	int curpos = 0;
	File fileHandle = OpenFile(paintloc, "w");
	int limit = DECAL_LIMIT-1;
	for(int i = 0; i <= limit; i++)
	{
		float pos[3];
		int paint;
		int size;
		pos = Ppos[i];
		size = Psize[i];
		paint = Pcol[i];
		if( size != -1337 )
		{
			FormatEx(sBuffer, sizeof(sBuffer), "%f_%f_%f_%i_%i",pos[0],pos[1],pos[2],size,paint);
			WriteFileLine(fileHandle,sBuffer);
			curpos++;
		}
	}
	CloseHandle(fileHandle);
	if(showmsg)
		PrintToChatAll("\x01Saved \x04%i\x01 decals.", curpos);

	paintsaved = true;
	deleted = false;
}

void LoadPaint( bool showmsg = true )
{
	char sBuffer[256];
	int curpos = 1;
	File fileHandle = OpenFile(paintloc, "r");
	bool validfile = true;
	if (fileHandle == INVALID_HANDLE)
		validfile = false;

	if(validfile)
	{
		int limit = DECAL_LIMIT-1;
		for(int i = 0; i <= limit; i++)
		{
			Psize[i] = -1337;
		}
		dcl = 1;
		g_index =-1;
		addDecal = 1;
		while(ReadFileLine(fileHandle, sBuffer, sizeof(sBuffer)))
		{
			ReplaceString(sBuffer, sizeof(sBuffer), "\n", "", false);
			char bufs[5][12];
			ExplodeString( sBuffer, "_", bufs, sizeof( bufs ), sizeof( bufs[] ) );
			Ppos[curpos][0] = StringToFloat(bufs[0]);
			Ppos[curpos][1] = StringToFloat(bufs[1]);
			Ppos[curpos][2] = StringToFloat(bufs[2]);
			Psize[curpos] = StringToInt(bufs[3]);
			Pcol[curpos] = StringToInt(bufs[4]);
			if( Psize[curpos] != -1337 )
			{
				dcl = curpos;
			}
			curpos++;
		}
	}

	CloseHandle(fileHandle);
	added = false;
	if(validfile && curpos > 1)
	{
		g_hLocCoords.Clear();
		for( int i = 1; i <= MaxClients; i++ )
		{
			if( IsClientInGame( i ) && IsPlayerAlive( i ) && !IsFakeClient( i ) )
			{
				g_bTryToRemove[i] = false;
				g_fLastPaint[i][0] = 0.0;
				g_fLastPaint[i][1] = 0.0;
				g_fLastPaint[i][2] = 0.0;
				ClientCommand(i,"r_cleardecals");
			}
		}
		loaded = true;
		if(showmsg)
			PrintToChatAll("\x01Loaded \x04%i\x01 decals.", curpos-1);
	}
}

public void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity, int data)
{
	if(type==Zone_Start && track==Track_Main)
		if(!paintsaved && !deleted)
			if( Psize[1] != -1337 )
				SavePaint( false );

}
public void OnClientDisconnect(int client)
{
	g_bTryToRemove[client] = false;
	g_bIsPainting[client] = false;
	if(!IsFakeClient(client))
	{
		connected = false;
		if(!paintsaved && !deleted)
			if( Psize[1] != -1337 )
				SavePaint( false );
	}
}


public void OnClientPostAdminCheck(int client)
{
	if(!IsFakeClient(client))
	{
		ClientCommand(client,"mp_decals 4000");
		ClientCommand(client,"r_decals 4000");
		connected = true;
		LoadPaint(false);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(IsFakeClient(client)) 
		return Plugin_Continue;


	if(g_bTryToRemove[client])
	{
		if(g_index!=-1)
		{
			if((buttons & IN_USE) > 0)
			{
				if(added)
				{
					dcl--;
					added = false;
				}
				removed = true;
				g_hLocCoords.Clear();
				g_fLastPaint[client][0] = 0.0;
				g_fLastPaint[client][1] = 0.0;
				g_fLastPaint[client][2] = 0.0;
				int xdIndex = g_index+1;
				Psize[xdIndex] = -1337;
				bool shifted = false;
				for(int i = 1; i <= dcl; i++)
				{
					if(i>=xdIndex&&i!=4095)
					{
						if( Psize[i+1] != -1337 )
						{	
							Ppos[i][0] = Ppos[i+1][0];
							Ppos[i][1] = Ppos[i+1][1];
							Ppos[i][2] = Ppos[i+1][2];
							Psize[i] = Psize[i+1];
							Pcol[i] = Pcol[i+1];
							shifted = true;
						}
					}
				}
				if(shifted)
					Psize[dcl] = -1337;

				addDecal = 1;
				if(dcl>0)
				{
					dcl--;
					premovd = true;
					ClientCommand(client,"r_cleardecals");
					loaded = true;
				}
				if(dcl==0)
				{
					
					dcl = 1;
					loaded = false;
					ClientCommand(client,"r_cleardecals");
				}
				g_bTryToRemove[client] = false;
				Menu_Paint(client);
				removed = false;
			}
		}
	}

	if(loaded)
	{
		if(dcl < addDecal)
		{
			if(g_hLocCoords.Length)
			{
				delete gH_ClosestPos;
				gH_ClosestPos = new ClosestPos(g_hLocCoords,0,0,g_hLocCoords.Length);
			}

			loaded = false;
			removed = false;
			char ReallyNiceText[52];
			Format(ReallyNiceText,52,"\x01Drew \x04%i\x01 decals.", addDecal-1);
			if(addDecal-1 == 1)
				Format(ReallyNiceText,52,"\x01Drew \x041\x01 decal.");

			PrintToChat(client,ReallyNiceText);
			addDecal = 1;
			return Plugin_Continue;
		}
		if(skipframe)
		{
			skipframe = false;
			return Plugin_Continue;
		}

		if(addDecal % 100 == 0)
			skipframe = true;

		if( Psize[addDecal] != -1337 )
		{
			TE_SetupWorldDecal( Ppos[addDecal], g_Sprites[Pcol[addDecal]][Psize[addDecal]] );
			g_hLocCoords.PushArray(Ppos[addDecal]);
			TE_SendToAll();
		}
		addDecal++;
	}
	return Plugin_Continue;
}


public Action Command_Paint(int client, int args)
{
	if (!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu_Paint(client);
	return Plugin_Handled;
}

void Menu_Paint(int client)
{
	Menu menu = new Menu(MenuHandler_Paint);

	menu.SetTitle("Paint");
	if(!g_bTryToRemove[client])
		menu.AddItem("paint", g_bIsPainting[client] ? "Paint - [x]\n " : "Paint - [ ]\n ");
	else
		menu.AddItem("paint", "Paint - [ ]\n ",ITEMDRAW_DISABLED);

	if(g_PlayerPaintSize[client]==0)//XD
	{
		menu.AddItem("size1", "Size - Small [x]",ITEMDRAW_DISABLED);
		menu.AddItem("size2", "Size - Medium [ ]");
		menu.AddItem("size3", "Size - Large [ ]\n ");
	}
	if(g_PlayerPaintSize[client]==1)
	{
		menu.AddItem("size1", "Size - Small [ ]");
		menu.AddItem("size2", "Size - Medium [x]",ITEMDRAW_DISABLED);
		menu.AddItem("size3", "Size - Large [ ]\n ");
	}
	if(g_PlayerPaintSize[client]==2)
	{
		menu.AddItem("size1", "Size - Small [ ]");
		menu.AddItem("size2", "Size - Medium [ ]");
		menu.AddItem("size3", "Size - Large [x]\n ",ITEMDRAW_DISABLED);
	}

	menu.AddItem("color", "Paint Color");
	if(dcl>1 && !g_bIsPainting[client])
		menu.AddItem("erase", g_bTryToRemove[client] ? "Erase - [x]\n use +use to remove (e)\n " : "Erase - [ ]\n ");
	else
		menu.AddItem("erase", "Erase - [ ]\n ",ITEMDRAW_DISABLED);

	if(FileExists(paintloc)&& !g_bIsPainting[client]||dcl>1&& !g_bIsPainting[client])
		menu.AddItem("eraseA", "Erase ALL ( IT WILL ALSO REMOVE YOUR SAVED FILE )");
	else
		menu.AddItem("eraseA", "Erase ALL",ITEMDRAW_DISABLED);

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Paint(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(param2, info, sizeof(info));

		if (StrEqual(info, "paint"))
		{
			if(g_bTryToRemove[param1])
				g_bTryToRemove[param1] = false;

			g_bIsPainting[param1] = !g_bIsPainting[param1];
			Menu_Paint(param1);
		}
		else if (StrEqual(info, "color"))
		{
			g_hPaintMenu.Display( param1, MENU_TIME_FOREVER );
		}
		else if (StrEqual(info, "size1"))
		{
			SetClientPaintSize( param1, 0 );
			Menu_Paint(param1);
		}
		else if (StrEqual(info, "size2"))
		{
			SetClientPaintSize( param1, 1 );
			Menu_Paint(param1);
		}
		else if (StrEqual(info, "size3"))
		{
			SetClientPaintSize( param1, 2 );
			Menu_Paint(param1);
		}
		else if (StrEqual(info, "erase"))
		{
			if(g_bIsPainting[param1])
				g_bIsPainting[param1] = false;

			g_bTryToRemove[param1] = !g_bTryToRemove[param1];
			g_index = -1;
			LastPos[0] = 0.0;
			LastPos[1] = 0.0;
			LastPos[2] = 0.0;

			Menu_Paint(param1);
		}
		else if (StrEqual(info, "eraseA"))
		{
			if(FileExists(paintloc))
			{
				DeleteFile(paintloc);
				PrintToChat(param1,"\x01Deleted your saved decals on \x04%s\x01!", mapname);
			}
			g_bTryToRemove[param1] = false;
			g_hLocCoords.Clear();
			int limit = DECAL_LIMIT-1;
			for(int i = 0; i <= limit; i++)
			{
				Psize[i] = -1337;
			}
			g_fLastPaint[param1][0] = 0.0;
			g_fLastPaint[param1][1] = 0.0;
			g_fLastPaint[param1][2] = 0.0;
			dcl = 1;
			g_index =-1;
			addDecal = 1;
			loaded = false;
			ClientCommand(param1,"r_cleardecals");
			deleted = true;

			Menu_Paint(param1);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public Action Timer_Remove( Handle timer )
{
	if(!removed)
	{
		for( int client = 1; client <= MaxClients; client++ )
		{
			if( IsClientInGame( client ) && IsPlayerAlive( client ) && g_bTryToRemove[client] && !g_bIsPainting[client] )
			{
				static float pos[3];
				float vAngles[3], vOrigin[3];
				float g_aCoords[3];
				GetClientEyePosition( client, vOrigin );
				GetClientEyeAngles( client, vAngles );
				
				TR_TraceRayFilter( vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer );

				if( TR_DidHit() )
					TR_GetEndPosition( pos );

				if( GetVectorDistance( pos, LastPos, true ) > PAINT_DISTANCE_SQ )
				{
					if(g_hLocCoords.Length)
					{	
						int iIndex = gH_ClosestPos.Find(pos);
						if(iIndex!=g_index)
						{
							g_hLocCoords.GetArray(iIndex, g_aCoords);
							if( IsPointVisible(vOrigin,g_aCoords) )
							{
								g_fCoords = g_aCoords;
								g_index = iIndex;
							}
						}
					}
					
					LastPos = pos;
				}
				if(g_index!=-1)
				{
					TE_SetupGlowSprite(g_fCoords, redglow, 0.1, 0.4, 255);
					TE_SendToAll();

					TE_SetupBeamRingPoint(g_fCoords, 13.0, 14.0, redglow, redglow, 0, 15, 0.1, 2.0, 0.0, {255, 0, 0, 255}, 10, 0);
					TE_SendToAll();
				}
			}
		}
	}
}

//SMAC xd
stock bool IsPointVisible(float start[3], float end[3])
{
    TR_TraceRayFilter(start, end, MASK_VISIBLE, RayType_EndPoint, TraceEntityFilterPlayer);

    return TR_GetFraction() == 1.0;
}