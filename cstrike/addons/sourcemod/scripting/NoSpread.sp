#include <sourcemod>
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name 			= "Accuracy Nospread",
	author 			= "Haze",
	description 	= "",
	version 		= "1.1",
	url 			= "https://steamcommunity.com/id/0x134/"
};

ConVar gCV_AcurracyNoSpread = null;
ConVar gCV_AcurracyNoRecoil = null;

public void OnPluginStart()
{
	gCV_AcurracyNoSpread = CreateConVar("sm_accuracy_nospread", "1", "", 0, true, 0.0, true, 1.0);
	gCV_AcurracyNoRecoil = CreateConVar("sm_accuracy_norecoil", "1", "", 0, true, 0.0, true, 1.0);
	
	AutoExecConfig();
	
	Handle hGameData = LoadGameConfigFile("NoSpread.games");
	if(!hGameData)
	{
		delete hGameData;
		SetFailState("Failed to load Nospread gamedata.");
	}

	Handle hFireBullets = DHookCreateDetour(Address_Null, CallConv_CDECL, ReturnType_Void, ThisPointer_Ignore); 
	DHookSetFromConf(hFireBullets, hGameData, SDKConf_Signature, "FX_FireBullets");
	DHookAddParam(hFireBullets, HookParamType_Int);
	DHookAddParam(hFireBullets, HookParamType_VectorPtr);
	DHookAddParam(hFireBullets, HookParamType_VectorPtr); 
	DHookAddParam(hFireBullets, HookParamType_Int);
	DHookAddParam(hFireBullets, HookParamType_Int);
	DHookAddParam(hFireBullets, HookParamType_Int);
	DHookAddParam(hFireBullets, HookParamType_Float);
	DHookAddParam(hFireBullets, HookParamType_Float);
	DHookAddParam(hFireBullets, HookParamType_Float);
	
	delete hGameData;

	if(!DHookEnableDetour(hFireBullets, false, DHook_FireBullets))
	{
		SetFailState("Couldn't enable FX_FireBullets detour.");
	}
}

public MRESReturn DHook_FireBullets(Handle hParams)
{
	//float vOrigin[3], vAngles[3];
	//int index = DHookGetParam(hParams, 1);
	//DHookGetParamVector(hParams, 2, vOrigin);
	//DHookGetParamVector(hParams, 3, vAngles);
	//int weaponid = DHookGetParam(hParams, 4);
	//int mode = DHookGetParam(hParams, 5);
	//int seed = DHookGetParam(hParams, 6);
	//float innacuracy = DHookGetParam(hParams, 7);
	//float spread = DHookGetParam(hParams, 8);
	//float sound_time = DHookGetParam(hParams, 9);
	//PrintToChatAll("Fire: %d | (%.2f %.2f %.2f) | (%.2f %.2f %.2f) | %d | %d | %d | %.2f | %.2f | %.2f", index, vOrigin[0], vOrigin[1], vOrigin[2], vAngles[0], vAngles[1], vAngles[2], weaponid, mode, seed, innacuracy, spread, sound_time);
	
	if(gCV_AcurracyNoRecoil.BoolValue)
	{
		float vAngles[3];
		int index = DHookGetParam(hParams, 1);
		GetClientEyeAngles(index, vAngles);
		DHookSetParamVector(hParams, 3, vAngles);
	}
	
	if(gCV_AcurracyNoSpread.BoolValue)
	{
		DHookSetParam(hParams, 7, 0.0);
	}
	
	if(gCV_AcurracyNoSpread.BoolValue || gCV_AcurracyNoRecoil.BoolValue)
	{
		return MRES_ChangedOverride;
	}
	
	return MRES_Ignored;
}