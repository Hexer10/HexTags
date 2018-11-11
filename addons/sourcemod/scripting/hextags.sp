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
#define REQUIRE_EXTENSIONS
#define REQUIRE_PLUGIN

#define PLUGIN_AUTHOR         "Hexah"
#define PLUGIN_VERSION        "<TAG>"

#pragma semicolon 1
#pragma newdecls required

Handle fTagsUpdated;
Handle fMessageProcess;
Handle fMessageProcessed;

bool bCSGO;
bool bLate;
bool bMostActive;
bool bRankme;
bool bWarden;
bool bMyJBWarden;

int iRank[MAXPLAYERS+1] = {-1, ...};

char sTags[MAXPLAYERS+1][eTags][128];
bool bForceTag[MAXPLAYERS+1];

KeyValues kv;

DataPack dataOrder;

//Plugin infos
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
	
	fMessageProcess = CreateGlobalForward("HexTags_OnMessageProcess", ET_Single, Param_Cell, Param_String, Param_Cell, Param_String, Param_Cell);
	fMessageProcessed = CreateGlobalForward("HexTags_OnMessageProcessed", ET_Ignore, Param_Cell, Param_String, Param_String);
	
	EngineVersion engine = GetEngineVersion();
	bCSGO = (engine == Engine_CSGO || engine == Engine_CSS);
	
	//LateLoad
	bLate = late;
	return APLRes_Success;
}

//TODO: Cache client ip instead of getting it every time.
public void OnPluginStart()
{
	CreateConVar("sm_hextags_version", PLUGIN_VERSION, "HexTags plugin version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	//Reg Cmds
	RegAdminCmd("sm_reloadtags", Cmd_ReloadTags, ADMFLAG_GENERIC, "Reload HexTags plugin config");
	RegConsoleCmd("sm_getteam", Cmd_GetTeam, "Get current team name");
	
	LoadKv();
	
	//LateLoad
	if (bLate)
	{
		for (int i = 1; i <= MaxClients; i++)if (IsClientInGame(i)) 
		{
			OnClientPostAdminCheck(i); 
			Frame_SetTag(GetClientUserId(i));
		}
	}
	
	//Timers
	if (bCSGO)
		CreateTimer(5.0, Timer_ForceTag, _, TIMER_REPEAT);
}

public void OnAllPluginsLoaded()
{
	bMostActive = LibraryExists("mostactive");
	bRankme = LibraryExists("rankme");
	bWarden = LibraryExists("warden");
	bMyJBWarden = LibraryExists("myjbwarden");
	
	if (FindPluginByFile("custom-chatcolors-cp.smx") || LibraryExists("ccc"))
		LogMessage("[HexTags] Found Custom Chat Colors running!\n	Please avoid running it with this plugin!");
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "mostactive"))
	{
		bMostActive = true;
		LoadKv();
	}
	else if (StrEqual(name, "rankme"))
	{
		bRankme = true;
		LoadKv();
	}
	else if (StrEqual(name, "warden"))
	{
		bWarden = true;
	}
	else if (StrEqual(name, "myjbwarden"))
	{
		bMyJBWarden = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
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
	}
	else if (StrEqual(name, "myjbwarden"))
	{
		bMyJBWarden = false;
	}
}


//Thanks to https://forums.alliedmods.net/showpost.php?p=2573907&postcount=6
public Action OnClientCommandKeyValues(int client, KeyValues TagKv)
{
	char sKey[64]; 
	
	if (!TagKv.GetSectionName(sKey, sizeof(sKey)))
		return Plugin_Continue;
	
	//TODO: Set the key value tag instead of requesting the frame.
	if(StrEqual(sKey, "ClanTagChanged"))
	{
		RequestFrame(Frame_SetTag, GetClientUserId(client));
	}
	
	return Plugin_Continue; 
}

public void Frame_SetTag(any iUserID)
{
	int client = GetClientOfUserId(iUserID);
	LoadTags(client);
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
	RequestFrame(Frame_LoadTag, client);
	
}

public void warden_OnDeputyCreated(int client)
{
	RequestFrame(Frame_LoadTag, client);
}

public void warden_OnDeputyRemoved(int client)
{
	RequestFrame(Frame_LoadTag, client);
}

//Commands
public Action Cmd_ReloadTags(int client, int args)
{
	LoadKv();
	for (int i = 1; i <= MaxClients; i++)if (IsClientInGame(i))OnClientPostAdminCheck(i);
	
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

//Events
public void OnClientPostAdminCheck(int client)
{
	LoadTags(client);
	
	if (bRankme)
		RankMe_GetRank(client, RankMe_CheckRank);
}


public Action CP_OnChatMessage(int& author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool& processcolors, bool& removecolors)
{
	
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
	
	//Rainbow Chat
	if (StrEqual(sTags[author][ChatColor], "{rainbow}", false))
	{
		ReplaceString(sNewMessage, sizeof(sNewMessage), "{rainbow}", "");
		char sTemp[MAXLENGTH_MESSAGE]; 
		
		int sub = -1;
		for(int i = 0; i < strlen(sNewMessage); i++)
		{
			if (sNewMessage[i] == ' ')
			{
				Format(sTemp, sizeof(sTemp), "%s%c", sTemp, sNewMessage[i]);
				sub++;
				continue;
			}
			Format(sTemp, sizeof(sTemp), "%s%c%c", sTemp, GetColor(i-sub), sNewMessage[i]);
		}
		
		Format(sNewMessage, MAXLENGTH_MESSAGE, "%s", sTemp); 
	}
	
	//Random Chat
	if (StrEqual(sTags[author][ChatColor], "{random}", false))
	{
		ReplaceString(sNewMessage, sizeof(sNewMessage), "{random}", "");
		char sTemp[MAXLENGTH_MESSAGE]; 
		
		for(int i = 0; i < strlen(sNewMessage); i++)
		{
			if (sNewMessage[i] == ' ')
			{
				Format(sTemp, sizeof(sTemp), "%s%c", sTemp, sNewMessage[i]);
				continue;
			}
			Format(sTemp, sizeof(sTemp), "%s%c%c", sTemp, GetRandomColor(), sNewMessage[i]);
		}
		
		Format(sNewMessage, MAXLENGTH_MESSAGE, "%s", sTemp); 
	}
	
	char sPassedName[MAXLENGTH_NAME];
	char sPassedMessage[MAXLENGTH_NAME];
	sPassedName = sNewName;
	sPassedMessage = sNewMessage;
	
	
	Action result = Plugin_Continue;
	//Call the forward
	Call_StartForward(fMessageProcess);
	Call_PushCell(author);
	Call_PushStringEx(sPassedName, sizeof(sPassedName), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(sizeof(sPassedName));
	Call_PushStringEx(sPassedMessage, sizeof(sPassedMessage), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(sizeof(sPassedMessage));
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

public int RankMe_CheckRank(int client, int rank, any data)
{
	LoadTags(client);
}

//Functions
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
	
	if (kv != null)
		delete kv;
	
	kv = new KeyValues("HexTags"); //Create the kv
	
	if (!kv.ImportFromFile(sConfig))
		SetFailState("Couldn't import: \"%s\"", sConfig); //Check if file was imported properly
	
	if (!kv.GotoFirstSubKey())
		LogMessage("No entries found in: \"%s\"", sConfig); //Notify that there aren't any entries
}

void LoadTags(int client, bool sub = false)
{
	if (!client)
		return;
	
	//Clear the tags when re-checking
	ResetTags(client);
	
	if (!sub)
		kv.Rewind();
	
	dataOrder.Reset();
	while(dataOrder.IsReadable(1))
	{
		bool res;
		Function func = dataOrder.ReadFunction();
		Call_StartFunction(INVALID_HANDLE, func);
		Call_PushCell(client);
		Call_Finish(res);
		if (res)
			return;
	}
	
	//Check for 'All' entry
	//Mark as depreaced
	if (kv.JumpToKey("Default"))
	{
		LogMessage("[HexTags] Default select is depreaced! Put the tags without any selector to make them on every player");
		GetTags(client);
		return;
	}
	GetTags(client, true);
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
bool Select_SteamID(int client)
{
	char steamid[32];
	if (!GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid)))
		return false;
	
	if (kv.JumpToKey(steamid))
	{
		GetTags(client, false);
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
		GetTags(client);
		return true;
	}
	return false;
}

bool Select_AdminGroup(int client)
{
	AdminId admin = GetUserAdmin(client);
	if (admin != INVALID_ADMIN_ID)
	{
		char sGroup[32];
		admin.GetGroup(0, sGroup, sizeof(sGroup));
		Format(sGroup, sizeof(sGroup), "@%s", sGroup);
		
		if (kv.JumpToKey(sGroup))
		{
			GetTags(client);
			return true;
		}
	}
	return false;
}

bool Select_Flags(int client)
{
	static char sFlags[21] = "abcdefghijklmnopqrstz";
	
	for (int i = sizeof(sFlags)-1; 0 <= i; i--)
	{
		char sFlag[1];
		sFlag[0] = sFlags[i];
		
		if (ReadFlagString(sFlag) & GetUserFlagBits(client))
		{
			if (kv.JumpToKey(sFlag))
			{
				GetTags(client);
				return true;
			}
		}
	}
	return false;
}

bool Select_Time(int client)
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
			GetTags(client);
			iOldTime = StringToInt(sSecs); //Save the time
			bReturn = true; 
		}
	}
	while (kv.GotoNextKey());
	
	if (bReturn)
		return true;
	
	return false;
}

bool Select_Rankme(int client)
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
		
		if (StringToInt(sSecs) <= iRank[client])
		{
			GetTags(client);
			iOldRank = StringToInt(sSecs); //Save the time
			bReturn = true; 
		}
	}
	while (kv.GotoNextKey());
	
	if (bReturn)
		return true;

	return false;
}

bool Select_Team(int client)
{
	char sTeam[32];
	int team = GetClientTeam(client);
	GetTeamName(team, sTeam, sizeof(sTeam));
	
	if (kv.JumpToKey(sTeam))
	{
		GetTags(client);
		return true;
	}
	return false;
}

bool Select_Warden(int client)
{
	if (warden_iswarden(client) && kv.JumpToKey("warden"))
	{
		GetTags(client);
		return true;
	}
	return false;
}

bool Select_Deputy(int client)
{
	if (warden_deputy_isdeputy(client) && kv.JumpToKey("deputy"))
	{
		GetTags(client);
		return true;
	}
	return false;
}

//Stocks
void GetTags(int client, bool final = false)
{
	if (!final)
	{
		LoadTags(client, true);
		return;
	}
	
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
			bool ip = GetClientIP(client, sIP, sizeof(sIP));
			if (!ip)
				LogError("Unable to get %L ip!", client);
			GeoipCode2(sIP, sCountry);
			ReplaceString(sTags[client][ScoreTag], sizeof(sTags[][]), "{country}", sCountry);
		}
	
		CS_SetClientClanTag(client, sTags[client][ScoreTag]); //Instantly load the score-tag
	}
}

void ResetTags(int client)
{
	strcopy(sTags[client][ScoreTag], sizeof(sTags[][]), "");
	strcopy(sTags[client][ChatTag], sizeof(sTags[][]), "");
	strcopy(sTags[client][ChatColor], sizeof(sTags[][]), "");
	strcopy(sTags[client][NameColor], sizeof(sTags[][]), "");
	bForceTag[client] = true;
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
			dataOrder.WriteFunction(Select_SteamID);
		}
		else if (StrEqual(sLine, "AdminGroup", false))
		{
			dataOrder.WriteFunction(Select_AdminGroup);
		}
		else if (StrEqual(sLine, "AdminFlags", false))
		{
			dataOrder.WriteFunction(Select_Flags);
		}
		else if (StrEqual(sLine, "Warden", false))
		{
			if (!bWarden)
			{
				LogMessage("[HexTags] Disabling Warden support...");
				continue;
			}
			dataOrder.WriteFunction(Select_Warden);
		}
		else if (StrEqual(sLine, "Deputy", false))
		{
			if (!bMyJBWarden)
			{
				LogMessage("[HexTags] Disabling (MyJB)Warden support...");
				continue;
			}
			dataOrder.WriteFunction(Select_Deputy);
		}
		else if (StrEqual(sLine, "ActiveTime", false))
		{
			if (!bMostActive)
			{
				LogMessage("[HexTags] Disabling MostActive support...");
				continue;
			}
			dataOrder.WriteFunction(Select_Time);
		}
		else if (StrEqual(sLine, "RankMe", false))
		{
			if (!bRankme)
			{
				LogMessage("[HexTags] Disabling RankMe support...");
				continue;
			}
			dataOrder.WriteFunction(Select_Rankme);
		}
		else if (StrEqual(sLine, "Team", false))
		{
			dataOrder.WriteFunction(Select_Team);
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