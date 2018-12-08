/*
 * HexTags Plugin.
 * by: Hexah
 * https://github.com/Hexer10/HexTags
 * 
 * Copyright (C) 2017 Mattia (Hexah|Hexer10|Papero)
 *
 * This file is part of the HexTags SourceMod Plugin.
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 */
//#define DEBUG 1

#include <sourcemod>
#include <sdktools>
#include <chat-processor>
#include <geoip>
#include <hexstocks>
#include <hextags>

#undef REQUIRE_EXTENSIONS
#undef REQUIRE_PLUGIN
#include <mostactive>
#include <cstrike>
#include <rankme>
#include <warden>
#include <myjbwarden>
#include <hl_gangs>
#include <SteamWorks>
#define REQUIRE_EXTENSIONS
#define REQUIRE_PLUGIN

#define PLUGIN_AUTHOR         "Hexah"
#define PLUGIN_VERSION        "<TAG>"

#pragma semicolon 1
#pragma newdecls required

Handle fTagsUpdated;
Handle fMessageProcess;
Handle fMessageProcessed;
Handle fMessagePreProcess;

DataPack dataOrder;

ConVar cv_sFlagOrder;
ConVar cv_sDefaultGang;
ConVar cv_bParseRoundEnd;

bool bCSGO;
bool bLate;
bool bMostActive;
bool bRankme;
bool bWarden;
bool bMyJBWarden;
bool bGangs;
bool bSteamWorks = true;
bool bForceTag[MAXPLAYERS+1];

int iRank[MAXPLAYERS+1] = {-1, ...};

char sTags[MAXPLAYERS+1][eTags][128];

//Plugin info
public Plugin myinfo =
{
	name = "hextags",
	author = PLUGIN_AUTHOR,
	description = "Edit Tags & Colors!",
	version = PLUGIN_VERSION,
	url = "github.com/Hexer10/HexTags"
};

//Startup
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	//API
	RegPluginLibrary("hextags");
	
	CreateNative("HexTags_GetClientTag", Native_GetClientTag);
	CreateNative("HexTags_SetClientTag", Native_SetClientTag);
	CreateNative("HexTags_ResetClientTag", Native_ResetClientTags);
	
	fTagsUpdated = CreateGlobalForward("HexTags_OnTagsUpdated", ET_Ignore, Param_Cell);
	
	fMessageProcess = CreateGlobalForward("HexTags_OnMessageProcess", ET_Single, Param_Cell, Param_String, Param_String);
	fMessageProcessed = CreateGlobalForward("HexTags_OnMessageProcessed", ET_Ignore, Param_Cell, Param_String, Param_String);
	fMessagePreProcess = CreateGlobalForward("HexTags_OnMessagePreProcess", ET_Single, Param_Cell, Param_String, Param_String);
	
	EngineVersion engine = GetEngineVersion();
	bCSGO = (engine == Engine_CSGO || engine == Engine_CSS);
	
	//LateLoad
	bLate = late;
	return APLRes_Success;
}

//TODO: Cache client ip instead of getting it every time.
public void OnPluginStart()
{
	//CVars
	CreateConVar("sm_hextags_version", PLUGIN_VERSION, "HexTags plugin version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	cv_sFlagOrder = CreateConVar("sm_hextags_flagorder", "ztsrqponmlkjihgfedcba", "Flags in the order they should be selected.");
	cv_sDefaultGang = CreateConVar("sm_hextags_nogang", "", "Text to use if user has no tag - needs hl_gangs");
	cv_bParseRoundEnd = CreateConVar("sm_hextags_roundend", "0", "If 1 the tags will be reloaded even on round end - Suggested to be used with plugins like mostactive or rankme.");
	
	AutoExecConfig();
	
	//Reg Cmds
	RegAdminCmd("sm_reloadtags", Cmd_ReloadTags, ADMFLAG_GENERIC, "Reload HexTags plugin config");
	RegConsoleCmd("sm_getteam", Cmd_GetTeam, "Get current team name");
	
	//Event hooks
	if (!HookEventEx("round_end", Event_RoundEnd))
		LogError("Failed to hook \"round_end\", \"sm_hextags_roundend\" won't produce any effect.");
	
#if defined DEBUG
	RegConsoleCmd("sm_gettagvars", Cmd_GetVars);
#endif
}

public void OnAllPluginsLoaded()
{	
	Debug_Print("Called OnAllPlugins!");
	
	if (FindPluginByFile("custom-chatcolors-cp.smx") || LibraryExists("ccc"))
		LogMessage("[HexTags] Found Custom Chat Colors running!\n	Please avoid running it with this plugin!");
	
	bMostActive = LibraryExists("mostactive");
	bRankme = LibraryExists("rankme");
	bWarden = LibraryExists("warden");
	bMyJBWarden = LibraryExists("myjbwarden");
	bGangs = LibraryExists("gl_gangs");
	bSteamWorks = LibraryExists("SteamWorks");
	
	LoadKv();
	if (bLate) for (int i = 1; i <= MaxClients; i++)if (IsClientInGame(i))OnClientPostAdminCheck(i);
	
	//Timers
	if (bCSGO)
		CreateTimer(5.0, Timer_ForceTag, _, TIMER_REPEAT);
}


public void OnLibraryAdded(const char[] name)
{
	Debug_Print("Called OnLibraryAdded %s", name);
	if (StrEqual(name, "mostactive"))
	{
		bMostActive = true;
	}
	else if (StrEqual(name, "rankme"))
	{
		bRankme = true;
	}
	else if (StrEqual(name, "warden"))
	{
		bWarden = true;
	}
	else if (StrEqual(name, "myjbwarden"))
	{
		bMyJBWarden = true;
	}
	else if (StrEqual(name, "hl_gangs"))
	{
		bGangs = true;
	}
	else if (StrEqual(name, "SteamWorks", false))
	{
		bSteamWorks = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	Debug_Print("Called OnLibraryRemoved %s", name);
	if (StrEqual(name, "mostactive"))
	{
		bMostActive = false;
		LoadKv();
	}
	else if (StrEqual(name, "rankme"))
	{
		bRankme = false;
		LoadKv();
	}
	else if (StrEqual(name, "warden"))
	{
		bWarden = false;
		LoadKv();
	}
	else if (StrEqual(name, "myjbwarden"))
	{
		bMyJBWarden = false;
		LoadKv();
	}
	else if (StrEqual(name, "hl_gangs"))
	{
		bGangs = false;
		LoadKv();
	}
	else if (StrEqual(name, "SteamWorks", false))
	{
		bSteamWorks = false;
		LoadKv();
	}
}


//Thanks to https://forums.alliedmods.net/showpost.php?p=2573907&postcount=6
public Action OnClientCommandKeyValues(int client, KeyValues kv)
{
	char sKey[64]; 
	
	if (!kv.GetSectionName(sKey, sizeof(sKey)))
		return Plugin_Continue;
	
#if defined DEBUG
	char sKV[256];
	kv.ExportToString(sKV, sizeof(sKV));
	Debug_Print("Called ClientCmdKv: %s\n%s\n", sKey, sKV);
#endif
	
	if(StrEqual(sKey, "ClanTagChanged"))
	{
		//RequestFrame(Frame_SetTag, GetClientUserId(client));
		LoadTags(client);
		kv.SetString("tag", sTags[client][ScoreTag]);
		return Plugin_Changed;
	}
	
	return Plugin_Continue; 
}

public void Frame_SetTag(any client)
{
	LoadTags(GetClientOfUserId(client));
}

public void OnClientDisconnect(int client)
{
	ResetTags(client);
}

public void warden_OnWardenCreated(int client)
{
	RequestFrame(Frame_LoadTag, client);
}

public void warden_OnWardenRemoved(int client)
{
	//TODO Set the original clantag
	if (bCSGO)
		CS_SetClientClanTag(client, "");
	
	RequestFrame(Frame_LoadTag, client);
	
}

public void warden_OnDeputyCreated(int client)
{
	RequestFrame(Frame_LoadTag, client);
}

public void warden_OnDeputyRemoved(int client)
{
	//TODO Set the original clantag
	if (bCSGO)
		CS_SetClientClanTag(client, "");
	
	RequestFrame(Frame_LoadTag, client);
}

//Commands
public Action Cmd_ReloadTags(int client, int args)
{
	LoadKv();
	for (int i = 1; i <= MaxClients; i++)if (IsClientInGame(i))LoadTags(i);
	
	ReplyToCommand(client, "[SM] Tags succesfully reloaded!");
	return Plugin_Handled;
}

public Action Cmd_GetTeam(int client, int args)
{
	char sTeam[32];
	GetTeamName(GetClientTeam(client), sTeam, sizeof(sTeam));
	ReplyToCommand(client, "[SM] Current team name: %s", sTeam);
	return Plugin_Handled;
}

#if defined DEBUG
public Action Cmd_GetVars(int client, int args)
{
	ReplyToCommand(client, sTags[client][ScoreTag]);
	ReplyToCommand(client, sTags[client][ChatTag]);
	ReplyToCommand(client, sTags[client][ChatColor]);
	ReplyToCommand(client, sTags[client][NameColor]);
	return Plugin_Handled;
}
#endif

//Events
public void OnClientPostAdminCheck(int client)
{
	if (bRankme)
	{
		RankMe_GetRank(client, RankMe_LoadTags);
		return;
	}
	LoadTags(client);
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!cv_bParseRoundEnd.BoolValue)
		return;
	
	if (bLate) for (int i = 1; i <= MaxClients; i++)if (IsClientInGame(i))OnClientPostAdminCheck(i);
}

public Action RankMe_LoadTags(int client, int rank, any data)
{
	iRank[client] = rank;
	LoadTags(client);
}

public Action CP_OnChatMessage(int& author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool& processcolors, bool& removecolors)
{
	Action result = Plugin_Continue;
	//Call the forward
	Call_StartForward(fMessagePreProcess);
	Call_PushCell(author);
	Call_PushStringEx(name, MAXLENGTH_NAME, SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushStringEx(message, MAXLENGTH_MESSAGE, SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_Finish(result);
	
	if (result >= Plugin_Handled)
	{
		return Plugin_Continue;
	}
	
	//Add colors & tags
	char sNewName[MAXLENGTH_NAME];
	char sNewMessage[MAXLENGTH_MESSAGE];
	Format(sNewName, MAXLENGTH_NAME, "%s%s%s{default}", sTags[author][ChatTag], sTags[author][NameColor], name); 
	Format(sNewMessage, MAXLENGTH_MESSAGE, "%s%s", sTags[author][ChatColor], message);
	
	//Update the params
	char sTime[16];
	FormatTime(sTime, sizeof(sTime), "%H:%M");  
	ReplaceString(sNewName, sizeof(sNewName), "{time}", sTime);
	ReplaceString(sNewMessage, sizeof(sNewMessage), "{time}", sTime);
	
	
	char sIP[32];
	char sCountry[3];
	GetClientIP(author, sIP, sizeof(sIP));
	GeoipCode2(sIP, sCountry);
	ReplaceString(sNewName, sizeof(sNewName), "{country}", sCountry);
	ReplaceString(sNewMessage, sizeof(sNewMessage), "{country}", sCountry);
	
	if (bGangs)
	{
		char sGang[32];
		Gangs_HasGang(author) ?  Gangs_GetGangName(author, sGang, sizeof(sGang)) : cv_sDefaultGang.GetString(sGang, sizeof(sGang));
		
		ReplaceString(sNewName, sizeof(sNewName), "{gang}", sGang);
		ReplaceString(sNewMessage, sizeof(sNewMessage), "{gang}", sGang);
	}
	
	if (bRankme)
	{
		char sPoints[16];
		IntToString(RankMe_GetPoints(author), sPoints, sizeof(sPoints));
		ReplaceString(sNewName, sizeof(sNewName), "{rmPoints}", sPoints);
		ReplaceString(sNewMessage, sizeof(sNewMessage), "{rmPoints}", sPoints);
		
		char sRank[16];
		IntToString(iRank[author], sRank, sizeof(sRank));
		ReplaceString(sNewName, sizeof(sNewName), "{rmRank}", sRank);
		ReplaceString(sNewMessage, sizeof(sNewMessage), "{rmRank}", sRank);
	}
	
	//Rainbow Chat
	if (StrEqual(sTags[author][ChatColor], "{rainbow}", false))
	{
		ReplaceString(sNewMessage, sizeof(sNewMessage), "{rainbow}", "");
		char sTemp[MAXLENGTH_MESSAGE]; 
		
		int color;
		int len = strlen(sNewMessage);
		for(int i = 0; i < len; i++)
		{
			if (IsCharSpace(sNewMessage[i]))
			{
				Format(sTemp, sizeof(sTemp), "%s%c", sTemp, sNewMessage[i]);
				continue;
			}
			
			int bytes = GetCharBytes(sNewMessage[i])+1;
			char[] c = new char[bytes];
			strcopy(c, bytes, sNewMessage[i]);
			Format(sTemp, sizeof(sTemp), "%s%c%s", sTemp, GetColor(++color), c);
			if (IsCharMB(sNewMessage[i]))
				i += bytes-2;
		}		
		Format(sNewMessage, MAXLENGTH_MESSAGE, "%s", sTemp); 
	}
	
	//Random Chat
	if (StrEqual(sTags[author][ChatColor], "{random}", false))
	{
		ReplaceString(sNewMessage, sizeof(sNewMessage), "{random}", "");
		char sTemp[MAXLENGTH_MESSAGE]; 
		
		int len = strlen(sNewMessage);
		for(int i = 0; i < len; i++)
		{
			if (IsCharSpace(sNewMessage[i]))
			{
				Format(sTemp, sizeof(sTemp), "%s%c", sTemp, sNewMessage[i]);
				continue;
			}
			
			int bytes = GetCharBytes(sNewMessage[i])+1;
			char[] c = new char[bytes];
			strcopy(c, bytes, sNewMessage[i]);
			Format(sTemp, sizeof(sTemp), "%s%c%s", sTemp, GetRandomColor(), c);
			if (IsCharMB(sNewMessage[i]))
				i += bytes-2;
		}		
		Format(sNewMessage, MAXLENGTH_MESSAGE, "%s", sTemp); 
	}
	
	char sPassedName[MAXLENGTH_NAME];
	char sPassedMessage[MAXLENGTH_NAME];
	sPassedName = sNewName;
	sPassedMessage = sNewMessage;
	
	
	result = Plugin_Continue;
	//Call the forward
	Call_StartForward(fMessageProcess);
	Call_PushCell(author);
	Call_PushStringEx(sPassedName, sizeof(sPassedName), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushStringEx(sPassedMessage, sizeof(sPassedMessage), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_Finish(result);
	
	if (result == Plugin_Continue)
	{
    	//Update the name & message
		strcopy(name, MAXLENGTH_NAME, sNewName);
		strcopy(message, MAXLENGTH_MESSAGE, sNewMessage);
	}
	else if (result == Plugin_Changed)
	{
    	//Update the name & message
		strcopy(name, MAXLENGTH_NAME, sPassedName);
		strcopy(message, MAXLENGTH_MESSAGE, sPassedMessage);
	}
	else
	{
		return Plugin_Continue;
	}
	
	processcolors = true;
	removecolors = false;
	
	
	//Call the (post)forward
	Call_StartForward(fMessageProcessed);
	Call_PushCell(author);
	Call_PushString(sPassedName);
	Call_PushString(sPassedMessage);
	Call_Finish();
	
	return Plugin_Changed;
}

//Functions
char sTagConf[PLATFORM_MAX_PATH];

void LoadKv()
{
	char sConfig[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sConfig, sizeof(sConfig), "configs/hextags-order.txt"); //Get cfg file
	
	if (!FileExists(sConfig))
	{
		File file = OpenFile(sConfig, "wt");
		if (file == null)
			SetFailState("Failed to created: \"%s\"", sConfig); //Check if cfg exist
		
		file.WriteLine("SteamID");
		file.WriteLine("AdminGroup");
		file.WriteLine("AdminFlags");
		file.WriteLine("Warden");
		file.WriteLine("Deputy");
		file.WriteLine("NoPrime");
		file.WriteLine("ActiveTime");
		file.WriteLine("RankMe");
		file.WriteLine("Team");
		delete file;
	}
	
	File file = OpenFile(sConfig, "rt");
	if (file == null)
		SetFailState("Couldn't find: \"%s\"", sConfig); //Check if cfg exist
	
	GetOrder(file);
	BuildPath(Path_SM, sConfig, sizeof(sConfig), "configs/hextags.cfg"); //Get cfg file
	
	if (OpenFile(sConfig, "rt") == null)
		SetFailState("Couldn't find: \"%s\"", sConfig); //Check if cfg exist
	
	KeyValues kv = new KeyValues("HexTags"); //Create the kv
	
	if (!kv.ImportFromFile(sConfig))
		SetFailState("Couldn't import: \"%s\"", sConfig); //Check if file was imported properly
	
	if (!kv.GotoFirstSubKey())
		LogMessage("No entries found in: \"%s\"", sConfig); //Notify that there aren't any entries
	
	delete kv;
	strcopy(sTagConf, sizeof(sTagConf), sConfig);
}
void LoadTags(int client, KeyValues kv = null)
{
	if (!IsValidClient(client, true, true))
		return;
	
	//Clear the tags when re-checking
	ResetTags(client);
	
	if (kv == null)
	{
		kv = new KeyValues("HexTags");
		kv.ImportFromFile(sTagConf);
		Debug_Print("KeyValue handle: %i", kv);
	}
	
	dataOrder.Reset();
	while(dataOrder.IsReadable(1))
	{
		//Debug_Print("Called: %i", dataOrder.Position);
		bool res;
		Function func = dataOrder.ReadFunction();
		Call_StartFunction(INVALID_HANDLE, func);
		Call_PushCell(client);
		Call_PushCell(kv);
		Call_Finish(res);
		if (res)
		{
			LoadTags(client, kv);
			return;
		}
	}
	
	//Check for 'All' entry
	//Mark as depreaced
	if (kv.JumpToKey("Default"))
	{
		LogMessage("[HexTags] Default select is depreaced! Put the tags without any selector to make them on every player");
		LoadTags(client, kv);
		return;
	}
	GetTags(client, kv, true);
	delete kv;
}

//Timers
public Action Timer_ForceTag(Handle timer)
{
	if (!bCSGO)
		return;
	
	for (int i = 1; i <= MaxClients; i++)if (IsClientInGame(i) && bForceTag[i] && strlen(sTags[i][ScoreTag]) > 0)
	{
		char sTag[32];
		CS_GetClientClanTag(i, sTag, sizeof(sTag));
		if (StrEqual(sTag, sTags[i][ScoreTag]))
			continue;
		
		LogMessage("%L was changed by an external plugin, forcing him back to the HexTags' default one!", i, sTag);
		CS_SetClientClanTag(i, sTags[i][ScoreTag]);
	}
}

//Frams
public void Frame_LoadTag(any client)
{
	LoadTags(client);
}

//Tags selectors.
bool Select_SteamID(int client, KeyValues kv)
{
	char steamid[32];
	if (!GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid)))
		return false;
	
	if (kv.JumpToKey(steamid))
	{
		return true;
	}
	
	//Replace the STEAM_1 to STEAM_0 or viceversa
	if (steamid[6] == '1')
		steamid[6] = '0'; 
	else
		steamid[6] = '1';
	
	//Check again with STEAM_0/STEAM_1
	if (kv.JumpToKey(steamid)) 
	{
		return true;
	}
	return false;
}

bool Select_AdminGroup(int client, KeyValues kv)
{
	AdminId admin = GetUserAdmin(client);
	if (admin != INVALID_ADMIN_ID)
	{
		char sGroup[32];
		admin.GetGroup(0, sGroup, sizeof(sGroup));
		Format(sGroup, sizeof(sGroup), "@%s", sGroup);
		
		return kv.JumpToKey(sGroup);
	}
	return false;
}

bool Select_Flags(int client, KeyValues kv)
{
	AdminId admin = GetUserAdmin(client);
	if (admin == INVALID_ADMIN_ID)
		return false;
	
	char sFlags[32];
	cv_sFlagOrder.GetString(sFlags, sizeof(sFlags));
	
	int len = strlen(sFlags);
	Debug_Print("Flags: %s", sFlags);
	for (int i = 0; i < len; i++)
	{
		char sFlag[1];
		sFlag[0] = sFlags[i];
		
		AdminFlag flag;
		if (!FindFlagByChar(sFlags[i], flag))
		{
			LogError("Failed to read flag: %s", sFlag);
			return false;
		}
		
		
		if (admin.HasFlag(flag))
		{
			if (kv.JumpToKey(sFlag))
				return true;
			
			continue;
		}
	}
	return false;
}

bool Select_Time(int client, KeyValues kv)
{
	int iOldTime;
	bool bReturn;
	
	if (!kv.GotoFirstSubKey())
		return false;
	do
	{
		char sSecs[16];
		kv.GetSectionName(sSecs, sizeof(sSecs));
		
		if (sSecs[0] != '#') //Check if it's a "time-format"
			continue;
		
		Format(sSecs, sizeof(sSecs), "%s", sSecs[1]); //Cut the '#' at the start
		
		if (iOldTime >= StringToInt(sSecs)) //Select only the higher time.
			continue;
		
		if (StringToInt(sSecs) <= MostActive_GetPlayTimeTotal(client))
		{
			iOldTime = StringToInt(sSecs); //Save the time
			bReturn = true; 
		}
	}
	while (kv.GotoNextKey());
	
	if (bReturn)
		return true;
	
	kv.GoBack();
	return false;
}

bool Select_Rankme(int client, KeyValues kv)
{
	int iOldRank;
	bool bReturn;
	
	if (!kv.GotoFirstSubKey())
		return false;
	do
	{
		char sSecs[16];
		kv.GetSectionName(sSecs, sizeof(sSecs));
		
		if (sSecs[0] != '!') //Check if it's a "time-format"
			continue;
		
		Format(sSecs, sizeof(sSecs), "%s", sSecs[1]); //Cut the '#' at the start
		
		if (iOldRank >= StringToInt(sSecs)) //Select only the higher time.
			continue;
		
		if (StringToInt(sSecs) <= RankMe_GetPoints(client))
		{
			iOldRank = StringToInt(sSecs); //Save the time
			bReturn = true; 
		}
	}
	while (kv.GotoNextKey());
	
	if (bReturn)
		return true;
	
	kv.GoBack();
	return false;
}

bool Select_Team(int client, KeyValues kv)
{
	char sTeam[32];
	int team = GetClientTeam(client);
	GetTeamName(team, sTeam, sizeof(sTeam));
	
	return kv.JumpToKey(sTeam);
}

bool Select_Warden(int client, KeyValues kv)
{
	if (warden_iswarden(client) && kv.JumpToKey("warden"))
	{
		Debug_Print("Called Select_Warden: true");
		return true;
	}
	return false;
}

bool Select_Deputy(int client, KeyValues kv)
{
	if (warden_deputy_isdeputy(client) && kv.JumpToKey("deputy"))
	{
		return true;
	}
	return false;
}

bool Select_NoPrime(int client, KeyValues kv)
{
	if (k_EUserHasLicenseResultDoesNotHaveLicense == SteamWorks_HasLicenseForApp(client, 624820) && kv.JumpToKey("NoPrime"))
	{
		return true;
	}
	return false;
}
//Stocks

//TODO Remove final parameter.
void GetTags(int client, KeyValues kv, bool final = false)
{
	if (!final)
	{
		LoadTags(client, kv);
		return;
	}
	
	char sSection[64];
	kv.GetSectionName(sSection, sizeof(sSection));
	Debug_Print("Section: %s", sSection);
	
	if (StrEqual(sSection, "HexTags", false))
		return;
	
	Call_StartForward(fTagsUpdated);
	Call_PushCell(client);
	Call_Finish();
	
	kv.GetString("ScoreTag", sTags[client][ScoreTag], sizeof(sTags[][]), "");
	kv.GetString("ChatTag", sTags[client][ChatTag], sizeof(sTags[][]), "");
	kv.GetString("ChatColor", sTags[client][ChatColor], sizeof(sTags[][]), "");
	kv.GetString("NameColor", sTags[client][NameColor], sizeof(sTags[][]), "{teamcolor}");
	bForceTag[client] = kv.GetNum("ForceTag", 1) == 1;
	
	
	if (strlen(sTags[client][ScoreTag]) > 0 && bCSGO)
	{
		//Update params
		if (StrContains(sTags[client][ScoreTag], "{country}") != -1)
		{
			char sIP[32];
			char sCountry[3];
			if (!GetClientIP(client, sIP, sizeof(sIP)))
				LogError("Unable to get %L ip!", client);
			GeoipCode2(sIP, sCountry);
			ReplaceString(sTags[client][ScoreTag], sizeof(sTags[][]), "{country}", sCountry);
		}
		if (bGangs && StrContains(sTags[client][ScoreTag], "{gang}") != -1)
		{
			char sGang[32];
			Gangs_HasGang(client) ?  Gangs_GetGangName(client, sGang, sizeof(sGang)) : cv_sDefaultGang.GetString(sGang, sizeof(sGang));
			ReplaceString(sTags[client][ScoreTag], sizeof(sTags[][]), "{gang}", sGang);
		}
		if (bRankme && StrContains(sTags[client][ScoreTag], "{rmPoints}") != -1)
		{
			char sPoints[16];
			IntToString(RankMe_GetPoints(client), sPoints, sizeof(sPoints));
			ReplaceString(sTags[client][ScoreTag], sizeof(sTags[][]), "{rmPoints}", sPoints);
		}
		if (bRankme && StrContains(sTags[client][ScoreTag], "{rmRank}") != -1)
		{
			char sRank[16];
			IntToString(iRank[client], sRank, sizeof(sRank));
			ReplaceString(sTags[client][ScoreTag], sizeof(sTags[][]), "{rmRank}", sRank);
		}
		
		Debug_Print("Setted tag: %s", sTags[client][ScoreTag]);
		CS_SetClientClanTag(client, sTags[client][ScoreTag]); //Instantly load the score-tag
	}
	Debug_Print("Succesfully setted tags");
}

void ResetTags(int client)
{
	strcopy(sTags[client][ScoreTag], sizeof(sTags[][]), "");
	strcopy(sTags[client][ChatTag], sizeof(sTags[][]), "");
	strcopy(sTags[client][ChatColor], sizeof(sTags[][]), "");
	strcopy(sTags[client][NameColor], sizeof(sTags[][]), "");
	bForceTag[client] = true;
	iRank[client] = -1;
}

void GetOrder(File file)
{
	if (dataOrder != null)
		delete dataOrder;
	
	dataOrder = new DataPack();
	char sLine[32];
	while(file.ReadLine(sLine, sizeof(sLine)))
	{
		TrimString(sLine);
		if (StrEqual(sLine, "SteamID", false))
		{
			Debug_Print("Added: %s", sLine);
			dataOrder.WriteFunction(Select_SteamID);
		}
		else if (StrEqual(sLine, "AdminGroup", false))
		{
			Debug_Print("Added: %s", sLine);
			dataOrder.WriteFunction(Select_AdminGroup);
		}
		else if (StrEqual(sLine, "AdminFlags", false))
		{
			Debug_Print("Added: %s", sLine);
			dataOrder.WriteFunction(Select_Flags);
		}
		else if (StrEqual(sLine, "Warden", false))
		{
			if (!bWarden)
			{
				LogMessage("[HexTags] Disabling Warden support...");
				continue;
			}
			Debug_Print("Added: %s", sLine);
			dataOrder.WriteFunction(Select_Warden);
		}
		else if (StrEqual(sLine, "Deputy", false))
		{
			if (!bMyJBWarden)
			{
				LogMessage("[HexTags] Disabling (MyJB)Warden support...");
				continue;
			}
			Debug_Print("Added: %s", sLine);
			dataOrder.WriteFunction(Select_Deputy);
		}
		else if (StrEqual(sLine, "ActiveTime", false))
		{
			if (!bMostActive)
			{
				LogMessage("[HexTags] Disabling MostActive support...");
				continue;
			}
			Debug_Print("Added: %s", sLine);
			dataOrder.WriteFunction(Select_Time);
		}
		else if (StrEqual(sLine, "RankMe", false))
		{
			if (!bRankme)
			{
				LogMessage("[HexTags] Disabling RankMe support...");
				continue;
			}
			Debug_Print("Added: %s", sLine);
			dataOrder.WriteFunction(Select_Rankme);
		}
		else if (StrEqual(sLine, "Team", false))
		{
			Debug_Print("Added: %s", sLine);
			dataOrder.WriteFunction(Select_Team);
		}
		else if (StrEqual(sLine, "NoPrime", false))
		{
			if (!bSteamWorks)
			{
				LogMessage("[HexTags] Disabling SteamWorks support...");
				continue;
			}
			Debug_Print("Added: %s", sLine);
			dataOrder.WriteFunction(Select_NoPrime);
		}
		else
		{
			LogError("Invalid selector: %s", sLine);
		}
	}
}

int GetRandomColor()
{
	switch(GetRandomInt(1, 16))
	{
		case  1: return '\x01';
		case  2: return '\x02';
		case  3: return '\x03';
		case  4: return '\x03';
		case  5: return '\x04';
		case  6: return '\x05';
		case  7: return '\x06';
		case  8: return '\x07';
		case  9: return '\x08';
		case 10: return '\x09';
		case 11: return '\x10';
		case 12: return '\x0A';
		case 13: return '\x0B';
		case 14: return '\x0C';
		case 15: return '\x0E';
		case 16: return '\x0F';
	}
	return '\01';
}

int GetColor(int color)
{
	while(color > 7)
		color -= 7;
	
	switch(color)
	{
		case  1: return '\x02';
		case  2: return '\x10';
		case  3: return '\x09';
		case  4: return '\x06';
		case  5: return '\x0B';
		case  6: return '\x0C';
		case  7: return '\x0E';
	}
	return '\x01';
}

//API
public int Native_GetClientTag(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (client < 1 || client > MaxClients)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	eTags Tag = view_as<eTags>(GetNativeCell(2));
	
	SetNativeString(3, sTags[client][Tag], GetNativeCell(4));
	return 0;
}

public int Native_SetClientTag(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (client < 1 || client > MaxClients)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	char sTag[32];
	eTags Tag = view_as<eTags>(GetNativeCell(2));
	GetNativeString(3, sTag, sizeof(sTag));
	
	
	ReplaceString(sTag, sizeof(sTag), "{darkgray}", "{gray2}");
	strcopy(sTags[client][Tag], sizeof(sTags[][]), sTag);
	return 0;
}

public int Native_ResetClientTags(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (client < 1 || client > MaxClients)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	LoadTags(client);
	return 0;
}