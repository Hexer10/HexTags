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
 
#include <sourcemod>
#include <sdktools>
#include <chat-processor>
#include <hextags>

#undef REQUIRE_EXTENSIONS
#undef REQUIRE_PLUGIN
#include <mostactive>
#include <cstrike>
#define REQUIRE_EXTENSIONS
#define REQUIRE_PLUGIN

#define PLUGIN_AUTHOR         "Hexah"
#define PLUGIN_VERSION        "<TAG>"


#pragma semicolon 1
#pragma newdecls required

Handle fTagsUpdated;

bool bLate;
bool bMostActive;

char sTags[MAXPLAYERS+1][eTags][128];

KeyValues kv;

//Plugin infos
public Plugin myinfo =
{
	name = "hextags",
	author = PLUGIN_AUTHOR,
	description = "Edit Tags & Colors!",
	version = PLUGIN_VERSION,
	url = "csitajb.it"
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
	
	//LateLoad
	bLate = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("sm_hextags_version", PLUGIN_VERSION, "HexTags plugin version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	//Reg Cmds
	RegAdminCmd("sm_reloadtags", Cmd_ReloadTags, ADMFLAG_BAN);
	
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
	
}

public void OnAllPluginsLoaded()
{
	bMostActive = LibraryExists("mostactive");
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "mostactive"))
		bMostActive = true;
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "mostactive"))
		bMostActive = false;
}


//Thanks to https://forums.alliedmods.net/showpost.php?p=2573907&postcount=6
public Action OnClientCommandKeyValues(int client, KeyValues TagKv)
{
    char sKey[64]; 
     
    if (!TagKv.GetSectionName(sKey, sizeof(sKey)))
    	return Plugin_Continue;
    	
    if(StrEqual(sKey, "ClanTagChanged"))
    {
    	RequestFrame(Frame_SetTag, GetClientUserId(client));
    }

    return Plugin_Continue; 
}

public void Frame_SetTag(any iUserID)
{
	int client = GetClientOfUserId(iUserID);
	
	if (strlen(sTags[client][ScoreTag]) > 0 && IsCS())
		CS_SetClientClanTag(client, sTags[client][ScoreTag]);
}


//Commands
public Action Cmd_ReloadTags(int client, int args)
{
	LoadKv();
	for (int i = 1; i <= MaxClients; i++)if (IsClientInGame(i))OnClientPostAdminCheck(i);

	ReplyToCommand(client, "[SM] Tags succesfully reloaded!");
	return Plugin_Handled;
}

//Events
public void OnClientPostAdminCheck(int client)
{
	LoadTags(client);
	
	if (strlen(sTags[client][ScoreTag]) > 0 && IsCS())
		CS_SetClientClanTag(client, sTags[client][ScoreTag]); //Instantly load the score-tag
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
	
	//Update the name & message
	strcopy(name, MAXLENGTH_NAME, sNewName);
	strcopy(message, MAXLENGTH_MESSAGE, sNewMessage);
	
	processcolors = true;
	removecolors = false;
	
	return Plugin_Changed;
}


//Functions
void LoadKv()
{
	char sConfig[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sConfig, sizeof(sConfig), "configs/hextags.cfg"); //Get cfg file
	
	if (OpenFile(sConfig, "rt") == null)
		SetFailState("Couldn't find: \"%s\"", sConfig); //Check if cfg exist
	
	if (kv != null)
		delete kv;
		
	kv = new KeyValues("HexTags"); //Create the kv
	
	if (!kv.ImportFromFile(sConfig))
		SetFailState("Couldn't import: \"%s\"", sConfig); //Check if file was imported properly
		
	if (!kv.GotoFirstSubKey())
		LogMessage("No entries found in: \"%s\"", sConfig); //Notify that there aren't any entry
}

void LoadTags(int client)
{
	//Clear the tags when re-checking
	ResetTags(client);
	
	kv.Rewind();
	
	//Check steamid checking
	char steamid[32];
	if (!GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid)))
		return;
		
	if (kv.JumpToKey(steamid))
	{
		Call_StartForward(fTagsUpdated);
		Call_PushCell(client);
		Call_Finish();
		GetTags(client);
		return;
	}
	
	steamid[6] = '0'; //Replace the STEAM_1 to STEAM_0
	
	if (kv.JumpToKey(steamid)) //Check again with STEAM_0
	{
		GetTags(client);
		Call_StartForward(fTagsUpdated);
		Call_PushCell(client);
		Call_Finish();
		return;
	}
	
	//Start AdminGroups checking
	AdminId admin = GetUserAdmin(client);
	if (admin != INVALID_ADMIN_ID)
	{
		char sGroup[32];
		admin.GetGroup(0, sGroup, sizeof(sGroup));
		Format(sGroup, sizeof(sGroup), "@%s", sGroup);
		
		if (kv.JumpToKey(sGroup))
		{
			GetTags(client);
			Call_StartForward(fTagsUpdated);
			Call_PushCell(client);
			Call_Finish();
			return;
		}
	}
	
	//Start flags checking
	char sFlags[21] = "abcdefghijklmnopqrstz";
	
	for (int i = sizeof(sFlags)-1; 0 <= i; i--)
	{
		char sFlag[1];
		sFlag[0] = sFlags[i];
		
		if (ReadFlagString(sFlag) & GetUserFlagBits(client))
		{
			if (kv.JumpToKey(sFlag))
			{
				GetTags(client);
				Call_StartForward(fTagsUpdated);
				Call_PushCell(client);
				Call_Finish();
				return;
			}
		}
	}
	
	//Start total play-time checking
	if (bMostActive)
	{
		int iOldTime;
		bool bReturn;
		
		if (!kv.GotoFirstSubKey())
			return;
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
		
		kv.Rewind();
		if (bReturn)
		{
			Call_StartForward(fTagsUpdated);
			Call_PushCell(client);
			Call_Finish();
			return;
		}
	}
	//Check for 'All' entry
	if (kv.JumpToKey("Default"))
		GetTags(client);
		
	//Call the forward
	Call_StartForward(fTagsUpdated);
	Call_PushCell(client);
	Call_Finish();
}

//Stocks
void GetTags(int client)
{
	kv.GetString("ScoreTag", sTags[client][ScoreTag], sizeof(sTags[][]), "");
	kv.GetString("ChatTag", sTags[client][ChatTag], sizeof(sTags[][]), "");
	kv.GetString("ChatColor", sTags[client][ChatColor], sizeof(sTags[][]), "");
	kv.GetString("NameColor", sTags[client][NameColor], sizeof(sTags[][]), "{teamcolor}");
}

void ResetTags(int client)
{
	strcopy(sTags[client][ScoreTag], sizeof(sTags[][]), "");
	strcopy(sTags[client][ChatTag], sizeof(sTags[][]), "");
	strcopy(sTags[client][ChatColor], sizeof(sTags[][]), "");
	strcopy(sTags[client][NameColor], sizeof(sTags[][]), "");
}

bool IsCS()
{
	EngineVersion engine = GetEngineVersion();
	
	return (engine == Engine_CSGO || engine == Engine_CSS);
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