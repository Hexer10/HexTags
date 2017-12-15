/*
 * HexTags Plugin.
 * by: Hexah
 * https://github.com/Hexer10/HexTags
 * 
 * Copyright (C) 2017 Mattia (Hexah|Hexer10|Papero)
 *
 * This file is part of the MyJailbreak SourceMod Plugin.
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
#include <sdkhooks>
#include <chat-processor>
#include <hexstocks>

#define PLUGIN_AUTHOR         "Hexah"
#define PLUGIN_VERSION        "1.01"


#pragma semicolon 1
#pragma newdecls required

bool bLate;

KeyValues kv;

enum eTags
{
	ScoreTag,
	ChatTag,
	ChatColor,
	NameColor
}
char sTags[MAXPLAYERS+1][eTags][32];

public Plugin myinfo =
{
	name = "HexTags",
	author = PLUGIN_AUTHOR,
	description = "",
	version = PLUGIN_VERSION,
	url = "csitajb.it"
};


public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	bLate = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	//Reg Cmds
	RegAdminCmd("sm_reloadtags", Cmd_ReloadTags, ADMFLAG_BAN);
	
	LoadKv();
	if (bLate)
		for (int i = 1; i <= MaxClients; i++)if (IsClientInGame(i)) OnClientPostAdminCheck(i); //LateLoad
	
	//Event Hooks
	HookEvent("player_spawn", Event_CheckTags);
	HookEvent("player_team", Event_CheckTags);
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
	
	if (strlen(sTags[client][ScoreTag]) > 0)
		CS_SetClientClanTag(client, sTags[client][ScoreTag]); //Instantly load the score-tag
}

public void Event_CheckTags(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (strlen(sTags[client][ScoreTag]) > 0)
		CS_SetClientClanTag(client, sTags[client][ScoreTag]);
}

public Action CP_OnChatMessage(int& author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool& processcolors, bool& removecolors)
{
	Format(name, MAXLENGTH_MESSAGE, "%s%s%s{default}", sTags[author][ChatTag], sTags[author][NameColor], name);	
	Format(message, MAXLENGTH_MESSAGE, "%s %s", sTags[author][ChatColor], message);
	
	processcolors = true;	
	
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
		LogMessage("No entries found in: \"%s\"", sConfig); //Notify that there isn't any entry
}

void LoadTags(int client)
{
	//Clear the tags when re-checking
	strcopy(sTags[client][ScoreTag], sizeof(sTags[][]), "");
	strcopy(sTags[client][ChatTag], sizeof(sTags[][]), "");
	strcopy(sTags[client][ChatColor], sizeof(sTags[][]), "");
	strcopy(sTags[client][NameColor], sizeof(sTags[][]), "");
	
	kv.Rewind();
	
	//Check steamid checking
	char steamid[32];
	if (!GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid)))
		return;
		
	if (kv.JumpToKey(steamid))
	{
		GetTags(client);
		return;
	}
	
	steamid[6] = '0'; //Replace the STEAM_1 to STEAM_0
	
	if (kv.JumpToKey(steamid)) //Check again with STEAM_0
	{
		GetTags(client);
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
				return;
			}
		}
	}
	
	//Check for 'All' entry
	if (kv.JumpToKey("Default"))
		GetTags(client);
}

void GetTags(int client)
{
	kv.GetString("ScoreTag", sTags[client][ScoreTag], sizeof(sTags[][]), "");
	kv.GetString("ChatTag", sTags[client][ChatTag], sizeof(sTags[][]), "");
	kv.GetString("ChatColor", sTags[client][ChatColor], sizeof(sTags[][]), "");
	kv.GetString("NameColor", sTags[client][NameColor], sizeof(sTags[][]), "{teamcolor}");
}

