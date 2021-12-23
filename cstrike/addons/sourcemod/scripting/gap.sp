#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <regex>

#define POINT_A 0
#define POINT_B 1
#define NUM_POINTS 2
#define CURSOR_TIME GetTickInterval() * 10.0
#define PREVIEW_TIME 1.0
#define RING_START_RADIUS 7.0
#define RING_END_RADIUS 7.7
#define CURSOR_SIZE 3.0
#define CHAT_PREFIX "{ALTO}[{PERIWINKLE}Gap{ALTO}]"

static stock StringMap colors;
static stock EngineVersion game;

public Plugin myinfo =
{
	name = "Gap",
	author = "ici, velocity calculation by Saul and implemented by Charles_(hypnos)",
	description = "",
	version = "1.1",
	url = ""
}

EngineVersion gEV_Type = Engine_Unknown;

bool gGap[MAXPLAYERS + 1];
int gCurrPoint[MAXPLAYERS + 1];
float gPointPos[MAXPLAYERS + 1][NUM_POINTS][3];
Handle gCursorTimer[MAXPLAYERS + 1];
Handle gPreviewTimer[MAXPLAYERS + 1];
bool gShowCursor[MAXPLAYERS + 1];

int gSnapToGrid[MAXPLAYERS + 1];
int gSnapValues[] = {0, 1, 2, 4, 8, 16};

ConVar gCvarBeamMaterial;
int gModelIndex;
int gColorRed[4] = {255, 0, 0, 255};
int gColorGreen[4] = {0, 255, 0, 255};
int gColorWhite[4] = {255, 255, 255, 255};

float gGravity;

float gCursorStart[3][3] =
{
	{CURSOR_SIZE, 0.0, 0.0},
	{0.0, CURSOR_SIZE, 0.0},
	{0.0, 0.0, CURSOR_SIZE}
};

float gCursorEnd[3][3] =
{
	{-CURSOR_SIZE, 0.0, 0.0},
	{0.0, -CURSOR_SIZE, 0.0},
	{0.0, 0.0, -CURSOR_SIZE}
};

enum struct Line
{
	float start[3];
	float end[3];
}

public void OnPluginStart()
{
	RegConsoleCmd("sm_gap", ConCmd_Gap, "Activates the feature", .flags = 0)

	ConVar sv_gravity = FindConVar("sv_gravity");
	sv_gravity.AddChangeHook(OnGravityChanged);
	gGravity = sv_gravity.FloatValue;

	gEV_Type = GetEngineVersion();
	if(gEV_Type == Engine_CSS)
	{
		gCvarBeamMaterial = CreateConVar("gap_beams_material", "sprites/laser.vmt", "Material used for beams. Server restart needed for this to take effect.");
	}
	else
	{
		gCvarBeamMaterial = CreateConVar("gap_beams_material", "sprites/laserbeam.vmt", "Material used for beams. Server restart needed for this to take effect.");
	}
}

public void OnGravityChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gGravity = StringToFloat(newValue);
}

public void OnClientPutInServer(int client)
{
	ResetVariables(client);
}

public void OnMapStart()
{
	char buff[PLATFORM_MAX_PATH];
	gCvarBeamMaterial.GetString(buff, sizeof(buff));
	gModelIndex = PrecacheModel(buff, true);
}

public Action ConCmd_Gap(int client, int args)
{
	if ( client == 0 ) 
		return Plugin_Handled;

	OpenMenu(client);
	return Plugin_Handled;
}

void OpenMenu(int client)
{
	Panel panel = new Panel();

	panel.SetTitle("Gap");
	panel.DrawItem("Select point");

	// Feeling kinda lazy today
	if (gShowCursor[client])
	{
		panel.DrawItem("Show cursor: on");
	}
	else
	{
		panel.DrawItem("Show cursor: off");
	}

	if (gSnapToGrid[client] == 0)
	{
		panel.DrawItem("Snap to grid: off");
	}
	else
	{
		char gridText[32];
		FormatEx(gridText, sizeof(gridText), "Snap to grid: %d", gSnapValues[ gSnapToGrid[client] ] );
		panel.DrawItem(gridText);
	}

	if(gEV_Type == Engine_CSS)
	{
		panel.CurrentKey = 10;
	}
	else
	{
		panel.CurrentKey = 9;
	}
	panel.DrawItem("Exit", ITEMDRAW_CONTROL);

	gGap[client] = panel.Send(client, handler, MENU_TIME_FOREVER);

	if (gGap[client])
	{
		if (gCursorTimer[client] != null)
		{
			KillTimer(gCursorTimer[client]);
			gCursorTimer[client] = null;
		}
		gCursorTimer[client] = CreateTimer(CURSOR_TIME, Cursor, GetClientUserId(client), .flags = TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}

	delete panel;
}

public Action Cursor(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!client || !gGap[client])
	{
		gCursorTimer[client] = null;
		return Plugin_Stop;
	}

	if (gCurrPoint[client] == POINT_A)
	{
		float endPos[3];

		if (!GetAimPosition(client, endPos))
		{
			return Plugin_Continue;
		}

		DrawCursor(client, endPos, 1.0, CURSOR_TIME, gColorWhite);
	}
	else if (gCurrPoint[client] == POINT_B)
	{
		float endPos[3];

		if (!GetAimPosition(client, endPos))
		{
			return Plugin_Continue;
		}

		float startPos[3];
		startPos = gPointPos[client][ POINT_A ];

		DrawRing(client, startPos, RING_START_RADIUS, RING_END_RADIUS, CURSOR_TIME, gColorGreen, FBEAM_FADEIN);
		DrawCursor(client, endPos, 1.0, CURSOR_TIME, gColorWhite);
		DrawLine(client, gPointPos[ client ][ POINT_A ], endPos, 1.0, CURSOR_TIME, gColorWhite);
	}

	return Plugin_Continue;
}

public int handler(Menu menu, MenuAction action, int client, int item)
{
	if (action != MenuAction_Select)
	{
		gGap[client] = false;

		if (gPreviewTimer[client] != null)
		{
			KillTimer(gPreviewTimer[client]);
			gPreviewTimer[client] = null;
		}

		if (gCursorTimer[client] != null)
		{
			KillTimer(gCursorTimer[client]);
			gCursorTimer[client] = null;
		}

		return 0;
	}

	switch (item)
	{
		case 1: // Select point
		{
			if (GetAimPosition(client, gPointPos[ client ][ gCurrPoint[client] ]))
			{
				if (gCurrPoint[client] == POINT_A && gPreviewTimer[client] != null)
				{
					// Don't retrigger the timer
					KillTimer(gPreviewTimer[client]);
					gPreviewTimer[client] = null;
				}

				gCurrPoint[client]++;

				if (gCurrPoint[client] == NUM_POINTS)
				{
					float startPos[3], endPos[3];

					startPos = gPointPos[client][ POINT_A ];
					endPos   = gPointPos[client][ POINT_B ];

					// Draw a line between the two points
					DrawRing(client, startPos, RING_START_RADIUS, RING_END_RADIUS, PREVIEW_TIME, gColorGreen, FBEAM_FADEIN);
					DrawRing(client, endPos, RING_START_RADIUS, RING_END_RADIUS, PREVIEW_TIME, gColorRed, FBEAM_FADEIN);
					DrawLine(client, startPos, endPos, 1.0, PREVIEW_TIME, gColorWhite);
					gPreviewTimer[client] = CreateTimer(PREVIEW_TIME, CompleteGap, GetClientUserId(client), .flags = TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

					float distance = GetDistance(startPos, endPos);
					float difference[3];
					SubtractVectors(endPos, startPos, difference);

					if(difference[2] > 65)
					{
						Print2(client, "{CHAT}Distance: {YELLOWORANGE}%.2f {CHAT}DiifX: {YELLOWORANGE}%.2f {CHAT}DiffY: {YELLOWORANGE}%.2f {CHAT}DiffZ: {YELLOWORANGE}%.2f {CHAT}MinVelocity: {YELLOWORANGE}Impossible Jump ΔZ>65",
									distance,
									difference[0], difference[1], difference[2]);
					}
					else
					{
						// Credit to Saul for velocity calculations
						float gFallTime, gFallHeight, gFallVelocity;

						if (difference[2] > 64)
						{
							gFallHeight = 65 - difference[2]; // z distance from top of jump to selected point, assuming sv_gravity 800 is used.
						}
						else
						{
							gFallHeight = 64 - difference[2];
						}

						float m_flGravity = GetEntityGravity(client);

						float g_flGravityTick = SquareRoot(2 * 800 * 57.0) - (gGravity  * m_flGravity * 1.5 * GetTickInterval());
						gFallVelocity = -1 * SquareRoot(2 * gGravity * m_flGravity * gFallHeight); // z velocity player should have right before hitting the ground
						gFallTime = -1 * (gFallVelocity - g_flGravityTick) / gGravity * m_flGravity; // The amount of time the jump should have taken

						float gInitialVel[3];

						gInitialVel[0] = (endPos[0] - startPos[0]) / gFallTime; // Minimum velocity needed in x and y directions
						gInitialVel[1] = (endPos[1] - startPos[1]) / gFallTime; // to reach the destination

						float gMinVel = SquareRoot(Pow(gInitialVel[0], 2.0) + Pow(gInitialVel[1], 2.0));
						float gInitialTick = Pow((gMinVel - 16.97) / 30.02, 1 / 0.5029);
						float gFallTimeTicks = gFallTime * (1/GetTickInterval()); // carnifex' fault if it bugs
						float gVelGain = (30.02 * Pow(gInitialTick + gFallTimeTicks, 0.5029) + 16.97) - (30.02 * Pow(gInitialTick, 0.5029) + 16.97);
						float gMinVelOneTick = gMinVel - gVelGain;

						if(gMinVelOneTick < 0 || gMinVel < 16.97)
						{
							gMinVelOneTick = 0.0;
						}


						// Credit to Charles_(hypnos) for the implementation of velocity stuff (https://hyps.dev/)
						Print2(client, "{CHAT}Distance: {YELLOWORANGE}%.2f {CHAT}DiifX: {YELLOWORANGE}%.2f {CHAT}DiffY: {YELLOWORANGE}%.2f {CHAT}DiffZ: {YELLOWORANGE}%.2f {CHAT}MinVelocity: {YELLOWORANGE}%.2f {CHAT}MinVelocityWith1Tick: {YELLOWORANGE}%.2f",
										distance,
										difference[0], difference[1], difference[2], gMinVel, gMinVelOneTick);
					}

					gCurrPoint[client] = POINT_A;
				}
			}
			else
			{
				Print2(client, "{CHAT}Couldn't get point position (raytrace did not hit). Try again.");
			}
			OpenMenu(client);
		}
		case 2: // Show cursor
		{
			gShowCursor[client] = !gShowCursor[client];
			OpenMenu(client);
		}
		case 3: // Snap to grid
		{
			gSnapToGrid[client]++;
			gSnapToGrid[client] = gSnapToGrid[client] % sizeof(gSnapValues);

			OpenMenu(client);
		}
		case 9, 10:
		{
			gGap[client] = false;

			if (gPreviewTimer[client] != null)
			{
				KillTimer(gPreviewTimer[client]);
				gPreviewTimer[client] = null;
			}

			if (gCursorTimer[client] != null)
			{
				KillTimer(gCursorTimer[client]);
				gCursorTimer[client] = null;
			}
		}

	}
	return 0;
}

public Action CompleteGap(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!client || !gGap[client])
	{
		gPreviewTimer[client] = null;
		return Plugin_Stop;
	}

	float startPos[3], endPos[3];

	startPos = gPointPos[client][ POINT_A ];
	endPos   = gPointPos[client][ POINT_B ];

	DrawRing(client, startPos, RING_START_RADIUS, RING_END_RADIUS, PREVIEW_TIME, gColorGreen, FBEAM_FADEIN);
	DrawRing(client, endPos, RING_START_RADIUS, RING_END_RADIUS, PREVIEW_TIME, gColorRed, FBEAM_FADEIN);
	DrawLine(client, startPos, endPos, 1.0, PREVIEW_TIME, gColorWhite);

	return Plugin_Continue;
}

bool GetAimPosition(int client, float endPosition[3])
{
	float eyePosition[3];
	GetClientEyePosition(client, eyePosition);

	float eyeAngles[3];
	GetClientEyeAngles(client, eyeAngles);

	//float dirVector[3];
	//GetAngleVectors(eyeAngles, dirVector, NULL_VECTOR, NULL_VECTOR);

	TR_TraceRayFilter(eyePosition, eyeAngles, MASK_PLAYERSOLID, RayType_Infinite, TraceFilter);

	if (TR_DidHit(null))
	{
		TR_GetEndPosition(endPosition, null);

		if (gSnapToGrid[client])
		{
			endPosition = SnapToGrid(endPosition, gSnapValues[ gSnapToGrid[client] ], true);
		}
		return true;
	}
	return false;
}

public bool TraceFilter(int entity, int contentsMask)
{
	// Pass through players
	return !(0 < entity && entity <= MaxClients);
}

stock void DrawLine(int client, float start[3], float end[3], float width, float life, int color[4])
{
	float origin[3];
	GetClientAbsOrigin(client, origin);

	TE_SetupBeamPoints(start, end,
				.ModelIndex = gModelIndex,
				.HaloIndex = 0,
				.StartFrame = 0,
				.FrameRate = 0,
				.Life = life,
				.Width = width,
				.EndWidth = width,
				.FadeLength = 0,
				.Amplitude = 0.0,
				.Color = color,
				.Speed = 0);

	TE_SendToAllInRange(origin, RangeType_Visibility, .delay = 0.0);
}

stock void DrawRing(int client, float center[3], float startRadius, float endRadius, float life, int color[4], int flags = 0)
{
	float origin[3];
	GetClientAbsOrigin(client, origin);

	TE_SetupBeamRingPoint(center,
				.Start_Radius = startRadius,
				.End_Radius = endRadius,
				.ModelIndex = gModelIndex,
				.HaloIndex = 0,
				.StartFrame = 0,
				.FrameRate = 30,
				.Life = life,
				.Width = 2.0,
				.Amplitude = 0.0,
				.Color = color,
				.Speed = 3,
				.Flags = flags);

	TE_SendToAllInRange(origin, RangeType_Visibility, .delay = 0.0);
}

stock void DrawCursor(int client, float center[3], float width, float life, int color[4])
{
	if (!gShowCursor[client])
	{
		return;
	}

	Line line[3];

	for (int i = 0; i < 3; i++)
	{
		line[ i ].start = gCursorStart[ i ];
		line[ i ].end = gCursorEnd[ i ];

		//RotateClockwise(line[ i ].start, 45.0);
		//RotateClockwise(line[ i ].end, 45.0);

		AddVectors(center, line[ i ].start, line[ i ].start);
		AddVectors(center, line[ i ].end, line[ i ].end);

		DrawLine(client, line[ i ].start, line[ i ].end, width, life, color);
	}
}

void ResetVariables(int client)
{
	gGap[client] = false;
	gCurrPoint[client] = POINT_A;

	for (int i = 0; i < NUM_POINTS; i++)
	{
		gPointPos[client][i] = NULL_VECTOR;
	}

	gSnapToGrid[client] = 0; // off
	gShowCursor[client] = true;

	if (gPreviewTimer[client] != null)
	{
		KillTimer(gPreviewTimer[client]);
		gPreviewTimer[client] = null;
	}

	if (gCursorTimer[client] != null)
	{
		KillTimer(gCursorTimer[client]);
		gCursorTimer[client] = null;
	}
}

float GetDistance(float startPos[3], float endPos[3])
{
	float difference[3];
	SubtractVectors(endPos, startPos, difference);
	return GetVectorLength(difference);
}

stock float[] SnapToGrid(float pos[3], int grid, bool third)
{
    float origin[3];
    origin = pos;

    origin[0] = float(RoundToNearest(pos[0] / grid) * grid);
    origin[1] = float(RoundToNearest(pos[1] / grid) * grid);

    if(third)
    {
        origin[2] = float(RoundToNearest(pos[2] / grid) * grid);
    }

    return origin;
}

stock void RotateClockwise(float p[3], float angle) // 2d
{
	float s = Sine( DegToRad(angle) );
	float c = Cosine( DegToRad(angle) );

	p[0] = p[0] * c + p[1] * s;
	p[1] = p[1] * c - p[0] * s;
}

stock void InitColors()
{
	if (colors != null)
		return;
	
	colors = new StringMap();
	game = GetEngineVersion();

	// Reddish
	colors.SetValue("CARNATION", game != Engine_CSGO ? 0xF25A5A : 0x07)
	colors.SetValue("MAUVELOUS", game != Engine_CSGO ? 0xF29191 : 0x07)

	// Pinkish
	colors.SetValue("SUNGLO", game != Engine_CSGO ? 0xE26A7E : 0x03)
	colors.SetValue("BRICKRED", game != Engine_CSGO ? 0xCB344B : 0x03)
	colors.SetValue("YOURPINK", game != Engine_CSGO ? 0xFFCCCC : 0x03)
	colors.SetValue("HOTPINK", game != Engine_CSGO ? 0xFF69B4 : 0x03)

	// Orangish
	colors.SetValue("PUMPKIN", game != Engine_CSGO ? 0xFF711A : 0x10)
	colors.SetValue("CORAL", game != Engine_CSGO ? 0xFF914D : 0x10)
	colors.SetValue("SUNSETORANGE", game != Engine_CSGO ? 0xFF4D4D : 0x10)
	colors.SetValue("YELLOWORANGE", game != Engine_CSGO ? 0xFFA64D : 0x10)

	// Yellowish
	colors.SetValue("TURBO", game != Engine_CSGO ? 0xFAF200 : 0x09)
	colors.SetValue("LASERLEMON", game != Engine_CSGO ? 0xFFFA66 : 0x09)
	colors.SetValue("GOLD", game != Engine_CSGO ? 0xFFD700 : 0x09)

	// Greenish
	colors.SetValue("SUSHI", game != Engine_CSGO ? 0xA3BD42 : 0x06)
	colors.SetValue("WATTLE", game != Engine_CSGO ? 0xD2DD49 : 0x06)

	// Blueish
	colors.SetValue("DODGERBLUE", game != Engine_CSGO ? 0x4D91FF : 0x0B)
	colors.SetValue("PERIWINKLE", game != Engine_CSGO ? 0xB3D0FF : 0x0A)
	colors.SetValue("CYAN", game != Engine_CSGO ? 0x00FFFF : 0x0B)

	// Misc
	colors.SetValue("WHITE", game != Engine_CSGO ? 0xFFFFFF : 0x01)
	colors.SetValue("RED", game != Engine_CSGO ? 0xFF0000 : 0x02)
	colors.SetValue("BLUE", game != Engine_CSGO ? 0x3D87FF : 0x0C)
	colors.SetValue("GREEN", game != Engine_CSGO ? 0x00FF08 : 0x04)
	colors.SetValue("YELLOW", game != Engine_CSGO ? 0xFFFF00 : 0x09)
	colors.SetValue("AQUAMARINE", game != Engine_CSGO ? 0x63F8F3 : 0x0B)
	colors.SetValue("MERCURY", game != Engine_CSGO ? 0xE6E6E6 : 0x08)
	colors.SetValue("TUNDORA", game != Engine_CSGO ? 0x404040 : 0x08)
	colors.SetValue("ALTO", game != Engine_CSGO ? 0xE0E0E0 : 0x0B)

	// Defaults
	colors.SetValue("CHAT", game != Engine_CSGO ? 0xFFFFFF : 0x01)
	colors.SetValue("ADMIN", game != Engine_CSGO ? 0x99FF99 : 0x0B)
	colors.SetValue("TARGET", game != Engine_CSGO ? 0x00FF08 : 0x04)
}

stock void Print2(int client, const char[] message, any ...)
{
	InitColors();
	
	char buffer[1024], buffer2[1024];
	
	FormatEx(buffer, sizeof(buffer), "\x01%s %s", CHAT_PREFIX, message);
	VFormat(buffer2, sizeof(buffer2), buffer, 3);
	ReplaceColorCodes(buffer2, sizeof(buffer2));

	if (game != Engine_CSGO)
	{
		Handle msg = StartMessageOne("SayText2", client);
		if (msg == null) return;
		BfWriteByte(msg, 0); // author
		BfWriteByte(msg, true); // chat
		BfWriteString(msg, buffer2); // translation
		EndMessage();
	}
	else
	{
		PrintToChat(client, buffer2);
	}
}

stock void Print2All(const char[] message, any ...)
{
	InitColors();
	
	char buffer[1024], buffer2[1024];
	
	FormatEx(buffer, sizeof(buffer), "\x01%s %s", CHAT_PREFIX, message);
	VFormat(buffer2, sizeof(buffer2), buffer, 2);
	ReplaceColorCodes(buffer2, sizeof(buffer2));
	
	if (game != Engine_CSGO)
	{
		Handle msg = StartMessageAll("SayText2");
		if (msg == null) return;
		BfWriteByte(msg, 0); // author
		BfWriteByte(msg, true); // chat
		BfWriteString(msg, buffer2); // translation
		EndMessage();
	}
	else
	{
		PrintToChatAll(buffer2);
	}
}

stock void ReplaceColorCodes(char[] input, int maxlen)
{
	int cursor;
	int value;
	char tag[32], buff[32];
	char[] output = new char[maxlen];
	strcopy(output, maxlen, input);
	
	Regex regex = new Regex("{[a-zA-Z0-9]+}");
	for (int i = 0; i < 1000; i++)
	{
		if (regex.Match(input[cursor]) < 1)
		{
			delete regex;
			strcopy(input, maxlen, output);
			return;
		}

		// Found a potential tag string
		GetRegexSubString(regex, 0, tag, sizeof(tag));
		
		// Update the cursor
		cursor = StrContains(input[cursor], tag) + cursor + 1;
		
		// Get rid of brackets
		strcopy(buff, sizeof(buff), tag);
		ReplaceString(buff, sizeof(buff), "{", "");
		ReplaceString(buff, sizeof(buff), "}", "");
		
		// Does such a color exist?
		if (!colors.GetValue(buff, value))
			continue; // No, keep iterating through the string
		
		// Yes, it does. Replace text with the corresponding color
		if (game != Engine_CSGO)
			Format(buff, sizeof(buff), "\x07%06X", value);
		else
			Format(buff, sizeof(buff), "%c", value);
		
		ReplaceString(output, maxlen, tag, buff);
	}
}