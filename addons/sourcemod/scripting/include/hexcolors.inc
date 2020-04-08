#if defined _hexcolors_included
#endinput
#endif
#define _hexcolors_included

static StringMap colorMap = null;
static StringMapSnapshot colorSnap = null;

static char tagString[64];

/**
 * Adds a prefix to every 'Colored' function.
 *
 *
 * @param format		Formatting rules.
 * @param ...			Variable number of format parameters.
 */
stock void CSetPrefix(const char[] format, any...)
{
	char buffer[256];
	VFormat(buffer, sizeof buffer, format, 2);
	
	Format(buffer, sizeof buffer, " %s{default} ", buffer);
	strcopy(tagString, sizeof tagString, buffer);
}

/**
 * Replies to a message in a command supporting colors.
 *
 * A client index of 0 will use PrintToServer().
 * If the command was from the console, PrintToConsole() is used.
 * If the command was from chat, CPrintToChat() is used.
 *
 * @param client		Client index, or 0 for server.
 * @param format		Formatting rules.
 * @param ...			Variable number of format parameters.
 * @error				If the client is not connected or invalid.
 */
stock void CReplyToCommand(int client, const char[] format, any...)
{
	if (client < 0 || client > MaxClients)
	{
		ThrowError("Invalid client index (%d)", client);
	}
	
	if (client != 0 && !IsClientInGame(client))
	{
		ThrowError("Client %d is not connected", client);
	}
	
	char buffer[256];
	SetGlobalTransTarget(client);
	
	VFormat(buffer, sizeof buffer, format, 3);
	
	if (client == 0)
	{
		RemoveColors(buffer);
		PrintToServer(buffer);
	}
	else if (GetCmdReplySource() == SM_REPLY_TO_CHAT)
	{
		CPrintToChat(client, buffer);
	}
	else
	{
		RemoveColors(buffer);
		PrintToConsole(client, buffer);
	}
}

/**
 * Prints a colored message to a specific client in the chat area.
 *
 * @param client		Client index.
 * @param format		Formatting rules.
 * @param ...			Variable number of format parameters.
 * @error				If the client is not connected an error will be thrown.
 */
stock void CPrintToChat(int client, const char[] format, any...)
{
	if (client < 1 || client > MaxClients)
	{
		ThrowError("Invalid client index (%d)", client);
	}
	
	if (!IsClientInGame(client))
	{
		ThrowError("Client %d is not connected", client);
	}
	
	char buffer[256];
	SetGlobalTransTarget(client);
	
	VFormat(buffer, sizeof buffer, format, 3);
	ProcessColors(buffer, sizeof buffer);
	PrintToChat(client, buffer);
}

/**
 * Prints a colored message to all clients in the chat area.
 *
 * @param format		Formatting rules.
 * @param ...			Variable number of format parameters.
 */
stock void CPrintToChatAll(const char[] format, any...)
{
	char buffer[256];
	
	for (int i = 1; i <= MaxClients; i++)if (IsClientInGame(i))
	{
		SetGlobalTransTarget(i);
		VFormat(buffer, sizeof buffer, format, 2);
		CPrintToChat(i, buffer);
	}
}


/**
 * Proccesses all the colors in the buffer.
 *
 * @param buffer		Buffer.
 * @param maxlength		Buffer length.
 * @param tag			If true the tag will be prepended to the buffer.
 */
stock void ProcessColors(char[] buffer, int maxlength, bool tag = true)
{
	initColors();
	
	if (tag && tagString[0] != '\0')
	{
		Format(buffer, maxlength, "%s%s", tagString, buffer);
	}
	else
	{
		//Fix for CSGO, the tag is already fixed.
		Format(buffer, maxlength, " %s", buffer);
	}
	
	for (int i = 0; i < colorSnap.Length; i++)
	{
		char sSearch[32];
		char sKey[32];
		int iColorCode;
		
		colorSnap.GetKey(i, sKey, sizeof sKey);
		colorMap.GetValue(sKey, iColorCode);
		
		char sColor[1];
		sColor[0] = iColorCode;
		Format(sSearch, sizeof sSearch, "{%s}", sKey);
		ReplaceString(buffer, maxlength, sSearch, sColor, false);
	}
}

stock void CFormat(char[] buffer, int maxlength, const char[] format, any...)
{
	VFormat(buffer, maxlength, format, 4);
	ProcessColors(buffer, maxlength, false);
}

/**
 * Removes all the color strings from the buffer.
 *
 * @param buffer		Buffer.
 * @param tag			If true the tag will be prepended to the buffer.
 */
stock void RemoveColors(char[] buffer, bool tag = true)
{
	initColors();
	int len = strlen(buffer) + strlen(tagString) + 1;
	
	if (tag && tagString[0] != '\0')
	{
		Format(buffer, len, "%s%s", tagString, buffer);
	}
	
	for (int i = 0; i < colorSnap.Length; i++)
	{
		char sSearch[32];
		char sKey[32];
		
		colorSnap.GetKey(i, sKey, sizeof sKey);
		
		Format(sSearch, sizeof sSearch, "{%s}", sKey);
		ReplaceString(buffer, len, sSearch, "", false);
	}
}

static void initColors()
{
	if (colorMap != null)
		return;
	
	colorMap = new StringMap();
	colorMap.SetValue("default", '\x01');
	colorMap.SetValue("darkred", '\x02');
	colorMap.SetValue("purple", '\x04');
	colorMap.SetValue("teamcolor", '\x03');
	colorMap.SetValue("lime", '\x04');
	colorMap.SetValue("lightgreen", '\x05');
	colorMap.SetValue("green", '\x06');
	colorMap.SetValue("lightred", '\x07');
	colorMap.SetValue("grey", '\x08');
	colorMap.SetValue("yellow", '\x09');
	colorMap.SetValue("gold", '\x10');
	colorMap.SetValue("bluegrey", '\x0A');
	colorMap.SetValue("blue", '\x0B');
	colorMap.SetValue("darkblue", '\x0C');
	colorMap.SetValue("grey2", '\x0D');
	colorMap.SetValue("orchid", '\x0E');
	colorMap.SetValue("red", '\x0F');
	
	colorSnap = colorMap.Snapshot();
}

void CSayText2(int sender, int reciever, const char[] buffer/* name + message */, bool chat, bool textallchat)
{
	char message[128 + 256];
	CFormat(message, sizeof(message), buffer);
	
	SayText2(sender, reciever, message, chat, textallchat);
}

void SayText2(int sender, int reciever, const char[] buffer/* name + message */, bool chat, bool textallchat)
{
	Protobuf proto = view_as<Protobuf>(StartMessageOne("SayText2", reciever, USERMSG_RELIABLE | USERMSG_BLOCKHOOKS));
	proto.SetInt("ent_idx", sender);
	proto.SetBool("chat", chat);
	proto.SetString("msg_name", buffer);
	proto.AddString("params", "");
	proto.AddString("params", "");
	proto.AddString("params", "");
	proto.AddString("params", "");
	proto.SetBool("textallchat", textallchat);
	EndMessage();
} 