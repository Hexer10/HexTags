/*
 * HexTags Plugin.
 * by: Hexah
 * https://github.com/Hexer10/HexTags
 * 
 * Copyright (C) 2017-2020 Mattia (Hexah|Hexer10|Papero)
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
#define DEBUG 1

#include <sourcemod>
#include <sdktools>
#include <chat-processor>
#include <geoip>
#include <hexstocks>
#include <hextags>
#include <clientprefs>

#undef REQUIRE_EXTENSIONS
#undef REQUIRE_PLUGIN
#include <mostactive>
#include <cstrike>
#include <kento_rankme/rankme>
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
Handle hVibilityCookie;

ConVar cv_sDefaultGang;
ConVar cv_bParseRoundEnd;
ConVar cv_bOrderDisabled;
ConVar cv_bDisableRankme;

bool bCSGO;
bool bLate;
bool bMostActive;
bool bRankme;
bool bWarden;
bool bMyJBWarden;
bool bGangs;
bool bSteamWorks = true;

int iRank[MAXPLAYERS+1] = {-1, ...};
bool bHideTag[MAXPLAYERS+1];

// TODO: Workaround for sm 1.11, implement eTags enum struct
char sUserTag[MAXPLAYERS+1][64];
char sTagConf[PLATFORM_MAX_PATH];

CustomTags sTags[MAXPLAYERS+1];

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
	cv_sDefaultGang = CreateConVar("sm_hextags_nogang", "", "Text to use if user has no tag - needs hl_gangs");
	cv_bParseRoundEnd = CreateConVar("sm_hextags_roundend", "0", "If 1 the tags will be reloaded even on round end - Suggested to be used with plugins like mostactive or rankme.");
	cv_bOrderDisabled = CreateConVar("sm_hextags_disable_order", "0", "If 1 the hextags-order.txt file will be disabled and the order will be the default one.");
	cv_bDisableRankme = CreateConVar("sm_hextags_disable_rankme", "0", "Set to 1 if you're having issues with rankme releted APIs.");
	
	AutoExecConfig();
	
	//Reg Cmds
	RegAdminCmd("sm_reloadtags", Cmd_ReloadTags, ADMFLAG_GENERIC, "Reload HexTags plugin config");
	RegAdminCmd("sm_toggletags", Cmd_ToggleTags, ADMFLAG_GENERIC, "Toggle the visibility of your tags");
	RegConsoleCmd("sm_getteam", Cmd_GetTeam, "Get current team name");
	
	//Event hooks
	if (!HookEventEx("round_end", Event_RoundEnd))
	LogError("Failed to hook \"round_end\", \"sm_hextags_roundend\" won't produce any effect.");
	
	hVibilityCookie = RegClientCookie("HexTags_Visibility", "Show or hide the tags.", CookieAccess_Private);
	
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
	bRankme = LibraryExists("rankme") && !cv_bDisableRankme.BoolValue;
	bWarden = LibraryExists("warden");
	bMyJBWarden = LibraryExists("myjbwarden");
	bGangs = LibraryExists("hl_gangs");
	bSteamWorks = LibraryExists("SteamWorks");
	
	LoadKv();
	if (bLate) for (int i = 1; i <= MaxClients; i++)if (IsClientInGame(i)) 
	{
		if (!AreClientCookiesCached(i))
		OnClientCookiesCached(i);
		OnClientPostAdminCheck(i);
	}
	
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
	else if (StrEqual(name, "rankme") && !cv_bDisableRankme.BoolValue)
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
	if (bHideTag[client])
	return Plugin_Continue;
	
	char sKey[64];
	
	if (!bCSGO || !kv.GetSectionName(sKey, sizeof(sKey)))
	return Plugin_Continue;
	
#if defined DEBUG
	char sKV[256];
	kv.ExportToString(sKV, sizeof(sKV));
	Debug_Print("Called ClientCmdKv: %s\n%s\n", sKey, sKV);
#endif
	
	if(StrEqual(sKey, "ClanTagChanged"))
	{
		kv.GetString("tag", sUserTag[client], sizeof(sUserTag[]));
		LoadTags(client);
		
		if(sTags[client].ScoreTag[0] == '\0')
		return Plugin_Continue;
		
		kv.SetString("tag", sTags[client].ScoreTag);
		Debug_Print("[ClanTagChanged] Setted tag: %s ", sTags[client].ScoreTag);
		return Plugin_Changed;
	}
	
	return Plugin_Continue; 
}

public void OnClientDisconnect(int client)
{
	ResetTags(client);
	iRank[client] = -1;
	bHideTag[client] = false;
	sUserTag[client][0] = '\0';
}

public void warden_OnWardenCreated(int client)
{
	RequestFrame(Frame_LoadTag, client);
}

public void warden_OnWardenRemoved(int client)
{
	if (bCSGO)
	CS_SetClientClanTag(client, sUserTag[client]);
	
	RequestFrame(Frame_LoadTag, client);
	
}

public void warden_OnDeputyCreated(int client)
{
	RequestFrame(Frame_LoadTag, client);
}

public void warden_OnDeputyRemoved(int client)
{
	if (bCSGO)
	CS_SetClientClanTag(client, sUserTag[client]);
	
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

public Action Cmd_ToggleTags(int client, int args)
{
	if (bHideTag[client])
	{
		bHideTag[client] = false;
		LoadTags(client);
		ReplyToCommand(client, "[SM] Your tags are visible again.");
	} 
	else
	{
		bHideTag[client] = true;
		CS_SetClientClanTag(client, sUserTag[client]);
		ReplyToCommand(client, "[SM] Your tags are no longer visible.");
	}
	
	SetClientCookie(client, hVibilityCookie, bHideTag[client] ? "0" : "1");
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
	ReplyToCommand(client, sTags[client].ScoreTag);
	ReplyToCommand(client, sTags[client].ChatTag);
	ReplyToCommand(client, sTags[client].ChatColor);
	ReplyToCommand(client, sTags[client].NameColor);
	return Plugin_Handled;
}
#endif

//Events
public void OnClientPostAdminCheck(int client)
{
	LoadTags(client);
}

public void OnClientCookiesCached(int client)
{
	char sValue[8];
	GetClientCookie(client, hVibilityCookie, sValue, sizeof(sValue));
	
	bHideTag[client] = sValue[0] == '\0' ? false : !StringToInt(sValue);
}

public Action RankMe_OnPlayerLoaded(int client)
{
	RankMe_GetRank(client, RankMe_LoadTags);
}

public Action RankMe_OnPlayerSaved(int client)
{
	RankMe_GetRank(client, RankMe_LoadTags);
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!cv_bParseRoundEnd.BoolValue)
	return;
	
	for (int i = 1; i <= MaxClients; i++)if (IsClientInGame(i))OnClientPostAdminCheck(i);
}

public Action RankMe_LoadTags(int client, int rank, any data)
{
	Debug_Print("Callback load rankme-tags");
	if (IsValidClient(client, true, true))
	{
		iRank[client] = rank;
		Debug_Print("Callback valid rank %L - %i", client, rank);
		char sRank[16];
		IntToString(iRank[client], sRank, sizeof(sRank));
		ReplaceString(sTags[client].ScoreTag, sizeof(CustomTags::ScoreTag), "{rmRank}", sRank);
		CS_SetClientClanTag(client, sTags[client].ScoreTag); //Instantly load the score-tag
	}
}

public Action CP_OnChatMessage(int& author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool& processcolors, bool& removecolors)
{
	if (bHideTag[author])
	{
		return Plugin_Continue;
	}
	
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
	// Rainbow name
	if (StrEqual(sTags[author].NameColor, "{rainbow}")) 
	{
		char sTemp[MAXLENGTH_MESSAGE]; 
		
		int color;
		int len = strlen(name);
		for(int i = 0; i < len; i++)
		{
			if (IsCharSpace(name[i]))
			{
				Format(sTemp, sizeof(sTemp), "%s%c", sTemp, name[i]);
				continue;
			}
			
			int bytes = GetCharBytes(name[i])+1;
			char[] c = new char[bytes];
			strcopy(c, bytes, name[i]);
			Format(sTemp, sizeof(sTemp), "%s%c%s", sTemp, GetColor(++color), c);
			if (IsCharMB(name[i]))
			i += bytes-2;
		}		
		Format(sNewName, MAXLENGTH_NAME, "%s%s{default}", sTags[author].ChatTag, sTemp);
	}
	else if (StrEqual(sTags[author].NameColor, "{random}")) //Random name
	{
		char sTemp[MAXLENGTH_MESSAGE]; 
		
		int len = strlen(name);
		for(int i = 0; i < len; i++)
		{
			if (IsCharSpace(name[i]))
			{
				Format(sTemp, sizeof(sTemp), "%s%c", sTemp, name[i]);
				continue;
			}
			
			int bytes = GetCharBytes(name[i])+1;
			char[] c = new char[bytes];
			strcopy(c, bytes, name[i]);
			Format(sTemp, sizeof(sTemp), "%s%c%s", sTemp, GetRandomColor(), c);
			if (IsCharMB(name[i]))
			i += bytes-2;
		}		
		Format(sNewName, MAXLENGTH_NAME, "%s%s{default}", sTags[author].ChatTag, sTemp);
	}
	else
	{
		Format(sNewName, MAXLENGTH_NAME, "%s%s%s{default}", sTags[author].ChatTag, sTags[author].NameColor, name);
	}
	Format(sNewMessage, MAXLENGTH_MESSAGE, "%s%s", sTags[author].ChatColor, message);
	
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
	if (StrEqual(sTags[author].ChatColor, "{rainbow}", false))
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
	if (StrEqual(sTags[author].ChatColor, "{random}", false))
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

KeyValues tagsKv;

//Functions
void LoadKv()
{
	static char sConfig[PLATFORM_MAX_PATH];
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
	delete tagsKv;
}
void LoadTags(int client)
{
	if (bHideTag[client])
		return;
	
	if (!IsValidClient(client, true, true))
		return;
	
	//Clear the tags when re-checking
	ResetTags(client);
	 
	if (tagsKv == null)
	{
		tagsKv = new KeyValues("HexTags");
		tagsKv.ImportFromFile(sTagConf);
		Debug_Print("KeyValue handle: %i", tagsKv);
	}
	tagsKv.Rewind();
	ParseConfig(tagsKv, client);
}

// This functions returns a CustomTags enum struct.
void ParseConfig(KeyValues kv, int client)
{
	static char sSectionName[64];
	do
	{
        // Check if current key is a section. Assume it has sub keys and attempt
        // to enter the section.
		if (kv.GotoFirstSubKey())
		{
            // Success. Confirmed that it's a sub key.
			
			
			kv.GetSectionName(sSectionName, sizeof(sSectionName));
			Debug_Print("Current key: %s", sSectionName);
			
			if (CheckSelector(sSectionName, sizeof(sSectionName), client)) 
			{
				Debug_Print("*******FOUND VALID SELECTOR -> %s.", sSectionName);
				ParseConfig(kv, client);
				return;
			}
		}
		else
		{
			Debug_Print("***********SETTINGS TAGS", sSectionName);
			GetTags(client, kv);
			return;
		}
	} while (kv.GotoNextKey());
	
	Debug_Print("-- Section end --");
}

bool CheckSelector(char[] selector, int maxlen, int client)
{
	/* CHECK DEFAULT */
	if (StrEqual(selector, "default", false))
	{
		return true;
	}
	
	/* CHECK STEAMID */
	static char steamid[32];
	if (!GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid)))
		return false;
	
	if (StrEqual(steamid, selector)) 
	{
		return true;
	}
	
	//Replace the STEAM_1 to STEAM_0 or viceversa
	(steamid[6] == '1') ? (steamid[6] = '0') : (steamid[6] = '1');
	if (StrEqual(steamid, selector)) 
	{
		return true;
	}
	
	/* PERMISSIONS RELATED CHECKS */
	AdminId admin = GetUserAdmin(client);
	if (admin != INVALID_ADMIN_ID)
	{
		/* CHECK ADMIN GROUP */
		if (selector[0] == '@')
		{
			static char sGroup[32];
			ReplaceString(selector, maxlen, "@", "", false);
			
			GroupId group = admin.GetGroup(0, sGroup, sizeof(sGroup));
			if (group != INVALID_GROUP_ID)
			{
				if (StrEqual(selector, sGroup))
				{
					return true;
				}
			}
		}
		
		/* CHECK ADMIN FLAGS */
		if (strlen(selector) == 1 || selector[0] == '&')
		{
			ReplaceString(selector, maxlen, "&", "", false); //Remove the & symbol.
			for (int i = 0; i < strlen(selector); i++)
			{
				AdminFlag flag;
				if (FindFlagByChar(selector[i], flag))
				{
					if (admin.HasFlag(flag))
					{
						return true;
					}
				}
			}
		}
	}
	
	/* CHECK PLAYER TEAM */
	int team = GetClientTeam(client);
	static char sTeam[32];
	
	GetTeamName(team, sTeam, sizeof(sTeam));
	if (StrEqual(sTeam, selector))
	{
		return true;
	}
	
	return false;
}

/*
 @ - Group
 & - FLAG

*/
//Timers
public Action Timer_ForceTag(Handle timer)
{
	if (!bCSGO)
	return;
	
	for (int i = 1; i <= MaxClients; i++)if (IsClientInGame(i) && sTags[i].ForceTag && sTags[i].ScoreTag[0] != '\0' && !bHideTag[i])
	{
		char sTag[32];
		CS_GetClientClanTag(i, sTag, sizeof(sTag));
		if (StrEqual(sTag, sTags[i].ScoreTag))
		continue;
		
		LogMessage("%L was changed by an external plugin, forcing him back to the HexTags' default one!", i, sTag);
		CS_SetClientClanTag(i, sTags[i].ScoreTag);
	}
}

//Frames
public void Frame_LoadTag(any client)
{
	LoadTags(client);
}

bool Select_Time(int client, KeyValues kv)
{
	int iOldTime;
	bool bReturn;
	
	if (!kv.GotoFirstSubKey())
	return false;
	
	
	int iPlayTime = MostActive_GetPlayTimeTotal(client);
	do
	{
		char sSecs[16];
		kv.GetSectionName(sSecs, sizeof(sSecs));
		
		if (sSecs[0] != '#') //Check if it's a "time-format"
		continue;
		
		Format(sSecs, sizeof(sSecs), "%s", sSecs[1]); //Cut the '#' at the start
		int iReqTime = StringToInt(sSecs);
		if (iReqTime < iPlayTime || iOldTime > iReqTime) //Select only the higher time.
		continue;
		
		iOldTime = iReqTime; //Save the time
		bReturn = true; 
		
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

bool Select_Gang(int client, KeyValues kv)
{
	if (Gangs_HasGang(client) && kv.JumpToKey("Gang"))
	{
		return true;
	}
	return false;
}

//Stocks
void GetTags(int client, KeyValues kv)
{
	static char sSection[64];
	kv.GetSectionName(sSection, sizeof(sSection));
	Debug_Print("Section: %s", sSection);
	
	kv.GetString("ScoreTag", sTags[client].ScoreTag, sizeof(CustomTags::ScoreTag), "");
	kv.GetString("ChatTag", sTags[client].ChatTag, sizeof(CustomTags::ChatTag), "");
	kv.GetString("ChatColor", sTags[client].ChatColor, sizeof(CustomTags::ChatColor), "");
	kv.GetString("NameColor", sTags[client].NameColor, sizeof(CustomTags::NameColor), "{teamcolor}");
	sTags[client].ForceTag = kv.GetNum("ForceTag", 1) == 1;
	
	Call_StartForward(fTagsUpdated);
	Call_PushCell(client);
	Call_Finish();
	
	if (sTags[client].ScoreTag[0] != '\0' && bCSGO)
	{
		//Update params
		if (StrContains(sTags[client].ScoreTag, "{country}") != -1)
		{
			static char sIP[32];
			static char sCountry[3];
			if (!GetClientIP(client, sIP, sizeof(sIP)))
				LogError("Unable to get %L ip!", client);
			GeoipCode2(sIP, sCountry);
			ReplaceString(sTags[client].ScoreTag, sizeof(CustomTags::ScoreTag), "{country}", sCountry);
		}
		if (bGangs && StrContains(sTags[client].ScoreTag, "{gang}") != -1)
		{
			static char sGang[32];
			Gangs_HasGang(client) ?  Gangs_GetGangName(client, sGang, sizeof(sGang)) : cv_sDefaultGang.GetString(sGang, sizeof(sGang));
			ReplaceString(sTags[client].ScoreTag, sizeof(CustomTags::ScoreTag), "{gang}", sGang);
		}
		if (bRankme && StrContains(sTags[client].ScoreTag, "{rmPoints}") != -1)
		{
			static char sPoints[16];
			IntToString(RankMe_GetPoints(client), sPoints, sizeof(sPoints));
			ReplaceString(sTags[client].ScoreTag, sizeof(CustomTags::ScoreTag), "{rmPoints}", sPoints);
		}
		if (bRankme && StrContains(sTags[client].ScoreTag, "{rmRank}") != -1)
		{
			Debug_Print("Contains rmRank");
			RankMe_GetRank(client, RankMe_LoadTags);
		}
		
		Debug_Print("Setted tag: %s", sTags[client].ScoreTag);
		CS_SetClientClanTag(client, sTags[client].ScoreTag); //Instantly load the score-tag
	}
	if (StrContains(sTags[client].ChatTag, "{rainbow}") == 0) 
	{
		Debug_Print("Found {rainbow} in ChatTag");
		ReplaceString(sTags[client].ChatTag, sizeof(CustomTags::ChatTag), "{rainbow}", "");
		char sTemp[MAXLENGTH_MESSAGE]; 
		
		int color;
		int len = strlen(sTags[client].ChatTag);
		for(int i = 0; i < len; i++)
		{
			if (IsCharSpace(sTags[client].ChatTag[i]))
			{
				Format(sTemp, sizeof(sTemp), "%s%c", sTemp, sTags[client].ChatTag[i]);
				continue;
			}
			
			int bytes = GetCharBytes(sTags[client].ChatTag[i])+1;
			char[] c = new char[bytes];
			strcopy(c, bytes, sTags[client].ChatTag[i]);
			Format(sTemp, sizeof(sTemp), "%s%c%s", sTemp, GetColor(++color), c);
			if (IsCharMB(sTags[client].ChatTag[i]))
			i += bytes-2;
		}
		strcopy(sTags[client].ChatTag, sizeof(CustomTags::ChatTag), sTemp);
		Debug_Print("Replaced ChatTag with %s", sTags[client].ChatTag);
	}
	if (StrContains(sTags[client].ChatTag, "{random}") == 0) 
	{
		ReplaceString(sTags[client].ChatTag, sizeof(CustomTags::ChatTag), "{random}", "");
		char sTemp[MAXLENGTH_MESSAGE];
		int len = strlen(sTags[client].ChatTag);
		for(int i = 0; i < len; i++)
		{
			if (IsCharSpace(sTags[client].ChatTag[i]))
			{
				Format(sTemp, sizeof(sTemp), "%s%c", sTemp, sTags[client].ChatTag[i]);
				continue;
			}
			
			int bytes = GetCharBytes(sTags[client].ChatTag[i])+1;
			char[] c = new char[bytes];
			strcopy(c, bytes, sTags[client].ChatTag[i]);
			Format(sTemp, sizeof(sTemp), "%s%c%s", sTemp, GetRandomColor(), c);
			if (IsCharMB(sTags[client].ChatTag[i]))
			i += bytes-2;
		}
		strcopy(sTags[client].ChatTag, sizeof(CustomTags::ChatTag), sTemp);
	}
	Debug_Print("Succesfully setted tags");
}

void ResetTags(int client)
{
	strcopy(sTags[client].ScoreTag, sizeof(CustomTags::ScoreTag), "");
	strcopy(sTags[client].ChatTag, sizeof(CustomTags::ChatTag), "");
	strcopy(sTags[client].ChatColor, sizeof(CustomTags::ChatColor), "");
	strcopy(sTags[client].NameColor, sizeof(CustomTags::NameColor), "");
	sTags[client].ForceTag = true;
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
	
//	SetNativeString(3, sTags[client][Tag], GetNativeCell(4));
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
	
	Debug_Print("Called Native_SetClientTag(%i, %i, %s)", client, Tag, sTag);
	ReplaceString(sTag, sizeof(sTag), "{darkgray}", "{gray2}");
//	strcopy(sTags[client][Tag], sizeof(sTags[][]), sTag);
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
