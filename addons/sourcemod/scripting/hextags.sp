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
//#define DEBUG 0

#include <sourcemod>
#include <sdktools>
#include <geoip>
#include <hexstocks>
#include <hextags>
#include <clientprefs>
#include <hexcolors>

#undef REQUIRE_EXTENSIONS
#undef REQUIRE_PLUGIN
#include <chat-processor>
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


PrivateForward pfCustomSelector;

Handle fTagsUpdated;
Handle fMessageProcess;
Handle fMessageProcessed;
Handle fMessagePreProcess;
Handle hVibilityCookie;
Handle hSelTagCookie;

ConVar cv_sDefaultGang;
ConVar cv_bParseRoundEnd;
ConVar cv_bEnableTagsList;

bool bCSGO;
bool bLate;
bool bMostActive;
bool bRankme;
bool bWarden;
bool bMyJBWarden;
bool bGangs;
bool bSteamWorks;
bool bChatProcessor;
bool bHideTag[MAXPLAYERS + 1];

int iRank[MAXPLAYERS + 1] =  { -1, ... };
int iNextDefTag;
int iSelTagId[MAXPLAYERS + 1];

char sUserTag[MAXPLAYERS + 1][64];
char sTagConf[PLATFORM_MAX_PATH];

ArrayList userTags[MAXPLAYERS + 1];
CustomTags selectedTags[MAXPLAYERS + 1];
KeyValues tagsKv;
StringMap messageFormat;


//Plugin info
public Plugin myinfo = 
{
	name = "hextags", 
	author = PLUGIN_AUTHOR, 
	description = "Edit Tags & Colors!", 
	version = PLUGIN_VERSION, 
	url = "github.com/Hexer10/HexTags"
};

// Startup
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	//API
	RegPluginLibrary("hextags");
	
	CreateNative("HexTags_GetClientTag", Native_GetClientTag);
	CreateNative("HexTags_SetClientTag", Native_SetClientTag);
	CreateNative("HexTags_ResetClientTag", Native_ResetClientTags);
	CreateNative("HexTags_AddCustomSelector", Native_AddCustomSelector);
	CreateNative("HexTags_RemoveCustomSelector", Native_RemoveCustomSelector);
	
	fTagsUpdated = new GlobalForward("HexTags_OnTagsUpdated", ET_Ignore, Param_Cell);
	
	fMessageProcess = new GlobalForward("HexTags_OnMessageProcess", ET_Single, Param_Cell, Param_String, Param_String);
	fMessageProcessed = new GlobalForward("HexTags_OnMessageProcessed", ET_Ignore, Param_Cell, Param_String, Param_String);
	fMessagePreProcess = new GlobalForward("HexTags_OnMessagePreProcess", ET_Single, Param_Cell, Param_String, Param_String);
	
	pfCustomSelector = new PrivateForward(ET_Single, Param_Cell, Param_String);
	
	EngineVersion engine = GetEngineVersion();
	bCSGO = (engine == Engine_CSGO || engine == Engine_CSS);
	
	//LateLoad
	bLate = late;
	return APLRes_Success;
}

//TODO: Cache client ip instead of getting it every time.
public void OnPluginStart()
{
	//ConVars
	CreateConVar("sm_hextags_version", PLUGIN_VERSION, "HexTags plugin version", FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY);
	cv_sDefaultGang = CreateConVar("sm_hextags_nogang", "", "Text to use if user has no tag - needs hl_gangs.");
	cv_bParseRoundEnd = CreateConVar("sm_hextags_roundend", "0", "If 1 the tags will be reloaded even on round end - Suggested to be used with plugins like mostactive or rankme.");
	cv_bEnableTagsList = CreateConVar("sm_hextags_enable_tagslist", "0", "Set to 1 to enable the sm_tagslist command.");
	
	AutoExecConfig();
	
	//Reg Cmds
	RegAdminCmd("sm_reloadtags", Cmd_ReloadTags, ADMFLAG_GENERIC, "Reload HexTags plugin config");
	RegAdminCmd("sm_toggletags", Cmd_ToggleTags, ADMFLAG_GENERIC, "Toggle the visibility of your tags");
	RegConsoleCmd("sm_tagslist", Cmd_TagsList, "Select your tag!");
	RegConsoleCmd("sm_getteam", Cmd_GetTeam, "Get current team name");
	
	//Event hooks
	if (!HookEventEx("round_end", Event_RoundEnd))
		LogError("Failed to hook \"round_end\", \"sm_hextags_roundend\" won't produce any effect.");
	
	hVibilityCookie = RegClientCookie("HexTags_Visibility", "Show or hide the tags.", CookieAccess_Private);
	hSelTagCookie = RegClientCookie("HexTags_SelectedTag", "Selected Tag", CookieAccess_Private);
	
	#if defined DEBUG
	RegConsoleCmd("sm_gettagvars", Cmd_GetVars);
	RegConsoleCmd("sm_firesel", Cmd_FireSel);
	#endif
	
	UserMsg sayText2 = GetUserMessageId("SayText2");
	
	HookUserMessage(sayText2, Hook_SayText2, true);
	
	GenerateFormat();
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
	bGangs = LibraryExists("hl_gangs");
	bSteamWorks = LibraryExists("SteamWorks");
	bChatProcessor = LibraryExists("chat-processor");
	
	LoadKv();
	if (bLate)for (int i = 1; i <= MaxClients; i++)if (IsClientInGame(i))
	{
		OnClientPutInServer(i);
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
	else if (StrEqual(name, "chat-processor"))
	{
		bChatProcessor = true;
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
	else if (StrEqual(name, "chat-processor"))
	{
		bChatProcessor = false;
	}
}

public Action Hook_SayText2(UserMsg msg_id, Protobuf msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if (bChatProcessor)
		return Plugin_Continue;
		
	static char msg_name[128];
	int sender = msg.ReadInt("ent_idx");
	msg.ReadString("msg_name", msg_name, sizeof(msg_name));
	bool chat = msg.ReadBool("chat");
	bool textallchat = msg.ReadBool("textallchat");
	
	static char params[4][128];
	msg.ReadString("params", params[0], sizeof(params[]), 0);
	msg.ReadString("params", params[1], sizeof(params[]), 1);
	
	ArrayList recievers = new ArrayList();
	
	for (int i = 0; i < playersNum; i++)
	{
		recievers.Push(players[i]);
	}
	
	DataPack pack = new DataPack();
	pack.WriteCell(sender);
	pack.WriteCell(recievers);
	pack.WriteString(msg_name);
	pack.WriteString(params[0]);
	pack.WriteString(params[1]);
	pack.WriteCell(chat);
	pack.WriteCell(textallchat);
	
	RequestFrame(Frame_Resend, pack);
	return Plugin_Stop;
}

public void Frame_Resend(DataPack pack)
{
	static char msg_name[64];
	static char name[MAXLENGTH_NAME];
	static char message[MAXLENGTH_MESSAGE];
	
	// Read the incoming data
	pack.Reset();
	int author = pack.ReadCell();
	ArrayList recievers = pack.ReadCell();
	pack.ReadString(msg_name, sizeof(msg_name));
	pack.ReadString(name, sizeof(name));
	pack.ReadString(message, sizeof(message));
	bool chat = pack.ReadCell();
	bool textallchat = pack.ReadCell();
	delete pack;
	
	Debug_Setup(true, false, false, true); // Disable chat.
	
	// Don't parse tags
	if (bHideTag[author])
	{
		SendMessages(author, recievers, msg_name, name, message, chat, textallchat, false);
		return;
	}
	
	// Fire event
	Action result = FirePreProcess(author, name, message);

	// Don't parse the tags
	if (result >= Plugin_Handled)
	{
		SendMessages(author, recievers, msg_name, name, message, chat, textallchat, false);
		return;
	}
	
	// Add colors & tags
	char sNewName[MAXLENGTH_NAME];
	char sNewMessage[MAXLENGTH_MESSAGE];

	// Apply colors only if it is not random or rainbow
	if (!ReplaceRainbow(author, name, sNewName) && !ReplaceRandom(author, name, sNewName))
	{
		Format(sNewName, sizeof(sNewName), "%s%s%s{default}", selectedTags[author].ChatTag, selectedTags[author].NameColor, name);
	}

	Format(sNewMessage, sizeof(sNewMessage), "%s%s", selectedTags[author].ChatColor, message);
	
	// Replace Time
	ReplaceTime(name, message);

	// Replace Country
	ReplaceCountry(author, name, message);
	
	// Replace Gang
	ReplaceGang(author, name, message);
	
	// Replace Rankme
	ReplaceRankMe(author, name, message);
	
	//Rainbow Chat
	if (StrEqual(selectedTags[author].ChatColor, "{rainbow}", false))
	{
		Debug_Print("Rainbow chat");
		ReplaceString(sNewMessage, sizeof(sNewMessage), "{rainbow}", "");
		char sTemp[MAXLENGTH_MESSAGE];
		
		int color;
		int len = strlen(sNewMessage);
		for (int i = 0; i < len; i++)
		{
			if (IsCharSpace(sNewMessage[i]))
			{
				Format(sTemp, sizeof(sTemp), "%s%c", sTemp, sNewMessage[i]);
				continue;
			}
			
			int bytes = GetCharBytes(sNewMessage[i]) + 1;
			char[] c = new char[bytes];
			strcopy(c, bytes, sNewMessage[i]);
			Format(sTemp, sizeof(sTemp), "%s%c%s", sTemp, GetColor(++color), c);
			if (IsCharMB(sNewMessage[i]))
				i += bytes - 2;
		}
		Format(sNewMessage, MAXLENGTH_MESSAGE, "%s", sTemp);
	}
	
	//Random Chat
	if (StrEqual(selectedTags[author].ChatColor, "{random}", false))
	{
		Debug_Print("Random chat");
		ReplaceString(sNewMessage, sizeof(sNewMessage), "{random}", "");
		char sTemp[MAXLENGTH_MESSAGE];
		
		int len = strlen(sNewMessage);
		for (int i = 0; i < len; i++)
		{
			if (IsCharSpace(sNewMessage[i]))
			{
				Format(sTemp, sizeof(sTemp), "%s%c", sTemp, sNewMessage[i]);
				continue;
			}
			
			int bytes = GetCharBytes(sNewMessage[i]) + 1;
			char[] c = new char[bytes];
			strcopy(c, bytes, sNewMessage[i]);
			Format(sTemp, sizeof(sTemp), "%s%c%s", sTemp, GetRandomColor(), c);
			if (IsCharMB(sNewMessage[i]))
				i += bytes - 2;
		}
		Format(sNewMessage, MAXLENGTH_MESSAGE, "%s", sTemp);
	}
	
	static char sPassedName[MAXLENGTH_NAME];
	static char sPassedMessage[MAXLENGTH_MESSAGE];
	sPassedName = sNewName;
	sPassedMessage = sNewMessage;
	
	
	result = FireMessageProcess(author, sPassedName, sPassedMessage);
	
	if (result == Plugin_Continue)
	{
		// No changes
		strcopy(name, MAXLENGTH_NAME, sNewName);
		strcopy(message, MAXLENGTH_MESSAGE, sNewMessage);
	}
	else if (result == Plugin_Changed)
	{
		// Update the name & message
		strcopy(name, MAXLENGTH_NAME, sPassedName);
		strcopy(message, MAXLENGTH_MESSAGE, sPassedMessage);
	}
	else
	{
		// Stop the execution
		SendMessages(author, recievers, msg_name, name, message, chat, textallchat, false);
		return;
	}
	
	SendMessages(author, recievers, msg_name, name, message, chat, textallchat, true);
	
	//Call the (post)forward
	FireMessageProcessed(author, sPassedName, sPassedMessage);
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
	
	if (StrEqual(sKey, "ClanTagChanged"))
	{
		kv.GetString("tag", sUserTag[client], sizeof(sUserTag[]));
		LoadTags(client);
		
		if (selectedTags[client].ScoreTag[0] == '\0')
			return Plugin_Continue;
		
		kv.SetString("tag", selectedTags[client].ScoreTag);
		Debug_Print("[ClanTagChanged] Setted tag: %s ", selectedTags[client].ScoreTag);
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
	delete userTags[client];
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

// Commands
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

public Action Cmd_TagsList(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "[SM] In-game only command.");
		return Plugin_Handled;
	}
	
	if (userTags[client] == null)
	{
		ReplyToCommand(client, "[SM] Tags not yet loaded.");
		return Plugin_Handled;
	}
	
	if (!cv_bEnableTagsList.BoolValue)
	{
		ReplyToCommand(client, "[SM] This feature is not enabled.");
		return Plugin_Handled;
	}
	
	if (userTags[client].Length == 0)
	{
		ReplyToCommand(client, "[SM] No tags available.");
		return Plugin_Handled;
	}
	
	Menu menu = new Menu(Handler_TagsMenu);
	menu.SetTitle("Choose your tag:");
	static char sIndex[16];
	int len = userTags[client].Length;
	CustomTags tags;
	for (int i = 0; i < len; i++)
	{
		userTags[client].GetArray(i, tags, sizeof(tags));
		IntToString(i, sIndex, sizeof(sIndex));
		menu.AddItem(sIndex, tags.TagName);
	}
	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int Handler_TagsMenu(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
	}
	else if (action == MenuAction_Select)
	{
		static char sIndex[16];
		menu.GetItem(param2, sIndex, sizeof(sIndex));
		userTags[param1].GetArray(StringToInt(sIndex), selectedTags[param1], sizeof(CustomTags));
		if (selectedTags[param1].ScoreTag[0] != '\0')
		{
			CS_SetClientClanTag(param1, selectedTags[param1].ScoreTag);
		}
		iSelTagId[param1] = selectedTags[param1].SectionId;
		
		static char sValue[32];
		IntToString(iSelTagId[param1], sValue, sizeof(sValue));
		SetClientCookie(param1, hSelTagCookie, sValue);
		PrintToChat(param1, "[SM] Setted %s tags", selectedTags[param1].TagName);
	}
	
}

public Action Cmd_GetTeam(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "[SM] In-game only command.");
		return Plugin_Handled;
	}
	
	char sTeam[32];
	GetTeamName(GetClientTeam(client), sTeam, sizeof(sTeam));
	ReplyToCommand(client, "[SM] Current team name: %s", sTeam);
	return Plugin_Handled;
}

#if defined DEBUG
public Action Cmd_GetVars(int client, int args)
{
	ReplyToCommand(client, selectedTags[client].ScoreTag);
	ReplyToCommand(client, selectedTags[client].ChatTag);
	ReplyToCommand(client, selectedTags[client].ChatColor);
	ReplyToCommand(client, selectedTags[client].NameColor);
	return Plugin_Handled;
}

public Action Cmd_FireSel(int client, int args)
{
	int count = pfCustomSelector.FunctionCount;
	int res;
	
	Call_StartForward(pfCustomSelector);
	Call_PushCell(client);
	Call_PushString("thistoggle");
	Call_Finish(res);
	ReplyToCommand(client, "[SM] Fire %i functions, res: %i!", count, res);
	return Plugin_Handled;
}
#endif

// Events
public void OnClientPutInServer(int client)
{
	delete userTags[client];
	userTags[client] = new ArrayList(sizeof(CustomTags));
}

public void OnClientPostAdminCheck(int client)
{
	LoadTags(client);
}

public void OnClientCookiesCached(int client)
{
	static char sValue[32];
	GetClientCookie(client, hVibilityCookie, sValue, sizeof(sValue));
	
	bHideTag[client] = sValue[0] == '\0' ? false : !StringToInt(sValue);
	
	GetClientCookie(client, hSelTagCookie, sValue, sizeof(sValue));
	if (sValue[0] == '\0')
	{
		return;
	}
	int id = StringToInt(sValue);
	if (!id)
	{
		LogError("Invalid id: %s", sValue);
	}
	iSelTagId[client] = id;
	
}

public Action RankMe_OnPlayerLoaded(int client)
{
	RankMe_GetRank(client, RankMe_LoadTags);
}

public Action RankMe_OnPlayerSaved(int client)
{
	RankMe_GetRank(client, RankMe_LoadTags);
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
		
		if (selectedTags[client].ScoreTag[0] == '\0')
			return;
		
		ReplaceString(selectedTags[client].ScoreTag, sizeof(CustomTags::ScoreTag), "{rmRank}", sRank);
		CS_SetClientClanTag(client, selectedTags[client].ScoreTag); //Instantly load the score-tag
	}
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!cv_bParseRoundEnd.BoolValue)
		return;
	
	for (int i = 1; i <= MaxClients; i++)if (IsClientInGame(i))OnClientPostAdminCheck(i);
}

public Action CP_OnChatMessage(int & author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool& processcolors, bool & removecolors)
{
	Debug_Setup(true, false, false, true); // Disable chat.
	if (bHideTag[author])
	{
		return Plugin_Continue;
	}
	
	Action result = FirePreProcess(author, name, message);
	
	if (result >= Plugin_Handled)
	{
		return Plugin_Continue;
	}
	
	//Add colors & tags
	char sNewName[MAXLENGTH_NAME];
	char sNewMessage[MAXLENGTH_MESSAGE];
	
	// Apply colors only if it is not random or rainbow
	if (!ReplaceRainbow(author, name, sNewName) && !ReplaceRandom(author, name, sNewName))
	{
		Format(sNewName, sizeof(sNewName), "%s%s%s{default}", selectedTags[author].ChatTag, selectedTags[author].NameColor, name);
	}

	Format(sNewMessage, sizeof(sNewMessage), "%s%s", selectedTags[author].ChatColor, message);
	
	// Replace Time
	ReplaceTime(name, message);

	// Replace Country
	ReplaceCountry(author, name, message);
	
	// Replace Gang
	ReplaceGang(author, name, message);
	
	// Replace Rankme
	ReplaceRankMe(author, name, message);
	
	//Rainbow Chat
	if (StrEqual(selectedTags[author].ChatColor, "{rainbow}", false))
	{
		Debug_Print("Rainbow chat");
		ReplaceString(sNewMessage, sizeof(sNewMessage), "{rainbow}", "");
		char sTemp[MAXLENGTH_MESSAGE];
		
		int color;
		int len = strlen(sNewMessage);
		for (int i = 0; i < len; i++)
		{
			if (IsCharSpace(sNewMessage[i]))
			{
				Format(sTemp, sizeof(sTemp), "%s%c", sTemp, sNewMessage[i]);
				continue;
			}
			
			int bytes = GetCharBytes(sNewMessage[i]) + 1;
			char[] c = new char[bytes];
			strcopy(c, bytes, sNewMessage[i]);
			Format(sTemp, sizeof(sTemp), "%s%c%s", sTemp, GetColor(++color), c);
			if (IsCharMB(sNewMessage[i]))
				i += bytes - 2;
		}
		Format(sNewMessage, MAXLENGTH_MESSAGE, "%s", sTemp);
	}
	
	//Random Chat
	if (StrEqual(selectedTags[author].ChatColor, "{random}", false))
	{
		Debug_Print("Random chat");
		ReplaceString(sNewMessage, sizeof(sNewMessage), "{random}", "");
		char sTemp[MAXLENGTH_MESSAGE];
		
		int len = strlen(sNewMessage);
		for (int i = 0; i < len; i++)
		{
			if (IsCharSpace(sNewMessage[i]))
			{
				Format(sTemp, sizeof(sTemp), "%s%c", sTemp, sNewMessage[i]);
				continue;
			}
			
			int bytes = GetCharBytes(sNewMessage[i]) + 1;
			char[] c = new char[bytes];
			strcopy(c, bytes, sNewMessage[i]);
			Format(sTemp, sizeof(sTemp), "%s%c%s", sTemp, GetRandomColor(), c);
			if (IsCharMB(sNewMessage[i]))
				i += bytes - 2;
		}
		Format(sNewMessage, MAXLENGTH_MESSAGE, "%s", sTemp);
	}
	
	static char sPassedName[MAXLENGTH_NAME];
	static char sPassedMessage[MAXLENGTH_NAME];
	sPassedName = sNewName;
	sPassedMessage = sNewMessage;
	
	result = FireMessageProcess(author, name, message);
	
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
		Debug_Setup();
		return Plugin_Continue;
	}
	
	processcolors = true;
	removecolors = false;
	
	//Call the (post)forward
	FireMessageProcessed(author, name, message);
	
	
	Debug_Print("Message sent");
	Debug_Setup();
	return Plugin_Changed;
}

// Functions
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
	if (userTags[client] == null)
	{
		userTags[client] = new ArrayList(sizeof(CustomTags));
	}
	ParseConfig(tagsKv, client);
	
	if (userTags[client].Length > 0)
	{
		if (iSelTagId[client] == 0 || !cv_bEnableTagsList.BoolValue)
		{
			userTags[client].GetArray(0, selectedTags[client], sizeof(CustomTags));
			return;
		}
		tagsKv.Rewind();
		if (!tagsKv.JumpToKeySymbol(iSelTagId[client]))
		{
			SetClientCookie(client, hSelTagCookie, "");
			userTags[client].GetArray(0, selectedTags[client], sizeof(CustomTags));
			return;
		}
		// Key found
		int len = userTags[client].Length;
		CustomTags tags;
		
		for (int i = 0; i < len; i++)
		{
			userTags[client].GetArray(i, tags, sizeof(CustomTags));
			if (tags.SectionId == iSelTagId[client])
			{
				selectedTags[client] = tags;
				if (selectedTags[client].ScoreTag[0] == '\0')
					return;
				
				CS_SetClientClanTag(client, selectedTags[client].ScoreTag);
				return;
			}
		}
	}
}

void ParseConfig(KeyValues kv, int client)
{
	userTags[client].Clear();
	static char sSectionName[64];
	do
	{
		if (kv.GotoFirstSubKey())
		{
			kv.GetSectionName(sSectionName, sizeof(sSectionName));
			Debug_Print("Current key: %s", sSectionName);
			
			if (CheckSelector(sSectionName, client))
			{
				Debug_Print("*******FOUND VALID SELECTOR -> %s.", sSectionName);
				ParseConfig(kv, client);
			}
		}
		else
		{
			kv.GetSectionName(sSectionName, sizeof(sSectionName));
			if (!CheckSelector(sSectionName, client))
			{
				continue;
			}
			Debug_Print("***********SETTINGS TAGS", sSectionName);
			GetTags(client, kv);
		}
	} while (kv.GotoNextKey());
	Debug_Print("-- Section end --");
}

bool CheckSelector(const char[] selector, int client)
{
	/* CHECK DEFAULT */
	if (StrEqual(selector, "default", false))
	{
		return true;
	}
	
	/* CHECK STEAMID */
	if (strlen(selector) > 11 && StrContains(selector, "STEAM_", true) == 0)
	{
		char steamid[32];
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
	}
	
	
	/* PERMISSIONS RELATED CHECKS */
	AdminId admin = GetUserAdmin(client);
	if (admin != INVALID_ADMIN_ID)
	{
		/* CHECK ADMIN GROUP */
		if (selector[0] == '@')
		{
			static char sGroup[32];
			
			GroupId group = admin.GetGroup(0, sGroup, sizeof(sGroup));
			if (group != INVALID_GROUP_ID)
			{
				if (StrEqual(selector[1], sGroup))
				{
					return true;
				}
			}
		}
		
		/* CHECK ADMIN FLAGS (1)*/
		if (strlen(selector) == 1)
		{
			AdminFlag flag;
			if (FindFlagByChar(selector[0], flag))
			{
				if (admin.HasFlag(flag))
				{
					return true;
				}
			}
		}
		
		/* CHECK ADMIN FLAGS (2)*/
		if (selector[0] == '&')
		{
			for (int i = 1; i < strlen(selector); i++)
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
	
	/* CHECK TIME */
	if (bMostActive && selector[0] == '#')
	{
		int iPlayTime = MostActive_GetPlayTimeTotal(client);
		if (iPlayTime >= StringToInt(selector[1]))
		{
			return true;
		}
	}
	
	/* CHECK WARDEN */
	if (bWarden && StrEqual(selector, "warden", false) && warden_iswarden(client))
	{
		return true;
	}
	
	/* CHECK DEPUTY */
	if (bMyJBWarden && StrEqual(selector, "deputy", false) && warden_deputy_isdeputy(client))
	{
		return true;
	}
	
	/* CHECK PRIME */
	if (bSteamWorks && StrEqual(selector, "NoPrime", false))
	{
		if (k_EUserHasLicenseResultDoesNotHaveLicense == SteamWorks_HasLicenseForApp(client, 624820))
		{
			return true;
		}
	}
	
	/* CHECK GANG */
	if (bGangs && StrEqual(selector, "Gang", false) && Gangs_HasGang(client))
	{
		return true;
	}
	
	/* CHECK RANKME */
	if (bRankme && selector[0] == '!')
	{
		int iPoints = RankMe_GetPoints(client);
		if (iPoints >= StringToInt(selector[1]))
		{
			return true;
		}
	}
	
	/* CHECK STEAM GROUP */
	if (bSteamWorks && selector[0] == '$')
	{
		if (SteamWorks_GetUserGroupStatus(client, selector[1]))
		{
			return true;
		}
	}
	
	
	bool res = false;
	
	Call_StartForward(pfCustomSelector);
	Call_PushCell(client);
	Call_PushString(selector);
	Call_Finish(res);
	
	return res;
}

// Timers
public Action Timer_ForceTag(Handle timer)
{
	if (!bCSGO)
		return;
	
	for (int i = 1; i <= MaxClients; i++)if (IsClientInGame(i) && selectedTags[i].ForceTag && selectedTags[i].ScoreTag[0] != '\0' && !bHideTag[i])
	{
		char sTag[32];
		CS_GetClientClanTag(i, sTag, sizeof(sTag));
		if (StrEqual(sTag, selectedTags[i].ScoreTag))
			continue;
		
		LogMessage("%L was changed by an external plugin, forcing him back to the HexTags' default one!", i, sTag);
		CS_SetClientClanTag(i, selectedTags[i].ScoreTag);
	}
}

// Frames
public void Frame_LoadTag(any client)
{
	LoadTags(client);
}

// Helpers
void GetTags(int client, KeyValues kv)
{
	static char sSection[64];
	static char sDef[8];
	IntToString(iNextDefTag++, sDef, sizeof(sDef));
	
	kv.GetSectionName(sSection, sizeof(sSection));
	Debug_Print("Section: %s", sSection);
	int id;
	if (!kv.GetSectionSymbol(id))
	{
		LogError("Unable to get section symbol.");
	}
	
	CustomTags tags;
	
	tags.SectionId = id;
	kv.GetString("TagName", tags.TagName, sizeof(CustomTags::TagName), sDef);
	kv.GetString("ScoreTag", tags.ScoreTag, sizeof(CustomTags::ScoreTag), "");
	kv.GetString("ChatTag", tags.ChatTag, sizeof(CustomTags::ChatTag), "");
	kv.GetString("ChatColor", tags.ChatColor, sizeof(CustomTags::ChatColor), "");
	kv.GetString("NameColor", tags.NameColor, sizeof(CustomTags::NameColor), "{teamcolor}");
	tags.ForceTag = kv.GetNum("ForceTag", 1) == 1;
	
	
	Call_StartForward(fTagsUpdated);
	Call_PushCell(client);
	Call_Finish();
	
	if (tags.ScoreTag[0] != '\0' && bCSGO)
	{
		//Update params
		if (StrContains(tags.ScoreTag, "{country}") != -1)
		{
			static char sIP[32];
			static char sCountry[3];
			if (!GetClientIP(client, sIP, sizeof(sIP)))
				LogError("Unable to get %L ip!", client);
			GeoipCode2(sIP, sCountry);
			ReplaceString(tags.ScoreTag, sizeof(CustomTags::ScoreTag), "{country}", sCountry);
		}
		if (bGangs && StrContains(tags.ScoreTag, "{gang}") != -1)
		{
			static char sGang[32];
			Gangs_HasGang(client) ? Gangs_GetGangName(client, sGang, sizeof(sGang)) : cv_sDefaultGang.GetString(sGang, sizeof(sGang));
			ReplaceString(tags.ScoreTag, sizeof(CustomTags::ScoreTag), "{gang}", sGang);
		}
		if (bRankme && StrContains(tags.ScoreTag, "{rmPoints}") != -1)
		{
			static char sPoints[16];
			IntToString(RankMe_GetPoints(client), sPoints, sizeof(sPoints));
			ReplaceString(tags.ScoreTag, sizeof(CustomTags::ScoreTag), "{rmPoints}", sPoints);
		}
		if (bRankme && StrContains(tags.ScoreTag, "{rmRank}") != -1)
		{
			Debug_Print("Contains rmRank");
			RankMe_GetRank(client, RankMe_LoadTags);
		}
		
		Debug_Print("Setted tag: %s", tags.ScoreTag);
		CS_SetClientClanTag(client, tags.ScoreTag); //Instantly load the score-tag
	}
	if (StrContains(tags.ChatTag, "{rainbow}") == 0)
	{
		Debug_Print("Found {rainbow} in ChatTag");
		ReplaceString(tags.ChatTag, sizeof(CustomTags::ChatTag), "{rainbow}", "");
		char sTemp[MAXLENGTH_MESSAGE];
		
		int color;
		int len = strlen(tags.ChatTag);
		for (int i = 0; i < len; i++)
		{
			if (IsCharSpace(tags.ChatTag[i]))
			{
				Format(sTemp, sizeof(sTemp), "%s%c", sTemp, tags.ChatTag[i]);
				continue;
			}
			
			int bytes = GetCharBytes(tags.ChatTag[i]) + 1;
			char[] c = new char[bytes];
			strcopy(c, bytes, tags.ChatTag[i]);
			Format(sTemp, sizeof(sTemp), "%s%c%s", sTemp, GetColor(++color), c);
			if (IsCharMB(tags.ChatTag[i]))
				i += bytes - 2;
		}
		strcopy(tags.ChatTag, sizeof(CustomTags::ChatTag), sTemp);
		Debug_Print("Replaced ChatTag with %s", tags.ChatTag);
	}
	if (StrContains(tags.ChatTag, "{random}") == 0)
	{
		ReplaceString(tags.ChatTag, sizeof(CustomTags::ChatTag), "{random}", "");
		char sTemp[MAXLENGTH_MESSAGE];
		int len = strlen(tags.ChatTag);
		for (int i = 0; i < len; i++)
		{
			if (IsCharSpace(tags.ChatTag[i]))
			{
				Format(sTemp, sizeof(sTemp), "%s%c", sTemp, tags.ChatTag[i]);
				continue;
			}
			
			int bytes = GetCharBytes(tags.ChatTag[i]) + 1;
			char[] c = new char[bytes];
			strcopy(c, bytes, tags.ChatTag[i]);
			Format(sTemp, sizeof(sTemp), "%s%c%s", sTemp, GetRandomColor(), c);
			if (IsCharMB(tags.ChatTag[i]))
				i += bytes - 2;
		}
		strcopy(tags.ChatTag, sizeof(CustomTags::ChatTag), sTemp);
	}
	Debug_Print("Succesfully setted tags");
	userTags[client].PushArray(tags, sizeof(tags));
}

void ResetTags(int client)
{
	strcopy(selectedTags[client].ScoreTag, sizeof(CustomTags::ScoreTag), "");
	strcopy(selectedTags[client].ChatTag, sizeof(CustomTags::ChatTag), "");
	strcopy(selectedTags[client].ChatColor, sizeof(CustomTags::ChatColor), "");
	strcopy(selectedTags[client].NameColor, sizeof(CustomTags::NameColor), "");
	selectedTags[client].ForceTag = true;
}

int GetRandomColor()
{
	switch (GetRandomInt(1, 16))
	{
		case 1:return '\x01';
		case 2:return '\x02';
		case 3:return '\x03';
		case 4:return '\x03';
		case 5:return '\x04';
		case 6:return '\x05';
		case 7:return '\x06';
		case 8:return '\x07';
		case 9:return '\x08';
		case 10:return '\x09';
		case 11:return '\x10';
		case 12:return '\x0A';
		case 13:return '\x0B';
		case 14:return '\x0C';
		case 15:return '\x0E';
		case 16:return '\x0F';
	}
	return '\x01';
}

int GetColor(int color)
{
	switch (color % 7)
	{
		case 0:return '\x02';
		case 1:return '\x10';
		case 2:return '\x09';
		case 3:return '\x06';
		case 4:return '\x0B';
		case 5:return '\x0C';
		case 6:return '\x0E';
	}
	return '\x01';
}

// Fire Pre Process
Action FirePreProcess(int author, char[] name, char[] message)
{
	int result;
	Call_StartForward(fMessagePreProcess);
	Call_PushCell(author);
	Call_PushStringEx(name, MAXLENGTH_NAME, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushStringEx(message, MAXLENGTH_MESSAGE, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_Finish(result);
	
	return view_as<Action>(result);
}

// Fire Process
Action FireMessageProcess(int author, char[] name, char[] message)
{
	int result;
	Call_StartForward(fMessageProcess);
	Call_PushCell(author);
	Call_PushStringEx(name, MAXLENGTH_NAME, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushStringEx(message, MAXLENGTH_MESSAGE, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_Finish(result);
	
	return view_as<Action>(result);
}

// Fire (Post) Process
void FireMessageProcessed(int author, const char[] name, const char[] message)
{
	Call_StartForward(fMessageProcessed);
	Call_PushCell(author);
	Call_PushString(name);
	Call_PushString(message);
	Call_Finish();
}

// Replace {rainbow}
bool ReplaceRainbow(int author, const char[] name, char[] buffer)
{
	if (StrEqual(selectedTags[author].NameColor, "{rainbow}"))
	{
		Debug_Print("Rainbow name");
		char sTemp[MAXLENGTH_MESSAGE];
		
		int color;
		int len = strlen(name);
		for (int i = 0; i < len; i++)
		{
			if (IsCharSpace(name[i]))
			{
				Format(sTemp, sizeof(sTemp), "%s%c", sTemp, name[i]);
				continue;
			}
			
			int bytes = GetCharBytes(name[i]) + 1;
			char[] c = new char[bytes];
			strcopy(c, bytes, name[i]);
			Format(sTemp, sizeof(sTemp), "%s%c%s", sTemp, GetColor(++color), c);
			if (IsCharMB(name[i]))
				i += bytes - 2;
		}
		Format(buffer, MAXLENGTH_NAME, "%s%s{default}", selectedTags[author].ChatTag, sTemp);
		return true;
	}
	return false;
}

// Replace {random}
bool ReplaceRandom(int author, const char[] name, char[] buffer)
{
	if (StrEqual(selectedTags[author].NameColor, "{random}")) //Random name
	{
		Debug_Print("Random name");
		char sTemp[MAXLENGTH_MESSAGE];
		
		int len = strlen(name);
		for (int i = 0; i < len; i++)
		{
			if (IsCharSpace(name[i]))
			{
				Format(sTemp, sizeof(sTemp), "%s%c", sTemp, name[i]);
				continue;
			}
			
			int bytes = GetCharBytes(name[i]) + 1;
			char[] c = new char[bytes];
			strcopy(c, bytes, name[i]);
			Format(sTemp, sizeof(sTemp), "%s%c%s", sTemp, GetRandomColor(), c);
			if (IsCharMB(name[i]))
				i += bytes - 2;
		}
		Format(buffer, MAXLENGTH_NAME, "%s%s{default}", selectedTags[author].ChatTag, sTemp);
	
		return true;
	}
	return false;
}

// Replace {time}
bool ReplaceTime(char[] name, char[] message)
{
	static char sTime[16];
	FormatTime(sTime, sizeof(sTime), "%H:%M");
	ReplaceString(name, MAXLENGTH_NAME, "{time}", sTime);
	ReplaceString(message, MAXLENGTH_MESSAGE, "{time}", sTime);
	return true;
}

// Replace {country}
bool ReplaceCountry(int author, char[] name, char[] message)
{
	static char sIP[32];
	static char sCountry[3];
	GetClientIP(author, sIP, sizeof(sIP));
	GeoipCode2(sIP, sCountry);
	ReplaceString(name, MAXLENGTH_NAME, "{country}", sCountry);
	ReplaceString(message, MAXLENGTH_MESSAGE, "{country}", sCountry);
	return true;
}

// Replace {gang}
bool ReplaceGang(int author, char[] name, char[] message)
{
	if (bGangs)
	{
		Debug_Print("Apply gans");
		static char sGang[32];
		Gangs_HasGang(author) ? Gangs_GetGangName(author, sGang, sizeof(sGang)) : cv_sDefaultGang.GetString(sGang, sizeof(sGang));
		
		ReplaceString(name, MAXLENGTH_NAME, "{gang}", sGang);
		ReplaceString(message, MAXLENGTH_MESSAGE, "{gang}", sGang);
		return true;
	}
	return false;
}

// Replace {rmPoints} & {rmRank}
bool ReplaceRankMe(int author, char[] name, char[] message)
{
	if (bRankme)
	{
		Debug_Print("Apply rankme");
		static char sPoints[16];
		IntToString(RankMe_GetPoints(author), sPoints, sizeof(sPoints));
		ReplaceString(name, MAXLENGTH_NAME, "{rmPoints}", sPoints);
		ReplaceString(message, MAXLENGTH_MESSAGE, "{rmPoints}", sPoints);
		
		static char sRank[16];
		IntToString(iRank[author], sRank, sizeof(sRank));
		ReplaceString(name, MAXLENGTH_NAME, "{rmRank}", sRank);
		ReplaceString(message, MAXLENGTH_MESSAGE, "{rmRank}", sRank);
		return true;
	}
	return false;
}

void SendMessages(int author, ArrayList recievers, const char[] msg_name, const char[] name, const char[] message, bool chat, bool textallchat, bool colors = false)
{
	char buffer[MAXLENGTH_BUFFER];
	if (!messageFormat.GetString(msg_name, buffer, sizeof(buffer)))
	{
		LogError("Flag %s not found!", msg_name);
		delete recievers;
		return;
	}
	
	ReplaceString(buffer, sizeof(buffer), "{1}", name);
	ReplaceString(buffer, sizeof(buffer), "{2}", message);
	
	for (int i = 0; i < recievers.Length; i++)
	{
		if (colors)
			CSayText2(author, recievers.Get(i), buffer, chat, textallchat);
		else
			SayText2(author, recievers.Get(i), buffer, chat, textallchat);
	}
	
	delete recievers;
}

void GenerateFormat()
{
	delete messageFormat;
	messageFormat = new StringMap();
	// From Kxnrl chat-processor
	messageFormat.SetString("Cstrike_Chat_CT_Loc", "(CT) {1} :  {2}");
	messageFormat.SetString("Cstrike_Chat_CT", "(CT) {1} :  {2}");
	messageFormat.SetString("Cstrike_Chat_T_Loc", "(TE) {1} :  {2}");
	messageFormat.SetString("Cstrike_Chat_T", "(TE) {1} :  {2}");
	messageFormat.SetString("Cstrike_Chat_CT_Dead", "*DEAD*(CT) {1} :  {2}");
	messageFormat.SetString("Cstrike_Chat_T_Dead", "*DEAD*(TE) {1} :  {2}");
	messageFormat.SetString("Cstrike_Chat_Spec", "(SPEC) {1} :  {2}");
	messageFormat.SetString("Cstrike_Chat_All", " {1} :  {2}");
	messageFormat.SetString("Cstrike_Chat_AllDead", "*DEAD* {1} :  {2}");
	messageFormat.SetString("Cstrike_Chat_AllSpec", "*SPEC* {1} :  {2}");
}

// API
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
	
	eTags tag = view_as<eTags>(GetNativeCell(2));
	switch (tag)
	{
		case (ScoreTag):
		{
			SetNativeString(3, selectedTags[client].ScoreTag, GetNativeCell(4));
		}
		case (ChatTag):
		{
			SetNativeString(3, selectedTags[client].ChatTag, GetNativeCell(4));
		}
		case (ChatColor):
		{
			SetNativeString(3, selectedTags[client].ChatColor, GetNativeCell(4));
		}
		case (NameColor):
		{
			SetNativeString(3, selectedTags[client].NameColor, GetNativeCell(4));
		}
	}
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
	
	char sTag[64];
	eTags tag = view_as<eTags>(GetNativeCell(2));
	
	GetNativeString(3, sTag, sizeof(sTag));
	ReplaceString(sTag, sizeof(sTag), "{darkgray}", "{gray2}");
	
	switch (tag)
	{
		case (ScoreTag):
		{
			strcopy(selectedTags[client].ScoreTag, sizeof(CustomTags::ScoreTag), sTag);
		}
		case (ChatTag):
		{
			strcopy(selectedTags[client].ChatTag, sizeof(CustomTags::ChatTag), sTag);
		}
		case (ChatColor):
		{
			strcopy(selectedTags[client].ChatColor, sizeof(CustomTags::ChatColor), sTag);
		}
		case (NameColor):
		{
			strcopy(selectedTags[client].NameColor, sizeof(CustomTags::NameColor), sTag);
		}
	}
	
	
	Debug_Print("Called Native_SetClientTag(%i, %i, %s)", client, tag, sTag);
	
	//	strcopy(selectedTags[client][Tag], sizeof(sTags[][]), sTag);
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

public int Native_AddCustomSelector(Handle plugin, int numParams)
{
	return pfCustomSelector.AddFunction(plugin, GetNativeFunction(1));
}

public int Native_RemoveCustomSelector(Handle plugin, int numParams)
{
	return pfCustomSelector.RemoveFunction(plugin, GetNativeFunction(1));
} 